--- === notify.gesture ===
--- Swipe-to-dismiss state machine over `hs.eventtap.event.types.gesture`.
---
--- Owns the eventtap and the single-touch state machine only. Has **no
--- knowledge of cards**: the caller injects a `hitTest(point) -> cardId|nil`
--- and an `onSwipe(cardId)` callback (see `notify.gesture.new`). That
--- separation is the testing seam -- specs drive `_handleEvent` with
--- synthetic touch arrays and never touch a real eventtap.
---
--- Safety: the tap subscribes to `gesture` events only, its callback is
--- `pcall`-wrapped throughout, and it **always returns `false`** (propagate,
--- never delete) -- this shares a process with window management and an
--- eventtap that swallows input system-wide is a much worse failure than a
--- missed swipe.

local M = {}

-- Metadata
M.name = "NotifyGesture"
M.version = "1.0"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
M.license = "MIT - https://opensource.org/licenses/MIT"

M._logger = hs.logger.new("NotifyGesture")
local logger = M._logger

--- notify.gesture.new(opts) -> gesture
--- Creates a swipe-to-dismiss state machine. Does not start the eventtap;
--- call `start()`. `opts` is `{ cfg, hitTest, onSwipe }`: `cfg` is a complete
--- swipe config (`notify` owns the defaults), `hitTest(point) -> cardId|nil`
--- is called once, at touch `began`, with `hs.mouse.absolutePosition()`, and
--- `onSwipe(cardId)` fires when a swipe completes past threshold
--- (`pcall`-wrapped: a throwing `onSwipe` is logged, not propagated).
---
--- Returns `{ start, stop, isRunning, _handleEvent }`.
function M.new(opts)
  opts = opts or {}
  local cfg = opts.cfg
  local hitTest = opts.hitTest
  local onSwipe = opts.onSwipe

  local self = {}
  local tap = nil

  -- Single-touch gesture state. `identity` non-nil means a gesture is
  -- latched onto that touch; everything else is meaningless while it's nil.
  local identity = nil
  local cardId = nil
  local startPos = nil
  local startTime = nil
  local lastPos = nil
  local lastTime = nil
  local lastVelocity = nil

  local function resetState()
    identity = nil
    cardId = nil
    startPos = nil
    startTime = nil
    lastPos = nil
    lastTime = nil
    lastVelocity = nil
  end

  -- True if the jump from prevV to newV is a real direction reversal or a
  -- speed spike, per cfg.direction_tolerance / cfg.max_velocity_change.
  -- prevV/newV are signed scalar velocities along the swipe axis (x),
  -- normalized-surface-units per second; positive = rightward.
  local function isVelocityAbort(prevV, newV)
    if prevV == nil then return false end
    if prevV > 0 and newV < -cfg.direction_tolerance then return true end
    if math.abs(newV - prevV) > cfg.max_velocity_change then return true end
    return false
  end

  -- Updates lastPos/lastTime/lastVelocity from a moved/ended touch sample.
  -- Returns false if this sample's velocity triggers an abort.
  local function updateSample(t, now)
    local ok = true
    if lastTime ~= nil and now > lastTime and t.normalizedPosition ~= nil then
      local v = (t.normalizedPosition.x - lastPos.x) / (now - lastTime)
      if isVelocityAbort(lastVelocity, v) then ok = false end
      lastVelocity = v
    end
    if t.normalizedPosition ~= nil then lastPos = t.normalizedPosition end
    lastTime = now
    return ok
  end

  local function beginTouch(t)
    if t.normalizedPosition == nil then return end
    local point = hs.mouse.absolutePosition()
    local id = hitTest(point)
    if id == nil then return end -- gesture didn't start over a card: ignore it whole
    identity = t.identity
    cardId = id
    startPos = t.normalizedPosition
    startTime = hs.timer.secondsSinceEpoch()
    lastPos = startPos
    lastTime = startTime
    lastVelocity = nil
  end

  local function handleMoved(t)
    local now = hs.timer.secondsSinceEpoch()
    if not updateSample(t, now) then
      resetState() -- direction reversal or speed spike: abort
    end
  end

  local function handleEnded(t)
    local now = hs.timer.secondsSinceEpoch()
    local velocityOk = updateSample(t, now)
    local myCardId = cardId
    local travel = (t.normalizedPosition and startPos) and (t.normalizedPosition.x - startPos.x) or nil
    local duration = startTime and (now - startTime) or nil
    resetState() -- reset before firing, so a card shown from onSwipe can't see a stale latch

    if not velocityOk or travel == nil or duration == nil then return end
    if travel < cfg.min_distance or travel > cfg.max_distance then return end
    if duration > cfg.max_duration then return end

    local ok, err = pcall(onSwipe, myCardId)
    if not ok then
      logger.e("notify.gesture: onSwipe error: " .. tostring(err))
    end
  end

  -- Count of distinct touches currently down (began/moved/stationary).
  local function distinctTouchingCount(touches)
    local seen = {}
    local count = 0
    for _, t in ipairs(touches) do
      if t.touching and not seen[t.identity] then
        seen[t.identity] = true
        count = count + 1
      end
    end
    return count
  end

  local function processTouches(touches)
    -- Safety valve: never let a latch outlive max_duration, even if the
    -- matching ended/cancelled touch never arrives (e.g. a missed OS
    -- event) -- a stuck latch would otherwise block every future gesture.
    if identity ~= nil and startTime ~= nil
        and (hs.timer.secondsSinceEpoch() - startTime) > cfg.max_duration then
      resetState()
    end

    local touchingCount = distinctTouchingCount(touches)

    if identity ~= nil then
      if touchingCount > 1 then
        resetState() -- a second finger joined mid-gesture: single-finger only
        return
      end
      for _, t in ipairs(touches) do
        if t.identity == identity then
          if t.phase == "moved" then
            handleMoved(t)
          elseif t.phase == "ended" then
            handleEnded(t)
          elseif t.phase == "cancelled" then
            resetState()
          end
          -- "stationary": no state change.
          break
        end
      end
      return
    end

    if touchingCount > 1 then
      return -- multiple fingers arrived together: never latch, single-finger only
    end
    for _, t in ipairs(touches) do
      if t.phase == "began" then
        beginTouch(t)
        break
      end
    end
  end

  self._handleEvent = function(event)
    local ok, err = pcall(function()
      local touches = event:getTouches()
      if touches then processTouches(touches) end
    end)
    if not ok then
      logger.e("notify.gesture: eventtap handler error: " .. tostring(err))
      resetState()
    end
    return false -- never swallow: gesture events are never consumed
  end

  function self.start()
    if tap ~= nil then return end
    if cfg.enabled == false then return end
    local ok, result = pcall(hs.eventtap.new, { hs.eventtap.event.types.gesture }, self._handleEvent)
    if not ok then
      logger.e("notify.gesture: failed to create eventtap: " .. tostring(result))
      return
    end
    tap = result
    local startOk, startErr = pcall(function() tap:start() end)
    if not startOk then
      logger.e("notify.gesture: failed to start eventtap: " .. tostring(startErr))
      tap = nil
    end
  end

  function self.stop()
    resetState()
    if tap == nil then return end
    local ok, err = pcall(function() tap:stop() end)
    if not ok then
      logger.e("notify.gesture: failed to stop eventtap: " .. tostring(err))
    end
    tap = nil
  end

  function self.isRunning()
    return tap ~= nil
  end

  return self
end

return M
