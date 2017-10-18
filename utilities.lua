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

local function appNameFromHint(hint)
  return string.match(hint,'([^:]+)%.app:$') or string.match(hint,'/([^/]+)%.app/?$') or hint
end

function M.restartApplication(hint)
  local appname, app
  appname = appNameFromHint(hint)
  if appname then app = hs.application.get(appname) end
  if app then
    app:kill()
    hs.timer.doAfter(3, function() hs.application.open(appname) end)
  else
    hs.alert('Couldn\'t find app for '.. appname)
  end
end

function M.applicationBundleID(hint)
  local appname = appNameFromHint(hint)
  local app = hs.application.get(appname)
  if app then
    local bid = app:bundleID()
    hs.pasteboard.setContents(bid)
    hs.alert(bid)
  else
    hs.alert('Couldn\'t make '.. appname ..' into an app with a bundleID')
  end
end

function M.hex_to_char(x)
  return string.char(tonumber(x, 16))
end
function M.unescape(url)
  return url:gsub("%%(%x%x)", M.hex_to_char)
end

return M
