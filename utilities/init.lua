local logger = hs.logger.new("Utilities")
logger.i("Loading Utilities")

-- Module utilities

local M = {}

local function appNameFromHint(hint)
  -- Quicksilver/Applescript produces items like:
  --   Macintosh HD:Applications:MacVim.app:
  --   Macintosh HD:Applications:Utilities:Script Editor.app:
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

return M
