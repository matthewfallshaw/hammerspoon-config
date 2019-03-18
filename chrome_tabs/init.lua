--- === Chrome Tab Tools ===
---
--- Focus tabs or windows in Google Chrome

local M = {}

-- Metadata
M.name = 'ChromeTabs'
M.version = "0.2"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
M.homepage = "https://github.com/matthewfallshaw/"

local json = require "utilities.dkjson"

local logger = hs.logger.new("ChromeTabT")
M._logger = logger

hs.window.__type = 'hs.window'


-- ## Internal
local function sendMessage(msg)
  if not msg then
    hs.execute("~/bin/chrome-client getAllTabs")
  else
    hs.execute("~/bin/chrome-client '".. msg:gsub("'", "\\'") .."'")
  end
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
