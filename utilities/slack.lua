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

local function retry_fn(try_count)
  local setStatusRetry = function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then  -- if task fails, try again after 30s
      logger.w('Slack status update failed - exitCode:' .. tostring(exitCode) ..
      " stdOut:" .. tostring(stdOut) .. " stdErr:" .. tostring(stdErr)
      )
      if try_count < 5 then
        hs.timer.doAfter((try_count == 1) and 30 or (2^(try_count-1) * 60),
          function() hs.task.new(cli, setStatusRetry, {location}) end
        ):start()
      end
    else
      logger.i('Slack status update successful')
    end
  end
  return setStatusRetry
end


function obj.setStatus(location, try_count)
  if not try_count then try_count = 1 end

  if location == '' then
    logger.i('Slack status -')
  else
    logger.i('Slack status ' .. location)
  end

  hs.task.new(cli, retry_fn(try_count), {location}):start()
end

return obj
