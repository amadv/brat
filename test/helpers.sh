FIXTURE_DIR="$DIR"/fixtures
cd "$FIXTURE_DIR"

MYPROG_DIR=myprog
MYPROG="$MYPROG_DIR"/bin/myprog
MYPROG_PATH="$(realpath "$MYPROG")"
MYPROG_ROOT="$(realpath "$MYPROG_DIR")"

install() {
  printf "%s\n" "#!/bin/sh" "set -eu" >"$1"
  chmod +x "$1"
}
