alias self='"$SELF"'
alias error='self --- error "$0"'
alias usage='self --- usage "$0" "${USAGE:-}"'

infile() {
  infile="${1:-$BRAT_ROOT/brat.sh}"
  [ "$infile" = "-" ] || [ -r "$infile" ] || error "$infile: no such file"
}
