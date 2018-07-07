--- === Chrome Tab Tools ===
---
--- Tracks Google Chrome windows and tabs, and provides tools to manipulate
--- them.

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


-- ## Internal

local function error_and_cleanup(...)
  M._in_update_window = false
  M._in_update_all_windows = false
  error(...)
end

function M._applescript(as)
  checks('string')
  local as = [[
tell (load script POSIX file "]].. lfs.currentdir() ..[[/chrome_tabs/chrome_tabs.scpt")
  ]].. as ..[[

end tell
  ]]
  logger.d("Applescript:\n"..as)
  local status, output, raw = hs.osascript.applescript(as)
  if status and output then
    return output
  else
    error_and_cleanup("applescript failed:\n\n"..as.."\n\n\z
        raw:\n\n"..i(raw).."\n\n\z
        status:"..tostring(status).."\n\n\z
        output:\n\n"..tostring(i(output)).."\n\n")
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
      removed_windows[chromeWindow.windowId] = nil  -- window still exists
    end
  end)
  for win_id,_ in pairs(removed_windows) do
    -- windows that used to exist, but don't any more
    M.chromeWindows[win_id]:destroy()
  end
end

function M._refresh_one_window(window_id)
  local raw = M._applescript("return one_window_and_tabs(".. window_id ..")")
  ChromeWindow:createOrUpdate(raw)
end

function M._focus_tab(index_of_tab, id_of_window)
  return M._applescript("focus_tab(".. index_of_tab ..", find_window(".. id_of_window .."))")
end

function M._focus_window(id_of_window)
  return M._applescript("focus_window(find_window(".. id_of_window .."))")
end


function M._chromeWindow_from_window(window)
  M._check_and_update_windows()
  for _,chromeWindow in pairs(M.chromeWindows) do
    if window:title() == chromeWindow.activeTab.tabTitle then
      if chromeWindow.windowIndex <= 2 then
        return chromeWindow
      else
        logger.w("Found ChromeWindow for ".. i(window) .." at index "..
            chromeWindow.windowIndex .." (which is high)")
        return chromeWindow
      end
    end
  end
  return nil
end


-- ## Classes

--- ChromeTabs.chromeWindows
--- Variable
--- Chrome's windows.
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

ChromeWindow = {
  __type = 'ChromeWindow',
  __fields = {
    windowId = 'number', windowIndex = 'number', activeTabIndex = 'number',
    activeTab = '?ChromeTab'
  },
  __tostring = function(self)
    return "ChromeWindow: { "..
        "windowId: ".. tostring(self.windowId) ..", "..
        "windowIndex: ".. tostring(self.windowIndex) ..", "..
        "activeTabIndex: ".. tostring(self.activeTabIndex) .."}"
  end,
  focus = function(self)
    checks('ChromeWindow')
    logger.d("ChromeWindow:focus()")

    M._focus_window(self.windowId)
    return self
  end,
  title = function(self)
    return self.activeTab.tabTitle
  end,
  url = function(self)
    return self.activeTab.tabURL
  end,
  destroy = function(self)
    hs.fnutils.each(self.chromeTabs, function(tab) tab:destroy() end)
    M.chromeWindows[self.windowId] = nil
  end,
}
ChromeWindow.__index = ChromeWindow
function ChromeWindow:createOrUpdate(o)
  checks('table')
  logger.i("ChromeWindow:createOrUpdate("..o.windowId..")")

  local removed_tabs = {}  -- track tabs that no longer exist
  local chromeWindow = M.chromeWindows[o.windowId]
  if not chromeWindow then
    chromeWindow = setmetatable({}, ChromeWindow)
  else
    -- track existing tabs so we can remove those not in o.windowTabs
    hs.fnutils.each(chromeWindow.chromeTabs, function(tab)
      removed_tabs[tab.tabId] = true
    end)
  end

  hs.fnutils.each(
      {'windowId', 'windowIndex', 'activeTabIndex'},
      function(prop) chromeWindow[prop] = o[prop] end)

  chromeWindow.chromeTabs = chromeWindow.chromeTabs or {}
  hs.fnutils.each(o.windowTabs, function(raw_tab)
    raw_tab.chromeWindow = chromeWindow
    chromeWindow.chromeTabs[raw_tab.tabId] = ChromeTab:createOrUpdate(raw_tab)
    if raw_tab.tabIndex == o.activeTabIndex then
      chromeWindow.activeTab = chromeWindow.chromeTabs[raw_tab.tabId]
    end
    -- tab in o.windowTabs, so not removed (don't remove it below)
    removed_tabs[raw_tab.tabId] = nil
  end)
  assert(chromeWindow.activeTab, "ChromeWindow created without activeTab: ".. hs.inspect(o))
  for tab_id,_ in pairs(removed_tabs) do
    -- tabs that used to exist, but don't any more
    chromeWindow.chromeTabs[tab_id]:destroy()
  end

  M.chromeWindows[o.windowId] = chromeWindow

  return chromeWindow
end
M._ChromeWindow = ChromeWindow


ChromeTab = {
  __type = 'ChromeTab',
  __fields = {
    chromeWindow = 'ChromeWindow', tabId = 'number', tabIndex = 'number',
    tabURL = 'string', tabTitle = 'string' },
  __tostring = function(self)
    return "ChromeTab: { tabId: ".. tostring(self.tabId) ..
        " (chromeWindow: ".. tostring(self.chromeWindow and self.chromeWindow.windowId or '?') .."),\n  \z
        tabTitle: ".. tostring(self.tabTitle) ..",\n  \z
        tabURL: ".. tostring(self.tabURL) .." }"
  end,
  focus = function(self)
    checks('ChromeTab')
    logger.d("ChromeTab:focus()")

    M._focus_tab(self.tabIndex, self.chromeWindow.windowId)
  end,
  find = function(self, search)
    if type(search) == 'string' then
      return self:find({title=search})
    end

    assert(search.title or search.url or search.not_title or search.not_url,
    'in ChromeTab:find:: when passing a table of search parameters, \z
    I need one of `title` or `url`')

    local found_chrome_tab
    local found_window = hs.fnutils.find(M.chromeWindows, function(chromeWindow)
      checks('table')
      return hs.fnutils.find(chromeWindow.chromeTabs, function(chromeTab)
        found_chrome_tab = chromeTab
        return (search.title == nil or (chromeTab.tabTitle:match(search.title))) and
               (search.url == nil or (chromeTab.tabURL:match(search.url))) and
               (search.not_title == nil or (not chromeTab.tabTitle:match(search.not_title))) and
               (search.not_url == nil or (not chromeTab.tabURL:match(search.not_url)))
      end)
    end)
    if found_window then
      return found_chrome_tab
    else
      error_and_cleanup('in ChromeTab:find('..i(search)..')::\n\z
      Not found.')
    end
  end,
  destroy = function(self)
    if self.chromeWindow then self.chromeWindow.chromeTabs[self.tabId] = nil end
    self.chromeWindow = nil
  end,
}
ChromeTab.__index = ChromeTab
function ChromeTab:createOrUpdate(o)
  checks('table')
  logger.i("ChromeTab:createOrUpdate("..o.chromeWindow.windowId..":"..o.tabId..")")

  local chromeTab = o.chromeWindow.chromeTabs[o.tabId]
  if not chromeTab then
    chromeTab = setmetatable({}, ChromeTab)
  end

  hs.fnutils.each(
      {'tabId', 'windowId', 'tabIndex', 'tabTitle', 'tabURL', 'chromeWindow'},
      function(prop) chromeTab[prop] = o[prop] end)

  return chromeTab
end
M._ChromeTab = ChromeTab

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
  logger.i("ChromeTabs:update('".. i(chromeWindow) .."')")

  self._in_update_window = true
  M._refresh_one_window(chromeWindow.windowId)
  self._in_update_window = false
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

  self._in_update_all_windows = true
  M._create_all_windows_and_tabs()
  self._in_update_all_windows = false
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

  M:update(M._chromeWindow_from_window(window))
end
local function refresh_window_after_change(window, app_name, event)
  checks('userdata', 'string', 'string')
  logger.i("refresh_window_after_change("..i({window, app_name, event})..")")

  M:update(M._chromeWindow_from_window(window))
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

  local chromeWindow = M._chromeWindow_from_window(window)
  assert(chromeWindow == nil, "Erm… hs reports ".. hs.inspect(window) .." destroyed.\z
      Its matching ChromeWindow should have been destroyed too, but… "..
      hs.inspect(chromeWindow))
end
local function chrome_window_filter(self)
  checks('ChromeTabs')

  local wf_chrome = hs.window.filter.new(
      function(win) return win:title() ~= '' and win:application() == self._chrome_app end)
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
