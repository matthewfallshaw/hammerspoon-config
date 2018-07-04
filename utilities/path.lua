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

return M
