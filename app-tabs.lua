-- Utilities for navigating app tabs
local logger = hs.logger.new("App tabs")
logger.i("Loading App tabs")

local M = {}

local _APP_TAB_LIST_APPLESCRIPT_STRING = [[
tell application "%s"
	set _tabs to {}
	set _index to 0
	repeat with _tab in (tabs of (window %d))
		set _index to _index + 1
		try
			set _url to URL of _tab
			if _url is missing value then
				set _url to -1
			end if
		on error
			set _url to -1
		end try
		try
			set _name to title of _tab
			if _name is missing value then
				set _name to -1
			end if
		on error
			try
				set _name to name of _tab
				if _name is missing value then
					set _name to -1
				end if
			on error
				set _name to -1
			end try
		end try
		set end of _tabs to {_index, _url, _name}
	end repeat
	return _tabs
end tell
]]
function M._app_tab_list_applescript_fn(window)
  local applescriptIndex = window:applescriptIndex()
  if applescriptIndex then
    return string.format(_APP_TAB_LIST_APPLESCRIPT_STRING, window:application():name(), applescriptIndex)
  else
    return false
  end
end

local DELAY_BEFORE_RERUNNING_USTT = hs.timer.minutes(10)
M._updateSafariTabsTimer = hs.timer.doAfter(DELAY_BEFORE_RERUNNING_USTT, function() return end):stop()
function M._updateSafariTabs()
  -- Safari tabs can background such that they have URL: missing value
  -- … wake them up
  -- Slow, and only necessary when Safari has put tabs to sleep (or failed to properly load them?)
  -- so don't rerun too often
  if M._updateSafariTabsTimer:running() then return end
  hs.osascript.applescript([[
tell application "Safari"
	repeat with _window in (every window)
		set the_original_tab to the current tab of _window
		repeat with _tab in (every tab of _window)
			if URL of _tab is missing value then
				set current tab of _window to _tab
			end if
		end repeat
		set the current tab of _window to the_original_tab
	end repeat
end tell
]])
  M._updateSafariTabsTimer:start()
end

-- hs.window extensions
-- ====================
function hs.window:applescriptIndex()
  -- Applescript's `every window` and HS's hs.window:allWindows() index the same
  local count_of_windows_that_dont_count = 0
  for index, win in ipairs(self:application():allWindows()) do
    if win == self then
      return index - count_of_windows_that_dont_count
    elseif not (win:isStandard() or win:isMinimized()) then
      count_of_windows_that_dont_count = count_of_windows_that_dont_count + 1
    end
  end
  if not self:subrole() or self:subrole() == "" then
    return false
  end
  logger.e("Couldn't find applescriptIndex of "..self:application():name().."'s window…")
  logger.e("… ("..hs.inspect(self)..")")
  logger.e("… with title: "..hs.inspect(self:title()))
  logger.e("… and subrole: "..hs.inspect(self:subrole()))
  logger.e("")
  return 1
end

local Tab = {}
Tab.__index = Tab
function Tab.new(window, index, url, name)
  local self = setmetatable({}, Tab)

  self.window = window
  self.index = index
  self.url = url ~= -1 and url or ""
  self.name = name ~= -1 and name or ""

  return self
end
function Tab:focus()
  self.window:focusTab(self.index)
  self.window:focus()
end

function hs.window:_tabsRaw()
  local success, applescript_text, appname
  appname = self:application():name()
  if appname == "Safari" then M._updateSafariTabs() end
  local applescript = M._app_tab_list_applescript_fn(self)
  if applescript then
    local out, window_tabs_raw, err = hs.osascript.applescript(applescript)
    if out and window_tabs_raw and window_tabs_raw[1] then
      return window_tabs_raw
    else
      -- If tabs change too fast handoff between HS & applescript can fail
      return {}
    end
  else
    -- If a window is closed… then it's not there anymore
    return {}
  end
end

function hs.window:tabs()
  local tabs = hs.fnutils.imap(self:_tabsRaw(), function(raw_tab)
    local index, url, name = table.unpack(raw_tab)
    return Tab.new(self, index, url, name)
  end)
  return tabs
end


function M.isTabAllowed(tab, filter)
  if not tab then return false end
  assert(filter["url_pattern"] or filter["title_pattern"])
  local allowed = true
  if filter["url_pattern"] then allowed = tab.url:match(filter["url_pattern"]) end
  if allowed and filter["title_pattern"] then allowed = tab.name:match(filter["title_pattern"]) end

  if allowed and filter["andFocus"] then tab:focus() end
  return allowed
end

-- move isWindowAllowed to hs.window.filter?

M.window_filter = setmetatable({}, hs.window.filter)
M.filters = {}
function M.window_filter.new(filters, logname, loglevel)
  -- (tab<n>|anyTab) = { (url_pattern|title_pattern) = <pattern>[, andFocus = true] }
  local isWindowAllowed = function(window)
    if not window then return false end
    local app_filters = filters[window:application():name()]
    if not app_filters then return false end
    local allowed = true
    for key, filter in pairs(app_filters) do
      local tab_number = key:match("^tab(%d)")
      if tab_number then
        local tab = window:tabs()[tonumber(tab_number)]
        allowed = M.isTabAllowed(tab, filter)
      elseif key == "anyTab" then
        local any_allowed = false
        for index, tab in pairs(window:tabs()) do
          local this_allowed = M.isTabAllowed(tab, filter)
          if this_allowed then
            any_allowed = true
          end
        end
        allowed = any_allowed
      end
      if not allowed then break end
    end
    return allowed
  end
  local wf = hs.window.filter.new(isWindowAllowed)
  wf.filters = filters
  M.filters[#M.filters + 1] = wf
  return wf
end


return M
