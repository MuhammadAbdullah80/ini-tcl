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

## Tests

```
tclsh tests/ini_test.tcl
```

45 tests via `tcltest`.

One note for anyone extending them: Tcl dicts compare as their string
representation, which carries insertion order. Two dicts holding identical data
built in a different order are not `eq`, so the round-trip test compares
serialised text rather than the dicts themselves.

## License

MIT
