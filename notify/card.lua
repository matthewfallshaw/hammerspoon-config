--- === notify.card ===
--- Thin `hs.canvas` renderer for a single notification card.
---
--- Deliberately does **no layout arithmetic**: every position it paints
--- comes straight from the `card` table `notify.layout.compose` already
--- produced (title, wrapped lines, overflow footer, height) and from the
--- `cfg` table handed in. If a wrap or a total height ever needs computing
--- here, that is a sign the value belongs in `notify.layout` instead.
---
--- Every element carries a stable `id` so `notify.init`'s `mouseCallback`
--- consumer can tell them apart: `"body"` for the background, `"close"` for
--- the dismiss glyph, `"icon"`/`"title"`/`"footer"` for their singletons,
--- and `"line1"`, `"line2"`, ... for wrapped body text, one element per
--- already-wrapped line (never handed to the canvas as one blob to
--- re-wrap -- see `buildElements` below).

local M = {}

-- Metadata
M.name = "NotifyCard"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

local logger = hs.logger.new("NotifyCard")

--------------------------------------------------------------------------------
-- Defaults
--
-- Mirrors configConsts.notify (see TODO.md "Styling"), so a caller that
-- forgets -- or only partially specifies -- a cfg/palette key still gets a
-- sane card instead of a crash.
--------------------------------------------------------------------------------

local DEFAULT_CFG = {
  padding = 12,
  title_height = 18,
  title_gap = 6,
  line_height = 16,
  char_width = 7.2,
  body_font = "SFMono-Regular",
  body_font_size = 12,
  title_font = ".AppleSystemUIFont",
  title_font_size = 13,
  icon_width = 32,
  icon_gap = 8,
  fade_in = 0.15,
  fade_out = 0.15,
  close_size = 14,
  corner_radius = 8,
  pulse_duration = 0.4,
}

-- Dark-anchored, matching hs.alert's own defaults ({white=0, alpha=0.75}
-- fill, white stroke) per TODO.md "Styling" -- used only when a caller
-- omits a palette key outright.
local DEFAULT_PALETTE = {
  background = { white = 0, alpha = 0.75 },
  border = { white = 1, alpha = 1 },
  title = { white = 1, alpha = 1 },
  body = { white = 1, alpha = 0.9 },
  footer = { white = 1, alpha = 0.6 },
  close = { white = 1, alpha = 0.6 },
  close_hover = { white = 1, alpha = 1 },
  pulse = { white = 1, alpha = 1 },
}

--- Shallow-merges `t` over a copy of `defaults`; `t`'s keys win.
local function withDefaults(defaults, t)
  local merged = {}
  for k, v in pairs(defaults) do merged[k] = v end
  for k, v in pairs(t or {}) do merged[k] = v end
  return merged
end

--------------------------------------------------------------------------------
-- Rendering (local; not part of the public API)
--------------------------------------------------------------------------------

--- Loads `icon` (a filesystem path or a named system/bundle image) into an
--- `hs.image` object. A string containing "/" is treated as a path
--- (`hs.image.imageFromPath`); anything else is treated as a named image
--- (`hs.image.imageFromName`) -- e.g. an `hs.image.systemImageNames` key.
local function loadIcon(icon)
  if not icon then return nil end
  if type(icon) == "string" and icon:find("/", 1, true) then
    return hs.image.imageFromPath(icon)
  end
  return hs.image.imageFromName(icon)
end

--- Builds the ordered element array for one card, in local canvas
--- coordinates (0,0 is the canvas's own top-left, independent of where
--- `notify.init` has placed the canvas on screen). Shared by `new` and
--- `update` so both paint identically.
---
--- Order: background, icon (optional), title (optional), one element per
--- body line, overflow footer (optional), close glyph.
local function buildElements(card, frame, palette, cfg, icon)
  local elements = {}
  local w, h = frame.w, frame.h

  table.insert(elements, {
    type = "rectangle",
    id = "body",
    action = "strokeAndFill",
    frame = { x = 0, y = 0, w = w, h = h },
    fillColor = palette.background,
    strokeColor = palette.border,
    roundedRectRadii = { xRadius = cfg.corner_radius, yRadius = cfg.corner_radius },
    -- Hover pauses the auto-dismiss countdown (notify.init's job); clicking
    -- the body itself is a deliberate no-op per TODO.md "Dismissal".
    trackMouseEnterExit = true,
  })

  local contentX = cfg.padding
  if card.hasIcon and icon then
    local image = loadIcon(icon)
    table.insert(elements, {
      type = "image",
      id = "icon",
      frame = { x = cfg.padding, y = cfg.padding, w = cfg.icon_width, h = cfg.icon_width },
      image = image,
    })
    contentX = cfg.padding + cfg.icon_width + cfg.icon_gap
  end
  local contentW = w - contentX - cfg.padding

  local y = cfg.padding
  if card.title then
    local title = {
      type = "text",
      id = "title",
      frame = { x = contentX, y = y, w = contentW - cfg.close_size - 4, h = cfg.title_height },
      text = card.title,
      textSize = cfg.title_font_size,
      textColor = palette.title,
      textAlignment = "left",
      -- Layout already decided the wrap; never let the canvas re-wrap.
      textLineBreak = "clip",
    }
    if cfg.title_font then title.textFont = cfg.title_font end
    table.insert(elements, title)
    y = y + cfg.title_height + cfg.title_gap
  end

  for i, line in ipairs(card.lines) do
    table.insert(elements, {
      type = "text",
      id = "line" .. i,
      frame = { x = contentX, y = y, w = contentW, h = cfg.line_height },
      text = line,
      textFont = cfg.body_font,
      textSize = cfg.body_font_size,
      textColor = palette.body,
      textAlignment = "left",
      textLineBreak = "clip",
    })
    y = y + cfg.line_height
  end

  if card.footer then
    table.insert(elements, {
      type = "text",
      id = "footer",
      frame = { x = contentX, y = y, w = contentW, h = cfg.line_height },
      text = card.footer,
      textFont = cfg.body_font,
      textSize = cfg.body_font_size,
      textColor = palette.footer,
      textAlignment = "left",
      textLineBreak = "clip",
    })
  end

  table.insert(elements, {
    type = "text",
    id = "close",
    frame = { x = w - cfg.padding - cfg.close_size, y = cfg.padding, w = cfg.close_size, h = cfg.close_size },
    text = "✕",
    textFont = cfg.body_font,
    textSize = cfg.close_size,
    textColor = palette.close,
    textAlignment = "center",
    trackMouseEnterExit = true,
    trackMouseDown = true,
    trackMouseUp = true,
  })

  return elements
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- notify.card.new(opts) -> handle
--- Constructor
--- Creates and shows the canvas for one notification card.
---
--- Parameters:
---  * opts - (table):
---    * card - (table) `notify.layout.compose`'s output: `{title, lines,
---      overflow, footer, height, hasIcon}`.
---    * frame - (table) `{x, y, w, h}`, the card's screen frame. `h`
---      should already equal `card.height`; this module does not compute
---      it.
---    * palette - (table or nil) `{background, border, title, body,
---      footer, close, close_hover, pulse}` hs colour tables. Missing
---      keys fall back to a dark-anchored default (see `DEFAULT_PALETTE`).
---    * cfg - (table or nil) render tuning; every key has an in-code
---      default (see `DEFAULT_CFG`) so a partial table is safe.
---    * icon - (string or nil) a filesystem path (containing "/") or a
---      named system/bundle image.
---    * onEvent - (function or nil) `function(eventName, elementId) end`,
---      called for every canvas mouse event this card tracks. Wrapped in
---      `pcall`; an error in it is logged, not propagated.
---
--- Returns:
---  * handle - (table) `{setFrame, update, pulse, delete, frame}`, all
---    methods. Every method is a silent no-op once `delete` has run.
function M.new(opts)
  opts = opts or {}
  local onEvent = opts.onEvent or function() end

  local state = {
    cfg = withDefaults(DEFAULT_CFG, opts.cfg),
    palette = withDefaults(DEFAULT_PALETTE, opts.palette),
    card = opts.card,
    icon = opts.icon,
    deleted = false,
    -- Numeric positions of the "body" and "close" elements in the array
    -- most recently pushed to the canvas -- see the comment at
    -- setElements below for why lookup is by index, not by id.
    bodyIndex = 1,
    closeIndex = nil,
  }

  local canvas = hs.canvas.new(opts.frame)
  state.canvas = canvas

  -- hs.canvas's string-keyed __index (`canvas["close"]`) only exists on
  -- the real userdata, which scans elements for a matching `id`; the
  -- recording mock used in tests does not implement that fallback and
  -- would silently hand back nil. Numeric indexing (`canvas[i]`) is
  -- supported by both -- the mock returns the same table it stored, and
  -- the real API returns a live proxy -- so mutating a single element
  -- (hover feedback, pulse) addresses elements by their position in the
  -- array most recently sent, tracked in state.bodyIndex/closeIndex.
  local function setElements(elements)
    state.bodyIndex = 1
    state.closeIndex = #elements
    return elements
  end

  -- clickActivating(false): a click on the card must not pull Hammerspoon
  -- to the front. behaviorAsLabels: cards survive a space switch
  -- ("stationary") and follow you to whichever space you're on
  -- ("canJoinAllSpaces"), matching sticky notifications' durability.
  -- level "floating": above normal app windows (so a card is never buried
  -- behind the window you're working in) but below the dock, menu bar and
  -- screen saver -- a notification is not a modal takeover.
  canvas:clickActivating(false)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  canvas:level(hs.canvas.windowLevels.floating)

  canvas:appendElements(table.unpack(setElements(
    buildElements(state.card, opts.frame, state.palette, state.cfg, state.icon)
  )))

  canvas:mouseCallback(function(_canvas, message, id, _x, _y)
    -- Close-hover feedback lives here, not in the consumer: it is pure
    -- rendering, not a decision notify.init needs to make.
    if id == "close" and state.closeIndex then
      if message == "mouseEnter" then
        canvas[state.closeIndex].textColor = state.palette.close_hover
      elseif message == "mouseExit" then
        canvas[state.closeIndex].textColor = state.palette.close
      end
    end
    local ok, err = pcall(onEvent, message, id)
    if not ok then
      logger.e("onEvent handler failed for " .. tostring(message) .. "/" .. tostring(id) .. ": " .. tostring(err))
    end
  end)

  canvas:show(state.cfg.fade_in)

  local handle = {}

  --- notify.card.handle:setFrame(frame)
  --- Method
  --- Repositions/resizes the card's canvas outright -- used for stack
  --- placement and gap-closing on dismissal. No-op once deleted.
  function handle:setFrame(frame)  --luacheck: no self
    if state.deleted then return end
    state.canvas:frame(frame)
  end

  --- notify.card.handle:update(opts)
  --- Method
  --- Replaces the card's contents in place: same keys as `new` minus
  --- `frame`/`onEvent`. Resizes the canvas to the new `card.height` while
  --- keeping its current origin and width -- the card does not move. This
  --- is `--id` replace-in-place's rendering half; the timer reset and
  --- pulse are the caller's job (see `notify.card.handle:pulse`).
  --- No-op once deleted.
  function handle:update(updateOpts)  --luacheck: no self
    if state.deleted then return end
    updateOpts = updateOpts or {}
    state.cfg = withDefaults(DEFAULT_CFG, updateOpts.cfg)
    state.palette = withDefaults(DEFAULT_PALETTE, updateOpts.palette)
    state.card = updateOpts.card
    state.icon = updateOpts.icon

    local current = state.canvas:frame()
    local newFrame = { x = current.x, y = current.y, w = current.w, h = state.card.height }
    state.canvas:frame(newFrame)
    state.canvas:replaceElements(table.unpack(setElements(
      buildElements(state.card, newFrame, state.palette, state.cfg, state.icon)
    )))
  end

  --- notify.card.handle:pulse()
  --- Method
  --- Briefly swaps the border to `palette.pulse`, then restores it after
  --- `cfg.pulse_duration` -- the visual cue for `--id` replace-in-place
  --- landing on a card you weren't watching. Guards against the canvas
  --- having been deleted before the timer fires. No-op once deleted.
  function handle:pulse()  --luacheck: no self
    if state.deleted then return end
    state.canvas[state.bodyIndex].strokeColor = state.palette.pulse
    hs.timer.doAfter(state.cfg.pulse_duration, function()
      if state.deleted then return end
      state.canvas[state.bodyIndex].strokeColor = state.palette.border
    end)
  end

  --- notify.card.handle:delete(fade)
  --- Method
  --- Fades the card out and destroys its canvas. Every other method is a
  --- silent no-op after this runs.
  ---
  --- Parameters:
  ---  * fade - (number or nil) fade-out duration in seconds; defaults to
  ---    `cfg.fade_out`.
  function handle:delete(fade)  --luacheck: no self
    if state.deleted then return end
    state.deleted = true
    state.canvas:delete(fade or state.cfg.fade_out)
  end

  --- notify.card.handle:frame() -> {x, y, w, h}
  --- Method
  --- Returns the card's current screen frame.
  function handle:frame()  --luacheck: no self
    return state.canvas:frame()
  end

  return handle
end

return M
