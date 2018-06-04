-- !! Global changes !!
function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end
function string:chomp()
  local output = self:gsub("\n$", "")
  return output
end
function string:titleCase()
  return (self:gsub('^%l', string.upper))
end
