# AGENTS.md

Guidance for AI agents working in this repository.

## What this project is

**Brat** is a single-file, POSIX shell script that acts as the front-end
executable ("router") for a Unix command-line program. It dispatches to a
collection of commands based on its own filename and the first argument it
receives — the same style popularized by the Git CLI.

The entire router is [`brat.sh`](brat.sh), which is simultaneously:

- the **distributable program** (what users download and rename to `bin/myprog`), and
- the **literate documentation** (the annotated manual, generated from `#|` comments).

The repository also contains the project's own build tool (`x`, a Brat program
in [`support/`](support/)), the static web site ([`site/`](site/)), and the test
suite ([`test/`](test/)).

## Repository layout

```
brat.sh                 The router + annotated docs (single source of truth)
x                       Symlink to support/bin/x (the build tool's router)
support/                The `x` build tool, itself a Brat program
  bin/x                 Router for the `x` program (built from brat.sh)
  lib/x/                Shared scripts for `x` (_init.sh, x.sh, Makefile, ...)
  libexec/x-*           Commands of the `x` program (build, test, watch, ...)
  lib/x-show/           Pandoc/awk sources for generating the docs site
  share/x/vendor/brat   Bundled third-party Brat *test runner* (do not edit)
site/                   Static web site (template, CSS, fonts, edge functions)
test/                   Test suite, written in Brat (.brat files) + fixtures
  *.brat                Test files
  helpers.sh            Shared test helpers
  setup                 Copies the built router into the test fixture
  fixtures/             A sample "myprog" program used by the tests
```

## Build and test commands

Run everything through the `x` build tool (via the `./x` symlink):

```sh
./x build      # build the static web site into dist/
./x preview    # build the annotated source for the working copy; open in browser
./x test       # run the test suite against the distributable built from the working copy
./x watch      # rebuild preview + rerun tests as you edit
./x clean      # remove build output (build/, dist/)
./x stats      # code/prose/dist size stats and the content-addressed version
./x show ...   # internal: extract code/prose/dist/page from a source file
./x version    # print the content-addressed version (6 hex digits)
```

Useful dependencies: **Git, make, Pandoc, sha256sum** to build; `fswatch`
for `./x watch`; `xdg-open` (non-macOS) for `./x preview`.

To run the test suite you need a `brat` **test runner** on `PATH`. One is
bundled at `support/share/x/vendor/brat`; `./x test` wires it up for you.
To test a specific router build, set `BRAT` to its path: `BRAT=./brat.sh ./x test`.

### Testing

- The suite is written in the Brat test-runner DSL (`.brat` files). Each test
  uses `@test "name" { ... }` with helpers such as `run`, `match`, `compare`,
  and the `$status`, `$stdout`, `$stderr` variables. See [`test/routing.brat`](test/routing.brat)
  for the canonical style.
- `test/helpers.sh` defines `$MYPROG`, `$MYPROG_ROOT`, `$MYPROG_PATH`, and
  `install()`.
- Tests execute against a **built** copy of the router placed in
  `test/fixtures/myprog/bin/myprog` (created by `test/setup`), not against `brat.sh` directly.
- Expected-output fixtures live under `test/fixtures/output/`.

## Editing `brat.sh` (important conventions)

`brat.sh` is a **literate program**. Prose documentation and code are
interleaved in one file:

- Lines beginning with `#|` are **prose** (rendered as the manual).
- All other lines are **code** (the distributable).
- `#| #`, `#| ##`, `#| ###` are headings. Some headings carry explicit anchors,
  e.g. `#| ### The `_init.sh` Hook {#the-init-hook}`.
- Reference-style links (`[routing]: #identifying-the-command-name`) are defined
  in the prose; keep them in sync with heading anchors.

Because versioning is **content-addressed**, changing only comments/prose does
not change the version, but changing any code line does. The distributable is
produced by stripping every `#|` line, trimming trailing blank lines, and
substituting the computed version into the `$version$` placeholder in the header.

When editing:

- Keep prose and the code it documents adjacent and consistent.
- Do not reflow or "tidy" unrelated prose; the diff should stay minimal.
- Keep the file POSIX-compliant (`#!/bin/sh`, `set -eu`, no bashisms).

## Constraints and conventions

- **POSIX only.** The router must run under `sh` with awk, find, realpath,
  sort, and tr available. No bash-specific syntax, no GNU-only flags.
- Tested on Alpine (busybox ash/awk), Debian (dash/mawk), Fedora (bash/gawk),
  FreeBSD (ash/nawk), and macOS (bash 3.2/nawk). See [`.forgejo/workflows/ci.yml`](.forgejo/workflows/ci.yml).
- Commands are executables named `<program>-<command>` in `libexec/`; the router
  finds them by searching `PATH`.
- Namespaces are symlinks back to the router (e.g. `libexec/myprog-ns`), enabling
  nested routing such as `myprog ns hello`.

## Pitfalls

- `support/share/x/vendor/brat` is a **bundled third-party artifact** (the Brat
  test runner, built with brat-pack). Do not edit it by hand; replace it wholesale
  if an upgrade is needed.
- Do not add new functionality to the router casually — it is intentionally
  feature-complete. Bug fixes and documentation improvements are the norm.
- `dist/` and `build/` are generated and git-ignored; never commit them.
- The `x` build tool depends on `BRAT_ROOT` being set (done by its `_init.sh`).

## Agent skills

Project-scoped skills live in [`.agents/skills/`](.agents/skills/). Load the
relevant one before starting matching work:

- **`brat-program`** — scaffold a brand-new Brat program (directory layout,
  router, `_init.sh`, first command/namespace, tests).
- **`brat-command`** — add a command or namespace to an existing Brat program.
