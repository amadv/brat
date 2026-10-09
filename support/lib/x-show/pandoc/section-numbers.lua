local chapter = 0
local section = 0

function Header(el)
  local number

  if el.level == 2 then
    chapter = chapter + 1
    section = 0
    number = tostring(chapter)
  elseif el.level == 3 then
    section = section + 1
    number = chapter .. "." .. section
  else
    return nil
  end

  el.content:insert(1, pandoc.Space())
  el.content:insert(1, pandoc.Link(pandoc.Str(number), "#" .. el.identifier, "", { class = "number" }))
  return el
end
