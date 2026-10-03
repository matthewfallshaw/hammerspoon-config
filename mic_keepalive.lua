-- Hold a Bluetooth mic open after each right-option press.
--
-- Monologue dictates on right-option. With a Bluetooth headset as the default
-- input, macOS drops the mic link when nothing is using it, and re-opening it
-- costs 2-3s. Holding it open with sox for a while after each press means only
-- the first dictation of a burst waits. While held, the headset stays in its
-- call profile, so playback is at call quality.
--
-- The tap only observes: it returns false, so Monologue sees the key as usual.
--
-- A menubar icon shows while the mic is held (to release it, or to disable the
-- keepalive) and while the keepalive is disabled (to re-enable it). Disabling
-- lasts until re-enabled or Hammerspoon reloads.

local M = {}

local logger = hs.logger.new('MicKeepalive')
M.logger = logger

local RIGHT_OPTION = hs.keycodes.map.rightalt
local ICON_HOLDING = hs.image.imageFromName("NSTouchBarAudioInputTemplate")
local ICON_DISABLED = hs.image.imageFromName("NSTouchBarAudioInputMuteTemplate")

-- sox exits at once unless given a duration, so the hold is sox's own
-- `trim 0 <seconds>`; a sox orphaned by a Hammerspoon restart ends by itself.
local function findSox()
  for _, path in ipairs({
    "/etc/profiles/per-user/" .. (os.getenv("USER") or "") .. "/bin/sox",
    "/run/current-system/sw/bin/sox",
    "/opt/homebrew/bin/sox",
  }) do
    if hs.fs.attributes(path, 'mode') == 'file' then return path end
  end
end

local function refreshMenubar()
  if not M.menubar then return end
  local icon = (M.disabled and ICON_DISABLED) or (M.task and ICON_HOLDING)
  if icon then
    M.menubar:setIcon(icon):returnToMenuBar()
  else
    M.menubar:removeFromMenuBar()
  end
end

local function release()
  if M.task then
    M.task:terminate()
    M.task = nil
  end
  refreshMenubar()
end

local function hold()
  if M.disabled then return end
  local device = hs.audiodevice.defaultInputDevice()
  if not (device and device:transportType() == "Bluetooth") then
    release()
    return
  end
  local previous = M.task
  local task
  task = hs.task.new(M.sox, function(rc, _, err)
    if rc ~= 0 and rc ~= 15 then logger.e("sox exited " .. rc .. ": " .. err) end
    if M.task == task then
      M.task = nil
      refreshMenubar()
    end
  end, { "-q", "-d", "-n", "trim", "0", tostring(M.hold_seconds) })
  M.task = task
  M.device_name = device:name()
  M.held_until = os.time() + M.hold_seconds
  task:start()
  -- Start the new hold before ending the old one, so the link never idles.
  if previous then previous:terminate() end
  refreshMenubar()
end

local function setDisabled(disabled)
  M.disabled = disabled
  release()
end

local function menu()
  if M.disabled then
    return {
      { title = "Mic keepalive disabled", disabled = true },
      { title = "Enable keepalive", fn = function() setDisabled(false) end },
    }
  end
  return {
    { title = "Holding " .. M.device_name .. " until " .. os.date("%H:%M", M.held_until),
      disabled = true },
    { title = "Release now", fn = release },
    { title = "Disable keepalive", fn = function() setDisabled(true) end },
  }
end

function M:start()
  self.hold_seconds = init.consts.mic_keepalive.hold_seconds
  self.sox = self.sox or findSox()
  if not self.sox then
    logger.e("sox not found; mic keepalive disabled")
    return self
  end
  self.menubar = hs.menubar.new(false):setMenu(menu):setTooltip("Mic keepalive")
  self.tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    if event:getKeyCode() == RIGHT_OPTION and event:getFlags().alt then hold() end
    return false
  end):start()
  return self
end

function M:stop()
  if self.tap then self.tap:stop() end
  release()
  if self.menubar then self.menubar:delete() end
  return self
end

return M
