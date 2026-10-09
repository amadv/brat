---
name: brat-command
description: Add a command or namespace to an existing Brat program (a POSIX-shell CLI routed by brat.sh). Use when the user wants to add, create, or register a new subcommand, wire up a new namespace/group of commands, make an executable private, or extend an existing bin/libexec program built with Brat.
---

# Adding Commands and Namespaces to a Brat Program

In a Brat program, every **command is a separate executable** in `libexec/`
named `<program>-<command>`. The router finds commands by searching `PATH` and
dispatches by name — there is no central command registry to edit. Adding a
command means adding one file; adding a namespace means adding a symlink, a
library directory, and namespaced command files.

Read [../brat-program/SKILL.md](../brat-program/SKILL.md) first if the program
does not exist yet.

## Adding a command

### 1. Confirm the program layout

The program root contains `bin/<program>` (the router) and `libexec/`:

```
myprog/
├── bin/myprog
├── lib/myprog/          # shared scripts (_init.sh, myprog.sh, ...)
└── libexec/             # commands: myprog-<command>
```

### 2. Create the command executable

Write `libexec/myprog-<command>`. Source the program's shared script so the
`error`/`usage` helpers are available:

```sh
#!/bin/sh
set -eu
. myprog.sh

# ... command logic ...
```

Name the file exactly `<program>-<command>`. The command may be multiple words
only via a namespace (below); the executable name after the program prefix is
the single command token.

### 3. Make it executable

```sh
chmod +x libexec/myprog-<command>
```

The router only dispatches to executables with the execute bit set.

### 4. Verify

```sh
bin/myprog                 # the new command appears in "commands: ..."
bin/myprog --- executables # confirm the router can see the file
bin/myprog <command>       # run it
```

### Private commands

A command whose name contains `--` (e.g. `myprog-internal--helper`) is
**private**: the router will not list it and will not dispatch to it by name,
but it can still be run explicitly via the special argument:

```sh
bin/myprog --- myprog-internal--helper
```

Use private executables to factor a command into reusable pieces.

## Adding a namespace

A namespace groups commands under a subcommand, e.g. `myprog ns hello`.

### 1. Add the namespace symlink

The namespace is a symlink in `libexec/` pointing back at the router:

```sh
ln -s ../bin/myprog libexec/myprog-ns
```

This makes `myprog ns ...` re-invoke the router in the `ns` namespace.

### 2. Add the namespace library directory

```sh
mkdir -p lib/myprog-ns
touch lib/myprog-ns/_init.sh
```

Brat sources the namespace's `_init.sh` in addition to the root program's.
Use it for namespace-specific `USAGE`/setup.

### 3. Add namespaced commands

Namespaced commands are named `<program>-<ns>-<command>`:

```sh
#!/bin/sh
set -eu
. myprog.sh
echo "hello from ns!"
```

```sh
chmod +x libexec/myprog-ns-hello
```

### 4. Verify

```sh
bin/myprog ns         # usage: myprog ns <COMMAND>  /  commands: hello
bin/myprog ns hello   # hello from ns!
```

## Best practices

- **One file per command.** Keep commands small; move shared logic into `$LIB`.
- **Source the shared script first.** `. myprog.sh` gives you `error`, `usage`,
  and any project helpers. (It resolves because Brat puts `$LIB` on `PATH`.)
- **Quote variables** and keep everything POSIX (`#!/bin/sh`, `set -eu`).
- **Report errors consistently.** Prefer the shared `error`/`usage` helpers so
  exit statuses and message formats match the rest of the program.
- **Handling an unknown command as a default:** if the program should do
  something other than print usage/not-found, add `$LIB/_unhandled.sh` — it runs
  when no command matches, before Brat falls back.
- **Do not edit `bin/<program>`** to register a command. Dispatch is by filename;
  editing the router is almost never what you want.

## Adding a test

Add a `.brat` test alongside the existing ones and run it with the test runner:

```sh
@test "myprog <command> does the thing" {
  run "$MYPROG" <command>
  [ $status -eq 0 ]
  match "$stdout" '/expected/'
}
```

```sh
brat test/*.brat
```

See [the test helper API](../brat-program/reference.md#test-runner-helper-api)
for `run`, `match`, `compare`, and the `$status`/`$stdout`/`$stderr` variables.

## Pitfalls

- The executable name must be exactly `<program>-<command>`; a typo means the
  router silently won't find it. Confirm with `bin/myprog --- executables`.
- Forgetting `chmod +x` makes a command invisible to the router.
- A namespace symlink must point at the router (`../bin/myprog`), not at another
  command.
- Names mentioned in a namespace are excluded from the parent's command list, so
  `myprog hello` and `myprog ns hello` are distinct commands.
