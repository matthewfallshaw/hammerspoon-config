--- === Chrome Tab Tools ===
---
--- Tracks Google Chrome windows and tabs, and provides tools to manipulate
--- them.

-- TODO:
-- actually check
--  - creating new tabs, deleting tabs, navigating to new pages

local M = {}

-- Metadata
M.name = 'ChromeTabs'
M.version = "0.1"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
M.homepage = "https://github.com/matthewfallshaw/"


setmetatable(M, {__type = M.name})

local logger = hs.logger.new("ChromeTabs")
M._logger = logger

require('checks')
local escape, unescape = require('utilities.string_escapes')()
local lfs = require('lfs')

local CHROME = 'Google Chrome'

local i = hs.inspect
hs.window.__type = 'hs.window'


-- ## Classes

--- ChromeTabs.chromeWindows
--- Variable
--- Chrome's windows, as ChromeWindows containing ChromeTabs.
--- 
--- ChromeWindow:focus() - focuses its window
--- ChromeWindow:create({ windowId = `integer`, windowIndex = `integer`,
---                       activeTabIndex = `integer`, windowTabs = {} })
---   - creates and returns a new ChromeWindow and adds it to
---     ChromeTabs.chromeWindows
--- ChromeWindow.activeTab - its active ChromeTab
--- 
--- ChromeTab:focus() - focuses its tab
--- ChromeTab:create({ tabId = `integer`, windowId = `integer`, tabIndex = `integer`,
---                    tabTitle = `string`, tabURL = `string` })
---   - creates and returns a new ChromeTab and adds it to its chromeWindow.
--- ChromeTab.chromeWindow - its ChromeWindow
M.chromeWindows = {}
ChromeWindow = require('chrome_tabs.ChromeWindow'):init(M)  -- Global!
ChromeTab    = require('chrome_tabs.ChromeTab'   ):init(M)  -- Global!


-- ## Internal

function M._applescript(as)
  checks('string')

  as = [[
tell (load script POSIX file "]].. lfs.currentdir() ..[[/chrome_tabs/chrome_tabs.scpt")
  ]].. as ..[[

end tell
  ]]
  logger.d("Applescript:\n"..as)
  local status, output, raw = hs.osascript.applescript(as)
local xstatus, xoutput = pcall(function() 
  if status and output then
    return output
  else
    if raw and
      raw.NSLocalizedFailureReason and
      tostring(raw.NSLocalizedFailureReason).match('Invalid index') then
      return nil
    else
      error("applescript failed:\n\n"..as.."\n\n\z
      raw:\n\n"..i(raw).."\n\n\z
      status:"..tostring(status).."\n\n\z
      output:\n\n"..tostring(i(output)).."\n\n")
    end
  end
end)
if status then
  return xoutput
else
  print("raw type: "..type(raw))
  for k,v in pairs(raw) do
    print("raw key type: "..type(k)..", value: '"..i(k).."'")
    print("raw value type: "..type(v)..", value: '"..i(v).."'")
  end
  error(i(raw))
end
end


function M._create_all_windows_and_tabs()
  local raw = M._applescript("return all_windows_and_tabs()")
  M.chromeWindows = {}
  hs.fnutils.each(raw, function(win_table)
    return ChromeWindow:createOrUpdate(win_table)
  end)
  return M
end

function M._check_and_update_windows()
  local raw = M._applescript("return all_windows()")
  local removed_windows = {}
  hs.fnutils.each(M.chromeWindows, function(win)
    removed_windows[win.windowId] = true
  end)
  hs.fnutils.each(raw, function(win_table)
    local chromeWindow = M.chromeWindows[win_table.windowId]
    if chromeWindow == nil then  -- a new window, create it!
      M._refresh_one_window(win_table.windowId)
    else
      chromeWindow.windowIndex = win_table.windowIndex
      chromeWindow.activeTabIndex = win_table.activeTabIndex

      chromeWindow.activeTab = hs.fnutils.find(chromeWindow.chromeTabs,
          function(t) return chromeWindow.activeTabIndex == t.tabIndex end)
      if chromeWindow.activeTab == nil then  -- new tab
        M._refresh_one_window(win_table.windowId)
      end

      removed_windows[chromeWindow.windowId] = nil  -- window still exists
    end
  end)
  for win_id,_ in pairs(removed_windows) do
    -- windows that used to exist, but don't any more
    if M.chromeWindows[win_id] then M.chromeWindows[win_id]:destroy() end
  end
end

function M._refresh_one_window(window_id)
  local raw = M._applescript("return one_window_and_tabs(".. window_id ..")")
  if raw then
    ChromeWindow:createOrUpdate(raw)
  else
    -- do nothing - window gone before update, which happens when multiple tabs
    -- closed simultaneously
  end
end

function M._focus_tab(index_of_tab, id_of_window)
  return M._applescript("focus_tab(".. index_of_tab ..", find_window(".. id_of_window .."))")
end

function M._focus_window(id_of_window)
  return M._applescript("focus_window(find_window(".. id_of_window .."))")
end


local fuzzel = require 'utilities.fuzzy.fuzzel'
function M._chromeWindow_from_window(window)
  M._check_and_update_windows()
  local target_window_title = window:title()
  local active_tabs = hs.fnutils.map(M.chromeWindows, function(w) return w.activeTab.tabTitle end)
  local best_match_title = fuzzel.FuzzyFindRatio(target_window_title, active_tabs)
  return hs.fnutils.find(M.chromeWindows, function(chromeWindow)
    return chromeWindow.activeTab.tabTitle == best_match_title
  end)
end


-- ## Public

--- ChromeTabs:update(window)
--- Method
--- Populates ChromeTabs.chromeWindows and updates chromeTabs for window.
---
--- Parameters:
---  * chromeWindow - ChromeWindow to be updated
---
--- Returns:
---  * The ChromeTabs object
function M:update(chromeWindow)
  checks('ChromeTabs', 'ChromeWindow')
  logger.i("ChromeTabs:update('".. tostring(chromeWindow) .."')")

  M._refresh_one_window(chromeWindow.windowId)
  return self
end

--- ChromeTabs:updateAllWindows()
--- Method
--- Populates ChromeTabs.chromeWindows for all windows.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The ChromeTabs object
function M:updateAllWindows()
  checks('ChromeTabs')
  logger.i("ChromeTabs:updateAllWindows()")

  M._create_all_windows_and_tabs()
  return self
end


local function chrome_watcher(self)
  checks('ChromeTabs')

  return hs.application.watcher.new(
      function(name, event, app)  
        if name == CHROME then
          if event == hs.application.watcher.launched then
            self._chrome_app = app
            self:updateAllWindows()
          elseif event == hs.application.watcher.terminated then
            self._chrome_app = nil
            self.chromeWindows = {}
          end
        end
      end
  ):start()
end

local WINDOW_CREATED_EVENTS = {
  'windowCreated',  -- created, 1st move to window's space
}
local WINDOW_CHANGE_EVENTS = {
  'windowTitleChanged',  -- new tab (>1×), switch tab, close tab, navigate
}
-- local WINDOW_UPDATE_EVENTS = {
--   'windowInCurrentSpace',    -- switch space (×x), created, fullscreened, unfullscreened,
--                              --   hidden
--   'windowNotInCurrentSpace', -- switch space (×x), closed, fullscreened, unfullscreened
--   'windowOnScreen',          -- switch space (×x), created, fullscreened, unfullscreened,
--                              --   unminimized, unhidden (lie if minimized)
--   'windowNotOnScreen',       -- switch space (×x), closed, fullscreened, unfullscreened,
--                              --   minimized, hidden
--   'windowVisible',           -- created, unminimized, unhidden (lie if minimized)
--   'windowNotVisible',        -- closed, minimized, hidden
--   'windowFullscreened',      -- fullscreened
--   'windowUnfullscreened',    -- unfullscreened
--   'windowMinimized',         -- minimized
--   'windowUnminimized',       -- unminimized
--   'windowHidden',            -- hidden
--   'windowUnhidden',          -- unhidden
-- }
local WINDOW_DESTROY_EVENTS = {
  'windowDestroyed',  -- closed
}
-- # ignored window events
-- 'windowFocused', 'windowUnfocused', 'windowRejected', 'windowsChanged',
--     'windowMoved',  -- moved, fullscreened, unfullscreened

-- local EVENT_PROPERTIES = {
--   windowInCurrentSpace    = { prop = 'inCurrentSpace', state = true  },
--   windowNotInCurrentSpace = { prop = 'inCurrentSpace', state = false },
--   windowOnScreen          = { prop = 'onScreen',       state = true  },
--   windowNotOnScreen       = { prop = 'onScreen',       state = false },
--   windowVisible           = { prop = 'visible',        state = true  },
--   windowNotVisible        = { prop = 'visible',        state = false },
--   windowFullscreened      = { prop = 'fullscreen',     state = true  },
--   windowUnfullscreened    = { prop = 'fullscreen',     state = false },
--   windowMinimized         = { prop = 'minimized',      state = true  },
--   windowUnminimized       = { prop = 'minimized',      state = false },
--   windowHidden            = { prop = 'hidden',         state = true  },
--   windowUnhidden          = { prop = 'hidden',         state = false },
-- }
local function create_window_after_created(window, app_name, event)
  checks('userdata', 'string', 'string')
  logger.i("create_window_after_created("..i({window, app_name, event})..")")

  local chromeWindow = M._chromeWindow_from_window(window)
  if chromeWindow ~= nil then
    M:update(chromeWindow)
  else
    error("Failed to find or make a ChromeWindow from ".. hs.inspect(window))
  end
end
local function refresh_window_after_change(window, app_name, event)
  checks('userdata', 'string', 'string')
  logger.i("refresh_window_after_change("..i({window, app_name, event})..")")

  local chromeWindow = M._chromeWindow_from_window(window)
  if chromeWindow ~= nil then
    M:update(chromeWindow)
  else
    logger.e(debug.traceback("Failed to find or make a ChromeWindow from ".. hs.inspect(window)))
  end
end
-- local function update_window_after_change(window, app_name, event)
--   checks('userdata', 'string', 'string')
--   logger.i("update_window_after_change("..i({window, app_name, event})..")")

--   local chromeWindow = M._chromeWindow_from_window(window)
--   chromeWindow[EVENT_PROPERTIES[event].prop] = EVENT_PROPERTIES[event].state
-- end
local function destroy_window_after_destroyed(window, app_name, event)
  checks('userdata', 'string', 'string')
  logger.i("destroy_window_after_destroyed("..i({window, app_name, event})..")")

  M._check_and_update_windows()
end
local function chrome_window_filter(self)
  checks('ChromeTabs')

  local wf_chrome = hs.window.filter.new(
      function(win) return win and win:title() ~= '' and win:application() == self._chrome_app end)
  wf_chrome:subscribe(WINDOW_CREATED_EVENTS, create_window_after_created)
  wf_chrome:subscribe(WINDOW_CHANGE_EVENTS, refresh_window_after_change)
  -- wf_chrome:subscribe(WINDOW_UPDATE_EVENTS, update_window_after_change)
  wf_chrome:subscribe(WINDOW_DESTROY_EVENTS, destroy_window_after_destroyed)
  wf_chrome.forceRefreshOnSpaceChange = true
  return wf_chrome
end

--- ChromeTabs:start()
--- Method
--- Starts ChromeTabs, populates ChromeTabs.chromeWindows and sets up
--- watchers to keep its view of Google Chrome up-to-date.
---
--- Parameters:
---  * None
---
--- Returns:
---  * The ChromeTabs object
function M:start()
  checks('ChromeTabs')

  -- Chrome
  self._chrome_app = hs.application.get(CHROME)
  self._chrome_watcher = chrome_watcher(self)

  -- Window filter
  self._wf_chrome = chrome_window_filter(self)

  self:updateAllWindows()

  return self
end


return M
