# Test suite for the ini package: tclsh tests/ini_test.tcl
package require tcltest 2
namespace import ::tcltest::*

set here [file dirname [file normalize [info script]]]
source [file join $here .. ini.tcl]

# --- basic parsing ---------------------------------------------------------

test parse-simple {a key in a section} -body {
    set c [ini::parse "\[server\]\nport = 8080"]
    ini::get $c server port
} -result 8080

test parse-global {keys before any section land in the global section} -body {
    set c [ini::parse "name = app\n\[server\]\nport = 80"]
    list [ini::get $c "" name] [ini::get $c server port]
} -result {app 80}

test parse-whitespace {whitespace around keys and values is trimmed} -body {
    ini::get [ini::parse "\[s\]\n   key   =   value   "] s key
} -result value

test parse-no-spaces {separators need no surrounding space} -body {
    ini::get [ini::parse "\[s\]\nkey=value"] s key
} -result value

test parse-empty-value {a bare empty value is the empty string} -body {
    ini::get [ini::parse "\[s\]\nkey ="] s key
} -result {}

test parse-value-with-equals {only the first = separates} -body {
    ini::get [ini::parse "\[s\]\nexpr = a=b=c"] s expr
} -result {a=b=c}

test parse-crlf {a trailing CR is not part of the value} -body {
    ini::get [ini::parse "\[s\]\r\nkey = value\r\n"] s key
} -result value

test parse-blank-lines {blank lines are ignored} -body {
    set c [ini::parse "\n\n\[s\]\n\n\nkey = v\n\n"]
    ini::get $c s key
} -result v

# --- comments -------------------------------------------------------------

test comment-semicolon {a leading semicolon is a comment} -body {
    set c [ini::parse "\[s\]\n; key = ignored\nkey = kept"]
    ini::get $c s key
} -result kept

test comment-hash {a leading hash is a comment} -body {
    set c [ini::parse "\[s\]\n# note\nkey = kept"]
    ini::get $c s key
} -result kept

test comment-indented {an indented comment is still a comment} -body {
    set c [ini::parse "\[s\]\n    ; note\nkey = kept"]
    ini::get $c s key
} -result kept

test comment-inline-kept {an inline hash is data, not a comment} -body {
    ini::get [ini::parse "\[s\]\nurl = http://x/y#frag"] s url
} -result {http://x/y#frag}

test comment-inline-semicolon-kept {an inline semicolon is data too} -body {
    ini::get [ini::parse "\[s\]\npass = a;b"] s pass
} -result {a;b}

# --- quoting --------------------------------------------------------------

test quote-preserves-space {quotes preserve surrounding whitespace} -body {
    ini::get [ini::parse "\[s\]\nkey = \"  padded  \""] s key
} -result {  padded  }

test quote-empty {an explicitly quoted empty value} -body {
    ini::get [ini::parse "\[s\]\nkey = \"\""] s key
} -result {}

test quote-single-layer {only one layer of quotes is removed} -body {
    ini::get [ini::parse "\[s\]\nkey = \"\"inner\"\""] s key
} -result {"inner"}

test quote-unbalanced-kept {an unmatched quote is data} -body {
    ini::get [ini::parse "\[s\]\nkey = \"unclosed"] s key
} -result {"unclosed}

# --- sections -------------------------------------------------------------

test section-reentry-merges {re-entering a section adds to it} -body {
    set c [ini::parse "\[s\]\na = 1\n\[t\]\nb = 2\n\[s\]\nc = 3"]
    list [ini::get $c s a] [ini::get $c s c] [ini::get $c t b]
} -result {1 3 2}

test section-name-trimmed {whitespace inside brackets is trimmed} -body {
    ini::get [ini::parse "\[  server  \]\nport = 1"] server port
} -result 1

test sections-order {global section first, then sorted} -body {
    ini::sections [ini::parse "g = 1\n\[zeta\]\na = 1\n\[alpha\]\nb = 2"]
} -result {{} alpha zeta}

test sections-omits-empty-global {an unused global section is not listed} -body {
    ini::sections [ini::parse "\[only\]\na = 1"]
} -result only

test keys-insertion-order {keys come back in the order written} -body {
    ini::keys [ini::parse "\[s\]\nz = 1\na = 2\nm = 3"] s
} -result {z a m}

test keys-missing-section {an absent section has no keys} -body {
    ini::keys [ini::parse "\[s\]\na = 1"] nope
} -result {}

# --- duplicate keys -------------------------------------------------------

test duplicate-key-last-wins {the last assignment wins} -body {
    ini::get [ini::parse "\[s\]\nkey = first\nkey = second"] s key
} -result second

# --- get and exists -------------------------------------------------------

test get-default {a missing key returns the default} -body {
    ini::get [ini::parse "\[s\]\na = 1"] s missing fallback
} -result fallback

test get-default-empty {the default default is the empty string} -body {
    ini::get [ini::parse "\[s\]\na = 1"] s missing
} -result {}

test get-missing-section {a missing section returns the default} -body {
    ini::get [ini::parse "\[s\]\na = 1"] nope key fallback
} -result fallback

test exists-true {exists finds a present key} -body {
    ini::exists [ini::parse "\[s\]\na = 1"] s a
} -result 1

test exists-false {exists rejects an absent key} -body {
    ini::exists [ini::parse "\[s\]\na = 1"] s b
} -result 0

test exists-distinguishes-empty {exists separates absent from empty} -body {
    set c [ini::parse "\[s\]\nset ="]
    list [ini::exists $c s set] [ini::exists $c s unset]
} -result {1 0}

# --- errors ---------------------------------------------------------------

test error-no-separator {a line with no = is an error} -body {
    ini::parse "\[s\]\njust some words"
} -returnCodes error -match glob -result {line 2:*expected*}

test error-unterminated-section {an unclosed bracket is an error} -body {
    ini::parse "\[server\nport = 1"
} -returnCodes error -match glob -result {line 1: unterminated section header:*}

test error-empty-section {an empty section name is an error} -body {
    ini::parse "\[\]\na = 1"
} -returnCodes error -match glob -result {line 1: empty section name}

test error-empty-key {an empty key is an error} -body {
    ini::parse "\[s\]\n = value"
} -returnCodes error -match glob -result {line 2: empty key}

test error-reports-line {the line number is accurate} -body {
    ini::parse "\[s\]\na = 1\n\nb = 2\noops"
} -returnCodes error -match glob -result {line 5:*}

# --- serialize and round trip ---------------------------------------------

test serialize-basic {sections are emitted with their keys} -body {
    ini::serialize [ini::parse "\[s\]\na = 1"]
} -result "\[s\]\na = 1"

test serialize-global-first {global keys precede any section header} -body {
    ini::serialize [ini::parse "name = app\n\[s\]\na = 1"]
} -result "name = app\n\n\[s\]\na = 1"

test serialize-key-after-header-is-sectioned {a key after a header belongs to it} -body {
    ini::serialize [ini::parse "\[s\]\na = 1\nname = app"]
} -result "\[s\]\na = 1\nname = app"

test serialize-quotes-padding {padded values are quoted on the way out} -body {
    ini::serialize [ini::parse "\[s\]\na = \"  x  \""]
} -result "\[s\]\na = \"  x  \""

test serialize-quotes-empty {an empty value is quoted} -body {
    ini::serialize [ini::parse "\[s\]\na ="]
} -result "\[s\]\na = \"\""

test serialize-quotes-comment-leader {a value starting with # is quoted} -body {
    ini::serialize [ini::parse "\[s\]\na = \"#fff\""]
} -result "\[s\]\na = \"#fff\""

set roundtripSrc "name = app\n; a comment\n\[server\]\nhost = example.com\nport = 8080\npad = \"  spaced  \"\nblank =\ncolour = \"#ff0000\"\nurl = http://x/y#frag\n\[db\]\ndsn = a=b=c"

# Note this compares serialised text, not the dicts. Tcl dicts compare as their
# string representation, which carries insertion order, so two dicts holding
# identical data but built in a different order are not `eq`. Serialising first
# normalises that away, and idempotent serialisation is the property that
# actually matters.
test roundtrip-idempotent {serialising a parsed document is idempotent} -body {
    set a [ini::serialize [ini::parse $roundtripSrc]]
    set b [ini::serialize [ini::parse $a]]
    if {$a eq $b} {
        return stable
    }
    return "DIFFERS
$a
---
$b"
} -result stable

test roundtrip-values-survive {every value survives a round trip intact} -body {
    set c [ini::parse [ini::serialize [ini::parse $roundtripSrc]]]
    list [ini::get $c "" name] \
         [ini::get $c server host] \
         [ini::get $c server pad] \
         [ini::get $c server blank] \
         [ini::get $c server colour] \
         [ini::get $c server url] \
         [ini::get $c db dsn]
} -result {app example.com {  spaced  } {} #ff0000 http://x/y#frag a=b=c}

test roundtrip-comments-dropped {comments do not survive, and that is documented} -body {
    string match {*a comment*} [ini::serialize [ini::parse $roundtripSrc]]
} -result 0

test roundtrip-empty {an empty document round-trips} -body {
    ini::serialize [ini::parse ""]
} -result {}

# --- mutation --------------------------------------------------------------

test put-adds-a-key {put adds a key to an existing section} -body {
    ini::get [ini::put [ini::parse "\[s\]\na = 1"] s b 2] s b
} -result 2

test put-overwrites {put replaces an existing value} -body {
    ini::get [ini::put [ini::parse "\[s\]\na = 1"] s a 9] s a
} -result 9

test put-creates-a-section {put creates a missing section} -body {
    ini::get [ini::put [ini::parse "\[s\]\na = 1"] new k v] new k
} -result v

test put-into-the-global-section {put works on the global section} -body {
    ini::get [ini::put [ini::parse ""] "" name app] "" name
} -result app

test put-is-immutable {put leaves the original untouched} -body {
    set a [ini::parse "\[s\]\nk = 1"]
    set b [ini::put $a s k 2]
    list [ini::get $a s k] [ini::get $b s k]
} -result {1 2}

test put-rejects-a-blank-key {put rejects a blank key} -body {
    ini::put [ini::parse ""] s "  " v
} -returnCodes error -match glob -result {key cannot be blank}

test put-allows-an-empty-value {an empty value is legitimate} -body {
    ini::exists [ini::put [ini::parse ""] s k ""] s k
} -result 1

test remove-deletes {remove deletes a key} -body {
    ini::exists [ini::remove [ini::parse "\[s\]\na = 1"] s a] s a
} -result 0

test remove-keeps-siblings {remove leaves other keys alone} -body {
    ini::get [ini::remove [ini::parse "\[s\]\na = 1\nb = 2"] s a] s b
} -result 2

test remove-missing-is-not-an-error {removing what is absent is a no-op} -body {
    ini::sections [ini::remove [ini::parse "\[s\]\na = 1"] s nope]
} -result s

test remove-missing-section-is-not-an-error {removing from a missing section is a no-op} -body {
    ini::sections [ini::remove [ini::parse "\[s\]\na = 1"] nope k]
} -result s

test remove-is-immutable {remove leaves the original untouched} -body {
    set a [ini::parse "\[s\]\nk = 1"]
    set b [ini::remove $a s k]
    list [ini::exists $a s k] [ini::exists $b s k]
} -result {1 0}

test remove-section-drops-everything {remove_section drops the whole section} -body {
    ini::sections [ini::remove_section [ini::parse "\[s\]\na = 1\n\[t\]\nb = 2"] s]
} -result t

test remove-section-missing-is-not-an-error {removing an absent section is a no-op} -body {
    ini::sections [ini::remove_section [ini::parse "\[s\]\na = 1"] nope]
} -result s

# --- merge -------------------------------------------------------------------

test merge-overlay-wins {a key in both takes the overlay value} -body {
    set base [ini::parse "\[s\]\na = 1"]
    ini::get [ini::merge $base [ini::parse "\[s\]\na = 9"]] s a
} -result 9

test merge-keeps-base-only-keys {keys only in base survive} -body {
    set base [ini::parse "\[s\]\na = 1\nb = 2"]
    ini::get [ini::merge $base [ini::parse "\[s\]\na = 9"]] s b
} -result 2

test merge-adds-new-sections {a section only in the overlay is added} -body {
    ini::get [ini::merge [ini::parse "\[s\]\na = 1"] [ini::parse "\[t\]\nc = 3"]] t c
} -result 3

test merge-is-per-key-not-per-section {merging does not replace a whole section} -body {
    set merged [ini::merge [ini::parse "\[s\]\na = 1\nb = 2"] [ini::parse "\[s\]\nb = 9"]]
    list [ini::get $merged s a] [ini::get $merged s b]
} -result {1 9}

test merge-with-empty-overlay {an empty overlay changes nothing} -body {
    ini::get [ini::merge [ini::parse "\[s\]\na = 1"] [ini::parse ""]] s a
} -result 1

test merge-is-immutable {merge leaves the base untouched} -body {
    set base [ini::parse "\[s\]\na = 1"]
    ini::merge $base [ini::parse "\[s\]\na = 9"]
    ini::get $base s a
} -result 1

test merge-chains {defaults, then site, then overrides} -body {
    set merged [ini::merge \
        [ini::merge [ini::parse "\[s\]\na = 1\nb = 1\nc = 1"] \
                    [ini::parse "\[s\]\nb = 2\nc = 2"]] \
        [ini::parse "\[s\]\nc = 3"]]
    list [ini::get $merged s a] [ini::get $merged s b] [ini::get $merged s c]
} -result {1 2 3}

# --- the reason these are not called set/unset -------------------------------

# A proc named `set` in this namespace would shadow the builtin for every other
# proc in it, since Tcl resolves an unqualified name in the current namespace
# first. ini::parse opens with `set result [dict create]`, so it would break.
test parse-still-works-after-mutators-exist {defining mutators did not shadow the builtin set} -body {
    ini::get [ini::parse "\[s\]\nk = v"] s k
} -result v

test mutators-round-trip-through-serialize {a mutated config serialises and reparses} -body {
    set c [ini::put [ini::put [ini::parse ""] server host example.com] server port 8080]
    set back [ini::parse [ini::serialize $c]]
    list [ini::get $back server host] [ini::get $back server port]
} -result {example.com 8080}

cleanupTests
