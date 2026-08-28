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

cleanupTests
