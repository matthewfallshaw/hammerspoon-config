--- === extensions/itunes ===
---
--- Extensions to hs.itunes

-- Extension code begins at `-- Extensions`

local itunes = hs.itunes

local alert = require "hs.alert"
local app = require "hs.application"

-- Internal function to pass a command to Applescript.
local function tell(cmd)
  local _cmd = 'tell application "iTunes" to ' .. cmd
  local ok, result = hs.applescript(_cmd)
  if ok then
    return result
  else
    return nil
  end
end

-- ##########
-- Extensions


--- hs.itunes.alert_duration
--- Variable
--- Alerts (such as from hs.displayCurrentTrack()) will display for this number of seconds
itunes.alert_duration = 1.75


function itunes.displayCurrentTrack()
  local artist = tell('artist of the current track as string') or "Unknown artist"
  local album  = tell('album of the current track as string') or "Unknown album"
  local track  = tell('name of the current track as string') or "Unknown track"
  alert.show(track .."\n".. album .."\n".. artist, itunes.alert_duration)
end


--- hs.itunes.quit()
--- Function
--- Quits iTunes if it's running
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function itunes.quit()
  if itunes.isRunning() then
    app.get("iTunes"):kill()
  else
    alert.show("iTunes isn't running", itunes.alert_duration)
  end
  return itunes
end


--- hs.itunes.hide()
--- Function
--- Hide (or show) iTunes
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function itunes.hide()
  if itunes.isRunning() then
    local application = app.get("iTunes")
    if application:isHidden() then
      application:activate()
      alert.show("Unhid iTunes", itunes.alert_duration)
    else
      application:hide()
      alert.show("Hid iTunes", itunes.alert_duration)
    end
    return itunes
  else
    alert.show("iTunes isn't running", itunes.alert_duration)
  end
end


--- hs.itunes.like()
--- Function
--- Likes ("Love") the current iTunes track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function itunes.like()
  if itunes.isRunning() then
    if tell("loved of the current track") ~= true then
      tell('set the loved of the current track to true')
      alert.show("Liked song in iTunes", itunes.alert_duration)
    else
      alert.show("Song in iTunes already Liked", itunes.alert_duration)
    end
    return itunes
  else
    alert.show("iTunes isn't running", itunes.alert_duration)
  end
end

--- hs.itunes.dislike()
--- Function
--- Dislikes ("Dislike") the current iTunes track and moved to the next one
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function itunes.dislike()
  if itunes.isRunning() then
    if tell("disliked of the current track") ~= true then
      tell('set the disliked of the current track to true')
      alert.show("Disliked song in iTunes", itunes.alert_duration)
      itunes.next()
    else
      alert.show("Song in iTunes already Disliked", itunes.alert_duration)
    end
    return itunes
  else
    alert.show("iTunes isn't running")
  end
end


-- Fix for Applescript launching iTunes without a music library selected
local function string_starts_with(str, x) return string.find(str, x) == 1 end
for k,v in pairs(hs.itunes) do
  if type(v) == "function" and string_starts_with(k, "is") == false and string_starts_with(k, "___") == false then
    function_name, func = k, v

    -- move functions to `__func`
    itunes["___"..function_name] = func
    -- redefine func to check if iTunes is running, then call original function
    itunes.func = function(...)
      if itunes.isRunning() == false then
        app.open("iTunes")
      end
      itunes["___"..function_name](...)
    end
  end
end


-- /Extensions
-- ###########

return itunes
