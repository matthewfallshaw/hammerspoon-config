--- === gpmdp ===
--- Controls for Google Play Music Desktop Player music player

local obj = { volume = {} }

-- Metadata
obj.name = "GPMDP"
obj.version = "1.0"
obj.author = "Matthew Fallshaw <m@fallshaw.me>"
obj.homepage = "https://github.com/matthewfallshaw/hammerspoon-config"
obj.license = "MIT - https://opensource.org/licenses/MIT"

local app_name = 'Google Play Music Desktop Player'

obj._logger = hs.logger.new(obj.name)
local logger = obj._logger
logger.i("Loading ".. obj.name)


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

local function notify(informativeText, subTitle, title)
  hs.notify.new(obj.hide,
    { title = title or "GPMDP", subTitle = subTitle,
      informativeText = informativeText,
      setIdImage = hs.image.imageFromAppBundle(obj.app():bundleID())
    }):send()
end

local cli = "~/bin/gpmdp-cli"
if not fileExists(cli) then
  error("I can't find ".. cli .." which I need to function. Install "..
  "https://github.com/Glitch-is/gpmdp-cli.git there.")
end

--- gpmdp.STATE_PAUSED
--- Constant
--- Returned by `gpmdp.getPlaybackState()` to indicate gpmdp is paused
--- https://github.com/gmusic-utils/gmusic.js#playbackgetplaybackstate
obj.STATE_PAUSED = 1

--- gpmdp.STATE_PLAYING
--- Constant
--- Returned by `gpmdp.getPlaybackState()` to indicate gpmdp is playing
--- https://github.com/gmusic-utils/gmusic.js#playbackgetplaybackstate
obj.STATE_PLAYING = 2

--- gpmdp.STATE_STOPPED
--- Constant
--- Returned by `gpmdp.getPlaybackState()` to indicate gpmdp is stopped
--- https://github.com/gmusic-utils/gmusic.js#playbackgetplaybackstate
obj.STATE_STOPPED = 0

--- gpmdp.tell(cmd)
-- Function
-- Pass a command directly to gpmdp-cli
--
-- Parameters:
--   * cmd - a command string: namespace method [arguments]*
-- 
-- Returns:
--   * string, whatever gpmdp-cli returns
function obj.tell(cmd)
  if not obj.app() then return nil end

  -- TODO:
  -- hs.task callback sometimes fails to run before task:waitUntilExit so
  -- rexitCode is nil (results collected by stream callback, so just ignore this
  -- problem by defaulting to 0 -
  -- NOTE THAT THIS IGNORES ERRORS IF THEY OCCUR)
  local rexitCode = 0
  local rstdOut, rstdErr = '', ''
  local task = hs.task.new(cli,
    function(exitCode, stdOut, stdErr)
      rexitCode = tonumber(exitCode)
      rstdOut = rstdOut .. stdOut; rstdErr = rstdErr .. stdErr  -- accumulated values
    end,
    function(task, stdOut, stdErr)
      rstdOut = rstdOut .. stdOut; rstdErr = rstdErr .. stdErr  -- accumulated values
      return true
    end,
    cmd:split(" "))
  task:setEnvironment({PATH =
    os.getenv("HOME")..'/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin'})
  task:start()
  task:waitUntilExit()
  if rexitCode ~= 0 then
    logger.e(cli .." failed - cmd:'"..cmd.."', exitcode:'"..tostring(rexitCode)..
      "', stdout:'"..tostring(rstdOut):chomp().."', stderr:'"..tostring(rstdErr):chomp()..
      "'")
  end
  return tostring(rstdOut):chomp()
end
local tell = obj.tell

--- gpmdp.app()
--- Function
--- Returns the GPMDP app, if it's running, nil otherwise
---
--- Parameters:
---  * None
---
--- Returns:
---  * hs.application, the GPMDP app
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
---  * The gpmdp object
function obj.playpause()
  local app = obj.app()
  if not app then
    hs.application.open(app_name)
  else
    tell('playback playPause')
  end
  return obj
end

--- gpmdp.play()
--- Function
--- Plays the current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.play()
  if not obj.isPlaying() then
    tell('playback playPause')
  end
  return obj
end

--- gpmdp.pause()
--- Function
--- Pauses the current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.pause()
  if obj.isPlaying() then
    tell('playback playPause')
  end
  return obj
end

--- gpmdp.next()
--- Function
--- Skips to the next gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.next()
  tell('playback forward')
  return obj
end

--- gpmdp.previous()
--- Function
--- If deep in the current track, rewinds to start, if close to start, jumps to
--- previous gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.previous()
  tell('playback rewind')
  return obj
end

--- gpmdp.like()
--- Function
--- Likes current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.like()
  local rating = obj.getRating()
  local track = obj.getCurrentTrackAndArtist()
  if rating == 5 then
    notify(track ..' already liked')
  else
    tell('rating setRating 5')
    notify('Liked '.. track)
  end
  return obj
end

--- gpmdp.dislike()
--- Function
--- Dislike current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * The gpmdp object
function obj.dislike()
  local rating = obj.getRating()
  local track = obj.getCurrentTrackAndArtist()
  if rating == 1 then
    notify(track ..' already disliked')
  else
    tell('rating setRating 1')
    notify('Disliked '.. track)
  end
  return obj
end

--- gpmdp.getRating()
--- Function
--- Get the rating of the current gpmdp track
---
--- Parameters:
---  * None
---
--- Returns:
---  * An integer, the rating (0 means no rating, 1 means disliked)
function obj.getRating()
  local rating = tell('rating getRating')
  return tonumber(rating)
end

--- gpmdp.setRating(rating)
--- Function
--- Set rating of the current gpmdp track (0, 1-5)
---
--- Parameters:
---  * rating - An integer, 0 means no rating, 1 means disliked, 5 means liked
---
--- Returns:
---  * The gpmdp object
function obj.setRating(rating)
  local rating = tonumber(rating)
  local track = obj.getCurrentTrackAndArtist()
  tell('rating setRating '.. tostring(rating))
  notify(track .." rated ".. tostring(rating) .." out of 5")
  return obj
end

--- gpmdp.getCurrentTrack()
--- Function
--- Gets information for current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * a table, the track information
function obj.getCurrentTrack()
  local info = tell('playback getCurrentTrack')
  local out = {}
  out.artist = info:match("'artist': '([^']+)'") or "Unknown artist"
  out.album  = info:match("'album': '([^']+)'") or "Unknown album"
  out.track  = info:match("'title': '([^']+)'") or "Unknown track"
  return out
end

--- gpmdp.displayCurrentTrack()
--- Function
--- Displays information for current track on screen
---
--- Parameters:
---  * None
---
--- Returns:
---  * a string, the track information
function obj.displayCurrentTrack()
  local info = obj.getCurrentTrack()
  local albumartist = 'from "'.. info.album ..'"\nby "'.. info.artist ..'"'
  notify(albumartist, info.track)
  return info.track .."\n".. albumartist
end

--- gpmdp.getCurrentTrackAndArtist()
--- Function
--- Gets the name and the name of the artist of the current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the name and Artist of the current track, or nil if an error occurred
function obj.getCurrentTrackAndArtist()
  return '"'.. obj.getCurrentTrackName() ..'" by "'.. obj.getCurrentArtist() ..'"'
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
  return obj.getCurrentTrack().artist
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
  return obj.getCurrentTrack().album
end

--- gpmdp.getCurrentTrackName()
--- Function
--- Gets the name of the current track
---
--- Parameters:
---  * None
---
--- Returns:
---  * A string containing the name of the current track, or nil if an error occurred
function obj.getCurrentTrackName()
  return obj.getCurrentTrack().track
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
---    - `gpmdp.STATE_STOPPED`
---    - `gpmdp.STATE_PAUSED`
---    - `gpmdp.STATE_PLAYING`
function obj.getPlaybackState()
  return tonumber(tell('playback getPlaybackState'))
end

--- gpmdp.isRunning()
--- Function
--- Returns whether gpmdp is currently open. Most other functions in hs.gpmdp
--- will automatically start the application, so this function can be used to
--- guard against that.
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
---  * A boolean value indicating whether gpmdp is currently playing a track, or
--- nil if an error occurred (unknown player state). Also returns false if the
--- application is not running
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
---  * The gpmdp object
function obj.setVolume(v)
  v = tonumber(v)
  if not v then error('volume must be a number 1..100', 2) end
  tell('volume setVolume ' .. tostring(math.min(100, math.max(0, v))))
  return obj
end

--- gpmdp.volumeUp()
--- Function
--- Increases the volume by 5
---
--- Parameters:
---  * None
---
--- Returns:
---  * The new volume (between 0 and 100)
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
---  * The new volume (between 0 and 100)
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
---  * The gpmdp object
function obj.mute()
  local current_volume = obj.getVolume()
  if current_volume == 0 then
    obj.setVolume(obj.volume['pre-mute'] or 30)
  else
    obj.volume['pre-mute'] = current_volume
    obj.setVolume(0)
  end
  return obj
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
---  * The gpmdp object
function obj.setPosition(p)
  p = tonumber(p)
  if not p then error('position must be a number in seconds', 2) end
  tell('playback setCurrentTime ' .. tostring(p * 1000))
  return gpmdp
end

--- gpmdp.ff()
--- Function
--- Skips the playback position forwards by 5 seconds
---
--- Parameters:
---  * None
---
--- Returns:
---  * A number indicating the new position in the song
function obj.ff()
  local pos = obj.getPosition() + 5
  obj.setPosition(pos)
  return pos
end

--- gpmdp.rw
--- Function
--- Skips the playback position backwards by 5 seconds
---
--- Parameters:
---  * None
---
--- Returns:
---  * A number indicating the new position in the song
function obj.rw()
  local pos = obj.getPosition() - 5
  obj.setPosition(pos)
  return pos
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
---  * None
function obj.quit()
  if obj.app() then obj.app():kill() end
end


-- Spoon interactions
obj.spoons = {}

-- spoon.HeadphoneAutoPause
obj.spoons.HeadphoneAutoPause = {
  controlfns = {
    ['Google Play Music Desktop Player'] = {
      appname = 'Google Play Music Desktop Player',
      isPlaying = obj.isPlaying,
      play = obj.play,
      pause = obj.pause
    }
  }
}
if spoon.HeadphoneAutoPause then
  local hap = spoon.HeadphoneAutoPause

  if not hap.controlfns['Google Play Music Desktop Player'] then
    hap.controlfns['Google Play Music Desktop Player'] =
    obj.spoons.HeadphoneAutoPause.controlfns['Google Play Music Desktop Player']
  end
end

return obj
