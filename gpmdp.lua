--- === gpmdp ===
--- Controls for Google Play Music Desktop Player music player

local app_name = 'Google Play Music Desktop Player'

local logger = hs.logger.new("GPMDP")
logger.i("Loading ".. app_name)


local obj = { volume = {} }

-- Utility functions
local function fileExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'file'
end
function string:split(sep)
   local sep, fields = sep or ":", {}
   local pattern = string.format("([^%s]+)", sep)
   self:gsub(pattern, function(c) fields[#fields+1] = c end)
   return fields
end
function string:chomp()
  local output = self:gsub("\n$", "")
  return output
end

local cli = "~/bin/gpmdp-cli"
if not fileExists(cli) then
  error("I can't find ".. cli .." which I need to function. Install https://github.com/Glitch-is/gpmdp-cli.git there.")
end

-- For states see https://github.com/gmusic-utils/gmusic.js

--- gpmdp.state_paused
--- Constant
--- Returned by `obj.getPlaybackState()` to indicates gpmdp is paused
obj.state_paused = 1

--- gpmdp.state_playing
--- Constant
--- Returned by `obj.getPlaybackState()` to indicates gpmdp is playing
obj.state_playing = 2

--- gpmdp.state_stopped
--- Constant
--- Returned by `obj.getPlaybackState()` to indicates gpmdp is stopped
obj.state_stopped = 0

-- Internal function to pass a command to gpmdp-cli
function obj.tell(cmd)
  if not obj.app() then return nil end

  local rexitCode, rstdOut, rstdErr = 0, '', ''
    -- hs.task callback sometimes fails to run before task:waitUntilExit so rexitCode is nil
    -- (results collected by stream callback, so just ignore this problem by defaulting to 0)
  local task = hs.task.new(cli,
    function(exitCode, stdOut, stdErr)
      rexitCode = tonumber(exitCode)  --; rstdOut = stdOut; rstdErr = stdErr
    end,
    function(task, stdOut, stdErr)
      rstdOut = rstdOut .. stdOut; rstdErr = rstdErr .. stdErr
      return true
    end,
    cmd:split(" "))
  task:setEnvironment({PATH = '/Users/matt/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin'})
  task:start()
  task:waitUntilExit()
  if rexitCode ~= 0 then
    logger.e(cli .." failed - cmd:'"..cmd.."', exitcode:'"..tostring(rexitCode).."', stdout:'"..tostring(rstdOut):chomp().."', stderr:'"..tostring(rstdErr):chomp().."'")
  end
  return tostring(rstdOut):chomp()
end
local tell = obj.tell

--- gpmdp.app()
--- Function
--- The GPMDP app, if it's running
---
--- Parameters:
---  * None
---
--- Returns:
---  * hs.application
function obj.app()
  return hs.application.get(app_name)
end

--- gpmdp.playpause()
--- Function
--- Toggles play/pause of current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.playpause()
  local app = obj.app()
  if not app then
    hs.application.open(app_name)
  else
    tell('playback playPause')
  end
end

--- gpmdp.play()
--- Function
--- Plays the current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.play()
  if not obj.isPlaying() then
    tell('playback playPause')
  end
end

--- gpmdp.pause()
--- Function
--- Pauses the current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.pause()
  if obj.isPlaying() then
    tell('playback playPause')
  end
end

--- gpmdp.next()
--- Function
--- Skips to the next gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.next()
  tell('playback forward')
end

--- gpmdp.previous()
--- Function
--- If deep in the current track, rewinds to start, if close to start, jumps to previous gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.previous()
  tell('playback rewind')
end

--- gpmdp.like()
--- Function
--- Likes current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.like()
  local rating = tell('rating getRating')
  if not rating or tonumber(rating) < 5 then
    tell('rating toggleThumbsUp')
  else
    hs.alert(obj.getCurrentTrack .." already liked")
  end
end

--- gpmdp.dislike()
--- Function
--- Dislike current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.dislike()
  local rating = tell('rating getRating')
  if not rating or tonumber(rating) > 1 then
    tell('rating toggleThumbsUp')
  else
    tell('rating setRating 1')
    hs.alert(obj.getCurrentTrack .." already disliked")
  end
end

--- gpmdp.displayCurrentTrack()
--- Function
--- Displays information for current track on screen
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.displayCurrentTrack()
  local info = tell('playback getCurrentTrack')
  local artist = info:match("'artist': '([^']+)'") or "Unknown artist"
  local album  = info:match("'album': '([^']+)'") or "Unknown album"
  local track  = info:match("'title': '([^']+)'") or "Unknown track"
  hs.alert.show(track .. "\n" .. album .. "\n" .. artist, 1.75)
end

--- gpmdp.getCurrentArtist()
--- Function
--- Gets the name of the artist of the current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the Artist of the current track, or nil if an error occurred
function obj.getCurrentArtist()
  local info = tell('playback getCurrentTrack')
  local artist = info:match("'artist': '([^']+)'") or "Unknown artist"
  return artist
end

--- gpmdp.getCurrentAlbum()
--- Function
--- Gets the name of the album of the current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the Album of the current track, or nil if an error occurred
function obj.getCurrentAlbum()
  local info = tell('playback getCurrentTrack')
  local album  = info:match("'album': '([^']+)'") or "Unknown album"
  return album
end

--- gpmdp.getCurrentTrack()
--- Function
--- Gets the name of the current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the name of the current track, or nil if an error occurred
function obj.getCurrentTrack()
  local info = tell('playback getCurrentTrack')
  local track  = info:match("'title': '([^']+)'") or "Unknown track"
  return track
end

--- gpmdp.getPlaybackState()
--- Function
--- Gets the current playback state of gpmdp
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing one of the following constants:
---    - `obj.state_stopped`
---    - `obj.state_paused`
---    - `obj.state_playing`
function obj.getPlaybackState()
  return tonumber(tell('playback getPlaybackState'))
end

--- gpmdp.isRunning()
--- Function
--- Returns whether gpmdp is currently open. Most other functions in hs.gpmdp will automatically start the application, so this function can be used to guard against that.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A boolean value indicating whether the gpmdp application is running.
function obj.isRunning()
  return obj.app(app_name) ~= nil
end

--- gpmdp.isPlaying()
--- Function
--- Returns whether gpmdp is currently playing
---
--- Parameters:
---  * None
---
--- Returns:
---  * A boolean value indicating whether gpmdp is currently playing a track, or nil if an error occurred (unknown player state). Also returns false if the application is not running
function obj.isPlaying()
  -- We check separately to avoid starting the application if it's not running
  if not obj.isRunning() then return false end
  return tell('playback isPlaying') == 'True'
end

--- gpmdp.getVolume()
--- Function
--- Gets the gpmdp volume setting
---
--- Parameters:
---  * None
---
--- Returns:
---  * A number containing the volume gpmdp is set to (between 0 and 100)
function obj.getVolume()
  return tonumber(tell('volume getVolume'))
end

--- gpmdp.setVolume(vol)
--- Function
--- Sets the gpmdp volume setting
---
--- Parameters:
---  * vol - A number between 1 and 100
---
--- Returns:
---  * The new volume (between 0 and 100)
function obj.setVolume(v)
  v = tonumber(v)
  if not v then error('volume must be a number 1..100', 2) end
  return tonumber(tell('volume setVolume ' .. math.min(100, math.max(0, v))))
end

--- gpmdp.volumeUp()
--- Function
--- Increases the volume by 5
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.volumeUp()
  tell('volume increaseVolume')
  return obj.getVolume()
end

--- gpmdp.volumeDown()
--- Function
--- Reduces the volume by 5
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.volumeDown()
  tell('volume decreaseVolume')
  return obj.getVolume()
end

--- gpmdp.mute()
--- Function
--- Sets the gpmdp volume setting to 0
---
--- Parameters:
---  * None
---
--- Returns:
---  * 0
function obj.mute()
  local current_volume = obj.getVolume()
  if current_volume == 0 then
    obj.setVolume(obj.volume['pre-mute'] or 30)
  else
    obj.volume['pre-mute'] = current_volume
    return obj.setVolume(0)
  end
end

--- gpmdp.getDuration()
--- Function
--- Gets the duration (in seconds) of the current song
---
--- Parameters:
---  * None
---
--- Returns:
---  * The number of seconds long the current song is, 0 if no song is playing
function obj.getDuration()
  local duration = tonumber(tell('playback getTotalTime')) / 1000
  return duration ~= nil and duration or 0
end

--- gpmdp.getPosition()
--- Function
--- Gets the playback position (in seconds) in the current song
---
--- Parameters:
---  * None
---
--- Returns:
---  * A number indicating the current position in the song
function obj.getPosition()
  return tonumber(tell('playback getCurrentTime') / 1000)
end

--- gpmdp.setPosition(pos)
--- Function
--- Sets the playback position in the current song
---
--- Parameters:
---  * pos - A number containing the position (in seconds) to jump to in the current song
---
--- Returns:
---  * None
function obj.setPosition(p)
  p = tonumber(p)
  if not p then error('position must be a number in seconds', 2) end
  return tonumber(tell('playback setCurrentTime ' .. p * 1000))
end

--- gpmdp.ff()
--- Function
--- Skips the playback position forwards by 5 seconds
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.ff()
  return obj.setPosition(obj.getPosition() + 5)
end

--- gpmdp.rw
--- Function
--- Skips the playback position backwards by 5 seconds
---
--- Parameters:
---  * None
---
--- Returns:
---  * None
function obj.rw()
  return obj.setPosition(obj.getPosition() - 5)
end

--- gpmdp.hide()
--- Function
--- Hide the GPMDP app, if it's running
---
--- Parameters:
---  * None
---
--- Returns:
---  * hs.application
function obj.hide()
  local app = obj.app()
  if not app then return nil end
  if app:isFrontmost() then
    app:hide()
  else
    app:activate()
  end
  return app
end

--- gpmdp.quit()
--- Function
--- Quit the GPMDP app, if it's running
---
--- Parameters:
---  * None
---
--- Returns:
---  * hs.application
function obj.quit()
  if obj.app() then obj.app():kill() end
  return nil
end

return obj
