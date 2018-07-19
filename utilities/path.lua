local M = {}

function M.parts(path)
  local dir, file =  string.match(path, '^(.-)[\\/]?([^\\/]*)$')
  return dir, file
end

function M.basename(path, suffix)
  local dir, file = M.parts(path)
  if suffix == nil then
    return file
  else
    local base = file:match('^(.+)'.. suffix ..'$')
    if base then return base else return file end
  end
end

function M.dirname(path)
  return (M.parts(path))
end

function M.extension(path)
  local _, ext = path:match('(.-[^\\/.])(%.[^\\/.]*)$')
  return ext
end

function M.script_path(level)
  local src
  if level then
    src = debug.getinfo(level,"S").source:sub(2)
  else
    local sources = {}
    for level=1,5 do
      src = debug.getinfo(level,"S").source:sub(2)
      table.insert(sources, src)
      if src:match("%.lua$") and not src:match("utilities%.lua$") then
        return src, src:match("(.+/)[^/]+")
      end
    end
    return nil, '{"'.. table.concat(sources, '","') ..'"}'
  end
  return src
end

return M
