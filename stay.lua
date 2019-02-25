-- Stay replacement: Keep App windows in their places

local M = {}

local logger = hs.logger.new("Stay")
M._logger = logger
logger.i("Loading Stay")
hs.window.filter.setLogLevel(1)  -- GLOBAL!! wfilter is very noisy

M.window_layouts = {} -- see bottom of file
M.window_layouts_enabled = false

local function alert(message)
  hs.alert.closeAll()
  logger.i(message)
  if not M.starting then
    hs.alert.show('Stay: '.. message)
  end
end

function M:report_frontmost_window()
  local window = hs.application.frontmostApplication():focusedWindow()
  local filter_string
  if window:subrole() == 'AXStandardWindow' then
    filter_string = string.format("'%s'", window:application():name())
  else
    filter_string = string.format("{['%s']={allowRoles='%s'}}", window:application():name(), window:subrole())
  end
  local unit_rect = window:screen():toUnitRect(window:frame())
  local unit_rect_string = string.format("[%.0f,%.0f>%.0f,%.0f]",
            unit_rect.x1*100,unit_rect.y1*100,unit_rect.x2*100,unit_rect.y2*100)
  local screen_position_string = string.format("%i,%i", window:screen():position())
  local action_string
  if unit_rect_string == "[0,0>100,100]" then
    action_string = string.format("'maximize 1 oldest %s'", screen_position_string)
  else
    action_string = string.format("'move 1 oldest %s %s'", unit_rect_string, screen_position_string)
  end
  local layout_rule = string.format("{%s, %s}", filter_string, action_string)
  hs.pasteboard.setContents(layout_rule)
  alert("Active window position in clipboard\n".. layout_rule)
  return layout_rule
end

function M:report_screens()
  local screens = hs.fnutils.reduce(
    hs.fnutils.concat({{}}, hs.screen.allScreens()),
    function(list, screen)
      return hs.fnutils.concat(list,{{name = screen:name(), id = screen:id()}})
    end
  )
  local screens_string = hs.inspect(screens)
  hs.pasteboard.setContents(screens_string)
  alert("Screens in clipboard\n".. screens_string)
  return screens
end

local function toggle_window_layouts_enabled_descripton()
  if not M.window_layouts_enabled then
    return 'Starting window layout engine'
  else
    return 'Pausing window layout engine'
  end
end

function M:toggle_window_layouts_enabled()
  if self.window_layouts_enabled then
    self:window_layouts_disable()
  else
    self:window_layouts_enable()
  end
  return self
end

function M:window_layouts_enable()
  if not self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do layout:start() end
    self.window_layouts_enabled = true
  end
  return self
end

function M:window_layouts_disable()
  if self.window_layouts_enabled then
    for _,layout in pairs(self.window_layouts) do layout:stop() end
    self.window_layouts_enabled = false
  end
  return self
end

M.toggle_or_report_stack = {
  { name = 'toggle', description = toggle_window_layouts_enabled_descripton,
      fn = function() M:toggle_window_layouts_enabled() end },
  { name = 'screens', description = 'Reporting screen details',
      fn = function() M:report_screens() end },
  { name = 'report', description = 'Reporting frontmost window position',
      fn = function() M:report_frontmost_window() end },
  { name = 'report_and_open', description = 'Reporting frontmost window position and opening',
      fn = function()
        M:report_frontmost_window()
        hs.execute("/usr/bin/open ".. debug.getinfo(1).short_src)
      end },
}
function M:toggle_or_report()
  local obj = self.double_tap_timer

  if not obj then
    -- First call, set up for the first action
    obj = { position = 1 }
  else
    -- Subsequent call, set up for subsequent action
    obj.timer:stop()
    obj.position = obj.position + 1
  end

  local descr = self.toggle_or_report_stack[obj.position].description
  descr = type(descr) == 'function' and descr() or descr
  if obj.position < #self.toggle_or_report_stack then
    alert(descr.. "\nTap again to achive: ".. M.toggle_or_report_stack[obj.position + 1].description)
    obj.timer = hs.timer.doAfter(0.5, function()
      obj.timer = nil
      M.toggle_or_report_stack[obj.position].fn()
      self.double_tap_timer = nil
    end)
  else
    alert(self.toggle_or_report_stack[obj.position].description)
    obj.timer = nil
    M.toggle_or_report_stack[obj.position].fn()
    obj = nil
  end
  self.double_tap_timer = obj
  return self
end

-- Decorating a global!
function hs.window.layout:active()
  if self.screens then
    for hint,test in pairs(self.screens) do
      local screen = hs.screen.find(hint)
      if screen then
        if type(test) == 'boolean' then
          if not test then return false end
        else
          local x,y = screen:position()
          local test_geometry = hs.geometry.new(test)
          if not x == test_geometry.x or not y == test_geometry.y then
            return false
          end
        end
      else
        if test then  -- truthy: true or hs.geometry
          return false
        end
      end
    end
  end
  return true
end

function M:activeLayouts()
  local active_layouts = {}
  hs.fnutils.each(self.window_layouts, function(layout)
    if layout:active() then
      active_layouts[layout.logname] = true
    end
  end)
  return active_layouts
end

function M:start()
  self.starting = true
  self:window_layouts_enable()

  self.hotkey = self.hotkey or hs.hotkey.new({"⌘", "⌥", "⌃", "⇧"}, "s", function() M:toggle_or_report() end)
  self.hotkey:enable()
  self.starting = nil
  return self
end
function M:stop()
  self:window_layouts_disable()
  if self.hotkey then self.hotkey:disable() end
  return self
end


-- chrome_tabs = require 'chrome_tabs'
-- chrome_gmail_window_filter = hs.window.filter.new()

-- app_tabs = require "app_tabs"
-- chrome_gmail_window_filter = app_tabs.window_filter.new({['Google Chrome'] = {
    -- tab1 = {url_pattern = "^https://mail%.google%.com/mail/u/0/#"} }})
-- chrome_docs_window_filter = app_tabs.window_filter.new({['Google Chrome' ]= {
    -- tab1 = {url_pattern = "^https://drive%.google%.com/drive/..[^0]"} }})
-- safari_gmail_window_filter = app_tabs.window_filter.new({Safari = {
--     tab1 = {url_pattern = "^https://mail%.google%.com/mail/u/0/"} }})
-- safari_docs_window_filter = app_tabs.window_filter.new({Safari = {
--     tab1 = {url_pattern = "^https://drive%.google%.com/drive/u/0/"} }})

M.window_layouts = {
  shared = hs.window.layout.new({
    {'Morty', 'move 1 oldest [0,0>70,100] 0,0'},
    {'GitX', 'max all 0,0'},
    {{['nvALT']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [63,0>100,79] 0,0'},
    {'Finder','move 1 oldest [40,44>94,92] 0,0'},
    {'Skype', 'move 1 oldest [60,0>100,86] 0,0'},
    {'Messages', 'move 1 oldest [53,0>100,71] 0,0'},
    {'Activity Monitor', 'move 1 oldest [0,42>61,100] 0,0'},
    {'Slack', 'move 1 oldest [40,0>100,100] 0,0'},
    {{['Quicksilver']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [24,12>84,86] 0,0'},
    {'Lights Switch', 'move 1 oldest [59,0>87,67] 0,0'},
  },'Shared'),
  laptop = hs.window.layout.new({
    screens={['Color LCD']='0,0',
             ['-1,0']=false,['0,-1']=false,['1,0']=false,['0,1']=false}, -- when no external screens
    -- {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    -- {chrome_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    -- {safari_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    -- {safari_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    -- {'Opera', 'move 1 closest [0,0>77,100] 0,0'},
    -- {'Opera', 'move 1 closest [0,0>80,100] 0,0'},
    -- {'Gmail', 'move 1 oldest [0,0>77,100] 0,0'},
    -- {'Google Drive', 'move 1 oldest [0,0>80,100] 0,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>65,100] 0,0'},
    {'iTerm2', 'move 1 oldest [50,0>100,100] 0,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'PivotalTracker','Asana','Google Calendar','Calendar'},
      'max 1 oldest 0,0'},
  },'Laptop'),
  canningdesk = hs.window.layout.new({
    screens={["DELL U2718Q"]=true, ['0,-1']=true},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>42,100] 0,-1'},
    {'iTerm2', 'move 1 oldest [62,0>100,100] 0,-1'},
    {'PivotalTracker', 'max 1 oldest 0,-1'},
    {'Asana', 'move 1 oldest [0,0>50,100] 0,-1'},
    {'Google Calendar', 'move 1 oldest [0,8>100,100] 0,-1'},
    {'Calendar', 'max 1 oldest 0,-1'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
  }, 'CanningDesk'),
  bellroydesk = hs.window.layout.new({
    screens={["DELL U2718Q"]=true, ['1,0']=true},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>42,100] 1,0'},
    {'iTerm2', 'move 1 oldest [62,0>100,100] 1,0'},
    {'PivotalTracker', 'max 1 oldest 1,0'},
    {'Asana', 'move 1 oldest [0,0>50,100] 1,0'},
    {'Google Calendar', 'move 1 oldest [0,8>100,100] 1,0'},
    {'Calendar', 'max 1 oldest 1,0'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 1,0'},
  }, 'BellroyDesk'),
  miridesk = hs.window.layout.new({
    screens={['HP Z27']=true, ["DELL U2713HM"]=true},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>42,100] 0,-1'},
    {'iTerm2', 'move 1 oldest [62,0>100,100] 0,-1'},
    {'PivotalTracker', 'max 1 oldest 0,-1'},
    {'Asana', 'move 1 oldest [0,0>50,100] 0,-1'},
    {'Google Calendar', 'move 1 oldest [0,8>100,100] 0,-1'},
    {'Calendar', 'max 1 oldest 0,-1'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
  }, 'MiriDesk'),
  dualleft = hs.window.layout.new({
    screens={["DELL U2718Q"]=false,
             ['-1,0']=true,['0,-1']=false,['1,0']=false,['0,1']=false},
    -- {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    -- {chrome_docs_window_filter, 'move 1 oldest [20,0>80,100] -1,0'},
    -- {safari_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    -- {safari_docs_window_filter, 'move 1 oldest [20,0>80,100] -1,0'},
    -- {'Opera', 'move 1 closest [0,0>77,100] 0,0'},
    -- {'Opera', 'move 1 closest [20,0>80,100] -1,0'},
    -- {'Gmail', 'move 1 oldest [0,0>77,100] 0,0'},
    -- {'Google Drive', 'move 1 oldest [20,0>80,100] -1,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>50,100] -1,0'},
    {'iTerm2', 'move 1 oldest [50,0>100,100] -1,0'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,0'},
    {'PivotalTracker', 'max 1 oldest -1,0'},
    {'Asana', 'move 1 oldest [0,0>66,100] -1,0'},
    {'Google Calendar', 'max 2 oldest -1,0'},
    {'Calendar', 'max 1 oldest -1,0'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] -1,0'},
    {'Snagit 2018', 'move 1 oldest [15,12>85,88] -1,0'}
  },'DualLeft'),
  dualtop = hs.window.layout.new({
    screens={["DELL U2718Q"]=false,['DELL U2713HM']=false,
             ['-1,0']=false,['0,-1']=true,['1,0']=false,['0,1']=false,['-1,-1']=false},
    -- {chrome_gmail_window_filter, 'move 1 oldest [0,0>77,100] 0,0'},
    -- {chrome_docs_window_filter, 'move 1 oldest [20,0>80,100] 0,-1'},
    -- {safari_gmail_window_filter, 'move 1 oldest [0,0>60,100] 0,-1'},
    -- {safari_docs_window_filter, 'move 1 oldest [0,0>80,100] 0,0'},
    -- {'Opera', 'move 1 closest [0,0>60,100] 0,-1'},
    -- {'Opera', 'move 1 closest [0,0>80,100] 0,0'},
    -- {'Gmail', 'move 1 oldest [0,0>60,100] 0,-1'},
    -- {'Google Drive', 'move 1 oldest [0,0>80,100] 0,0'},
    {{'VimR', 'MacVim'}, 'move 1 oldest [0,0>50,100] 0,-1'},
    {'iTerm2', 'move 1 oldest [50,0>100,100] 0,-1'},
    {{['Hammerspoon']={allowRoles='AXStandardWindow'}}, 'move 1 oldest [50,0>100,90] 0,-1'},
    {'PivotalTracker', 'max 1 oldest 0,-1'},
    {'Asana', 'move 1 oldest [0,0>67,100] 0,-1'},
    {'Google Calendar', 'max 2 oldest 0,-1'},
    {'Calendar', 'max 1 oldest 0,-1'},
    {'FreeMindStarter', 'move 1 oldest [50,0>100,100] 0,-1'},
  },'DualTop'),
}
for _,layout in pairs(M.window_layouts) do
  for _,rule in pairs(layout.rules) do
    rule.windowfilter:setOverrideFilter({visible=true})
  end
end

return M
