local mt = { __index = table }
function Table(t)
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

table.clone = function(self)
  local out = {}
  for k,v in pairs(self) do
    if type(v) == 'table' then
      out[k] = table.clone(v)
    else
      out[k] = v
    end
  end
  return out
end

-- Shallow: `other`'s keys win, and table values are shared with the source
-- tables rather than copied (cf. table.clone, which is deep).
table.merge = function(self, other)
  local out = {}
  for k,v in pairs(self) do out[k] = v end
  for k,v in pairs(other or {}) do out[k] = v end
  return out
end

table.head = function(self)
  return self[1]
end

table.tail = function(self)
  return { select(2, table.unpack(self)) }
end

table.length = function(self)
  local count = 0
  for _ in pairs(self) do
    count = count + 1
  end
  return count
end
