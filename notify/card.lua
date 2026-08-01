--- === notify.card ===
--- Thin `hs.canvas` renderer for a single notification card.
---
--- Does no layout arithmetic: every position it paints comes from the `card`
--- table `notify.layout.compose` produced and from the `cfg` handed in. A wrap
--- or a total height that needs computing here belongs in `notify.layout`.
---
--- `cfg` and `palette` arrive complete -- `notify` owns the defaults and the
--- merge, so there is nothing to fall back to here.
---
--- Every element carries a stable `id` so the `onEvent` consumer can tell them
--- apart: `"body"` for the background, `"close"` for the dismiss glyph,
--- `"icon"`/`"title"`/`"footer"` for their singletons, and `"line1"`,
--- `"line2"`, ... one per already-wrapped body line (never handed to the
--- canvas as one blob to re-wrap).

local M = {}

-- Metadata
M.name = "NotifyCard"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

local logger = hs.logger.new("NotifyCard")

-- A string containing "/" is a filesystem path; anything else is a named
-- system/bundle image (e.g. an `hs.image.systemImageNames` key).
local function loadIcon(icon)
  if not icon then return nil end
  if type(icon) == "string" and icon:find("/", 1, true) then
    return hs.image.imageFromPath(icon)
  end
  return hs.image.imageFromName(icon)
end

-- The ordered element array for one card, in local canvas coordinates (0,0 is
-- the canvas's own top-left). Shared by `new` and `update` so both paint
-- identically. Order: background, icon, title, one per body line, overflow
-- footer, close glyph.
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
    -- Tracked so the consumer can pause the auto-dismiss countdown on hover;
    -- a click on the body itself is a deliberate no-op.
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

--- notify.card.new(opts) -> handle
--- Creates and shows the canvas for one notification card. `opts` is
--- `{ card, frame, palette, cfg, icon, onEvent }`: `card` is
--- `notify.layout.compose`'s output, `frame` its screen frame (`h` already
--- equals `card.height`), `palette` and `cfg` complete tables, `icon` a path
--- or image name, and `onEvent(eventName, elementId)` a callback for every
--- tracked mouse event (`pcall`-wrapped; an error in it is logged, not
--- propagated).
---
--- Returns a handle with `setFrame`, `update`, `pulse`, `delete` and `frame`
--- methods, every one a silent no-op once `delete` has run.
function M.new(opts)
  opts = opts or {}
  local onEvent = opts.onEvent or function() end

  local state = {
    cfg = opts.cfg,
    palette = opts.palette,
    card = opts.card,
    icon = opts.icon,
    deleted = false,
    bodyIndex = 1,
    closeIndex = nil,
  }

  local canvas = hs.canvas.new(opts.frame)
  state.canvas = canvas

  -- Individual elements are addressed by their numeric position in the array
  -- most recently sent, not by id: `canvas["close"]`'s string-keyed lookup
  -- exists only on the real userdata, and the recording mock used in specs
  -- would silently hand back nil.
  local function setElements(elements)
    state.bodyIndex = 1
    state.closeIndex = #elements
    return elements
  end

  -- clickActivating(false): a click on the card must not pull Hammerspoon to
  -- the front. behaviorAsLabels: cards survive a space switch and follow you
  -- to whichever space you're on. level "floating": above normal app windows,
  -- below the dock, menu bar and screen saver -- a notification is not a
  -- modal takeover.
  canvas:clickActivating(false)
  canvas:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  canvas:level(hs.canvas.windowLevels.floating)

  canvas:appendElements(table.unpack(setElements(
    buildElements(state.card, opts.frame, state.palette, state.cfg, state.icon)
  )))

  canvas:mouseCallback(function(_canvas, message, id, _x, _y)
    -- Close-hover feedback lives here, not in the consumer: it is pure
    -- rendering, not a decision anyone else needs to make.
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

  --- Repositions/resizes the canvas outright -- stack placement and gap
  --- closing on dismissal.
  function handle:setFrame(frame)  --luacheck: no self
    if state.deleted then return end
    state.canvas:frame(frame)
  end

  --- Replaces the card's contents in place (same keys as `new` minus
  --- `frame`/`onEvent`), resizing to the new `card.height` but keeping the
  --- current origin and width, so the card does not move.
  function handle:update(updateOpts)  --luacheck: no self
    if state.deleted then return end
    updateOpts = updateOpts or {}
    state.cfg = updateOpts.cfg
    state.palette = updateOpts.palette
    state.card = updateOpts.card
    state.icon = updateOpts.icon

    local current = state.canvas:frame()
    local newFrame = { x = current.x, y = current.y, w = current.w, h = state.card.height }
    state.canvas:frame(newFrame)
    state.canvas:replaceElements(table.unpack(setElements(
      buildElements(state.card, newFrame, state.palette, state.cfg, state.icon)
    )))
  end

  --- Briefly swaps the border to `palette.pulse` -- the visual cue for a
  --- replace-in-place landing on a card you weren't watching.
  function handle:pulse()  --luacheck: no self
    if state.deleted then return end
    state.canvas[state.bodyIndex].strokeColor = state.palette.pulse
    hs.timer.doAfter(state.cfg.pulse_duration, function()
      if state.deleted then return end
      state.canvas[state.bodyIndex].strokeColor = state.palette.border
    end)
  end

  --- Fades the card out over `fade` seconds (default `cfg.fade_out`) and
  --- destroys its canvas.
  function handle:delete(fade)  --luacheck: no self
    if state.deleted then return end
    state.deleted = true
    state.canvas:delete(fade or state.cfg.fade_out)
  end

  --- The card's current screen frame.
  function handle:frame()  --luacheck: no self
    return state.canvas:frame()
  end

  return handle
end

return M
