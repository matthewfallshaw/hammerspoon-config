--- === ChromeTab ===
---
--- Usage:
---   Depends on ChromeTabs!
---     ChromeWindow = require('chrome_tabs.ChromeWindow'):init(M)  -- Global!
---     ChromeTab    = require('chrome_tabs.ChromeTab'   ):init(M)  -- Global!

local logger = hs.logger.new("ChromeTab")

local ChromeTab = {
  _logger = logger,
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
  init = function(self, chrome_tabs)
    self.chrome_tabs = chrome_tabs
    return self
  end,
  focus = function(self)
    checks('ChromeTab')
    logger.d("ChromeTab:focus()")

    self.chrome_tabs._focus_tab(self.tabIndex, self.chromeWindow.windowId)
  end,
  find = function(self, search)
    if type(search) == 'string' then
      return self:find({title=search})
    end

    assert(search.title or search.url or search.not_title or search.not_url,
    'in ChromeTab:find:: when passing a table of search parameters, \z
    I need one of `title` or `url`')

    local found_chrome_tab
    local found_window = hs.fnutils.find(self.chrome_tabs.chromeWindows, function(chromeWindow)
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
      logger.w('in ChromeTab:find('..i(search)..')::\n Not found.')
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

return ChromeTab
