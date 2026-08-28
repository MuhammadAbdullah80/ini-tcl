# ini

A strict INI/config reader and writer for Tcl. One file, no dependencies
outside the core.

```tcl
package require ini

set config [ini::parse [read $fh]]

ini::get $config server host localhost
ini::get $config server port 8080
ini::sections $config
```

Parsed configuration is a plain Tcl dict of `section -> key -> value`, so
anything `dict` can do works on it directly. Keys written before any section
header live in the section named `""`.

## API

| Command | Returns |
| --- | --- |
| `ini::parse text` | dict of section -> key -> value; throws on a malformed line |
| `ini::get config section key ?default?` | the value, or `default` |
| `ini::exists config section key` | 1 or 0 |
| `ini::sections config` | section names, global first if used, then sorted |
| `ini::keys config section` | keys in the order they were written |
| `ini::serialize config` | INI text |
| `ini::put config section key value` | a copy with the key set |
| `ini::remove config section key` | a copy without that key |
| `ini::remove_section config section` | a copy without that section |
| `ini::merge base overlay` | a copy of base with overlay applied per key |
| `ini::read_file path` | parse a file |
| `ini::write_file path config` | serialise and write, atomically |

## Decisions

**Malformed lines throw.** A line that is neither a comment, a section header
nor `key = value` raises an error naming the line number. A config file that
loads half-applied is worse than one that refuses to load, because the process
then starts on defaults nobody chose.

**Comments are only recognised at the start of a line.** An inline `;` or `#` is
kept as data:

```ini
url = http://example.com/page#section
colour = #ff0000
```

Both of those are real values. Treating `#` as an inline comment would silently
truncate them, and silent truncation of a config value is very hard to debug.
Put a comment on its own line.

**Quotes preserve whitespace.** `key = "  padded  "` keeps its spaces; bare
values are trimmed. One layer of matching double quotes is removed, so
`key = ""inner""` yields `"inner"`. An unmatched quote is data.

**Last assignment wins** for a duplicate key, matching every INI reader users
have already met. Re-entering a section adds to it rather than replacing it.

**Serialising is idempotent.** Values whose whitespace or leading punctuation
would not survive a round trip are quoted on the way out, so
`serialize(parse(serialize(parse(x))))` equals `serialize(parse(x))`.

Comments and original ordering are *not* preserved - this parses configuration,
it is not a round-tripping editor.

## Mutation

Every mutator returns a new dict; nothing is modified in place.

```tcl
set config [ini::put $config server port 9090]
set config [ini::remove $config server legacy_flag]

# defaults, then site file, then overrides
set effective [ini::merge [ini::merge $defaults $site] $overrides]
```

`ini::merge` combines per key, not per section — a section present in both keeps
the base's keys except where the overlay names one.

They are called `put` and `remove` rather than `set` and `unset` for a concrete
reason: Tcl resolves an unqualified command name in the current namespace before
the global one, so a proc named `ini::set` shadows the builtin `set` for every
other proc in the namespace. `ini::parse` opens with `set result [dict create]`
and would break with a wrong-arg-count error.

## Files

```tcl
set config [ini::read_file /etc/myapp.ini]
set config [ini::put $config server port 9090]
ini::write_file /etc/myapp.ini $config
```

Both force the channel to utf-8 with lf translation rather than trusting the
platform default, so a file written on Windows and read on Linux gives the same
values.

`write_file` writes a sibling temp file and renames it into place. A half-written
config is worse than no config: whatever reads it next either fails to parse or,
worse, parses a truncated file and starts with settings silently missing. The
rename is atomic within a filesystem, which is why the temp file is a sibling
rather than in `/tmp`.

## Tests

```
tclsh tests/ini_test.tcl
```

76 tests via `tcltest`.

One note for anyone extending them: Tcl dicts compare as their string
representation, which carries insertion order. Two dicts holding identical data
built in a different order are not `eq`, so the round-trip test compares
serialised text rather than the dicts themselves.

## License

MIT
