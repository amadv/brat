function Str(elem)
  local text = elem.text
  local letters = text:gsub("[^A-Za-z]", "")
  if #letters >= 2 and letters:match("^[A-Z]+$") then
    return pandoc.SmallCaps { pandoc.Str(text) }
  end
end
