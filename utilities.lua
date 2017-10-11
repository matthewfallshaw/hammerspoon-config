local logger = hs.logger.new("Utilities")
logger.i("Loading Utilities")

local M = {}

function M.log_and_alert(logger, message)
  logger.i(message)
  hs.alert.show(message)
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
    return nil, "{\"".. table.concat(sources, "\",\"") .."\"}"
  end
  return src
end

return M
