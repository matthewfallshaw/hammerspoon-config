-- String escapes
--
-- Require with `local escape, unescape = require('utilities.string_escapes')()`

local escape, unescape = {}, {}

function escape.hex_to_char(x)
  return string.char(tonumber(x, 16))
end

function unescape.url(url)
  return url:gsub("%%(%x%x)", escape.hex_to_char)
end

function escape.for_regexp(str)
  return (str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"))
end


return function() return escape, unescape end
