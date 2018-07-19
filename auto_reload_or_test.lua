--- === Auto-reload or Test ===
---
--- If a config file changes then
---   If it's listed in arot.modules_under_test, call its spec file
---   If it's not, hs.reload()

local M = {}

-- Metadata
M.name = 'AutoReloadOrTest'
M.version = "0.1"
M.author = "Matthew Fallshaw <m@fallshaw.me>"
M.license = "MIT - https://opensource.org/licenses/MIT"
M.homepage = "https://github.com/matthewfallshaw/"


local logger = hs.logger.new("AutoReload")
M._logger = logger

local lfs = require 'lfs'
local consts = require 'configConsts'
local escape, unescape = require('utilities.string_escapes')()

function M.hs_configdir()
  local dir = hs.configdir
  local target = lfs.symlinkattributes(hs.configdir).target
  if target then
    if target:sub(1,7) == '/Users/' then
      dir = target
    else
      dir = os.getenv("HOME")..'/'..target
    end
  end
  M.hs_configdir = function() return dir end  -- memoize
  return dir
end

function M.modularise_file_path(file)
  local out = file
  out = (out:gsub(escape.for_regexp(M.hs_configdir()), ''))
  out = (out:gsub('^/spec/',''))
  out = (out:gsub('_spec%.lua$','.lua'))
  out = (out:gsub('/([^/]+)/init%.lua$','/%1.lua'))
  out = (out:gsub('%.lua$',''))
  out = (out:gsub('^/', ''))
  out = (out:gsub('/$', ''))
  out = (out:gsub('/', '.'))
  return out
end

function M.is_module_under_test(mod)
  local mods_under_test_with_spec_helper = {'spec_helper'}
  hs.fnutils.each(consts.modules_under_test,
      function(x) table.insert(mods_under_test_with_spec_helper, x) end)
  return hs.fnutils.contains(mods_under_test_with_spec_helper, mod)
end

function M.spec_from_module(mod)
  return "spec/".. (mod:gsub('%.','/')) .."_spec.lua"
end

function M.is_luafile(file)
  return (file:match('%.lua$')) and true or false
end

function M.is_specfile(file)
  return (file:match('_spec%.lua$'))
end

function M.file_types(files)
  local changed_modules_under_test = {}
  local changed_spec_files_for_modules_not_under_test = {}
  local changed_modules_not_under_test = {}
  hs.fnutils.each(
    files,
    function(f)
      if M.is_luafile(f) then
        local mod = M.modularise_file_path(f)
        if M.is_module_under_test(mod) then
          table.insert(changed_modules_under_test, mod)
        else
          if M.is_specfile(f) then
            table.insert(changed_spec_files_for_modules_not_under_test, f)
          else
            table.insert(changed_modules_not_under_test, mod)
          end
        end
      else
        -- do nothing with this file
      end
    end
  )
  return changed_modules_under_test,
         changed_spec_files_for_modules_not_under_test,
         changed_modules_not_under_test
end

function M.test_module(mod)
  print(mod .." is under test, testing it")
  local output,status,ret_type,ret_code =
      hs.execute("/usr/local/bin/busted ".. M.spec_from_module(mod))
  print(output)
end

function M.test_file(file)
  print(file .." is a spec file, running it")
  local output,status,ret_type,ret_code =
      hs.execute("/usr/local/bin/busted ".. file)
  print(output)
end

function M.test_or_reload(files)
  print("changed files: "..hs.inspect(files))
  local changed_modules_under_test,
        changed_spec_files_for_modules_not_under_test,
        changed_modules_not_under_test = M.file_types(files)

  if #changed_modules_not_under_test > 0 then
    logger.i("modules not under test changed, reloading")
    hs.reload()
  else
    hs.fnutils.every(changed_modules_under_test, M.test_module)
    hs.fnutils.every(changed_spec_files_for_modules_not_under_test, M.test_file)
    if (#changed_modules_under_test +
        #changed_spec_files_for_modules_not_under_test) > 0 then
      hs.openConsole()
    end
  end
end


function M:start()
  logger.i("Starting config file watcher")
  self.configFileWatcher = hs.pathwatcher.new(hs.configdir,
      function(files) M.test_or_reload(files) end)
  self.configFileWatcher:start()
end

return M
