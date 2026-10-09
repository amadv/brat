# Brat Program Reference

Supplementary details for the `brat-program` skill.

## Test-runner helper API

Tests are `.brat` files run by the separate **Brat test runner**. Each file is a
POSIX shell script that sources your helpers and declares tests with `@test`:

```sh
#!/bin/sh
. "$DIR"/helpers.sh

@test "description of the behavior" {
  run "$MYPROG" somecommand arg1 arg2
  [ $status -eq 0 ]
  match "$stdout" '/expected/'
}
```

Inside a test body the runner provides:

| Name      | Meaning                                            |
|-----------|----------------------------------------------------|
| `run`     | Run a command, capturing its output and exit status |
| `$status` | Exit status of the last `run`                      |
| `$stdout` | Path to a file containing the last `run`'s stdout  |
| `$stderr` | Path to a file containing the last `run`'s stderr  |
| `match`   | `match <file> <awk-regex>` — assert a line matches |
| `compare` | `compare <file> <expected-file>` — diff two files  |
| `skip`    | Skip the current test with a reason                |

`$DIR` is the directory of the test file (provided by the runner).

Run tests with:

```sh
brat test/*.brat          # all tests
brat -j 4 test/foo.brat   # 4 parallel jobs
brat test/foo.brat:12     # a single test at line 12
```

## Quick scaffold script

A minimal end-to-end scaffold. Run from an empty directory with `brat.sh`
available (set `BRAT_SH` to its path):

```sh
#!/bin/sh
set -eu
prog="${1:?usage: scaffold <program-name>}"
: "${BRAT_SH:?set BRAT_SH to the path of brat.sh}"

mkdir -p "$prog/bin" "$prog/lib/$prog" "$prog/libexec"
cp "$BRAT_SH" "$prog/bin/$prog"
chmod +x "$prog/bin/$prog"

cat >"$prog/lib/$prog/_init.sh" <<'EOF'
USAGE="<COMMAND>"
VERSION="0.1.0"
EOF

cat >"$prog/lib/$prog/$prog.sh" <<'EOF'
alias self='"$SELF"'
alias error='self --- error "$0"'
alias usage='self --- usage "$0" "${USAGE:-}"'
EOF

cat >"$prog/libexec/$prog-hello" <<'EOF'
#!/bin/sh
set -eu
. myprog.sh
echo "hello!"
EOF
chmod +x "$prog/libexec/$prog-hello"

printf 'scaffolded %s\n' "$prog"
```

## Environment a command runs under

Brat exports these to every command:

| Variable       | Value                                                    |
|----------------|----------------------------------------------------------|
| `SELF`         | Absolute path to the router                              |
| `NAME`         | Basename of the invoked router (may be a namespace)      |
| `PROGRAM_NAME` | Basename of the real router                              |
| `ROOT`         | Program root (two levels above the router)               |
| `LIB`          | `$ROOT/lib/$NAME`                                        |
| `LIBEXEC`      | `$ROOT/libexec`                                          |
| `SHARE`        | `$ROOT/share/$PROGRAM_NAME`                              |
| `VENDOR`       | `$SHARE/vendor`                                          |

`PATH` is set to `$LIB:$LIBEXEC:$VENDOR:$PATH`, which is why commands can
`. myprog.sh` and why bundled executables in `vendor/` are resolvable.

## Optional hooks

- `$LIB/_init.sh` — sourced once before routing. Use it to set `USAGE`,
  `VERSION`, and any shared state. Namespaced invocations source both the root
  program's `_init.sh` and the namespace's `lib/<program>-<ns>/_init.sh`.
- `$LIB/_unhandled.sh` — sourced when no command matches, before Brat reports
  "command not found" or prints usage. Lets a program provide a default command.

## The special `---` argument

`myprog --- <executable> [args...]` runs an exact executable with the router's
environment, bypassing normal dispatch. Use it to call shared helpers
(`error`, `usage`) from commands, and to inspect state:

```sh
bin/myprog --- executables   # list executables the router can see
bin/myprog --- env           # environment commands run under
```
