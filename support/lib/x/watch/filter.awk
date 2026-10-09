BEGIN {
  FS = "\t"
  prefix = ENVIRON["BRAT_ROOT"] "/"
  prefix_len = length(prefix)
}

$0 == "===" {
  started = 1
  next
}

$0 == "---" {
  print
  fflush()
  next
}

$2 in sums && sums[$2] == $1 {
  next
}

{
  sums[$2] = $1
}

started {
  print substr($2, prefix_len + 1)
  fflush()
}
