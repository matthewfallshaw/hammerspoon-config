--- === notify ===
--- Growl-replacement notifications: non-modal, persistent-until-dismissed,
--- stacked, styled cards drawn with `hs.canvas`. See TODO.md for the design
--- rationale (why `hs.canvas` over `hs.alert`/`hs.notify`, why a fixed-width
--- monospace card, why persistence goes through `hs.settings`, etc).
---
--- This module owns the stack: an ordered array of records (index 1 = oldest
--- = topmost, newest appended at the bottom), their auto-dismiss timers,
--- hover-pause, keyboard/mouse dismissal, id replace-in-place, and
--- persistence of non-private cards across `hs.reload()` and a restart. It
--- also owns the configuration for the whole of `notify`: layout arithmetic
--- (`notify.layout`), canvas drawing (`notify.card`) and the swipe state
--- machine (`notify.gesture`) are each handed a complete config and keep no
--- defaults of their own.
---
--- No error escapes any public function here (`show`/`dismiss`/`dismissAll`/
--- `start`/`stop`): this module shares a process with window management, so a
--- bug in a notification must not take that down.

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
require("utilities.table")

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

-- Fallbacks for anything `configConsts.notify` doesn't set, so a partial
-- config can never crash the module. The merge is shallow: `swipe` and
-- `palettes` are taken whole from `configConsts.notify` when present, never
-- merged key by key.
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
  hover_exit_grace = 0.05,
  settings_key = "notify.persisted",
  palettes = DEFAULT_PALETTES,
  swipe = {
    enabled = true,
    min_distance = 0.15,
    max_distance = 0.9,
    max_duration = 0.6,
    max_velocity_change = 2.0,
    direction_tolerance = 0.05,
  },
}

-- The config the module runs on, and the one handed whole to notify.card
-- (styling) and, as `cfg.swipe`, to notify.gesture. Exposed so specs (and the
-- console) read the live table.
M._cfg = table.merge(DEFAULTS, consts.notify)  --luacheck: ignore 143
local cfg = M._cfg

-- The macOS virtual keycode for Escape: a physical fact, not a tunable, so it
-- stays here rather than in configConsts (as hyper.lua does with its own).
local ESCAPE_KEYCODE = 53

-- Renderer seam. The require is deferred to first use and pcall-wrapped so a
-- broken notify/card.lua can't break `require("notify")` itself, and is an
-- overridable field so specs can inject a fake. States: nil = not yet
-- attempted; false = attempted and failed; table = the renderer module.
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

-- Ordered array of records; index 1 = oldest = topmost, new cards appended at
-- the end (bottom). Each record:
--   { id, title, message, icon, sticky, duration, private,
--     card, height, palette, frame, handle, timer, remaining, deadline,
--     hovered, hoverExitTimer, keyTap }
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

-- Swipe-to-dismiss gesture. Created on the first stack mutation that leaves
-- the stack non-empty and torn down whenever it empties, so the tap isn't
-- sitting in the event path all day. Lazily require()'d and pcall-wrapped
-- throughout: a broken gesture module must not take down show/dismiss.
-- cfg.swipe.enabled = false means the tap is never created at all.
M._gesture = nil

-- Topmost-first (index 1 = oldest = topmost, matching M._stack's ordering).
local function hitTestStack(point)
  for _, record in ipairs(M._stack) do
    local f = record.frame
    if f and point.x >= f.x and point.x <= f.x + f.w
        and point.y >= f.y and point.y <= f.y + f.h then
      return record.id
    end
  end
  return nil
end

local function ensureGestureStarted()
  local swipeCfg = cfg.swipe
  if not swipeCfg or swipeCfg.enabled == false then return end
  if M._gesture == nil then
    local ok, result = pcall(function()
      local gesture = require("notify.gesture")
      return gesture.new({
        cfg = swipeCfg,
        hitTest = hitTestStack,
        onSwipe = function(id) M.dismiss(id) end,
      })
    end)
    if not ok then
      logger.e("notify: failed to create gesture: " .. tostring(result))
      return
    end
    M._gesture = result
  end
  local ok, err = pcall(function() M._gesture.start() end)
  if not ok then
    logger.e("notify: failed to start gesture: " .. tostring(err))
  end
end

local function ensureGestureStopped()
  if M._gesture == nil then return end
  local ok, err = pcall(function() M._gesture.stop() end)
  if not ok then
    logger.e("notify: failed to stop gesture: " .. tostring(err))
  end
end

local function syncGestureToStack()
  if #M._stack > 0 then
    ensureGestureStarted()
  else
    ensureGestureStopped()
  end
end

-- notify's snake_case cfg -> notify.layout's camelCase cfg. notify.layout is
-- this shape's only consumer; notify.card takes `cfg` itself, unmapped.
local function buildLayoutCfg()
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
  }
end

local function currentPalette()
  if hs.host.interfaceStyle() == "Dark" then
    return cfg.palettes.dark
  end
  return cfg.palettes.light
end

local function framesEqual(a, b)
  if a == nil or b == nil then return a == b end
  return a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h
end

local function computeFrames()
  local heights = {}
  for i, record in ipairs(M._stack) do heights[i] = record.height end
  local screenFrame = hs.screen.primaryScreen():frame()
  return layout.stackFrames(heights, screenFrame, buildLayoutCfg())
end

-- Recompute from current heights, moving only the cards whose frame actually
-- changed: that is how a dismissal closes the gap above the cards below it
-- while leaving the cards above it alone.
local function applyFrames(frames)
  for i, record in ipairs(M._stack) do
    local newFrame = frames[i]
    if not framesEqual(record.frame, newFrame) then
      record.frame = newFrame
      if record.handle then record.handle:setFrame(newFrame) end
    end
  end
end

-- Non-private cards are written to hs.settings on every mutation as absolute
-- deadlines -- or, for a card paused under the mouse, as the `remaining`
-- duration, since its deadline stops meaning anything the moment the countdown
-- stops. Non-sticky cards are included (not just stickies) so a restore can
-- drop the already-expired ones and reschedule the rest, rather than losing a
-- mid-countdown card to every reload. Private cards are never written.
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
          remaining = record.remaining,
        })
      end
    end
    hs.settings.set(cfg.settings_key, records)
  end)
  if not ok then
    logger.e("notify: failed to persist stack: " .. tostring(err))
  end
end

local function stopTimer(record)
  if record.timer then
    record.timer:stop()
    record.timer = nil
  end
end

-- Timers hold absolute deadlines, not remaining durations, so a reload
-- mid-countdown doesn't reset or eat the timer. Sticky records get no timer.
local function scheduleTimerFor(record, duration)
  record.deadline = hs.timer.secondsSinceEpoch() + duration
  record.timer = hs.timer.doAfter(duration, function()
    M._expire(record.id)
  end)
end

-- Used when restoring persisted cards, where `deadline` -- not a fresh
-- `duration` -- is the thing that survived.
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

local function pauseTimer(record)
  if record.sticky then return end
  if record.timer then
    stopTimer(record)
  end
  if record.deadline then
    record.remaining = record.deadline - hs.timer.secondsSinceEpoch()
    record.deadline = nil
    persist()
  end
end

local function resumeTimer(record)
  if record.sticky then return end
  if record.remaining == nil then return end
  local remaining = record.remaining
  record.remaining = nil
  scheduleTimerFor(record, remaining)
  persist()
end

local function stopKeyTap(record)
  if record.keyTap then
    record.keyTap:stop()
    record.keyTap = nil
  end
end

-- Escape dismisses the card the mouse is over; the tap lives only for as long
-- as the hover does.
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

-- Hover is a property of the card, not of the element under the pointer:
-- `record.hovered` is the set of element ids currently entered.
local function isHovered(record)
  return next(record.hovered) ~= nil
end

local function cancelHoverExit(record)
  if record.hoverExitTimer then
    record.hoverExitTimer:stop()
    record.hoverExitTimer = nil
  end
end

-- Drops all hover state; used wherever a record stops being the one under the
-- pointer (dismissal, replacement) as well as at the end of a real un-hover.
local function clearHover(record)
  cancelHoverExit(record)
  record.hovered = {}
  stopKeyTap(record)
end

-- Internal. Fired by the hover-exit grace timer. Nils its own handle first, so
-- a timer stopped by cancelHoverExit (or by a dismissal) that fires anyway is
-- a no-op rather than a resume against a dead record.
function M._hoverExit(record)
  local ok, err = pcall(function()
    if not record.hoverExitTimer then return end
    record.hoverExitTimer = nil
    if isHovered(record) then return end
    stopKeyTap(record)
    resumeTimer(record)
  end)
  if not ok then
    logger.e("notify: hover exit error: " .. tostring(err))
  end
end

--- notify._handleEvent(record, eventName, elementId)
--- Internal. The `onEvent` callback passed to every card's renderer handle.
--- pcall-wrapped so a bug in mouse handling can't escape into the canvas's own
--- mouseCallback.
function M._handleEvent(record, eventName, elementId)
  local ok, err = pcall(function()
    record.hovered = record.hovered or {}
    local elementKey = elementId or "card"
    if eventName == "mouseEnter" then
      local wasHovered = isHovered(record) or record.hoverExitTimer ~= nil
      cancelHoverExit(record)
      record.hovered[elementKey] = true
      if not wasHovered then
        pauseTimer(record)
        startKeyTap(record)
      end
    elseif eventName == "mouseExit" then
      record.hovered[elementKey] = nil
      if not isHovered(record) then
        cancelHoverExit(record)
        record.hoverExitTimer = hs.timer.doAfter(cfg.hover_exit_grace, function()
          M._hoverExit(record)
        end)
      end
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
  clearHover(record)
  deleteHandle(record)
  table.remove(M._stack, idx)
  applyFrames(computeFrames())
  persist()
  syncGestureToStack()
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

-- Builds a record from `o` (a withDefaults-shaped table with an id), appends
-- it at the bottom of the stack and draws it. Returns the record, or nil --
-- leaving the stack exactly as it found it -- if the renderer failed, since a
-- handle-less record would occupy a stack slot forever. The caller owns the
-- timer, persistence and gesture sync.
local function pushCard(o)
  local palette = currentPalette()
  local card = layout.compose({ message = o.message, title = o.title, icon = o.icon }, buildLayoutCfg())

  local record = {
    id = o.id,
    title = o.title,
    message = o.message,
    icon = o.icon,
    sticky = o.sticky,
    duration = o.duration,
    private = o.private,
    card = card,
    height = card.height,
    palette = palette,
    hovered = {},
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
      cfg = cfg,
      icon = o.icon,
      onEvent = function(evt, el) M._handleEvent(record, evt, el) end,
    })
    if ok then
      handle = result
    else
      logger.e("notify: renderer.new failed for " .. tostring(o.id) .. ": " .. tostring(result))
    end
  else
    logger.e("notify: no renderer available, card will not be drawn")
  end

  if not handle then
    table.remove(M._stack, #M._stack)
    applyFrames(computeFrames())
    return nil
  end

  record.handle = handle
  applyFrames(frames)
  return record
end

local function appendNew(o)
  o.id = o.id or generateId()
  local record = pushCard(o)
  if not record then return nil end
  armTimer(record)
  persist()
  syncGestureToStack()
  return record.id
end

local function replaceInPlace(idx, o)
  local record = M._stack[idx]
  stopTimer(record)
  clearHover(record)

  record.title = o.title
  record.message = o.message
  record.icon = o.icon
  record.sticky = o.sticky
  record.duration = o.duration
  record.private = o.private

  local palette = currentPalette()
  local card = layout.compose({ message = o.message, title = o.title, icon = o.icon }, buildLayoutCfg())
  record.card = card
  record.height = card.height
  record.palette = palette

  if record.handle then
    local ok, err = pcall(function()
      record.handle:update({ card = card, palette = palette, cfg = cfg, icon = o.icon })
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
--- Shows a notification card, or replaces one in place if `opts.id` matches a
--- card already in the stack. `opts` is `{ message, title, sticky, duration,
--- icon, id, private }`; `message` defaults to `""`, `title` to `"Notice"`,
--- `sticky` and `private` to `false`, `duration` to `cfg.default_duration`
--- (ignored when `sticky`), and an id is generated when omitted.
---
--- Returns the card's id, or `nil` if the call failed.
function M.show(opts)
  local id = nil
  local ok, err = pcall(function()
    local o = withDefaults(opts)
    local existingIdx = o.id and findIndexById(o.id) or nil

    if existingIdx then
      id = replaceInPlace(existingIdx, o)
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
--- Dismisses the card with the given id; a no-op if no such card is in the
--- stack.
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
--- Dismisses every card in the stack; a no-op if it is already empty.
function M.dismissAll()
  local ok, err = pcall(function()
    for _, record in ipairs(M._stack) do
      stopTimer(record)
      clearHover(record)
      deleteHandle(record)
    end
    M._stack = {}
    persist()
    syncGestureToStack()
  end)
  if not ok then
    logger.e("notify.dismissAll error: " .. tostring(err))
  end
end

-- Internal. Restores persisted cards: drops any whose deadline has passed,
-- re-shows the rest in their persisted order, preserving id and -- for
-- non-sticky cards -- the original absolute deadline, or the remaining
-- duration for one persisted while hover-paused, rather than a fresh
-- full-length timer.
local function restore()
  local persisted = hs.settings.get(cfg.settings_key) or {}
  local now = hs.timer.secondsSinceEpoch()

  for _, rec in ipairs(persisted) do
    if rec.sticky or rec.remaining or (rec.deadline and rec.deadline > now) then
      local record = pushCard({
        id = rec.id,
        title = rec.title,
        message = rec.message,
        icon = rec.icon,
        sticky = rec.sticky,
        duration = rec.duration,
        private = false,
      })
      if record and not record.sticky then
        if rec.remaining then
          scheduleTimerFor(record, rec.remaining)
        else
          scheduleTimerAtDeadline(record, rec.deadline)
        end
      end
    end
  end

  persist()
  syncGestureToStack()
end

--- notify:start()
--- Restores persisted sticky (and not-yet-expired non-sticky) cards.
function M:start()  --luacheck: no self
  local ok, err = pcall(function()
    restore()
  end)
  if not ok then
    logger.e("notify.start error: " .. tostring(err))
  end
end

--- notify:stop()
--- Lifecycle counterpart to `start()`, deliberately empty: live cards and
--- their persisted state are left alone (`hs.reload()` destroys the canvases
--- and `start()` restores from `hs.settings`), and, as everywhere else in this
--- config, hyper bindings are not individually torn down.
function M:stop()  --luacheck: no self
end

return M
