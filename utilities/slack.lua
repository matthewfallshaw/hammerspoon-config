--- === Slack utilities ===
--- Ulitities for manipulating Slack
--- 
--- Currently just `setStatus(location)`

local obj = {}

-- Metadata
obj.name = "Slack"
obj.version = "1.0"
obj.author = "Matthew Fallshaw <m@fallshaw.me>"
obj.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj._logger = hs.logger.new("Slack")
local logger = obj._logger
logger.i("Loading Slack")

local function fileExists(filepath) return hs.fs.attributes(filepath, 'mode') == 'file' end
local cli = '~/bin/slack-status'
if not fileExists(cli) then
  error("I can't find ".. cli .." which I need to function. Install "..
  "https://github.com/matthewfallshaw/utilities/blob/master/shell/slack-status"..
  " there (insert your API token and `chmod u+x ...`).")
end

function obj.setStatus(location)
  if location == '' then
    logger.i('Slack status -')
  else
    logger.i('Slack status ' .. location)
  end

  -- recreate the retry fuction so that it captures the right `location`
  local function setStatusRetry(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then  -- if task fails, try again after 30s
      logger.w('Slack status update failed - exitCode:' .. tostring(exitCode) ..
        " stdOut:" .. tostring(stdOut) .. " stdErr:" .. tostring(stdErr)
      )
      hs.timer.doAfter(30,
        function() hs.task.new(cli, setStatusRetry, {location}) end
      ):start()
    else
      logger.i('Slack status update successful')
    end
  end

  hs.task.new(cli, setStatusRetry, {location}):start()
end

return obj
