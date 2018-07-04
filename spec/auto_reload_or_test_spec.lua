require 'spec.spec_helper'

expose("Auto-reload or test library", function()

  local arot = require 'auto_reload_or_test'

  setup(function()
    a_module_under_test_file = '/Users/user/code/hammerspoon_config/a_module_under_test.lua'
    a_module_not_under_test_file = '/Users/user/code/hammerspoon_config/a_module_not_under_test.lua'
    a_module_under_test_spec_file = '/Users/user/code/hammerspoon_config/a_module_under_test_spec.lua'
    consts.modules_under_test = {"a_module_under_test", "another_module_under_test"}
  end)
  
  describe("file_is_under_test", function()
    it("returns true when file basename listed in modules_under_test", function()
      assert.is_true(
          arot.file_is_under_test(a_module_under_test_file))
    end)
    it("returns true for spec file when matched file basename listed in modules_under_test", function()
      assert.is_true(
          arot.file_is_under_test(a_module_under_test_spec_file))
    end)
  end)

  describe("spec_file_from_file", function()
    it("is the right spec file", function()
      assert.are.equal(a_module_under_test_spec_file,
          arot.spec_file_from_file(a_module_under_test_file))
    end)
  end)

  describe("spec_file_from_module", function()
    it("is the right spec file", function()
      assert.are.equal("spec/a_module_under_test_spec.lua",
          arot.spec_file_from_module("a_module_under_test"))
    end)
  end)

  describe("file_from_spec_file", function()
    it("is the right file", function()
      assert.are.equal("spec/a_module_under_test_spec.lua",
          arot.spec_file_from_module("a_module_under_test"))
    end)
  end)

  describe("basename", function()
    it("is the basename", function()
      assert.are.equal("a_module_under_test",
          arot.basename(a_module_under_test_file))
      assert.are.equal("a_module_under_test",
          arot.basename(a_module_under_test_spec_file))
    end)
  end)

  describe("is_luafile", function()
    it("true for a lua file", function()
      assert.is_true(arot.is_luafile(a_module_under_test_file))
    end)
    it("false for a not-lua file", function()
      assert.is_false(arot.is_luafile("/tmp/not_a_lua_file"))
    end)
  end)

  describe("changed_modules_under_test", function()
    it("returns modules_under_test", function()
      local files = {a_module_under_test_file, "/tmp/not_a_lua_file"}
      assert.are_same(
        {"a_module_under_test"},
        arot.changed_modules_under_test(files)
      )
    end)

    it("returns an empty list when appropriate", function()
      local files = {'/Users/user/code/hammerspoon_config/a_module_not_under_test.lua'}
      assert.are_same( {}, arot.changed_modules_under_test(files))
    end)
  end)

  describe("did_any_module_not_under_test_change", function()
    it("returns true when it should", function()
      local files = {a_module_under_test_file, a_module_not_under_test_file}
      assert.is_true(arot.did_any_module_not_under_test_change(files))
    end)
    it("returns false when it should", function()
      local files = {a_module_under_test_file}
      assert.is_false(arot.did_any_module_not_under_test_change(files))
    end)
  end)

  describe("test_or_reload", function()
    it("should reload when non-test modules change", function()
      -- TODO
      pending("really should have a test or two")
    end)
    it("should execute tests when test modules change and no non-test modules change", function()
      -- TODO
      pending("really should have a test or two")
    end)
--[[
function M.test_or_reload(files)
  local changed_modules_under_test = M.changed_modules_under_test(files)
  local did_any_module_not_under_test_change = M.did_any_module_not_under_test_change(files)

  if #changed_modules_under_test ~= 0 and not did_any_module_not_under_test_change then
    hs.fnutils.every(changed_modules_under_test, function(module)
      logger.i(module .." is under test, testing it")
      local output,status,ret_type,ret_code = hs.execute("/usr/local/bin/busted ".. M.spec_file_from_module(module))
      print(output)
    end)
  elseif did_any_module_not_under_test_change then
    logger.i("modules not under test changed, reloading")
    hs.reload()
  else
    -- do nothing
  end
end
]]
  end)

  describe("start", function()
    it("should start a file watcher", function()
      -- TODO
      pending("really should have a test or two")
    end)
--[[
function M:start()
  logger.i("Starting config file watcher")
  self.configFileWatcher = hs.pathwatcher.new(hs.configdir,
      function(paths) M.test_or_reload(paths) end)
  self.configFileWatcher:start()
end
]]
  end)
end)
