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

function M.bundleID(hint)
  local app = hs.application.find(hint)
  local app_path = nil
  if app then
    app_path = app:path():gsub('(/Applications/[^.]+.app)/.*','%1')
  else
    app_path = "/Applications/"..hint..".app"
  end
  local command = 'mdls -name kMDItemCFBundleIdentifier -r '.. app_path
  print(command)

  return (hs.execute(command))
end

return M
