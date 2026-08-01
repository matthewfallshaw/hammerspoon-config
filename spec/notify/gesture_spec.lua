describe("notify.gesture", function()
  local gesture = require "notify.gesture"

  -- Generous thresholds by default so "happy path" tests aren't accidentally
  -- tripped by the velocity-abort logic; individual tests tighten as needed.
  local function makeCfg(overrides)
    local cfg = {
      enabled = true,
      min_distance = 0.1,
      max_distance = 0.6,
      max_duration = 1.0,
      max_velocity_change = 100,
      direction_tolerance = 100,
    }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
  end

  local function touch(identity, phase, x, y)
    return {
      identity = identity,
      phase = phase,
      normalizedPosition = { x = x, y = y },
      touching = (phase == "began" or phase == "moved" or phase == "stationary"),
      force = 0,
      device = "dev1",
      deviceSize = { w = 100, h = 100 },
      type = "indirect",
    }
  end

  local function event(touches)
    return { getTouches = function() return touches end }
  end

  before_each(function()
    hs.timer._reset()
    hs.mouse._position = { x = 0, y = 0 }
  end)

  local function alwaysHit(cardId)
    return function(_point) return cardId end
  end

  describe("happy path", function()
    it("fires onSwipe with the card id for a clean rightward swipe over a card", function()
      local fired = {}
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function(id) table.insert(fired, id) end,
      })

      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "moved", 0.35, 0.5) }))
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))

      assert.are.same({ "card1" }, fired)
    end)

    it("latches hitTest once at began and does not call it again during moved/ended", function()
      local calls = 0
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = function(_point) calls = calls + 1; return "card1" end,
        onSwipe = function() end,
      })

      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "moved", 0.35, 0.5) }))
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))

      assert.are.equal(1, calls)
    end)

    it("resets state fully after each gesture: two consecutive swipes both fire", function()
      local fired = {}
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function(id) table.insert(fired, id) end,
      })

      for _, start in ipairs({ 0, 10 }) do
        hs.timer._now = start
        g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
        hs.timer._now = start + 0.1
        g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))
      end

      assert.are.same({ "card1", "card1" }, fired)
    end)
  end)

  describe("no card under the gesture", function()
    it("fires nothing when the gesture starts not over a card", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = function(_point) return nil end,
        onSwipe = function() fired = true end,
      })

      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))

      assert.is_false(fired)
    end)
  end)

  describe("distance thresholds", function()
    it("fires nothing when travel is below min_distance", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg({ min_distance = 0.1 }),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "ended", 0.22, 0.5) })) -- travel 0.02
      assert.is_false(fired)
    end)

    it("fires nothing when travel is above max_distance", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg({ max_distance = 0.6 }),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.1, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "ended", 0.9, 0.5) })) -- travel 0.8
      assert.is_false(fired)
    end)
  end)

  describe("duration threshold", function()
    it("fires nothing when the gesture exceeds max_duration", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg({ max_duration = 1.0 }),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.1, 0.5) }))
      hs.timer._now = 2.0
      g._handleEvent(event({ touch("t1", "ended", 0.4, 0.5) })) -- good travel, too slow
      assert.is_false(fired)
    end)
  end)

  describe("velocity abort", function()
    it("aborts on a direction reversal mid-gesture", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg({ direction_tolerance = 0.02, max_velocity_change = 100 }),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "moved", 0.4, 0.5) })) -- v = +2.0
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "moved", 0.1, 0.5) })) -- v = -3.0: reversal
      hs.timer._now = 0.3
      g._handleEvent(event({ touch("t1", "ended", 0.3, 0.5) })) -- would otherwise pass
      assert.is_false(fired)
    end)

    it("aborts on an abrupt speed change between samples", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg({ max_velocity_change = 1.0, direction_tolerance = 100 }),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.1, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "moved", 0.15, 0.5) })) -- v = 0.5
      hs.timer._now = 0.11
      g._handleEvent(event({ touch("t1", "moved", 0.5, 0.5) })) -- v = 35: spike
      hs.timer._now = 0.3
      g._handleEvent(event({ touch("t1", "ended", 0.55, 0.5) })) -- would otherwise pass
      assert.is_false(fired)
    end)
  end)

  describe("second concurrent touch", function()
    it("aborts the gesture when a second finger joins mid-gesture", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      -- t1 still down, t2 begins concurrently: single-finger only.
      g._handleEvent(event({ touch("t1", "moved", 0.3, 0.5), touch("t2", "began", 0.6, 0.5) }))
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) })) -- would otherwise pass
      assert.is_false(fired)
    end)

    it("never latches when two fingers arrive together at began", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5), touch("t2", "began", 0.6, 0.5) }))
      hs.timer._now = 0.2
      g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))
      assert.is_false(fired)
    end)
  end)

  describe("cancelled phase", function()
    it("discards the gesture", function()
      local fired = false
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function() fired = true end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1
      g._handleEvent(event({ touch("t1", "cancelled", 0.3, 0.5) }))
      assert.is_false(fired)
    end)
  end)

  describe("safety: return value", function()
    local scenarios = {
      { name = "began", touches = { touch("t1", "began", 0.2, 0.5) }, hitTest = alwaysHit("card1") },
      { name = "moved", touches = { touch("t1", "moved", 0.3, 0.5) }, hitTest = alwaysHit("card1") },
      { name = "ended", touches = { touch("t1", "ended", 0.5, 0.5) }, hitTest = alwaysHit("card1") },
      { name = "cancelled", touches = { touch("t1", "cancelled", 0.3, 0.5) }, hitTest = alwaysHit("card1") },
      {
        name = "began with no card underneath",
        touches = { touch("t1", "began", 0.2, 0.5) },
        hitTest = function(_p) return nil end,
      },
      {
        name = "second concurrent touch",
        touches = { touch("t1", "moved", 0.3, 0.5), touch("t2", "began", 0.6, 0.5) },
        hitTest = alwaysHit("card1"),
      },
    }

    for _, scenario in ipairs(scenarios) do
      it("returns false for a " .. scenario.name .. " event", function()
        local g = gesture.new({
          cfg = makeCfg(),
          hitTest = scenario.hitTest,
          onSwipe = function() end,
        })
        hs.timer._now = 0
        local result = g._handleEvent(event(scenario.touches))
        assert.is_false(result)
      end)
    end
  end)

  describe("a throwing onSwipe", function()
    it("does not propagate out of the callback, and still returns false", function()
      local g = gesture.new({
        cfg = makeCfg(),
        hitTest = alwaysHit("card1"),
        onSwipe = function() error("boom from onSwipe") end,
      })
      hs.timer._now = 0
      g._handleEvent(event({ touch("t1", "began", 0.2, 0.5) }))
      hs.timer._now = 0.1

      local result
      assert.has_no.errors(function()
        result = g._handleEvent(event({ touch("t1", "ended", 0.5, 0.5) }))
      end)
      assert.is_false(result)
    end)
  end)
end)
