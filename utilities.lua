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

function M.hex_to_char(x)
  return string.char(tonumber(x, 16))
end
function M.unescape(url)
  return url:gsub("%%(%x%x)", M.hex_to_char)
end

function M._escape_for_regexp(str)
  return (str:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1"))
end

function M.table_keys(t)
  local ret, n = {}, 0
  for k,v in pairs(t) do
    n=n+1
    ret[n] = k
  end
  return ret
end

function M.table_values(t)
  local ret, n = {}, 0
  for k,v in pairs(t) do
    n=n+1
    ret[n] = v
  end
  return ret
end

function M.log_to_file(message, file)
  local file_path = file or "/var/log/com.matthewfallshaw.activities.log"

  local output_file = assert(io.open(file_path, "a+"))

  output_file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. tostring(message) .."\n")

  output_file:close()
  return true
end

function M.functionWithTimes(fn, ...)
  logger.w(hs.timer.secondsSinceEpoch())
  result = table.pack(fn(...))
  logger.w(hs.timer.secondsSinceEpoch())
  return table.unpack(result)
end
function M.profilingOn()
  debug.sethook(function (event)
    local x = debug.getinfo(2, 'nS')
    print(event, x.name, x.linedefined, x.source, hs.timer.secondsSinceEpoch())
  end, "c")
end
function M.profilingOff()
  debug.sethook()
end

return M
