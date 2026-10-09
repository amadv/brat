---
name: brat-program
description: Scaffold a brand-new Brat program from scratch — the POSIX-shell CLI router. Use when the user wants to create, start, bootstrap, or initialize a new Brat project or command-line tool, set up bin/lib/libexec directories, write a first command and namespace, or generate a starting test suite for a shell CLI.
---

# Creating a Brat Program

Brat is a single-file POSIX shell script that acts as the front-end "router"
for a Unix CLI. You drop the router into `bin/<program>`, add small executables
under `libexec/<program>-<command>`, and Brat dispatches to them by name. This
skill scaffolds a working program with its conventional layout, a first command,
a namespace, and a test.

For background on the router's internals, read [`brat.sh`](../../../brat.sh);
this skill is about *using* it to build a new program.

## Instructions

### 1. Choose the program name

Pick a short kebab-case name (the programs it will be invoked as), e.g.
`myprog`. Substitute it for `myprog` everywhere below. Command executables are
named `<program>-<command>`.

### 2. Create the directory structure

```sh
mkdir myprog
cd myprog
mkdir -p bin lib/myprog libexec
```

The layout Brat expects:

```
myprog/
├── bin/
│   └── myprog            # the router ($SELF)
├── lib/
│   └── myprog/           # shared library files ($LIB)
│       ├── _init.sh      # optional init hook (sets USAGE, VERSION, ...)
│       └── myprog.sh     # shared helpers/aliases for commands
└── libexec/              # command executables ($LIBEXEC)
    └── myprog-<command>
```

### 3. Install the router

Copy the distributable router to `bin/myprog` and make it executable. Either
download the latest release or copy the local `brat.sh`:

```sh
cp /path/to/brat.sh bin/myprog     # or: curl -sL https://github.com/amadv/brat >bin/myprog
chmod +x bin/myprog
```

The router infers everything from its own filename and location, so the copied
file **must** be named exactly `myprog` in `bin/`.

### 4. Create the library files

`lib/myprog/_init.sh` is sourced by Brat before dispatch. Set `USAGE` and,
optionally, `VERSION`:

```sh
# lib/myprog/_init.sh
USAGE="<COMMAND>"
VERSION="0.1.0"
```

`lib/myprog/myprog.sh` holds helpers and the call-back aliases that commands
source:

```sh
# lib/myprog/myprog.sh
alias self='"$SELF"'
alias error='self --- error "$0"'
alias usage='self --- usage "$0" "${USAGE:-}"'
```

The aliases use the special `---` argument to call back into the router's shared
helpers (`error`, `usage`) from a command.

### 5. Add the first command

Create `libexec/myprog-hello` and make it executable:

```sh
#!/bin/sh
set -eu
. myprog.sh
echo "hello!"
```

```sh
chmod +x libexec/myprog-hello
```

The `. myprog.sh` line works because Brat puts `$LIB` at the front of `PATH`.

### 6. Add a namespace (optional)

A namespace is a symlink from a `libexec/<program>-<ns>` name back to the
router, plus a matching `lib/` directory:

```sh
ln -s ../bin/myprog libexec/myprog-ns
mkdir -p lib/myprog-ns
touch lib/myprog-ns/_init.sh
```

Then add namespaced commands named `libexec/myprog-ns-<command>`:

```sh
#!/bin/sh
set -eu
. myprog.sh
echo "hello from ns!"
```

```sh
chmod +x libexec/myprog-ns-hello
```

This enables `myprog ns hello`, with nested routing handled by invoking the
router again through the symlink.

### 7. Run and verify

```sh
bin/myprog                 # usage: myprog <COMMAND>  /  commands: hello ...
bin/myprog hello           # hello!
bin/myprog ns              # usage: myprog ns <COMMAND>
bin/myprog ns hello        # hello from ns!
bin/myprog --- executables # what the router can see
bin/myprog --- env         # the environment commands run under
```

### 8. Add a test suite (recommended)

Create `test/` with `.brat` test files and a `helpers.sh`. The Brat **test
runner** (a separate tool from this router) executes them:

```sh
# test/helpers.sh
FIXTURE_DIR="$DIR"
cd "$FIXTURE_DIR"
MYPROG="myprog/bin/myprog"
```

```sh
#!/bin/sh
. "$DIR"/helpers.sh

@test "runs the hello command" {
  run "$MYPROG" hello
  [ $status -eq 0 ]
  match "$stdout" '/^hello!$/'
}
```

Run them with the bundled runner:

```sh
brat test/*.brat
```

See the reference for the full helper API and a scaffold script:
[reference.md](reference.md).

## Best practices

- **One command, one executable.** Keep each `libexec/` file small and focused;
  factor shared logic into `$LIB`.
- **Name files exactly right.** Commands are `<program>-<command>`; namespaced
  commands are `<program>-<ns>-<command>`. Anything containing `--` is treated as
  private and hidden from the command list.
- **POSIX shell only.** Use `#!/bin/sh`, `set -eu`. No bashisms.
- **Quote everything.** The router relies on strict quoting; so should your
  commands.
- **Use `error`/`usage`.** Call the shared helpers so messages and exit statuses
  stay consistent with Brat conventions.
- **Don't reimplement dispatch.** Let the router extend `PATH` and find commands;
  do not hand-roll argument parsing of the command name.

## Requirements

- A POSIX shell and the standard utilities Brat needs: `awk`, `find`,
  `realpath`, `sort`, `tr`.
- To run `.brat` tests: a `brat` test runner on `PATH` (bundled at
  `support/share/x/vendor/brat` in the Brat source repo).
