-- Stay replacement: Keep App windows in their places

-- luacheck: globals hs

local hs_geometry = hs.geometry
local fun = require 'fun'

local M = {}

local logger = hs.logger.new('Stay')
M._logger = logger
logger.i('Loading Stay')
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

M.watchable = hs.watchable.new('stay')
function M.activeLayoutChangeCallback(_, _, _, _, new)
  alert('I would have been storing or restoring window positions now (active layouts: '..new..')')
end
M.watchable_watcher = hs.watchable.watch('stay.activeLayouts', M.activeLayoutChangeCallback)

function M:report_frontmost_window()  --luacheck: no self
  local window = hs.application.frontmostApplication():focusedWindow()

  local filter_string
  if window:subrole() == 'AXStandardWindow' then
    filter_string = string.format("'%s'", window:application():name())
  else
    filter_string = string.format("{['%s']={allowRoles='%s'}}", window:application():name(), window:subrole())
  end

  local rect = window:frame()
  local rect_string = string.format('[%.0f,%.0f>%.0f,%.0f]',
                                    rect.x1,rect.y1,rect.x2,rect.y2)

  local unit_rect = window:screen():toUnitRect(rect)
  local unit_rect_string = string.format('[%.0f,%.0f>%.0f,%.0f]',
                                         unit_rect.x1*100,unit_rect.y1*100,unit_rect.x2*100,unit_rect.y2*100)
  local screen_position_string = string.format('%i,%i', window:screen():position())

  local action_string, abs_action_string
  if unit_rect_string == '[0,0>100,100]' then
    action_string = string.format("'maximize 1 oldest %s'", screen_position_string)
    abs_action_string = action_string
  else
    action_string = string.format("'move 1 oldest %s %s'", unit_rect_string, screen_position_string)
    abs_action_string = string.format("'move 1 oldest %s'", rect_string)
  end

  local layout_rule = string.format('{%s, %s}', filter_string, action_string)
  local abs_layout_rule = string.format('{%s, %s}', filter_string, abs_action_string)

  local res = 'Active layouts: '..self:activeLayouts():tostring()..'\n'..layout_rule..'\n'..abs_layout_rule
  hs.pasteboard.setContents(res)
  alert('Active window position in clipboard\n\n'..res)
  return res
end

function M:report_screens()  --luacheck: no self
  local screens = fun.totable(
    fun.map(function(screen) return {name = screen:name(), id = screen:id()} end,
      hs.screen.allScreens()
    )
  )
  local screens_string = hs.inspect(screens)
  hs.pasteboard.setContents(screens_string)
  alert('Screens in clipboard\n'.. screens_string)
  return screens
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
    for _,layout in pairs(self.window_layouts) do
      layout:start()
    end
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

local function toggle_window_layouts_enabled_descripton()
  if not M.window_layouts_enabled then
    return 'Start window layout engine'
  else
    return 'Pause window layout engine'
  end
end
local choices_list = {
  app_modes =       { text = 'App modes',
                      subText = 'Show apps with alternate modes',
                      fn = function() app_modes() end
                    },
  toggle =          { text = 'Toggle layout engine',
                      subText = toggle_window_layouts_enabled_descripton(),
                      fn = function() M:toggle_window_layouts_enabled() end
                    },
  screens =         { text = 'Screens',
                      subText = 'Report screen details',
                      fn = function() M:report_screens() end
                    },
  report =          { text = 'Report',
                      subText = 'Report frontmost window position',
                      fn = function() M:report_frontmost_window() end
                    },
  report_and_open = { text = 'Report and open',
                      subText = 'Report frontmost window position and open config',
                      fn = function()
                        M:report_frontmost_window()
                        hs.execute('/usr/bin/open -a VimR ~/.hammerspoon/configConsts.lua')
                      end
                    },
}
local function completionFn(choice) if choice then choices_list[choice.key].fn() end end
local function choicesFn()
  return fun.totable(
    fun.map(
      function(choice_key, choice)
        return { text    = choice.text,
                 subText = choice.subText,
                 key     = choice_key,
               }
      end,
      choices_list
    )
  )
end
M.chooser = hs.chooser.new(completionFn):
              choices(choicesFn):
              searchSubText(true)

local function app_modes()

end

function M:toggle_or_choose()
  if not self.double_tap_timer then
    -- First call, set up for toggle
    hs.alert(toggle_window_layouts_enabled_descripton()..'; tap again for options.')
    self.double_tap_timer = hs.timer.doAfter(0.5, function()
      self.double_tap_timer = nil
      M:toggle_window_layouts_enabled()
    end)
  else
    -- Subsequent call, show the chooser
    hs.alert.closeAll()
    M.chooser:refreshChoicesCallback()
    self.double_tap_timer:stop()
    self.double_tap_timer = nil
    self.chooser:show()
  end
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
          local test_geometry = hs_geometry.new(test)
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

function M:activeLayouts()  -- :string
  local active_layouts = {}
  hs.fnutils.each(self.window_layouts, function(layout)
    if layout:active() then
      active_layouts[#active_layouts+1] = layout.logname
    end
  end)
  setmetatable(active_layouts, { __tostring = function(t) return table.concat(t, '|') end, })
  function active_layouts:tostring() return tostring(self) end  -- luacheck: no redefined
  return active_layouts
end


function M:start()
  self.starting = true
  self:window_layouts_enable()

  self.hotkey = self.hotkey or hs.hotkey.new({'⌘', '⌥', '⌃', '⇧'}, 's', function() M:toggle_or_choose() end)
  self.hotkey:enable()

  self.screenwatcher = hs.screen.watcher.new(function()
    self.watchable.active_layouts = self:activeLayouts():tostring()
  end):start()
  self.starting = nil
  return self
end
function M:stop()
  self:window_layouts_disable()
  if self.hotkey then self.hotkey:disable() end
  if self.screenwatcher then self.screenwatcher:stop() end
  return self
end


-- config in init.consts.window_layouts
for layout_name,layout in pairs(init.consts.window_layouts) do
  local window_layout = hs.window.layout.new(layout, layout_name)
  M.window_layouts[layout_name] = window_layout
  for _,rule in pairs(window_layout.rules) do
    rule.windowfilter:setOverrideFilter({visible=true})
  end
end

return M
