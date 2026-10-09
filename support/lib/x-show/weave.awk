/^[ \t]*#\|/ {
  if (prose_count && !in_prose) {
    print_section()
  }

  in_prose = 1

  if ($0 ~ /^[ \t]/) {
    prose_indented = 1
  }

  text = $0
  sub(/^[ \t]*#\|/, "", text)
  sub(/^ /, "", text)
  prose[++prose_count] = text

  next
}

{
  code[++code_count] = $0
  code_line[code_count] = NR
  code_tangled[code_count] = ++tangled_count
  in_prose = 0
}

END {
  print_section()
}

function first_nonblank(lines, count, __, i) {
  for (i = 1; i <= count && lines[i] ~ /^[ \t]*$/; i++) i
  return i
}

function last_nonblank(lines, count, __, i) {
  for (i = count; i >= 1 && lines[i] ~ /^[ \t]*$/; i--) i
  return i
}

function print_section(__, i, prose_first, prose_last, code_first, code_last, has_prose, has_code) {
  prose_first = first_nonblank(prose, prose_count)
  prose_last = last_nonblank(prose, prose_count)
  has_prose = prose_first <= prose_last

  code_first = first_nonblank(code, code_count)
  code_last = last_nonblank(code, code_count)
  has_code = code_first <= code_last

  if (has_prose || has_code) {
    print "<section>"

    if (has_prose) {
      print prose_indented ? "<div class=\"prose indented\">\n" : "<div class=\"prose\">\n"
      for (i = prose_first; i <= prose_last; i++) {
        print prose[i]
      }
      print "\n</div>"
    }

    if (has_code) {
      print "<div class=\"code\">"

      i = code_first
      while (i <= code_last) {
        printf "\n```{.sh .numberLines startFrom=\"%d\"}\n", code_tangled[i]
        print code[i]
        while (i < code_last && code_line[i + 1] == code_line[i] + 1) {
          print code[++i]
        }
        print "```\n"

        i++
        while (i <= code_last && code[i] ~ /^[ \t]*$/) {
          i++
        }
      }

      print "</div>"
    }

    print "</section>\n"
  }

  split("", prose)
  split("", code)
  split("", code_line)
  split("", code_tangled)
  prose_count = code_count = 0
  prose_indented = 0
}
