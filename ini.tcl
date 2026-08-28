# ini - a strict INI/config reader and writer for Tcl.
#
#   package require ini
#   set config [ini::parse $text]
#   ini::get $config server port 8080
#
# Parsed configuration is a plain Tcl dict of section -> key -> value, so it
# needs no accessors beyond the conveniences below. Keys that appear before any
# section header live in the section named "" (the global section).

package require Tcl 8.6

namespace eval ini {
    namespace export parse serialize get exists sections keys
    namespace export put remove remove_section merge
    variable version 0.1.0
}

# Parses INI text into a dict of section -> key -> value.
#
# Throws on a malformed line rather than skipping it. A config file that is
# silently half-applied is worse than one that refuses to load, because the
# process starts with defaults nobody chose.
proc ini::parse {text} {
    set result [dict create]
    set section ""
    dict set result $section [dict create]

    set lineno 0
    foreach line [split $text \n] {
        incr lineno

        # A trailing CR from a CRLF file is not part of any value.
        set trimmed [string trim $line " \t\r"]

        if {$trimmed eq ""} continue

        # Comments are only recognised at the start of a line. An inline ; or #
        # is kept as data: values legitimately contain them (URL fragments,
        # passwords, colour literals) and guessing wrong silently truncates.
        if {[string index $trimmed 0] in {";" "#"}} continue

        if {[string index $trimmed 0] eq "\["} {
            if {[string index $trimmed end] ne "\]"} {
                return -code error "line $lineno: unterminated section header: $trimmed"
            }
            set name [string trim [string range $trimmed 1 end-1]]
            if {$name eq ""} {
                return -code error "line $lineno: empty section name"
            }
            set section $name
            # Re-entering a section adds to it rather than replacing it.
            if {![dict exists $result $section]} {
                dict set result $section [dict create]
            }
            continue
        }

        set idx [string first "=" $trimmed]
        if {$idx < 0} {
            return -code error \
                "line $lineno: expected 'key = value' or '\[section\]', got: $trimmed"
        }

        set key [string trim [string range $trimmed 0 $idx-1]]
        if {$key eq ""} {
            return -code error "line $lineno: empty key"
        }

        set value [string trim [string range $trimmed $idx+1 end]]
        set value [ini::Unquote $value]

        # Last assignment wins, matching every INI reader users have met.
        dict set result $section $key $value
    }

    return $result
}

# Strips one layer of matching double quotes, which is how a value keeps
# leading or trailing whitespace, or an empty value states itself explicitly.
proc ini::Unquote {value} {
    if {[string length $value] >= 2
        && [string index $value 0] eq "\""
        && [string index $value end] eq "\""} {
        return [string range $value 1 end-1]
    }
    return $value
}

# True when section/key is present. Distinguishes "absent" from "set to the
# same string you were going to default to", which ini::get cannot.
proc ini::exists {config section key} {
    return [dict exists $config $section $key]
}

# Returns the value, or default when section/key is absent.
proc ini::get {config section key {default ""}} {
    if {[dict exists $config $section $key]} {
        return [dict get $config $section $key]
    }
    return $default
}

# Section names, global section first if it holds anything, then sorted.
proc ini::sections {config} {
    set out {}
    if {[dict exists $config ""] && [dict size [dict get $config ""]] > 0} {
        lappend out ""
    }
    foreach name [lsort [dict keys $config]] {
        if {$name ne ""} {
            lappend out $name
        }
    }
    return $out
}

# Keys within a section, in insertion order (Tcl dicts preserve it).
proc ini::keys {config section} {
    if {![dict exists $config $section]} {
        return {}
    }
    return [dict keys [dict get $config $section]]
}

# Returns a copy of config with section/key set to value.
#
# Every mutator returns a new dict rather than mutating in place. Tcl dicts have
# value semantics, so `set b [ini::put $a ...]` leaving $a untouched is what a
# caller expects; a `dict set` on an upvar'd variable would surprise anyone who
# had passed the same config to two places.
#
# Named put/remove rather than set/unset deliberately. A proc named `set` in
# this namespace shadows the builtin for every *other* proc in the namespace,
# because Tcl resolves an unqualified command name in the current namespace
# before the global one. `ini::parse` opens with `set result [dict create]`, so
# an `ini::set` proc breaks parsing with a wrong-arg-count error.
proc ini::put {config section key value} {
    if {[string trim $key] eq ""} {
        return -code error "key cannot be blank"
    }
    if {![dict exists $config $section]} {
        dict set config $section [dict create]
    }
    dict set config $section $key $value
    return $config
}

# Returns a copy of config with section/key removed. Removing something that is
# not there is not an error - the caller's intent is satisfied either way.
proc ini::remove {config section key} {
    if {[dict exists $config $section $key]} {
        dict unset config $section $key
    }
    return $config
}

# Returns a copy of config with an entire section removed.
proc ini::remove_section {config section} {
    if {[dict exists $config $section]} {
        dict unset config $section
    }
    return $config
}

# Merges overlay onto base, key by key. A key present in both takes the overlay's
# value; sections and keys only in base survive.
#
# This is the shape config files are actually used in: defaults, then a
# site file, then the environment.
proc ini::merge {base overlay} {
    dict for {section pairs} $overlay {
        if {![dict exists $base $section]} {
            dict set base $section [dict create]
        }
        dict for {key value} $pairs {
            dict set base $section $key $value
        }
    }
    return $base
}

# Renders a config dict back to INI text.
#
# parse(serialize(parse(x))) equals parse(x) for any x that parses - values
# whose whitespace or leading punctuation would not survive a round trip are
# quoted on the way out.
proc ini::serialize {config} {
    set out {}

    if {[dict exists $config ""]} {
        dict for {key value} [dict get $config ""] {
            lappend out [ini::EmitPair $key $value]
        }
    }

    foreach section [lsort [dict keys $config]] {
        if {$section eq ""} continue
        if {[llength $out] > 0} {
            lappend out ""
        }
        lappend out "\[$section\]"
        dict for {key value} [dict get $config $section] {
            lappend out [ini::EmitPair $key $value]
        }
    }

    return [join $out \n]
}

proc ini::EmitPair {key value} {
    # Quote when reading the line back would not return this exact string:
    # surrounding whitespace would be trimmed, a leading ; or # would make the
    # line a comment, and a bare empty value is clearer stated as "".
    if {$value ne [string trim $value]
        || $value eq ""
        || [string index $value 0] in {";" "#"}
        || [string index $value 0] eq "\""} {
        return "$key = \"$value\""
    }
    return "$key = $value"
}

package provide ini $ini::version
