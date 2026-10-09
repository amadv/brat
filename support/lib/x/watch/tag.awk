$0 == "brat.sh#code" {
  tags["code"]
}

$0 == "brat.sh#prose" {
  tags["prose"]
}

/^site\// {
  tags["site"]
}

/^support\// {
  tags["support"]
}

/^test\// {
  tags["test"]
}

$0 == "---" {
  count = 0
  for (tag in tags) {
    printf "%s ", tag
    count++
  }
  if (count) print ""

  split("", tags)
  fflush()
}
