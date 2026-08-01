describe("notify", function()
  local notify = require "notify"
  local consts = require "configConsts"
  local cfg = consts.notify

  local defaultBindHotkey = notify._bindHotkey

  -- A recording fake renderer, injected via the M._renderer seam so these
  -- specs never require notify/card.lua (which may not exist yet).
  local function makeFakeRenderer()
    local renderer = { instances = {} }
    function renderer.new(opts)
      local handle = { _opts = opts, _frame = opts.frame,
                        setFrameCalls = 0, updateCalls = {}, pulseCalls = 0, deleteCalls = {},
                        onEvent = opts.onEvent }
      function handle:setFrame(f)
        self._frame = f
        self.setFrameCalls = self.setFrameCalls + 1
      end
      function handle:update(u)
        table.insert(self.updateCalls, u)
      end
      function handle:pulse()
        self.pulseCalls = self.pulseCalls + 1
      end
      function handle:delete(fade)
        table.insert(self.deleteCalls, fade)
      end
      function handle:frame()
        return self._frame
      end
      table.insert(renderer.instances, handle)
      return handle
    end
    return renderer
  end

  local fakeRenderer

  -- Synthetic hs.eventtap.event.types.gesture touch/event builders, for
  -- driving the swipe gesture tap end-to-end (via the real notify.gesture,
  -- the same mocked hs.eventtap the module itself uses).
  local function touch(identity, phase, x, y)
    return {
      identity = identity,
      phase = phase,
      normalizedPosition = { x = x, y = y },
      touching = (phase == "began" or phase == "moved" or phase == "stationary"),
      type = "indirect",
    }
  end

  local function gestureEvent(touches)
    return { getTouches = function() return touches end }
  end

  local function findGestureTap()
    for i = #hs.eventtap._instances, 1, -1 do
      local t = hs.eventtap._instances[i]
      for _, ty in ipairs(t._types) do
        if ty == hs.eventtap.event.types.gesture then return t end
      end
    end
    return nil
  end

  before_each(function()
    hs.canvas._reset()
    hs.timer._reset()
    hs.settings._reset()
    hs.eventtap._reset()
    hs.host._interfaceStyle = nil
    hs.screen._primaryFrame = { x = 0, y = 0, w = 1920, h = 1080 }

    notify._stack = {}
    notify._autoIdSeq = 0
    notify._bindHotkey = defaultBindHotkey
    notify._gesture = nil
    cfg.swipe.enabled = true
    fakeRenderer = makeFakeRenderer()
    notify._renderer = fakeRenderer
  end)

  describe(".show", function()
    it("returns a generated id when none is given, prefixed auto:", function()
      local id = notify.show({ message = "hi" })
      assert.is_not_nil(id)
      assert.is_not_nil(id:match("^auto:"))
    end)

    it("uses the caller's id when given", function()
      local id = notify.show({ message = "hi", id = "my-id" })
      assert.are.equal("my-id", id)
    end)

    it("defaults message to empty string", function()
      notify.show({})
      assert.are.equal("", notify._stack[1].message)
    end)

    it("defaults title to Notice", function()
      notify.show({ message = "hi" })
      assert.are.equal("Notice", notify._stack[1].title)
    end)

    it("honors an explicit title", function()
      notify.show({ message = "hi", title = "pb-copy" })
      assert.are.equal("pb-copy", notify._stack[1].title)
    end)

    it("wraps and truncates a message longer than max_lines, producing an overflow footer", function()
      local lines = {}
      for i = 1, cfg.max_lines + 5 do lines[i] = "line" .. i end
      notify.show({ message = table.concat(lines, "\n") })
      local card = notify._stack[1].card
      assert.are.equal(cfg.max_lines, #card.lines)
      assert.is_true(card.overflow > 0)
      assert.is_not_nil(card.footer)
    end)

    it("does not let a throwing renderer escape show(), and returns nil", function()
      fakeRenderer.new = function() error("boom from renderer") end
      local id = notify.show({ message = "hi" })
      assert.is_nil(id)
      -- and the module is still usable afterwards
      assert.are.equal(0, #notify._stack)
    end)
  end)

  describe("stack model / gap closing", function()
    it("appends new cards at the bottom (index 1 = oldest = topmost)", function()
      local id1 = notify.show({ message = "one", sticky = true })
      local id2 = notify.show({ message = "two", sticky = true })
      assert.are.equal(id1, notify._stack[1].id)
      assert.are.equal(id2, notify._stack[2].id)
    end)

    it("does not call setFrame on other cards when the last (bottom) card is dismissed", function()
      local id1 = notify.show({ message = "one", sticky = true })
      local id2 = notify.show({ message = "two", sticky = true })
      local id3 = notify.show({ message = "three", sticky = true })
      local h1 = fakeRenderer.instances[1]
      local h2 = fakeRenderer.instances[2]
      assert.are.equal(0, h1.setFrameCalls)
      assert.are.equal(0, h2.setFrameCalls)

      notify.dismiss(id3)

      assert.are.equal(0, h1.setFrameCalls)
      assert.are.equal(0, h2.setFrameCalls)
      assert.are.equal(2, #notify._stack)
      assert.are.equal(id1, notify._stack[1].id)
      assert.are.equal(id2, notify._stack[2].id)
    end)

    it("closes the gap (moves the cards below) when the topmost card is dismissed", function()
      local id1 = notify.show({ message = "one", sticky = true })
      notify.show({ message = "two", sticky = true })
      notify.show({ message = "three", sticky = true })
      local h2 = fakeRenderer.instances[2]
      local h3 = fakeRenderer.instances[3]

      notify.dismiss(id1)

      assert.is_true(h2.setFrameCalls > 0)
      assert.is_true(h3.setFrameCalls > 0)
      assert.are.equal(2, #notify._stack)
    end)
  end)

  describe("max_cards", function()
    it("drops (does not queue) a new card once the stack is at max_cards, returning nil", function()
      for i = 1, cfg.max_cards do
        assert.is_not_nil(notify.show({ message = "n" .. i, sticky = true }))
      end
      assert.are.equal(cfg.max_cards, #notify._stack)

      local dropped = notify.show({ message = "overflow", sticky = true })

      assert.is_nil(dropped)
      assert.are.equal(cfg.max_cards, #notify._stack)
    end)
  end)

  describe("auto-dismiss timers", function()
    it("stores an absolute deadline (now + duration), not a remaining duration", function()
      hs.timer._now = 1000
      notify.show({ message = "hi", duration = 5 })
      assert.are.equal(1005, notify._stack[1].deadline)
    end)

    it("gives sticky cards no timer", function()
      notify.show({ message = "hi", sticky = true })
      assert.is_nil(notify._stack[1].timer)
      assert.is_nil(notify._stack[1].deadline)
    end)

    it("removes the card when its timer fires", function()
      notify.show({ message = "hi", duration = 5 })
      local record = notify._stack[1]
      local timer = record.timer
      local handle = fakeRenderer.instances[1]

      timer.fn()

      assert.are.equal(0, #notify._stack)
      assert.are.equal(1, #handle.deleteCalls)
    end)
  end)

  describe("hover pause/resume", function()
    it("pauses on mouseEnter and resumes with the recomputed deadline on mouseExit", function()
      hs.timer._now = 0
      notify.show({ message = "hi", duration = 10 })
      local record = notify._stack[1]
      local handle = fakeRenderer.instances[1]

      hs.timer._now = 4
      handle.onEvent("mouseEnter")
      assert.is_true(record.timer == nil or not record.timer:running())
      assert.are.equal(6, record.remaining) -- 10 - 4

      hs.timer._now = 100 -- time passes while paused; must not matter
      handle.onEvent("mouseExit")

      assert.are.equal(106, record.deadline) -- 100 + 6
      assert.is_nil(record.remaining)
      assert.is_not_nil(record.timer)
    end)

    it("does not pause or create a timer for a sticky card on hover", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]
      handle.onEvent("mouseEnter")
      handle.onEvent("mouseExit")
      assert.is_nil(notify._stack[1].timer)
      assert.is_nil(notify._stack[1].deadline)
    end)

    it("persists the pause: the stale deadline is gone, the remaining time is written", function()
      hs.timer._now = 1000
      notify.show({ message = "hovered", duration = 10 }) -- deadline 1010
      local handle = fakeRenderer.instances[1]

      hs.timer._now = 1004
      handle.onEvent("mouseEnter")

      local persisted = hs.settings.get(cfg.settings_key)
      assert.are.equal(1, #persisted)
      assert.is_nil(persisted[1].deadline)
      assert.are.equal(6, persisted[1].remaining)
    end)

    it("persists the recomputed deadline on resume", function()
      hs.timer._now = 1000
      notify.show({ message = "hovered", duration = 10 })
      local handle = fakeRenderer.instances[1]

      hs.timer._now = 1004
      handle.onEvent("mouseEnter")
      hs.timer._now = 1100
      handle.onEvent("mouseExit")

      local persisted = hs.settings.get(cfg.settings_key)
      assert.are.equal(1106, persisted[1].deadline)
      assert.is_nil(persisted[1].remaining)
    end)

    it("restores a card hovered across a reload with its remaining time, not a past deadline", function()
      hs.timer._now = 1000
      notify.show({ message = "hovered", duration = 10 }) -- deadline 1010
      fakeRenderer.instances[1].onEvent("mouseEnter")

      -- Simulate hs.reload() well after the original deadline would have passed.
      notify._stack = {}
      fakeRenderer = makeFakeRenderer()
      notify._renderer = fakeRenderer
      notify._bindHotkey = function() end
      hs.timer._now = 2000

      notify:start()

      assert.are.equal(1, #notify._stack)
      assert.are.equal(2010, notify._stack[1].deadline) -- full 10s: nothing elapsed while paused
    end)
  end)

  describe("close button and click-elsewhere", function()
    it("dismisses the card on mouseUp with element id close", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]

      handle.onEvent("mouseUp", "close")

      assert.are.equal(0, #notify._stack)
      assert.are.equal(1, #handle.deleteCalls)
    end)

    it("does nothing on mouseUp anywhere else", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]

      handle.onEvent("mouseUp", "body")
      handle.onEvent("mouseUp", nil)

      assert.are.equal(1, #notify._stack)
      assert.are.equal(0, #handle.deleteCalls)
    end)
  end)

  describe("escape while hovering", function()
    it("starts the eventtap on mouseEnter and stops it on mouseExit", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]

      handle.onEvent("mouseEnter")
      local tap = hs.eventtap._instances[#hs.eventtap._instances]
      assert.is_true(tap:isEnabled())

      handle.onEvent("mouseExit")
      assert.is_false(tap:isEnabled())
    end)

    it("dismisses the hovered card when escape fires, and never swallows the key", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]
      handle.onEvent("mouseEnter")
      local tap = hs.eventtap._instances[#hs.eventtap._instances]

      local swallowed = tap._fn({ getKeyCode = function() return 53 end })

      assert.is_false(swallowed)
      assert.are.equal(0, #notify._stack)
    end)

    it("does not dismiss on a non-escape key", function()
      notify.show({ message = "hi", sticky = true })
      local handle = fakeRenderer.instances[1]
      handle.onEvent("mouseEnter")
      local tap = hs.eventtap._instances[#hs.eventtap._instances]

      tap._fn({ getKeyCode = function() return 0 end }) -- 'a'

      assert.are.equal(1, #notify._stack)
    end)
  end)

  describe("swipe-to-dismiss gesture wiring", function()
    it("starts the gesture tap when the stack becomes non-empty and stops it when empty", function()
      assert.is_nil(findGestureTap())

      local id = notify.show({ message = "hi", sticky = true })
      local tap = findGestureTap()
      assert.is_not_nil(tap)
      assert.is_true(tap:isEnabled())

      notify.dismiss(id)
      assert.is_false(tap:isEnabled())
    end)

    it("stops the tap once dismissAll empties the stack", function()
      notify.show({ message = "one", sticky = true })
      notify.show({ message = "two", sticky = true })
      local tap = findGestureTap()
      assert.is_true(tap:isEnabled())

      notify.dismissAll()
      assert.is_false(tap:isEnabled())
    end)

    it("never creates the tap when cfg.swipe.enabled is false", function()
      cfg.swipe.enabled = false

      notify.show({ message = "hi", sticky = true })

      assert.is_nil(findGestureTap())
    end)

    it("hitTest picks the topmost (first) card among stacked/overlapping frames", function()
      notify.show({ message = "one", sticky = true, id = "top" })
      notify.show({ message = "two", sticky = true, id = "bottom" })
      -- Force fully overlapping frames so hit-test order is observable.
      notify._stack[1].frame = { x = 0, y = 0, w = 100, h = 100 }
      notify._stack[2].frame = { x = 0, y = 0, w = 100, h = 100 }
      hs.mouse._position = { x = 50, y = 50 }

      local tap = findGestureTap()
      hs.timer._now = 0
      tap._fn(gestureEvent({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      tap._fn(gestureEvent({ touch("t1", "ended", 0.5, 0.5) }))

      assert.are.equal(1, #notify._stack)
      assert.are.equal("bottom", notify._stack[1].id) -- "top" was the one dismissed
    end)
  end)

  describe("id replace-in-place", function()
    it("keeps stack position, replaces every attribute, resets the timer, and pulses", function()
      notify.show({ message = "first", sticky = true, id = "top", title = "T1" })
      notify.show({ message = "middle", sticky = true, id = "mine", title = "T2" })
      notify.show({ message = "last", sticky = true, id = "bottom", title = "T3" })

      local handle = fakeRenderer.instances[2]

      hs.timer._now = 500
      local returnedId = notify.show(
        { message = "updated", sticky = false, duration = 7, id = "mine", title = "T2-new" }
      )

      assert.are.equal("mine", returnedId)
      assert.are.equal(3, #notify._stack)
      assert.are.equal("mine", notify._stack[2].id) -- same position
      assert.are.equal("updated", notify._stack[2].message)
      assert.are.equal("T2-new", notify._stack[2].title)
      assert.are.equal(false, notify._stack[2].sticky)
      assert.are.equal(507, notify._stack[2].deadline) -- timer reset off the new call
      assert.are.equal(1, #handle.updateCalls)
      assert.are.equal(1, handle.pulseCalls)
      assert.are.equal(3, #fakeRenderer.instances) -- no new handle created
    end)

    it("appends at the bottom as usual if no live card has that id", function()
      notify.show({ message = "one", sticky = true, id = "a" })
      notify.show({ message = "two", sticky = true, id = "b-not-live" }) -- different id, no replace
      assert.are.equal(2, #notify._stack)
      assert.are.equal("a", notify._stack[1].id)
      assert.are.equal("b-not-live", notify._stack[2].id)
    end)

    it("generates ids that never collide with a caller-supplied id, including auto: ones", function()
      notify.show({ message = "hi", sticky = true, id = "auto:1" })
      local generated = notify.show({ message = "hi2", sticky = true })
      assert.are_not.equal("auto:1", generated)
      assert.are.equal(2, #notify._stack)
    end)
  end)

  describe("persistence", function()
    it("never writes a private card to disk", function()
      notify.show({ message = "super secret password", sticky = true, private = true })
      local persisted = hs.settings.get(cfg.settings_key) or {}
      for _, rec in ipairs(persisted) do
        assert.is_not.equal("super secret password", rec.message)
      end
      assert.are.equal(0, #persisted)
    end)

    it("writes the persisted set on every mutation (show/dismiss)", function()
      local id = notify.show({ message = "keep me", sticky = true })
      assert.are.equal(1, #hs.settings.get(cfg.settings_key))
      notify.dismiss(id)
      assert.are.equal(0, #hs.settings.get(cfg.settings_key))
    end)

    it("round-trips: private is dropped, order and deadlines survive a simulated reload", function()
      hs.timer._now = 1000
      local privateId = notify.show({ message = "secret", sticky = true, private = true })
      local stickyId = notify.show({ message = "keep me", sticky = true })
      local tempId = notify.show({ message = "temp", sticky = false, duration = 50 }) -- deadline 1050

      -- Simulate hs.reload(): fresh module state, settings survive.
      notify._stack = {}
      fakeRenderer = makeFakeRenderer()
      notify._renderer = fakeRenderer
      notify._bindHotkey = function() end -- avoid touching real hyper in the test env

      notify:start()

      assert.are.equal(2, #notify._stack)
      assert.are.equal(stickyId, notify._stack[1].id)
      assert.are.equal(tempId, notify._stack[2].id)
      assert.are.equal(1050, notify._stack[2].deadline)
      assert.is_true(notify._stack[1].sticky)
      assert.is_false(notify._stack[1].id == privateId or notify._stack[2].id == privateId)

      -- settings key was rewritten to reflect the restored (non-private) set
      assert.are.equal(2, #hs.settings.get(cfg.settings_key))
    end)

    it("drops an already-expired non-sticky card on restore", function()
      hs.timer._now = 1000
      notify.show({ message = "will expire", sticky = false, duration = 10 }) -- deadline 1010

      notify._stack = {}
      fakeRenderer = makeFakeRenderer()
      notify._renderer = fakeRenderer
      notify._bindHotkey = function() end

      hs.timer._now = 2000 -- long past the deadline
      notify:start()

      assert.are.equal(0, #notify._stack)
    end)
  end)

  describe("palette selection at paint time", function()
    it("uses the dark palette when hs.host.interfaceStyle() is Dark", function()
      hs.host._interfaceStyle = "Dark"
      notify.show({ message = "hi", sticky = true })
      assert.are.same(cfg.palettes.dark, fakeRenderer.instances[1]._opts.palette)
    end)

    it("uses the light palette otherwise", function()
      hs.host._interfaceStyle = nil
      notify.show({ message = "hi", sticky = true })
      assert.are.same(cfg.palettes.light, fakeRenderer.instances[1]._opts.palette)
    end)
  end)

  describe("renderer config", function()
    -- notify.card reads snake_case (cfg.corner_radius); notify.layout reads
    -- camelCase (cfg.cornerRadius). The renderer must be handed the module's
    -- own config, not layout's mapping of it, or every styling value is
    -- silently discarded in favour of notify.card's defaults.
    local styling = { "corner_radius", "fade_in", "close_size" }
    local saved

    before_each(function()
      saved = {}
      for _, k in ipairs(styling) do saved[k] = notify._cfg[k] end
      notify._cfg.corner_radius = 99
      notify._cfg.fade_in = 0.42
      notify._cfg.close_size = 21
    end)

    after_each(function()
      for _, k in ipairs(styling) do notify._cfg[k] = saved[k] end
    end)

    it("hands a new card the configured styling values, in the keys card.lua reads", function()
      notify.show({ message = "hi", sticky = true })

      local rendered = fakeRenderer.instances[1]._opts.cfg
      assert.are.equal(99, rendered.corner_radius)
      assert.are.equal(0.42, rendered.fade_in)
      assert.are.equal(21, rendered.close_size)
      assert.is_nil(rendered.cornerRadius)
    end)

    it("keeps the configured styling when a card is replaced in place", function()
      notify.show({ message = "first", sticky = true, id = "mine" })
      notify.show({ message = "second", sticky = true, id = "mine" })

      local update = fakeRenderer.instances[1].updateCalls[1]
      assert.are.equal(99, update.cfg.corner_radius)
      assert.are.equal(21, update.cfg.close_size)
    end)
  end)

  describe("screen resolved at paint time", function()
    it("places the first card top-right of the current primary screen frame", function()
      hs.screen._primaryFrame = { x = 100, y = 50, w = 1000, h = 800 }
      notify.show({ message = "hi", sticky = true })
      local frame = fakeRenderer.instances[1]._frame
      assert.are.equal(100 + 1000 - cfg.margin_right - cfg.card_width, frame.x)
      assert.are.equal(50 + cfg.margin_top, frame.y)
    end)
  end)

  describe(".dismiss", function()
    it("is a no-op that does not throw for an unknown id", function()
      assert.has_no.errors(function() notify.dismiss("nope") end)
    end)
  end)

  describe(".dismissAll", function()
    it("is a no-op on an empty stack", function()
      assert.has_no.errors(function() notify.dismissAll() end)
      assert.are.equal(0, #notify._stack)
    end)

    it("dismisses every card", function()
      notify.show({ message = "one", sticky = true })
      notify.show({ message = "two", sticky = true })
      notify.dismissAll()
      assert.are.equal(0, #notify._stack)
      assert.are.equal(1, #fakeRenderer.instances[1].deleteCalls)
      assert.are.equal(1, #fakeRenderer.instances[2].deleteCalls)
    end)
  end)

  describe(".start", function()
    it("binds the dismissAll hotkey from cfg.dismiss_all_hotkey via M._bindHotkey", function()
      local capturedMods, capturedKey, capturedHandler
      notify._bindHotkey = function(mods, key, handler)
        capturedMods, capturedKey, capturedHandler = mods, key, handler
      end

      notify.show({ message = "one", sticky = true })
      notify:start()

      assert.are.same(cfg.dismiss_all_hotkey.mods, capturedMods)
      assert.are.equal(cfg.dismiss_all_hotkey.key, capturedKey)
      assert.is_not_nil(capturedHandler)

      capturedHandler()
      assert.are.equal(0, #notify._stack)
    end)

    it("does not let a failure escape (e.g. a broken binder)", function()
      notify._bindHotkey = function() error("boom") end
      assert.has_no.errors(function() notify:start() end)
    end)
  end)

  describe(".stop", function()
    it("does not throw", function()
      assert.has_no.errors(function() notify:stop() end)
    end)
  end)
end)
