require 'spec.spec_helper'

expose("Auto-reload or test library", function()

  local arot = require 'auto_reload_or_test'

  setup(function()
    local hs_configdir = arot.hs_configdir()
    fix = {
      a_module_under_test = {
        mod  = 'a_module_under_test',
        file = hs_configdir..'/a_module_under_test.lua',
        spec = 'spec/a_module_under_test_spec.lua',
        specfile = hs_configdir..'/spec/a_module_under_test_spec.lua',
      },
      an_init_module_under_test = {
        mod  = 'an_init_module_under_test',
        file = hs_configdir..'/an_init_module_under_test/init.lua',
        spec = 'spec/an_init_module_under_test_spec.lua',
        specfile = hs_configdir..'/spec/an_init_module_under_test_spec.lua',
      },
      a_subdir_module_under_test = {
        mod  = 'subdir.a_subdir_module_under_test',
        file = hs_configdir..'/subdir/a_subdir_module_under_test.lua',
        spec = 'spec/subdir/a_subdir_module_under_test_spec.lua',
        specfile = hs_configdir..'/spec/subdir/a_subdir_module_under_test_spec.lua',
      },
      a_module_not_under_test = {
        mod  = 'a_module_not_under_test',
        file = hs_configdir..'/a_module_not_under_test.lua',
        spec = 'spec/a_module_not_under_test_spec.lua',
        specfile = hs_configdir..'/spec/a_module_not_under_test_spec.lua',
      },
    }
    consts.modules_under_test = {
      fix.a_module_under_test.mod,
      fix.an_init_module_under_test.mod,
      fix.a_subdir_module_under_test.mod }
  end)
  
  describe("is_module_under_test", function()
    it("returns true when module listed in modules_under_test", function()
      assert.is_true(arot.is_module_under_test(fix.a_module_under_test.mod))
    end)
    it("returns true when subdir module listed in modules_under_test", function()
      assert.is_true(arot.is_module_under_test(fix.a_subdir_module_under_test.mod))
    end)
    it("returns true when init module listed in modules_under_test", function()
      assert.is_true(arot.is_module_under_test(fix.an_init_module_under_test.mod))
    end)
  end)

  describe("spec_from_module", function()
    it("is the right spec file", function()
      assert.are.equal(fix.a_module_under_test.spec,
          arot.spec_from_module(fix.a_module_under_test.mod))
    end)
    it("is the right spec file for a subdir module", function()
      assert.are.equal(fix.a_subdir_module_under_test.spec,
          arot.spec_from_module(fix.a_subdir_module_under_test.mod))
    end)
  end)

  describe("is_luafile", function()
    it("true for a lua file", function()
      assert.is_true(arot.is_luafile(fix.a_module_under_test.file))
    end)
    it("false for a not-lua file", function()
      assert.is_false(arot.is_luafile("/tmp/not_a_lua_file.conf"))
    end)
  end)

  describe("modularise_file_path", function()
    for k,v in pairs({'a_module_under_test', 'an_init_module_under_test',
        'a_subdir_module_under_test', 'a_module_not_under_test'}) do
      it("is "..fix[v].mod.." for "..fix[v].file, function()
        assert.equal(fix[v].mod, arot.modularise_file_path(fix[v].file))
      end)
      it("is "..fix[v].mod.." for "..fix[v].specfile, function()
        assert.equal(fix[v].mod, arot.modularise_file_path(fix[v].specfile))
      end)
    end
  end)

  describe("file_types", function()
    setup(function()
      changed_modules_under_test,
      changed_spec_files_for_modules_not_under_test,
      changed_modules_not_under_test = arot.file_types({
        fix.a_module_under_test.file,
        fix.a_module_under_test.specfile,
        fix.an_init_module_under_test.file,
        fix.an_init_module_under_test.specfile,
        fix.a_subdir_module_under_test.file,
        fix.a_subdir_module_under_test.specfile,
        fix.a_module_not_under_test.file,
        fix.a_module_not_under_test.specfile,
      })
    end)
    it("returns changed_modules_under_test", function()
      assert.are_same(
        {
          fix.a_module_under_test.mod,
          fix.a_module_under_test.mod,
          fix.an_init_module_under_test.mod,
          fix.an_init_module_under_test.mod,
          fix.a_subdir_module_under_test.mod,
          fix.a_subdir_module_under_test.mod,
        },
        changed_modules_under_test
      )
    end)
    it("returns changed_spec_files_for_modules_not_under_test", function()
      assert.are_same(
        { fix.a_module_not_under_test.specfile },
          changed_spec_files_for_modules_not_under_test
      )
    end)
    it("returns changed_modules_not_under_test", function()
      assert.are_same(
        { fix.a_module_not_under_test.mod },
          changed_modules_not_under_test
      )
    end)
  end)
end)
