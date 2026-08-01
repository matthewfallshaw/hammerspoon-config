--- === notify ===
--- Growl-replacement notifications: non-modal, persistent-until-dismissed,
--- stacked, styled cards drawn with `hs.canvas`. See TODO.md for the design
--- rationale (why `hs.canvas` over `hs.alert`/`hs.notify`, why a fixed-width
--- monospace card, why persistence goes through `hs.settings`, etc).
---
--- This module owns the stack: an ordered array of records (index 1 =
--- oldest = topmost, newest appended at the bottom), their auto-dismiss
--- timers, hover-pause, keyboard/mouse dismissal, id replace-in-place, and
--- persistence of sticky/non-private cards across `hs.reload()` and a
--- restart. Layout arithmetic (wrapping, truncation, stack frames) lives in
--- `notify.layout`, which has no `hs.*` dependency. Actual canvas drawing
--- lives in `notify.card` (see the `M._renderer` seam below), so this
--- module has no drawing code of its own.
---
--- No error escapes any public function here (`show`/`dismiss`/`dismissAll`/
--- `start`/`stop`): this module shares a process with window management,
--- so a bug in a notification must not take that down.

local M = {}

-- Metadata
M.name = "Notify"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

M._logger = hs.logger.new("Notify")
local logger = M._logger

local layout = require("notify.layout")
local consts = require("configConsts")

--------------------------------------------------------------------------------
-- Config: consts.notify, with in-code defaults for anything missing so a
-- partial config can never crash the module.
--------------------------------------------------------------------------------

local DEFAULTS = {
  card_width = 320,
  max_lines = 12,
  stack_gap = 8,
  margin_top = 8,
  margin_right = 8,
  padding = 12,
  title_height = 18,
  title_gap = 6,
  line_height = 16,
  min_height = 48,
  icon_width = 32,
  icon_gap = 8,
  tab_width = 4,
  close_size = 14,
  corner_radius = 8,
  char_width = 7.2,
  body_font = "SFMono-Regular",
  body_font_size = 12,
  title_font = ".AppleSystemUIFont",
  title_font_size = 13,
  default_duration = 5,
  fade_in = 0.15,
  fade_out = 0.15,
  pulse_duration = 0.4,
  max_cards = 8,
  settings_key = "notify.persisted",
  dismiss_all_hotkey = { mods = {}, key = "n" },
}

local DEFAULT_PALETTES = {
  dark = {
    background = { white = 0, alpha = 0.75 },
    border = { white = 1, alpha = 1 },
    title = { white = 1, alpha = 1 },
    body = { white = 1, alpha = 0.9 },
    footer = { white = 1, alpha = 0.6 },
    close = { white = 1, alpha = 0.6 },
    close_hover = { white = 1, alpha = 1 },
    pulse = { white = 1, alpha = 1 },
  },
  light = {
    background = { white = 1, alpha = 0.92 },
    border = { white = 0, alpha = 0.3 },
    title = { white = 0, alpha = 1 },
    body = { white = 0, alpha = 0.85 },
    footer = { white = 0, alpha = 0.5 },
    close = { white = 0, alpha = 0.5 },
    close_hover = { white = 0, alpha = 1 },
    pulse = { white = 0, alpha = 1 },
  },
}

local userCfg = consts.notify or {}
local cfg = {}
for k, v in pairs(DEFAULTS) do cfg[k] = v end
for k, v in pairs(userCfg) do cfg[k] = v end
cfg.palettes = userCfg.palettes or DEFAULT_PALETTES

-- The macOS virtual keycode for Escape. Not a "limit" (nothing to tune), so
-- unlike everything in `cfg` it's a plain local constant here, matching how
-- hyper.lua hardcodes its own physical key constants (`HOTKEY`/`HOTKEY_VIRTUAL`)
-- rather than pushing them into configConsts.
local ESCAPE_KEYCODE = 53

--------------------------------------------------------------------------------
-- Renderer seam
--
-- notify/card.lua is a sibling module (built concurrently); requiring it
-- eagerly would make a missing/broken card.lua break `require("notify")`
-- itself. So the require is deferred to first use and pcall-wrapped, and
-- exposed as an overridable field so specs can inject a fake renderer
-- without notify/card.lua needing to exist yet.
--
-- M._renderer states: nil = not yet attempted; false = attempted and
-- failed to load; table = the renderer module (real or a test double).
--------------------------------------------------------------------------------

M._renderer = nil

local function getRenderer()
  if M._renderer == nil then
    local ok, mod = pcall(require, "notify.card")
    if ok then
      M._renderer = mod
    else
      logger.e("notify: failed to load notify.card: " .. tostring(mod))
      M._renderer = false
    end
  end
  if M._renderer == false then
    return nil
  end
  return M._renderer
end

--------------------------------------------------------------------------------
-- Hotkey binding seam
--
-- hyper.lua calls hs.hotkey.modal.new(...) at load time, which isn't mocked
-- in spec_helper.lua, so requiring it under busted would error before any
-- test runs. Binding goes through an overridable field for the same reason
-- as the renderer seam: specs inject a fake and assert it was called,
-- rather than fighting the mocks.
--------------------------------------------------------------------------------

M._bindHotkey = function(mods, key, handler)
  local ok, hyper = pcall(require, "hyper")
  if ok and hyper and hyper.bindKey then
    hyper.bindKey(mods, key, handler)
  else
    logger.e("notify: could not bind dismissAll hotkey (hyper unavailable)")
  end
end

--------------------------------------------------------------------------------
-- Stack state
--------------------------------------------------------------------------------

-- Ordered array of records; index 1 = oldest = topmost, new cards appended
-- at the end (bottom). Each record:
--   { id, title, message, icon, sticky, duration, private,
--     card, height, palette, frame, handle, timer, remaining, deadline,
--     hovering, keyTap }
M._stack = {}
M._autoIdSeq = 0

local function findIndexById(id)
  if id == nil then return nil end
  for i, record in ipairs(M._stack) do
    if record.id == id then return i end
  end
  return nil
end

local function generateId()
  local id
  repeat
    M._autoIdSeq = M._autoIdSeq + 1
    id = "auto:" .. M._autoIdSeq
  until not findIndexById(id)
  return id
end

--------------------------------------------------------------------------------
-- Config mapping: notify's snake_case cfg -> layout/card's camelCase cfg.
-- One shared table for both: notify.layout's functions only read the keys
-- they need and ignore the rest, so the renderer-only keys (fonts, fades,
-- close size, etc) ride along harmlessly.
--------------------------------------------------------------------------------

local function buildRenderCfg()
  return {
    padding = cfg.padding,
    titleHeight = cfg.title_height,
    titleGap = cfg.title_gap,
    lineHeight = cfg.line_height,
    minHeight = cfg.min_height,
    cardWidth = cfg.card_width,
    stackGap = cfg.stack_gap,
    marginTop = cfg.margin_top,
    marginRight = cfg.margin_right,
    charWidth = cfg.char_width,
    maxLines = cfg.max_lines,
    iconWidth = cfg.icon_width,
    iconGap = cfg.icon_gap,
    tabWidth = cfg.tab_width,
    bodyFont = cfg.body_font,
    bodyFontSize = cfg.body_font_size,
    titleFont = cfg.title_font,
    titleFontSize = cfg.title_font_size,
    fadeIn = cfg.fade_in,
    fadeOut = cfg.fade_out,
    closeSize = cfg.close_size,
    cornerRadius = cfg.corner_radius,
    pulseDuration = cfg.pulse_duration,
  }
end

local function currentPalette()
  if hs.host.interfaceStyle() == "Dark" then
    return cfg.palettes.dark
  end
  return cfg.palettes.light
end

--------------------------------------------------------------------------------
-- Stack frame arithmetic: recompute from current heights, move only the
-- cards whose frame actually changed. This is how a dismissal closes the
-- gap above the cards below it, while cards above it (which didn't move)
-- are left alone.
--------------------------------------------------------------------------------

local function framesEqual(a, b)
  if a == nil or b == nil then return a == b end
  return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function computeFrames()
  local heights = {}
  for i, record in ipairs(M._stack) do heights[i] = record.height end
  local screenFrame = hs.screen.primaryScreen():frame()
  return layout.stackFrames(heights, screenFrame, buildRenderCfg())
end

local function applyFrames(frames)
  for i, record in ipairs(M._stack) do
    local newFrame = frames[i]
    if not framesEqual(record.frame, newFrame) then
      record.frame = newFrame
      if record.handle then record.handle:setFrame(newFrame) end
    end
  end
end

--------------------------------------------------------------------------------
-- Persistence: sticky and non-sticky non-private cards are written to
-- hs.settings on every mutation (show/dismiss/expire/update), keyed by
-- cfg.settings_key, as absolute deadlines. Non-sticky cards are included
-- (not just stickies) so a restore can drop already-expired ones and
-- correctly reschedule the rest, rather than losing a mid-countdown card
-- to every reload. Private cards are never written, full stop.
--------------------------------------------------------------------------------

local function persist()
  local ok, err = pcall(function()
    local records = {}
    for _, record in ipairs(M._stack) do
      if not record.private then
        table.insert(records, {
          id = record.id,
          title = record.title,
          message = record.message,
          icon = record.icon,
          sticky = record.sticky,
          duration = record.duration,
          deadline = record.deadline,
        })
      end
    end
    hs.settings.set(cfg.settings_key, records)
  end)
  if not ok then
    logger.e("notify: failed to persist stack: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- Timers: absolute deadlines (hs.timer.secondsSinceEpoch() + duration), not
-- remaining durations, so a reload mid-countdown doesn't reset or eat the
-- timer. Sticky records get no timer.
--------------------------------------------------------------------------------

local function stopTimer(record)
  if record.timer then
    record.timer:stop()
    record.timer = nil
  end
end

local function scheduleTimerFor(record, duration)
  record.deadline = hs.timer.secondsSinceEpoch() + duration
  record.timer = hs.timer.doAfter(duration, function()
    M._expire(record.id)
  end)
end

-- Schedules against a pre-existing absolute deadline (used when restoring
-- persisted cards, where `deadline` -- not a fresh `duration` -- is the
-- thing that survived).
local function scheduleTimerAtDeadline(record, deadline)
  local remaining = deadline - hs.timer.secondsSinceEpoch()
  if remaining < 0 then remaining = 0 end
  record.deadline = deadline
  record.timer = hs.timer.doAfter(remaining, function()
    M._expire(record.id)
  end)
end

local function armTimer(record)
  stopTimer(record)
  record.remaining = nil
  record.deadline = nil
  if record.sticky then return end
  scheduleTimerFor(record, record.duration)
end

--------------------------------------------------------------------------------
-- Hover pause/resume and the escape-while-hovering eventtap.
--------------------------------------------------------------------------------

local function pauseTimer(record)
  if record.sticky then return end
  if record.timer then
    stopTimer(record)
  end
  if record.deadline then
    record.remaining = record.deadline - hs.timer.secondsSinceEpoch()
  end
end

local function resumeTimer(record)
  if record.sticky then return end
  if record.remaining == nil then return end
  local remaining = record.remaining
  record.remaining = nil
  scheduleTimerFor(record, remaining)
end

local function stopKeyTap(record)
  if record.keyTap then
    record.keyTap:stop()
    record.keyTap = nil
  end
end

local function startKeyTap(record)
  if record.keyTap then return end
  record.keyTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local ok, err = pcall(function()
      if event:getKeyCode() == ESCAPE_KEYCODE then
        M.dismiss(record.id)
      end
    end)
    if not ok then
      logger.e("notify: eventtap handler error: " .. tostring(err))
    end
    return false -- never swallow the key
  end)
  record.keyTap:start()
end

--- notify._handleEvent(record, eventName, elementId)
--- Function
--- Internal. The `onEvent` callback passed to every card's renderer
--- handle. pcall-wrapped so a bug in mouse handling can't escape into the
--- canvas's own mouseCallback (which runs in-process with everything
--- else).
---
--- Parameters:
---  * record - the stack record this card belongs to.
---  * eventName - ("mouseEnter"|"mouseExit"|"mouseUp"|other) other event
---    names are accepted and ignored.
---  * elementId - the id of the canvas element hit, or nil.
function M._handleEvent(record, eventName, elementId)
  local ok, err = pcall(function()
    if eventName == "mouseEnter" then
      record.hovering = true
      pauseTimer(record)
      startKeyTap(record)
    elseif eventName == "mouseExit" then
      record.hovering = false
      stopKeyTap(record)
      resumeTimer(record)
    elseif eventName == "mouseUp" then
      if elementId == "close" then
        M.dismiss(record.id)
      end
      -- Anywhere else: nothing. Click is reserved for a future clickAction.
    end
  end)
  if not ok then
    logger.e("notify: event handler error: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- show / dismiss / dismissAll
--------------------------------------------------------------------------------

local function withDefaults(opts)
  opts = opts or {}
  return {
    message = opts.message or "",
    title = (opts.title ~= nil) and opts.title or "Notice",
    sticky = opts.sticky and true or false,
    duration = opts.duration or cfg.default_duration,
    icon = opts.icon,
    id = opts.id,
    private = opts.private and true or false,
  }
end

local function deleteHandle(record)
  if not record.handle then return end
  local ok, err = pcall(function() record.handle:delete(cfg.fade_out) end)
  if not ok then
    logger.e("notify: renderer delete failed: " .. tostring(err))
  end
end

local function removeAt(idx)
  local record = M._stack[idx]
  stopTimer(record)
  stopKeyTap(record)
  deleteHandle(record)
  table.remove(M._stack, idx)
  applyFrames(computeFrames())
  persist()
end

-- Internal. Fired by a record's auto-dismiss timer.
function M._expire(id)
  local ok, err = pcall(function()
    local idx = findIndexById(id)
    if idx then removeAt(idx) end
  end)
  if not ok then
    logger.e("notify: expire error: " .. tostring(err))
  end
end

local function appendNew(o)
  local id = o.id or generateId()
  local palette = currentPalette()
  local rcfg = buildRenderCfg()
  local card = layout.compose({ message = o.message, title = o.title, icon = o.icon }, rcfg)

  local record = {
    id = id,
    title = o.title,
    message = o.message,
    icon = o.icon,
    sticky = o.sticky,
    duration = o.duration,
    private = o.private,
    card = card,
    height = card.height,
    palette = palette,
    frame = nil,
    handle = nil,
    timer = nil,
    remaining = nil,
    deadline = nil,
    hovering = false,
    keyTap = nil,
  }

  table.insert(M._stack, record)
  local frames = computeFrames()
  record.frame = frames[#M._stack]

  local renderer = getRenderer()
  local handle = nil
  if renderer then
    local ok, result = pcall(renderer.new, {
      card = card,
      frame = record.frame,
      palette = palette,
      cfg = rcfg,
      icon = o.icon,
      onEvent = function(evt, el) M._handleEvent(record, evt, el) end,
    })
    if ok then
      handle = result
    else
      logger.e("notify: renderer.new failed: " .. tostring(result))
    end
  else
    logger.e("notify: no renderer available, card will not be drawn")
  end

  if not handle then
    -- Roll back rather than leave a handle-less record permanently
    -- occupying a stack slot (and counting against max_cards).
    table.remove(M._stack, #M._stack)
    applyFrames(computeFrames())
    return nil
  end

  record.handle = handle
  applyFrames(frames)
  armTimer(record)
  persist()
  return id
end

local function replaceInPlace(idx, o)
  local record = M._stack[idx]
  stopTimer(record)
  stopKeyTap(record)
  record.hovering = false

  record.title = o.title
  record.message = o.message
  record.icon = o.icon
  record.sticky = o.sticky
  record.duration = o.duration
  record.private = o.private

  local palette = currentPalette()
  local rcfg = buildRenderCfg()
  local card = layout.compose({ message = o.message, title = o.title, icon = o.icon }, rcfg)
  record.card = card
  record.height = card.height
  record.palette = palette

  if record.handle then
    local ok, err = pcall(function()
      record.handle:update({ card = card, palette = palette, icon = o.icon })
      record.handle:pulse()
    end)
    if not ok then
      logger.e("notify: renderer update/pulse failed: " .. tostring(err))
    end
  end

  applyFrames(computeFrames())
  armTimer(record)
  persist()
  return record.id
end

--- notify.show(opts) -> string or nil
--- Function
--- Shows a notification card, or replaces one in place if `opts.id`
--- matches a card already in the stack.
---
--- Parameters:
---  * opts - (table) `{ message, title, sticky, duration, icon, id,
---    private }`. `message` defaults to `""`; `title` defaults to
---    `"Notice"`; `sticky` and `private` default to `false`; `duration`
---    defaults to `cfg.default_duration` and is ignored when `sticky` is
---    true; `icon` and `id` default to `nil` (an id is generated when
---    omitted).
---
--- Returns:
---  * id - (string or nil) the card's id (generated if none given), or
---    `nil` if the call failed or was dropped because the stack is at
---    `cfg.max_cards`.
function M.show(opts)
  local id = nil
  local ok, err = pcall(function()
    local o = withDefaults(opts)
    local existingIdx = o.id and findIndexById(o.id) or nil

    if existingIdx then
      id = replaceInPlace(existingIdx, o)
    elseif #M._stack >= cfg.max_cards then
      logger.w("notify.show: dropping notification, stack at max_cards (" .. tostring(cfg.max_cards) .. ")")
    else
      id = appendNew(o)
    end
  end)
  if not ok then
    logger.e("notify.show error: " .. tostring(err))
    return nil
  end
  return id
end

--- notify.dismiss(id)
--- Function
--- Dismisses the card with the given id. A no-op (does not throw) if no
--- such card is currently in the stack.
---
--- Parameters:
---  * id - (string) the card's id.
function M.dismiss(id)
  local ok, err = pcall(function()
    local idx = findIndexById(id)
    if idx then removeAt(idx) end
  end)
  if not ok then
    logger.e("notify.dismiss error: " .. tostring(err))
  end
end

--- notify.dismissAll()
--- Function
--- Dismisses every card in the stack. A no-op (does not throw) if the
--- stack is already empty.
function M.dismissAll()
  local ok, err = pcall(function()
    for _, record in ipairs(M._stack) do
      stopTimer(record)
      stopKeyTap(record)
      deleteHandle(record)
    end
    M._stack = {}
    persist()
  end)
  if not ok then
    logger.e("notify.dismissAll error: " .. tostring(err))
  end
end

--------------------------------------------------------------------------------
-- Lifecycle
--------------------------------------------------------------------------------

-- Internal. Restores persisted cards on start(): drops any whose deadline
-- has passed, re-shows the rest in their persisted order (preserving id
-- and, for non-sticky cards, the original absolute deadline rather than a
-- fresh full-length timer), then rewrites the settings key.
local function restore()
  local persisted = hs.settings.get(cfg.settings_key) or {}
  local now = hs.timer.secondsSinceEpoch()

  for _, rec in ipairs(persisted) do
    if rec.sticky or (rec.deadline and rec.deadline > now) then
      local palette = currentPalette()
      local rcfg = buildRenderCfg()
      local card = layout.compose({ message = rec.message, title = rec.title, icon = rec.icon }, rcfg)

      local record = {
        id = rec.id,
        title = rec.title,
        message = rec.message,
        icon = rec.icon,
        sticky = rec.sticky,
        duration = rec.duration,
        private = false,
        card = card,
        height = card.height,
        palette = palette,
        frame = nil,
        handle = nil,
        timer = nil,
        remaining = nil,
        deadline = nil,
        hovering = false,
        keyTap = nil,
      }

      table.insert(M._stack, record)
      local frames = computeFrames()
      record.frame = frames[#M._stack]

      local renderer = getRenderer()
      local handle = nil
      if renderer then
        local ok, result = pcall(renderer.new, {
          card = card,
          frame = record.frame,
          palette = palette,
          cfg = rcfg,
          icon = rec.icon,
          onEvent = function(evt, el) M._handleEvent(record, evt, el) end,
        })
        if ok then
          handle = result
        else
          logger.e("notify: renderer.new failed while restoring " .. tostring(rec.id) .. ": " .. tostring(result))
        end
      else
        logger.e("notify: no renderer available, restored card will not be drawn")
      end

      if not handle then
        -- Roll back this one persisted card rather than wedge the whole
        -- restore or leave a handle-less record in the stack.
        table.remove(M._stack, #M._stack)
        applyFrames(computeFrames())
      else
        record.handle = handle
        applyFrames(frames)

        if record.sticky then
          record.timer = nil
          record.deadline = nil
        else
          scheduleTimerAtDeadline(record, rec.deadline)
        end
      end
    end
  end

  persist()
end

--- notify.start()
--- Function
--- Restores persisted sticky (and not-yet-expired non-sticky) cards, and
--- binds the `dismissAll` safety-valve hotkey (`cfg.dismiss_all_hotkey`,
--- default hyper-`n`) via `M._bindHotkey`.
function M.start()
  local ok, err = pcall(function()
    local hotkey = cfg.dismiss_all_hotkey or DEFAULTS.dismiss_all_hotkey
    M._bindHotkey(hotkey.mods, hotkey.key, function() M.dismissAll() end)
    restore()
  end)
  if not ok then
    logger.e("notify.start error: " .. tostring(err))
  end
end

--- notify.stop()
--- Function
--- Lifecycle counterpart to `start()`. Currently a no-op beyond safety
--- wrapping: persisted/live cards are left alone (nothing here should
--- make a reload lose state that `hs.settings` already has), and, matching
--- the rest of this config's convention (see `hyper.lua` callers), hyper
--- key bindings made in `start()` are not individually torn down.
function M.stop()
  local ok, err = pcall(function() end)
  if not ok then
    logger.e("notify.stop error: " .. tostring(err))
  end
end

return M
