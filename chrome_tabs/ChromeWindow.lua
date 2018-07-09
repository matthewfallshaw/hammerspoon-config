--- === ChromeWindow ===
---
--- Usage:
---   Depends on ChromeTabs!
---     ChromeWindow = require('chrome_tabs.ChromeWindow'):init(M)  -- Global!
---     ChromeTab    = require('chrome_tabs.ChromeTab'   ):init(M)  -- Global!

local logger = hs.logger.new("ChromeWindow")

local ChromeWindow = {
  _logger = logger,
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
  init = function(self, chrome_tabs)
    self.chrome_tabs = chrome_tabs
    return self
  end,
  focus = function(self)
    checks('ChromeWindow')
    logger.d("ChromeWindow:focus()")

    self.chrome_tabs._focus_window(self.windowId)
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
    self.chrome_tabs.chromeWindows[self.windowId] = nil
  end,
}
ChromeWindow.__index = ChromeWindow
function ChromeWindow:createOrUpdate(o)
  checks('table')
  logger.i("ChromeWindow:createOrUpdate("..o.windowId..")")

  local removed_tabs = {}  -- track tabs that no longer exist
  local chromeWindow = self.chrome_tabs.chromeWindows[o.windowId]
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

  self.chrome_tabs.chromeWindows[o.windowId] = chromeWindow

  return chromeWindow
end

return ChromeWindow
