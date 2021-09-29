--- === Chrome Tab Tools ===
---
--- Focus tabs or windows in Google Chrome

local M = {}

-- Metadata
M.name = 'ChromeTabs'
M.version = "0.2"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
M.homepage = "https://github.com/matthewfallshaw/chrome-tabs-finder"

local json = require "utilities.dkjson"

local logger = hs.logger.new("ChromeTabT")
M._logger = logger

hs.window.__type = 'hs.window'


-- ## Internal
local function sendMessage(msg)
  local response

  if not msg then
    response = hs.execute("~/bin/chrome-client getAllTabs")
  else
    response = hs.execute("~/bin/chrome-client '".. msg:gsub("'", "\\'") .."'")
  end

  if not string.match(response, '^ *$') then hs.alert(response) end
end


-- ## Public
--[[
  { focus = {↓} }
  { focusWindowContaining = {↓} }

  {
    title = "",
    url = "",
    not_title = "",
    not_url = "",
  }
]]
function M.sendCommand(cmd)
  sendMessage(json.encode(cmd))
end


local client = hs.socket.new()
local TAG_HTTP_HEADER, TAG_HTTP_CONTENT = 1, 2
local function httpCallback(data, tag)
  print(tag, "TAG_HTTP_HEADER"); print(data)
  client:read("\r\n\r\n", TAG_HTTP_CONTENT)
end

client:setCallback(httpCallback):connect("localhost", 22848)
M.client = client
function M.connect()
  client:connect("localhost", 22848)
end
function M.send(command)
  if not client:connected() then client:connect("localhost", 22848) end
  client:write(json.encode(command))
  client:read("\r\n\r\n", TAG_HTTP_HEADER)
end


--- ChromeTabs:start()
--- Method
--- Does nothing.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The ChromeTabs object
function M:start()
  return self
end

return M
