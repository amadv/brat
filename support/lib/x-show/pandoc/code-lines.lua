local options

function CodeBlock(el)
  if not el.classes:includes("numberLines") then
    return nil
  end

  options = options or pandoc.WriterOptions {
    highlight_style = PANDOC_WRITER_OPTIONS.highlight_style,
  }

  el.identifier = "code" .. el.attributes.startFrom
  local html = pandoc.write(pandoc.Pandoc { el }, "html", options)

  return pandoc.RawBlock("html", (html:gsub('<span id="[^"]*%-(%d+)"><a href="[^"]*"',
    '<span id="L%1"><a href="#L%1" data-line="%1" aria-label="Line %1" tabindex="-1"')))
end
