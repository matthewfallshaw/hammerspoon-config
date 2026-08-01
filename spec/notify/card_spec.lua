describe("notify.card", function()
  local card = require "notify.card"
  local consts = require "configConsts"

  local function findEl(canvas, id)
    for _, el in ipairs(canvas._elements) do
      if el.id == id then return el end
    end
    return nil
  end

  local function ids(canvas)
    local out = {}
    for i, el in ipairs(canvas._elements) do out[i] = el.id end
    return out
  end

  -- notify/init.lua owns the defaults and always hands notify.card a complete
  -- cfg and palette, so specs build theirs from the same configConsts.notify.
  local function cfgWith(overrides)
    local merged = {}
    for k, v in pairs(consts.notify) do merged[k] = v end
    for k, v in pairs(overrides or {}) do merged[k] = v end
    return merged
  end

  local frame = { x = 100, y = 50, w = 320, h = 120 }
  local darkPalette = consts.notify.palettes.dark
  local lightPalette = consts.notify.palettes.light

  local function baseCard(overrides)
    local c = {
      title = "Notice",
      lines = { "line one", "line two", "line three" },
      overflow = 0,
      footer = nil,
      height = 120,
      hasIcon = false,
    }
    for k, v in pairs(overrides or {}) do c[k] = v end
    return c
  end

  before_each(function()
    hs.canvas._reset()
    hs.timer._reset()
  end)

  describe("new", function()
    it("creates a canvas at the given frame", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      assert.is_not_nil(c)
      assert.are.same(frame, c._frame)
    end)

    it("disables click-activation", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      assert.is_false(hs.canvas._instances[1]._clickActivating)
    end)

    it("sets the space-joining, stationary window behaviour", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local behaviors = hs.canvas._instances[1]._behaviorAsLabels
      local set = {}
      for _, v in ipairs(behaviors) do set[v] = true end
      assert.is_true(set.canJoinAllSpaces)
      assert.is_true(set.stationary)
    end)

    it("sets a window level", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      assert.is_not_nil(hs.canvas._instances[1]._level)
    end)

    it("shows the canvas with the configured fade-in", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith({ fade_in = 0.3 }) })
      local c = hs.canvas._instances[1]
      assert.is_true(c._visible)
      local shown = false
      for _, call in ipairs(c._calls) do
        if call.name == "show" then
          shown = true
          assert.are.equal(0.3, call.args[1])
        end
      end
      assert.is_true(shown)
    end)

    it("orders elements: title, 3 body lines, close -- no icon, no overflow", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "title", "line1", "line2", "line3", "close" }, ids(c))
    end)

    it("omits the title element when card.title is nil", function()
      -- baseCard({title = nil}) wouldn't work: a nil-valued table entry
      -- is simply absent, so the override loop would never see it and
      -- the default "Notice" title would stick. Build the card in full.
      local noTitleCard = {
        title = nil,
        lines = { "line one", "line two", "line three" },
        overflow = 0,
        footer = nil,
        height = 120,
        hasIcon = false,
      }
      card.new({ card = noTitleCard, frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "line1", "line2", "line3", "close" }, ids(c))
    end)

    it("includes a footer element when the card has overflow", function()
      card.new({
        card = baseCard({ overflow = 2, footer = "… (+2 more lines)" }),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
      })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "title", "line1", "line2", "line3", "footer", "close" }, ids(c))
      assert.are.equal("… (+2 more lines)", findEl(c, "footer").text)
    end)

    it("includes an icon element, positioned before the title, when hasIcon and an icon are both given", function()
      card.new({
        card = baseCard({ hasIcon = true }),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
        icon = "/tmp/whatever.png",
      })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "icon", "title", "line1", "line2", "line3", "close" }, ids(c))
    end)

    it("loads a path-like icon (containing '/') via imageFromPath", function()
      card.new({
        card = baseCard({ hasIcon = true }),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
        icon = "/tmp/whatever.png",
      })
      local el = findEl(hs.canvas._instances[1], "icon")
      assert.are.same({ _path = "/tmp/whatever.png" }, el.image)
    end)

    it("loads a name-like icon (no '/') via imageFromName", function()
      card.new({
        card = baseCard({ hasIcon = true }),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
        icon = "NSInfo",
      })
      local el = findEl(hs.canvas._instances[1], "icon")
      assert.are.same({ _name = "NSInfo" }, el.image)
    end)

    it("skips the icon element when hasIcon is true but no icon is given", function()
      card.new({ card = baseCard({ hasIcon = true }), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      assert.is_nil(findEl(c, "icon"))
    end)

    it("renders each body line as its own text element, advancing y by line_height", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith({ line_height = 20 }) })
      local c = hs.canvas._instances[1]
      local l1, l2, l3 = findEl(c, "line1"), findEl(c, "line2"), findEl(c, "line3")
      assert.are.equal("line one", l1.text)
      assert.are.equal("line two", l2.text)
      assert.are.equal("line three", l3.text)
      assert.are.equal(l1.frame.y + 20, l2.frame.y)
      assert.are.equal(l2.frame.y + 20, l3.frame.y)
    end)

    it("does not let the canvas re-wrap a body line", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local l1 = findEl(hs.canvas._instances[1], "line1")
      assert.are_not.equal("wordWrap", l1.textLineBreak)
    end)

    it("positions the close glyph with id 'close' inside the top-right of the card", function()
      card.new({
        card = baseCard(),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith({ padding = 10, close_size = 14 }),
      })
      local closeEl = findEl(hs.canvas._instances[1], "close")
      assert.are.equal("✕", closeEl.text)
      assert.are.equal(frame.w - 10 - 14, closeEl.frame.x)
      assert.are.equal(10, closeEl.frame.y)
    end)

    it("produces different background fill colours for dark vs light palettes", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local darkFill = findEl(hs.canvas._instances[1], "body").fillColor

      hs.canvas._reset()
      card.new({ card = baseCard(), frame = frame, palette = lightPalette, cfg = cfgWith() })
      local lightFill = findEl(hs.canvas._instances[1], "body").fillColor

      assert.are_not.same(darkFill, lightFill)
    end)

    it("renders with the config notify hands it, unmodified", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = consts.notify })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "title", "line1", "line2", "line3", "close" }, ids(c))
    end)

    it("takes styling values from the cfg it is handed", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith({ corner_radius = 99 }) })
      local body = findEl(hs.canvas._instances[1], "body")
      assert.are.equal(99, body.roundedRectRadii.xRadius)
    end)
  end)

  describe("mouseCallback", function()
    it("translates a canvas event into onEvent(eventName, elementId)", function()
      local seen = {}
      card.new({
        card = baseCard(),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
        onEvent = function(eventName, elementId) table.insert(seen, { eventName, elementId }) end,
      })
      local c = hs.canvas._instances[1]
      c._mouseCallback(c, "mouseDown", "close", 5, 5)
      assert.are.same({ "mouseDown", "close" }, seen[1])
    end)

    it("does not propagate an error thrown by onEvent", function()
      card.new({
        card = baseCard(),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith(),
        onEvent = function() error("boom") end,
      })
      local c = hs.canvas._instances[1]
      assert.has_no.errors(function()
        c._mouseCallback(c, "mouseUp", "close", 5, 5)
      end)
    end)

    it("swaps the close glyph colour to close_hover on mouseEnter and back on mouseExit", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      c._mouseCallback(c, "mouseEnter", "close", 5, 5)
      assert.are.same(darkPalette.close_hover, findEl(c, "close").textColor)
      c._mouseCallback(c, "mouseExit", "close", 5, 5)
      assert.are.same(darkPalette.close, findEl(c, "close").textColor)
    end)

    it("leaves other elements' colours alone on close hover", function()
      card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local c = hs.canvas._instances[1]
      c._mouseCallback(c, "mouseEnter", "close", 5, 5)
      assert.are.same(darkPalette.body, findEl(c, "line1").textColor)
    end)
  end)

  describe("handle:setFrame", function()
    it("records the new frame on the canvas", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local newFrame = { x = 200, y = 60, w = 320, h = 140 }
      h:setFrame(newFrame)
      assert.are.same(newFrame, hs.canvas._instances[1]._frame)
    end)

    it("is reflected by handle:frame()", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      local newFrame = { x = 200, y = 60, w = 320, h = 140 }
      h:setFrame(newFrame)
      assert.are.same(newFrame, h:frame())
    end)
  end)

  describe("handle:update", function()
    it("keeps the canvas origin and width but changes the height to the new card.height", function()
      local h = card.new({ card = baseCard({ height = 120 }), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:update({
        card = baseCard({ lines = { "only one line" }, height = 60 }),
        palette = darkPalette,
        cfg = cfgWith(),
      })
      local c = hs.canvas._instances[1]
      assert.are.equal(frame.x, c._frame.x)
      assert.are.equal(frame.y, c._frame.y)
      assert.are.equal(frame.w, c._frame.w)
      assert.are.equal(60, c._frame.h)
    end)

    it("replaces the elements with the new content", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:update({
        card = baseCard({ title = "Updated", lines = { "new line" }, height = 80 }),
        palette = darkPalette,
        cfg = cfgWith(),
      })
      local c = hs.canvas._instances[1]
      assert.are.same({ "body", "title", "line1", "close" }, ids(c))
      assert.are.equal("Updated", findEl(c, "title").text)
      assert.are.equal("new line", findEl(c, "line1").text)
    end)
  end)

  describe("handle:pulse", function()
    it("swaps the border to palette.pulse immediately", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:pulse()
      local c = hs.canvas._instances[1]
      assert.are.same(darkPalette.pulse, findEl(c, "body").strokeColor)
    end)

    it("restores the border after cfg.pulse_duration once the timer fires", function()
      local h = card.new({
        card = baseCard(),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith({ pulse_duration = 0.4 }),
      })
      h:pulse()
      assert.are.equal(1, #hs.timer._timers)
      assert.are.equal(0.4, hs.timer._timers[1].seconds)
      hs.timer._timers[1].fn()
      local c = hs.canvas._instances[1]
      assert.are.same(darkPalette.border, findEl(c, "body").strokeColor)
    end)

    it("does not error if the canvas was deleted before the timer fires", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:pulse()
      h:delete()
      assert.has_no.errors(function()
        hs.timer._timers[1].fn()
      end)
    end)
  end)

  describe("handle:delete", function()
    it("calls delete on the canvas with the given fade", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:delete(0.5)
      local c = hs.canvas._instances[1]
      assert.is_true(c._deleted)
      local deleteCall
      for _, call in ipairs(c._calls) do
        if call.name == "delete" then deleteCall = call end
      end
      assert.are.equal(0.5, deleteCall.args[1])
    end)

    it("falls back to cfg.fade_out when no fade is given", function()
      local h = card.new({
        card = baseCard(),
        frame = frame,
        palette = darkPalette,
        cfg = cfgWith({ fade_out = 0.25 }),
      })
      h:delete()
      local c = hs.canvas._instances[1]
      local deleteCall
      for _, call in ipairs(c._calls) do
        if call.name == "delete" then deleteCall = call end
      end
      assert.are.equal(0.25, deleteCall.args[1])
    end)

    it("makes setFrame a silent no-op afterwards", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:delete()
      assert.has_no.errors(function()
        h:setFrame({ x = 0, y = 0, w = 10, h = 10 })
      end)
      assert.are_not.same({ x = 0, y = 0, w = 10, h = 10 }, hs.canvas._instances[1]._frame)
    end)

    it("makes update a silent no-op afterwards", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:delete()
      local elementsBefore = #hs.canvas._instances[1]._elements
      assert.has_no.errors(function()
        h:update({ card = baseCard({ title = "should not apply" }), palette = darkPalette, cfg = cfgWith() })
      end)
      assert.are.equal(elementsBefore, #hs.canvas._instances[1]._elements)
    end)

    it("makes pulse a silent no-op afterwards", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:delete()
      assert.has_no.errors(function()
        h:pulse()
      end)
      assert.are.equal(0, #hs.timer._timers)
    end)

    it("is itself idempotent", function()
      local h = card.new({ card = baseCard(), frame = frame, palette = darkPalette, cfg = cfgWith() })
      h:delete()
      assert.has_no.errors(function()
        h:delete()
      end)
    end)
  end)
end)
