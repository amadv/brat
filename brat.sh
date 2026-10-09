#!/bin/sh
set -eu

# Brat Router for Unix Tools
# https://github.com/amadv/brat/$version$
# Copyright (c) Aaron Madved <aaron@madved.com>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# “Software”), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#|
#|
#| # Brat: Router for Unix Tools
#|
#| This is the annotated source code for Brat, the _Brat Router for Unix
#| Tools_, a single-file POSIX shell script for building Unix command-line
#| programs. It serves as the front-end executable for such a program,
#| dispatching (or “routing”) to a collection of commands based on its
#| filename and the first argument passed to it, a style popularized by the
#| Git CLI.
#|
#| | `$ myprog build --release`
#| |     ↓  [_your shell finds_ `myprog` _(Brat) somewhere in your_ `PATH`]{}
#| |   `bin/myprog build --release`
#| |     ↓  [_Brat extends _`PATH`_, finds _`myprog-build`_, and runs it_]{}
#| |   `libexec/myprog-build --release`
#|
#|
#| ## Introduction
#|
#| Using Brat, you can create programs that are highly portable, able to run
#| on any contemporary Unix system with no runtime dependencies other than the
#| [basic utilities specified by POSIX.1-2024][posix-utilities]. (Of course,
#| your programs may have their own runtime dependencies; that’s fine. But
#| everything in Brat adheres to the POSIX constraint.) That means you can run
#| your program on a wide range of hosts, from a Linux virtual machine, to a
#| BSD server, to a Mac laptop, to a tiny single-board computer, without
#| having to manage language runtimes or compile and trust binary executables.
#|
#| Brat encourages a style of shell scripting in which a program is broken
#| into many small executables and shared library files, arranged in a
#| conventional directory layout. It is an antidote to the wall you hit when
#| a single shell script starts to grow beyond a couple of hundred lines.
#| Because each command is a separate process, with arguments, standard I/O
#| streams, and an exit status, the larger program becomes a composition of
#| independently testable parts. That makes Brat a good fit for bootstrapping
#| build systems and managing infrastructural work, and a good alternative to
#| task runners and command-line application frameworks written in other
#| languages.
#|
#| As you will see, Brat is little more than a handful of functions and a set
#| of carefully chosen environment variables. It essentially just sets up the
#| `PATH`, then searches it to find what executable to run. From this core, in
#| about 120 lines of shell, Brat gives your program [commands][routing],
#| access to [shared scripts][environment], [error handling][errors],
#| [routing hooks][init-hook], [extensibility][commands-anywhere], and
#| support for grouping commands into [namespaces][namespaces].
#|
#| [posix-utilities]: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/contents.html
#|


#|
#| ## Initialization
#|
#| We begin by orienting ourselves in the environment.
#|
#| Before we make any other assignments, we save the current environment as
#| `OLDENV`. The program can [restore it later][restoring-environment] with
#| `eval` if it wants to run a program in the calling environment.
#|
# Get our bearings
OLDENV="$(unset OLDENV; export -p)"
#|
#| ### Identifying the Program
#|
#| Next we will find exactly where this copy of Brat lives on the filesystem.
#| We use this for two purposes: to figure out the name of the program, and to
#| locate all of the other files that make up the program.
#|
#| `$0` contains the path to the router as it was invoked. Any part of this
#| path might be a symbolic link, so we pass it to `realpath` to get its
#| actual location on the filesystem, and then store that as `SELF`.
#|
SELF="$(realpath "$0")"
#|
#| We then store the basename of `$0` as `NAME`, and the basename of `$SELF`
#| as `PROGRAM_NAME`. (The two can differ when working with
#| [namespaces][namespaces].)
#|
NAME="${0##*/}"
PROGRAM_NAME="${SELF##*/}"
#|
#| The `ROOT` directory is two levels up from the router. For example, if the
#| router lives at `/usr/local/bin/myprog`, `$ROOT` will be `/usr/local`.
#|
ROOT="${SELF%/*/*}"


#|
#| ### Establishing the Directory Structure
#|
#| Now we can set `LIB`, `LIBEXEC`, `SHARE`, and `VENDOR` relative to `$ROOT`.
#| A Brat program organizes its source files according to these conventions:
#|
#|     $ROOT
#|      ├── bin/
#|      │    └── myprog            $SELF
#|      ├── lib/
#|      │    └── myprog/           $LIB
#|      │         ├── _init.sh
#|      │         ├── myprog.sh
#|      │         └── ...
#|      ├── libexec/               $LIBEXEC
#|      │    ├── myprog-build
#|      │    ├── myprog-test
#|      │    └── myprog-...
#|      └── share/
#|           └── myprog/           $SHARE
#|                ├── ...
#|                └── vendor/      $VENDOR
#|
#| 1. The router (`$SELF`) lives in `$ROOT/bin/$PROGRAM_NAME`.
#| 2. Library files live in `$ROOT/lib/$NAME/`. These include shell scripts,
#|    makefiles, awk programs, sed expressions, and any other source code
#|    loaded by the program.
#| 3. Command executables live in `$ROOT/libexec/$NAME-*`. The router finds
#|    and dispatches to these commands. Since `libexec/` directories usually
#|    are not in the `PATH` in interactive shells, these executables are
#|    effectively hidden from users, who see only what’s in `bin/`.
#| 4. Documentation, examples, and other shared static data files live in
#|    `$ROOT/share/$PROGRAM_NAME/`.
#| 5. Bundled runtime dependencies go in `$ROOT/share/$PROGRAM_NAME/vendor/`.
#|
# Set up the environment
LIB="$ROOT/lib/$NAME"
LIBEXEC="$ROOT/libexec"
SHARE="$ROOT/share/$PROGRAM_NAME"
VENDOR="$SHARE/vendor"

#|
#| ### Extending the Environment
#|
#| With these variables set, we now insert ourselves at the front of the
#| `PATH`. We give the highest priority to `$LIB`, even though it normally
#| contains no executables, because the shell’s `.` command consults `$PATH`
#| when loading files; this ensures library files are never shadowed.
#| Following that, we add `$LIBEXEC`, where command executables live, and
#| `$VENDOR`, where bundled runtime dependencies live.
#|
PATH="$LIB:$LIBEXEC:$VENDOR:$PATH"
#|
#| The only other variable Brat exports to commands is `SELF`. This allows
#| commands to call back into the router for access to helper functions. (We
#| will explore [how commands call helpers][calling-helpers] further below.)
#|
export SELF

#|
#| Two variables, `USAGE` and `VERSION`, can be set by programs in the special
#| [`$LIB/_init.sh`][init-hook] file sourced by Brat before command dispatch.
#| The `USAGE` variable configures the top-level program synopsis displayed
#| when running `myprog` without an argument, or with an invalid command name.
#| The `VERSION` variable, if set, enables and configures the output of
#| `myprog --version`.
#|
USAGE="<COMMAND>"
unset VERSION


#|
#| ---
#|
#| ## Shared Helpers
#|
#| Now we define the Brat “standard library.” These functions are all used by
#| Brat itself, but they are also made available to commands.
#|
#|
#| ### The `error` and `usage` Helpers
#|
#| We’ll begin with the `error` helper, which displays an error message and
#| returns with a non-zero status. The first argument to `error` is the name
#| of or path to the current command, which will be formatted for display. The
#| remaining arguments are written to standard error, one per line.
#|
# ---
# Define shared helpers

error() {
  printf "%s: " "$(invocation "${1##*/}")"
  shift
  printf "%s\n" "$@"
  return 1
} >&2

#|
#| The `usage` helper displays information about which command-line arguments
#| the program accepts. Like `error`, the first argument is the name of or
#| path to the current command. The second argument is a one-line synopsis of
#| the program’s command-line grammar. Any subsequent argument is displayed on
#| its own line following the synopsis. All output is written to standard
#| error. The `usage` helper returns with a non-zero status.
#|
usage() {
  [ $# -gt 0 ] || set -- "$NAME" "${USAGE:-}" "commands: $(flatten commands)"
  printf "usage: %s " "$(invocation "${1##*/}")"
  shift
  printf "%s\n" "$@"
  return 1
} >&2

# ---

#|
#| When the router is invoked [without a command][no-command], or with an
#| [invalid command][invalid-command], Brat calls the `usage` helper without
#| any arguments. This prints a top-level synopsis for the program followed by
#| a list of available commands. Programs can set the `USAGE` variable in
#| [`$LIB/_init.sh`][init-hook] to customize the top-level synopsis.
#|
#|
#| ### Calling Helpers From Commands
#|
#| Helper functions defined in Brat do not propagate from the router down to
#| the program’s commands, but environment variables exported by the router
#| _do_.
#|
#| Recall that Brat [exports the `SELF` variable][environment], which contains
#| the full path to the router. This gives commands the ability to reinvoke
#| Brat. When combined with the special `---` argument, commands can call
#| helper functions defined _inside the router_. For example, to print an
#| error message and fail, a command could run the following:
#|
#|     "$SELF" --- error "$0" "file not found"
#|
#| (We will see how Brat [implements the `---` argument][three-hyphen] later
#| on.)
#|
#| Most Brat programs will want to call `error` or `usage` eventually. Rather
#| than having to write `"$SELF" ---` every time, programs may want to define
#| aliases in a shared script in `$LIB` and source it at the beginning of each
#| command. For example, a program might have a `lib/myprog/myprog.sh` file
#| containing the following:
#|
#|     alias self='"$SELF"'
#|     alias error='self --- error "$0"'
#|
#| And a command might use it like so:
#|
#|     #!/bin/sh
#|     set -eu
#|     . myprog.sh
#|     [ $# -gt 0 ] || error "missing filename"
#|
#| (There are two things to note about the implementation of this command.
#| First, it begins with `set -eu`, which you can think of as enabling the
#| shell’s “strict mode” — it tells the shell to exit at the first failure.
#| Second, it can source the shared script without specifying a directory
#| because `$LIB` is first in the command’s `PATH`.)
#|
#| The `usage` helper benefits from a similar alias, with a twist: expanding
#| the `USAGE` variable automatically as the second argument.
#|
#|     alias usage='self --- usage "$0" "${USAGE:-}"'
#|
#| This establishes a convention where each command can optionally declare its
#| usage synopsis once at the top of the file. Commands set `USAGE` once, then
#| call `usage` freely without arguments:
#|
#|     #!/bin/sh
#|     set -eu
#|     . myprog.sh
#|     USAGE="<FILENAME>"
#|     [ $# -eq 1 ] || usage
#|
#| ---
#|
#| The remaining helpers are used by Brat to enumerate commands, executables,
#| and namespaces, to resolve commands into executable paths, and to format
#| executable names for display.
#|
#|
#| ### The `awka` Helper
#|
#| In general, it is useful to be able to pass a shell value to an inline awk
#| script. Awk has a mechanism for this, `-v VAR=value`, but it is unsafe for
#| arbitrary input: in [assignment operands][awk-asop], backslashes become
#| escape sequences and values are not allowed to contain line breaks. The
#| alternative — interpolating values into the inline script — requires
#| careful string escaping.
#|
#| [awk-asop]: https://pubs.opengroup.org/onlinepubs/9799919799/utilities/awk.html#tag_20_06_05
#|
#| We will define a small helper, `awka`, for running an inline awk script
#| with a single argument automatically assigned to the variable `a`. The
#| first argument to `awka` is the value of `a` and the second argument is the
#| script to run. An `awka` invocation always reads from standard input.
#|
awka() {
  awk "BEGIN { ARGC = 1; a = ARGV[1] } $2" "$1"
}

#|
#| ### The `searchpath` Helper
#|
#| We have now reached the engine of Brat, the `searchpath` helper, which
#| wraps `find` to search the directories in `$PATH` for executables matching
#| specified criteria.
#|
#| The idea is to build a list of arguments that restrict `find` to just the
#| directories in `$PATH`, using a portable expression to simulate the
#| non-standard `-maxdepth` option. The argument list we build looks like:
#|
#|     ( ! -name * -o -path /bin -o -path /usr/bin ... ) -o -prune
#|
#| `! -name *` always evaluates to false. It acts as the head of a chain of
#| “or” expressions; each directory in the path maps directly to `-o -path`.
#| `-o -prune` on the grouped expression instructs `find` not to traverse
#| into a directory unless it is listed in this chain.
#|
searchpath() {
  #|
  #| We build the `find` expression by looping over every directory in `$PATH`
  #| and appending the corresponding expression arguments. Then we insert
  #| every directory in `$PATH` at the front, telling `find` to search just
  #| those directories without descending into subdirectories.
  #|
  { IFS=:
    dirs=
    set -- \) -o -prune "$@"
    for dir in $PATH; do
      [ -d "$dir" ] || continue
      set -- -o -path "$dir" "$@"
      dirs="$dirs:$dir"
    done
    set -- ${dirs#:} \( \! -name "*" "$@"
    unset IFS
  } 2>/dev/null

  #|
  #| Now we invoke `find -H` with the constructed argument list, followed by
  #| options restricting matches to executable files or links without `--` in
  #| the name, which Brat [considers private][private-executables]. We
  #| suppress `find`’s error messages and exit status; we only care about the
  #| paths it writes to standard output.
  #|
  find -H "$@" 2>/dev/null \
    \( -perm -001 -o -perm -010 -o -perm -100 \) \
    \( -type f -o -type l \) \
    \! -name "?*--?*" \
    -print || true
}

#|
#| ### About Namespaces
#|
#| Namespaces provide a way to group a subset of a program’s commands together
#| under another command. A namespace is simply a symbolic link pointing back
#| to the router. Executable names prefixed by the namespace become commands
#| under that namespace.
#|
#|     $ROOT
#|      ├── bin/
#|      │    └── myprog
#|      └── libexec/
#|           ├── myprog-...
#|           ├── myprog-env -> ../bin/myprog
#|           ├── myprog-env-list
#|           ├── myprog-env-run
#|           └── myprog-env-set
#|
#| In this example, `myprog env list` runs the `list` command in the `env`
#| namespace. Since `myprog-env` is a symlink to the router, Brat runs twice:
#|
#| | `$ myprog env list`
#| |     ↓ [_your shell finds_ `myprog` _in the_ `PATH`]{}
#| |   `bin/myprog env list`
#| |     ↓ [_Brat finds and runs_ `myprog-env`_, a symlink to itself_]{}
#| |   `libexec/myprog-env list`
#| |     ↓ [_the nested Brat invocation finds and runs_ `myprog-env-list`]{}
#| |   `libexec/myprog-env-list`
#|
#| Note that the nested Brat invocation is not a special mode. Brat starts
#| again at the top of the file, with the same `$SELF` and `$PROGRAM_NAME`,
#| but with `$NAME` now set to `myprog-env`.
#|
#|
#| ### The `namespaces` Helper
#|
#| Although it is not strictly necessary for command dispatch, we will define
#| a `namespaces` helper to enumerate all namespaces in the program. This lets
#| us filter commands by namespace elsewhere.
#|
namespaces() {
  #|
  #| We construct a dense but straightforward pipeline that begins by finding
  #| all symbolic links in `$PATH` whose names start with the prefix `$NAME-`.
  #| (For example, `namespaces` in `myprog` will look for symlinks named
  #| `myprog-*`.) We further restrict this list to links that point to
  #| `$SELF`. Then we pipe the resulting list to awk, which splits each line
  #| into fields by directory separator and prints the last field (i.e., the
  #| basename of each matched link). Finally, we sort and de-duplicate the
  #| list.
  #|
  searchpath -type l -name "${1:-$NAME}-*" \
    -exec sh -c '[ "$0" = "$(realpath "$1")" ] 2>/dev/null' "$SELF" {} \; \
    | awk -F / '{ print $NF }' | sort -u
}

#|
#| ### The `executables` and `commands` Helpers
#|
#| Next we define two helpers: `executables`, which lists the full path of
#| every executable belonging to the current namespace, and `commands`, which
#| lists just their command names.
#|
executables() {
  #|
  #| In order to scope the list to executables in the current namespace, we
  #| append an exclusion rule to the argument list for each descendent
  #| namespace. For a namespace named `myprog-env`, this rule looks like `!
  #| -name "myprog-env-*"`.
  #|
  for ns in $(namespaces "$NAME"); do
    set -- "$@" \! -name "$ns-*"
  done 2>/dev/null

  #|
  #| With the argument list constructed, we pass it to `searchpath`, along
  #| with a rule to restrict the search to executables matching the current
  #| prefix. Then we pipe the results to awk, which de-duplicates the list
  #| using each executable’s basename, keeping the first result and discarding
  #| subsequent matches with the same name elsewhere in `$PATH`.
  #|
  searchpath -name "$NAME-*" "$@" \
    | awk -F / '!a[$NF]++'
}

commands() {
  #|
  #| To list command names, we pipe the output of `executables` to an awk
  #| filter that strips the path and prefix and sorts the resulting list.
  #|
  executables \
    | awka ${#NAME} 'BEGIN { FS = "/" } { print substr($NF, a+2) }' | sort
}

#|
#| ### The `resolve` Helper
#|
#| In order to dispatch to a command, we need to be able to find its
#| corresponding executable. The `resolve` helper takes a command name as its
#| argument and prints the path to a matching executable in the current
#| namespace. If there is no match, it returns with a non-zero status.
#|
#| We define `resolve` instead of using the shell’s `command -v` for a couple
#| of reasons. The first is that we want to ensure the router only dispatches
#| to commands in the current namespace. Otherwise, `myprog env-list` would
#| incorrectly dispatch directly to the `list` command from the `env`
#| namespace without routing through that namespace.
#|
#| The other reason is that shells disagree in some edge cases about which
#| files `command -v` considers executable. Because `resolve` searches with
#| `searchpath`, like the other helpers, we ensure the router dispatches to
#| only those commands listed in the program’s usage message.
#|
resolve() {
  #|
  #| If the command name contains a hyphen, it’s possibly a command belonging
  #| to another namespace, so we rely on `executables` to filter the list.
  #| Otherwise, if the command name has at least one character, we can avoid
  #| the overhead of `executables` by calling `searchpath` directly. We pipe
  #| the results to awk, which prints the first matching executable.
  #|
  case "${1:-}" in
    *-* ) executables ;;
    ?* ) searchpath -name "$NAME-*"
  esac \
    | awka "$NAME-${1:-}" \
      'BEGIN { FS = "/" } $NF == a { print; s = 1; exit } END { exit !s }'
}

#|
#| ### The `invocation` Helper
#|
#| The `invocation` helper formats an executable name for display in error and
#| usage messages, turning e.g. `myprog-env-list` into `myprog env list`. It’s
#| not as simple as replacing every hyphen with a space, because command names
#| may contain hyphens of their own; instead, we list the program name and all
#| of its namespaces, ordered from longest to shortest, and use awk to replace
#| the hyphen following each name that appears at the start of the executable
#| name.
#|
invocation() {
  { printf "%s\n" "$PROGRAM_NAME"; namespaces "$PROGRAM_NAME"; } | sort -r \
    | awka "${1:-$NAME}" \
      'index(a, $0 "-") == 1 { a = $0 " " substr(a, length($0) + 2) }
       END { print a }'
}

#|
#| ### The `flatten` Helper
#|
#| We define a small `flatten` helper to replace newlines in a command’s
#| output with spaces. This is used to format the list of commands in usage
#| messages.
#|
flatten() {
  "$@" | { tr "\n" " "; printf "\n"; }
}

#|
#| ### The `version` Helper
#|
#| The `version` helper is used by Brat to display the program’s name and
#| version number when the router is [invoked with the `--version`
#| argument][three-hyphen]. Programs must set the `VERSION` variable in
#| [`$LIB/_init.sh`][init-hook].
#|
version() {
  printf "%s %s\n" "$PROGRAM_NAME" "$VERSION"
}

# ---


#|
#| ---
#|
#| ## Command Routing
#|
#| Finally, we reach the point where we put our helpers to use. We will scan
#| the argument list, identify which argument is the command name, and route
#| to that command’s corresponding executable, replacing the current process
#| and passing along all the other arguments.
#|
#|
#| ### The `_init.sh` Hook {#the-init-hook}
#|
#| Brat provides optional hooks on either side of the command dispatch process
#| so that programs can modify the router’s behavior. These hooks are shell
#| scripts that live in `$LIB` and have names that start with an underscore.
#|
#| The first hook is `$LIB/_init.sh`. We wait until this point to source it so
#| that it can call any of the helpers defined above and so it has a chance to
#| exit early or modify the argument list before routing.
#|
#| The `_init.sh` hook is also the place for a program to export any of the
#| variables set by Brat during initialization. Commands that want to
#| reference files in `$LIB`, for example, will not be able to use that
#| variable unless the program’s `_init.sh` exports it first.
#|
#| One other variable to note here is `OLDENV`, which contains the calling
#| environment captured at the beginning of this file. To make this captured
#| environment available to commands, [export its value in `_init.sh` as a new
#| variable][restoring-environment] with a name unique to your program.
#|
#| Because `$LIB` is [derived from `$NAME`][directory-structure], each
#| namespace has its own library directory and thus its own `_init.sh` hook.
#| When routing to a namespaced command, Brat sources both the root program’s
#| hook and the namespace’s hook.
#|
#| (Note that, because Brat replaces itself with the command it runs, there is
#| usually little point in defining functions or aliases in `_init.sh`. You
#| probably want to put those in a shared library file and explicitly source
#| it from each command as needed.)
#|
# Load _init.sh, if it exists
if [ -r "$LIB"/_init.sh ]; then
  . "$LIB"/_init.sh
fi


#|
#| ### The Special `---` Argument {#the-special-three-hyphen-argument}
#|
#| Earlier we alluded to a special `---` argument that allows commands to call
#| back into the router to run helpers. Now we will see how it works,
#| beginning with the implementation of the `--version` argument.
#|
#| If a program defines the `VERSION` variable in `_init.sh`, and is invoked
#| with `--version` as its sole argument, we replace that argument with `---
#| version`:
#|
# Rewrite `--version` to `--- version`
if [ $# -eq 1 ] && [ -n "${VERSION:-}" ] && [ "$1" = "--version" ]; then
  set -- --- version
fi


#|
#| Then, if the first argument to the router is exactly three hyphens (`---`),
#| we drop it, invoke the rest of the argument list as a command in the
#| router’s shell, and exit. So `--- version` calls the `version` helper using
#| the same mechanism that enables commands to call back into the router (e.g.
#| `"$SELF" --- version`).
#|
# When invoked as `--- <COMMAND> ...`, run that exact command and exit
if [ "${1:-}" = "---" ]; then
  [ $# -gt 1 ] && shift || usage
  "$@"
  exit
fi


#|
#| ### About Private Executables
#|
#| Brat provides a way to hide executables from the router so that they do not
#| become commands. These _private executables_ are distinguished by the
#| presence of two hyphens (`--`) anywhere in the name, such as
#| `myprog-build--compile`. The two-hyphen convention is enforced by the
#| [`searchpath` helper][searchpath], which means the router will never
#| dispatch to a private executable, and it will not appear in usage messages
#| or the output of the `commands` or `executables` helpers.
#|
#| Private executables allow Brat programs to more easily factor commands into
#| multiple files in `$LIBEXEC`. Recall that Brat [inserts `$LIBEXEC` at the
#| front of the `PATH`][environment] during initialization. Commands inherit
#| this environment and can therefore call any other executable in `$LIBEXEC`
#| directly.
#|
#| Because the special `---` argument does not go through the [`resolve`
#| helper][resolve], it can also be used to invoke private executables from
#| outside the program. This can be useful for testing or debugging.
#|
#|
#| ### Identifying the Command Name
#|
#| Brat takes a relatively hands-off approach to argument syntax. Aside from
#| the `--version` and `---` arguments, Brat does not impose any particular
#| ideas about option parsing, leaving it as a question for each program to
#| answer on its own.
#|
#| There is one notable exception: when looking for the argument that contains
#| the command to dispatch to, Brat skips over any arguments that start with a
#| hyphen. Then all arguments before or after the command name are passed to
#| the command in their original order.
#|
#| | INVOCATION                    |     | COMMAND   | ARGUMENTS        |
#| | ----------------------------- | --- | --------- | ---------------- |
#| | `myprog build a`              |     | `build`   | `a`              |
#| | `myprog -v build a`           |     | `build`   | `-v a`           |
#| | `myprog build -v a`           |     | `build`   | `-v a`           |
#| | `myprog --file=out.txt build` |     | `build`   | `--file=out.txt` |
#| | `myprog --file out.txt build` |  ×  | `out.txt` | `--file build`   |
#| | `myprog build --file out.txt` |     | `build`   | `--file out.txt` |
#|
#| This behavior is convenient, but be aware that it does not work for
#| argument pairs where the first is an option and the second is a value. Such
#| pairs cannot precede the command name in the argument list.
#|
#| (Programs that need more sophisticated control over argument processing are
#| encouraged to parse and rewrite the argument list in
#| [`_init.sh`][init-hook].)
#|
#|
#| ### Constructing the Argument List
#|
#| We will loop over every argument and build a shell expression in the `args`
#| variable that can be evaluated to produce a properly quoted argument list
#| for execution.
#|
#| | INVOCATION           | COMMAND | ARGUMENT LIST            |
#| | -------------------- | ------- | ------------------------ |
#| | `myprog build a`     | `"$1"`  | `'"${2}"'`               |
#| | `myprog -v build a`  | `"$2"`  | `'"${1}" "${3}"'`        |
#| | `myprog build -v a`  | `"$1"`  | `'"${2}" "${3}"'`        |
#| | `myprog build a b c` | `"$1"`  | `'"${2}" "${3}" "${4}"'` |
#|
# Scan the argument list to find the command name
COMMAND=
args=
index=0

for arg; do
  index=$((index+1))
  case "$arg" in
    #|
    #| If the argument starts with a hyphen, it can’t be a command name. Do
    #| nothing and leave the `case` statement.
    #|
    -* ) ;;
    #|
    #| If the argument is empty, or contains two consecutive hyphens, it’s not
    #| a valid command name. So if we haven’t already set `COMMAND`, we will
    #| print the usage message and exit. Otherwise, it’s just a regular
    #| argument, so we leave the `case` statement.
    #|
    ?*--?* | "" ) [ -n "$COMMAND" ] || usage ;;
    #|
    #| For any other argument, if we haven’t already set `COMMAND`, set it now
    #| and continue immediately to the next iteration without accumulating an
    #| entry in the argument list.
    #|
    * )
      if [ -z "$COMMAND" ]; then
        COMMAND="$arg"
        continue
      fi
  esac
  #|
  #| If we make it here, the argument is not a command name. Add an entry to
  #| the argument list.
  #|
  args="$args"' "${'"$index"'}"'
done


#|
#| ### Executing the Command
#|
#| Now that we have the command name in `$COMMAND`, we will pass it to the
#| [`resolve` helper][resolve], and if we find a matching executable, we will
#| run it.
#|
# Match the command name to an executable in the current namespace;
# if one exists, exec it
if executable="$(resolve "$COMMAND")"; then
  #|
  #| The `resolve` helper found a corresponding executable, so we’re ready to
  #| hand off control. First, we use `set --` in conjunction with `eval` to
  #| replace this process’s argument list with the `$args` we constructed.
  #|
  eval "set --$args"
  #|
  #| Now, we `exec` into the executable we found, passing along the arguments
  #| we just loaded. (The use of `exec` here is important to note. It means
  #| the current process is _replaced_ by the executable it invokes. In other
  #| words, Brat does not continue to run with the executable as a child
  #| process; the executable takes full control.)
  #|
  exec "$executable" "$@"
fi


#|
#| ### The `_unhandled.sh` Hook {#the-unhandled-hook}
#|
#| At this point, the `resolve` helper did not find a matching executable. We
#| now delegate to our second hook, `$LIB/_unhandled.sh`, by sourcing the file
#| if it exists.
#|
#| The `_unhandled.sh` hook gives programs the ability to implement default or
#| fallback behavior. For example, if the program is invoked without any
#| arguments, `_unhandled.sh` could choose to execute a default command
#| instead.
#|
#| Because the `_unhandled.sh` script runs inside the Brat process, it has
#| access to the variables set during argument processing (`COMMAND`,
#| `executable`, and `args`). It must `exec` or `exit` to avoid the “command
#| not found” error below.
#|
# No matching executable; load _unhandled.sh, if it exists
if [ -r "$LIB"/_unhandled.sh ]; then
  . "$LIB"/_unhandled.sh
fi


#|
#| ### When All Else Fails
#|
#| We tried our best, but we couldn’t match the command to an executable, and
#| either the program doesn’t have an `_unhandled.sh` script or it ran without
#| `exec`ing or `exit`ing. It’s time to say goodbye.
#|
# No matching command or no command specified
if [ -n "$COMMAND" ]; then
  #|
  #| Print the “command not found” message and exit with status code 127, the
  #| same status code the shell sets when an interactive command is not found.
  #|
  error "$0" "$COMMAND: command not found" || exit 127
fi

#|
#| When no command was specified, we print the top-level usage message and
#| exit with a non-zero status.
#|
usage

#|
#| ## Additional Notes
#|
#| Although Brat’s behavior follows from a few simple conventions, many of the
#| consequences are easy to miss. We will discuss some of them here. Keep them
#| in mind as you write your program.
#|
#|
#| ### Commands Can Live Anywhere in the `PATH`
#|
#| Brat searches the entire `PATH` for commands, not just the program’s
#| `libexec/` directory. That means anyone can add commands to your program
#| by installing properly named executables elsewhere in the `PATH`.
#|
#| For example, an executable `/usr/bin/myprog-lint` will be accessible as the
#| `myprog lint` command, and `lint` will appear in the program’s usage
#| message.
#|
#| Because Brat puts the program’s `libexec/` directory at the front of the
#| `PATH`, such additions can extend the program but not replace any of its
#| own commands.
#|
#|
#| ### Commands Can Be Written in Any Language
#|
#| A Brat program’s commands are just executables whose names conform to a
#| particular pattern. There is no rule that says these executables must be
#| shell scripts. For example, `libexec/myprog-build` could be written as a
#| Ruby script:
#|
#|     #!/usr/bin/env ruby
#|     require_relative "../lib/myprog/commands/build"
#|     Myprog::Commands::Build.run(ARGV)
#|
#| Obviously, this adds a dependency on the Ruby runtime to your program. That
#| may be acceptable to you. If you want to ensure the environment is properly
#| configured first, you can move the script to a [private
#| executable][private-executables] and call it from a shell script instead:
#|
#|     #!/bin/sh
#|     set -eu
#|     . myprog.sh
#|     command -v ruby >/dev/null || error "this command requires Ruby"
#|     exec myprog-build--run "$@"
#|
#| Consider taking advantage of the shell’s portability to show better error
#| messages when a runtime is unavailable, inspect the environment in more
#| detail, set additional environment variables, or possibly even bootstrap
#| the required environment using a package manager.
#|
#|
#| ### Commands Can Restore the Caller’s Environment
#|
#| The very first thing Brat does is capture the environment it was started
#| with and store it in the `OLDENV` variable. This is useful when a command
#| wants to run another program without the changes Brat and the program’s
#| [`_init.sh`][init-hook] have made to the environment, such as additions to
#| `PATH` or the export of `SELF`.
#|
#| To make the calling environment available to commands, export it from the
#| program’s root `_init.sh`, using a variable name unique to your program:
#|
#|     export MYPROG_OLDENV="${MYPROG_OLDENV-$OLDENV}"
#|
#| (Only the outermost invocation of Brat captures the caller’s real
#| environment. Namespaces and calls to `"$SELF"` run Brat again from inside
#| the program. Therefore, we preserve the existing value of `$MYPROG_OLDENV`
#| if it is already set, or fall back to `$OLDENV` otherwise.)
#|
#| A command can then use `eval` to restore the captured environment before
#| running another program, so that the command’s internal environment does
#| not leak:
#|
#|     #!/bin/sh
#|     set -eu
#|     eval "unset MYPROG_OLDENV SELF; $MYPROG_OLDENV" 2>/dev/null || true
#|     exec other-program "$@"
#|
#| (Some shells include environment variables with nonstandard names like
#| `a.b` in the output of `export -p`, even though assigning to those
#| variables results in an error. To work around this, programs should
#| redirect the evaluation’s standard error and override its return value.)
#|
#|
#| ### Routing Isn’t Free
#|
#| On each invocation, Brat programs must spend some amount of time searching
#| the filesystem for their commands. This is the price of Brat’s extreme late
#| binding, lack of configuration, and intentionally simple implementation.
#|
#| Searching for commands takes a small fraction of a second on contemporary
#| hardware with flash storage, compounded linearly with each namespace level.
#| As computers get faster, this overhead will get smaller.
#|
#| However, you should still be mindful of it. If you are running a command
#| many times per second in a tight loop, you may want to bypass routing by
#| implementing the loop itself as a command, calling the inner command
#| directly instead of through Brat.
#|
#|
#| ---
#|
#| ## Creating Brat Programs
#|
#| Now we’ll briefly walk through the steps for creating a new Brat program
#| named `myprog`. (Substitute `myprog` everywhere you see it with your
#| program’s own name.)
#|
#|
#| ### Setting Up the Filesystem
#|
#| First, create a directory to contain the program, then enter into it:
#|
#|     $ mkdir myprog
#|     $ cd myprog
#|
#| Next, create the [directories required by Brat][directory-structure]:
#|
#|     $ mkdir -p bin lib/myprog libexec
#|
#| Download or copy Brat to `bin/myprog`, then make it executable:
#|
#|     $ curl -sL https://github.com/amadv/brat/$version$ >bin/myprog
#|     $ chmod +x bin/myprog
#|
#| Finally, create [`_init.sh` and `myprog.sh`][init-hook] scripts:
#|
#|     $ touch lib/myprog/_init.sh lib/myprog/myprog.sh
#|
#| You may wish to add the [following aliases][calling-helpers] to
#| `myprog.sh`:
#|
#|     alias self='"$SELF"'
#|     alias error='self --- error "$0"'
#|     alias usage='self --- usage "$0" "${USAGE:-}"'
#|
#|
#| ### Running the Program
#|
#| During development, you can run your program from within its directory
#| using the relative path `bin/myprog`:
#|
#|     $ bin/myprog
#|     usage: myprog <COMMAND>
#|     commands: ...
#|
#|
#| ### Adding a Command
#|
#| We’ll add a new command, `hello`. First, save the following script to
#| `libexec/myprog-hello`:
#|
#|     #!/bin/sh
#|     set -eu
#|     . myprog.sh
#|     echo "hello!"
#|
#| Then, make it executable:
#|
#|     $ chmod +x libexec/myprog-hello
#|
#| Run `bin/myprog` to confirm `hello` appears in the list of commands:
#|
#|     $ bin/myprog
#|     usage: myprog <COMMAND>
#|     commands: ... hello ...
#|
#| Lastly, run the command itself:
#|
#|     $ bin/myprog hello
#|     hello!
#|
#|
#| ### Adding a Namespace
#|
#| We’ll add a namespace called `ns`. First, create the [namespace
#| symlink][namespaces] in `libexec/`:
#|
#|     $ ln -s ../bin/myprog libexec/myprog-ns
#|
#| Create a library directory for the namespace:
#|
#|     $ mkdir -p lib/myprog-ns
#|     $ touch lib/myprog-ns/_init.sh
#|
#| Now, add a `hello` command to the namespace. Save the following script to
#| `libexec/myprog-ns-hello`:
#|
#|     #!/bin/sh
#|     set -eu
#|     . myprog.sh
#|     echo "hello ns!"
#|
#| Make the command executable:
#|
#|     $ chmod +x libexec/myprog-ns-hello
#|
#| Verify that the namespace is reachable:
#|
#|     $ bin/myprog ns
#|     usage: myprog ns <COMMAND>
#|     commands: hello
#|
#| Finally, run the new namespaced command:
#|
#|     $ bin/myprog ns hello
#|     hello ns!
#|
#|
#| ### Seeing What the Router Sees
#|
#| You can use the [special `---` argument][three-hyphen] to see how the
#| router finds commands and modifies the environment. This may be especially
#| helpful when diagnosing why your program isn’t behaving as you expect.
#|
#| To see a list of all the executables in the current namespace:
#|
#|     $ bin/myprog --- executables
#|
#| To see the full environment commands will run under:
#|
#|     $ bin/myprog --- env
#|
#|
#| ---
#|
#| ## Versioning and Distribution
#|
#| Brat is feature-complete software. Although certainly there will be bugs to
#| fix and small improvements to make over time, there will be no major
#| features or changes beyond what you see here. For this reason, Brat’s
#| versions are content-addressed rather than numbered in sequence.
#|
#|
#| ### Computing the Version Number
#|
#| Brat’s version numbers are derived from the content hash of its non-empty,
#| non-comment lines of source code. Changes to comments or documentation do
#| not result in a new version.
#|
#| To compute the version number, first strip every line matching the extended
#| regular expression `^[[:blank:]]*(#|$)`. Then the version number is the
#| first six hexadecimal digits of the stripped source’s SHA-256 digest:
#|
#|     $ grep -vE '^[[:blank:]]*(#|$)' brat.sh | sha256sum | head -c 6
#|
#|
#| ### About the Literate Documentation
#|
#| The literate documentation you are reading now is generated from specially
#| formatted comments (`#| …`) embedded in the source code. An awk script
#| groups sections of code and prose together to build a document rendered by
#| [Pandoc][pandoc].
#|
#| The rendered HTML documentation, along with a copy of the distributable
#| `brat.sh` file, is published at `https://github.com/amadv/brat/<VERSION>`. Each version’s
#| URL is permanent, so you can always find the documentation for the exact
#| copy of Brat in your project. Visitors to `https://github.com/amadv/brat` will be
#| redirected automatically to the latest version.
#|
#| [pandoc]: https://pandoc.org
#|
#|
#| ### About the Distributable File
#|
#| The [distributable `brat.sh` file](brat.sh) is generated by removing every
#| literate documentation comment line from the source code, removing any
#| trailing empty lines from the resulting output, and appending the computed
#| version number to the URL in the opening comment block. This way, every
#| copy of Brat includes the address of the documentation for its own version.
#|
#|
#| ### Downloading Brat
#|
#| You can download Brat without a browser. When you fetch `https://github.com/amadv/brat`
#| from the command line with a tool like `curl` or `wget`, the server
#| responds with the latest distributable file instead of the documentation:
#|
#|     $ curl -sSL brat.sh
#|     $ curl -sSL https://github.com/amadv/brat
#|     $ wget -qO- https://github.com/amadv/brat
#|
#| This also works for downloading specific versions:
#|
#|     $ curl -sSL https://github.com/amadv/brat/$version$
#|     $ wget -qO- https://github.com/amadv/brat/$version$
#|
#|
#| ---
#|
#| ## See Also
#|
#| - [Brat][brat], the _Brat Runner for Automated Tests_, is a shell test
#|   runner targeting the same POSIX specification.
#| - [brat-pack][brat-pack] bundles a Brat program’s entire source tree into
#|   a single self-extracting, self-executing script.
#|   for building programs in the “bratty suckless unixy” style.
#|
#| [brat]: https://github.com/amadv/brat
#| [brat-pack]: https://github.com/amadv/brat-pack
#|
#| [calling-helpers]: #calling-helpers-from-commands
#| [commands-anywhere]: #commands-can-live-anywhere-in-the-path
#| [directory-structure]: #establishing-the-directory-structure
#| [environment]: #extending-the-environment
#| [errors]: #the-error-and-usage-helpers
#| [init-hook]: #the-init-hook
#| [invalid-command]: #constructing-the-argument-list
#| [namespaces]: #about-namespaces
#| [no-command]: #when-all-else-fails
#| [private-executables]: #about-private-executables
#| [resolve]: #the-resolve-helper
#| [restoring-environment]: #commands-can-restore-the-callers-environment
#| [routing]: #command-routing
#| [searchpath]: #the-searchpath-helper
#| [three-hyphen]: #the-special-three-hyphen-argument
#|
