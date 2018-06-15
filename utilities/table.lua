local mt = { __index = table }
function T(t)
  return setmetatable(t or {}, mt)
end

table.keys = function(self)
  local keys,i = {},0
  for k,_ in pairs(self) do
    i = i + 1
    keys[i] = k
  end
  return keys
end

table.values = function(self)
  local values,i = {},0
  for _,v in pairs(self) do
    i = i + 1
    values[i] = v
  end
  return values
end
