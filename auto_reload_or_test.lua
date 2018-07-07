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

local consts = require 'configConsts'
local path = require 'utilities.path'

function M.file_is_under_test(file)
  if hs.fnutils.contains(
      consts.modules_under_test,
      path.basename(M.file_from_spec_file(file), '.lua')) then
    return true
  else
    return false
  end
end

function M.spec_file_from_file(file)
  if file:match('_spec.lua$') then return file end
  return (file:gsub('.lua$','_spec.lua'))
end

function M.spec_file_from_module(module)
  return "spec/".. module .."_spec.lua"
end

function M.file_from_spec_file(file)
  return (file:gsub('_spec.lua$','.lua'))
end

function M.basename(file)
  return path.basename(M.file_from_spec_file(file), '.lua')
end

function M.is_luafile(file)
  return path.extension(file) == '.lua'
end

function M.changed_modules_under_test(files)
  return hs.fnutils.map(
      hs.fnutils.filter(
          files,
          function(file)
            return M.is_luafile(file) and M.file_is_under_test(file)
          end),
      function(file)
        return M.basename(file)
      end)
end

function M.did_any_module_not_under_test_change(files)
  return hs.fnutils.some(
      hs.fnutils.filter(files, function(file) return M.is_luafile(file) end),
      function(file)
        return not M.file_is_under_test(file)
      end)
end

function M.test_or_reload(files)
  local changed_modules_under_test = M.changed_modules_under_test(files)
  local did_any_module_not_under_test_change = M.did_any_module_not_under_test_change(files)

  if #changed_modules_under_test > 0 and not did_any_module_not_under_test_change then
    hs.fnutils.every(changed_modules_under_test, function(module)
      local msg = module .." is under test, testing it"
      logger.i(msg)
      print(msg)
      local output,status,ret_type,ret_code = hs.execute("/usr/local/bin/busted ".. M.spec_file_from_module(module))
      print(output)
    end)
    hs.openConsole()
  elseif did_any_module_not_under_test_change then
    logger.i("modules not under test changed, reloading")
    hs.reload()
  else
    -- do nothing
  end
end


function M:start()
  logger.i("Starting config file watcher")
  self.configFileWatcher = hs.pathwatcher.new(hs.configdir,
      function(paths) M.test_or_reload(paths) end)
  self.configFileWatcher:start()
end

return M
