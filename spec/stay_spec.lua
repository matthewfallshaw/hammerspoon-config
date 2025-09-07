expose("Stay module", function()
  local stay

  setup(function()
    -- Add stay-specific hs mocks
    _G.hs.window.layout = {
      new = function() return {
        active = function() return false end
      } end
    }
    _G.hs.alert = {
      closeAll = function() end,
      show = function() end
    }
    _G.hs.geometry = {}
    _G.hs.pasteboard = {
      setContents = function() end
    }
    _G.hs.screen = {
      allScreens = function() return {} end,
      find = function() return {} end,
      watcher = {
        new = function() return {
          start = function() end
        } end
      }
    }
    _G.hs.timer.doAfter = function(_, _) end
    _G.hs.hotkey.new = function() return {} end

    -- Mock init global
    _G.init = {
      consts = {
        window_layouts = {}
      }
    }

    -- Mock the desktop_space_numbers module for testing
    package.loaded['desktop_space_numbers'] = {
      spaces_map = function()
        return {
          [123] = { spaceNumber = 6 },  -- personal space
          [456] = { spaceNumber = 7 },  -- bellroy space
          [789] = { spaceNumber = 8 },  -- mail space
          [101] = { spaceNumber = 10 }, -- miri space
        }
      end
    }

    -- Mock hs.spaces for testing
    _G.hs.spaces = {
      moveWindowToSpace = function(win, space_id)
        -- Just record that this was called for testing
        _G.test_moved_windows = _G.test_moved_windows or {}
        table.insert(_G.test_moved_windows, {window = win, space = space_id})
      end
    }

    -- Mock Chrome application and windows
    _G.test_chrome_windows = {
      {title = "Test Page - Google Chrome – Matthew (personal)", isStandard = function() return true end, isMinimized = function() return false end},
      {title = "Work Doc - Google Chrome – Matthew (bellroy)", isStandard = function() return true end, isMinimized = function() return false end},
      {title = "Research - Google Chrome – Matt (miri)", isStandard = function() return true end, isMinimized = function() return false end},
      {title = "Gmail - Google Chrome – Matthew (personal)", isStandard = function() return true end, isMinimized = function() return false end},
    }

    _G.hs.application.get = function(name)
      if name == "Google Chrome" then
        return {
          allWindows = function() return _G.test_chrome_windows end
        }
      end
      return nil
    end

    -- Now require the stay module after all mocks are set up
    stay = require 'stay'
  end)

  describe("detect_chrome_profile", function()
    -- Note: This function is local in stay.lua, so we can't test it directly
    -- But we can test the overall tidy_windows_by_profile function behavior
  end)

  describe("WindowTitleMatcher evaluation", function()
    it("should match personal profile window title", function()
      local mock_win = {
        title = function() return "Gmail - matthew.fallshaw@gmail.com - Google Chrome – Matthew (personal)" end
      }
      local matcher_config = {
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(personal%)$"
        }
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_true(result)
    end)

    it("should match bellroy profile window title", function()
      local mock_win = {
        title = function() return "Asana - Google Chrome – Matthew (bellroy)" end
      }
      local matcher_config = {
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(bellroy%)$"
        }
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_true(result)
    end)

    it("should match miri profile window title", function()
      local mock_win = {
        title = function() return "Research Paper - Google Chrome – Matt (miri)" end
      }
      local matcher_config = {
        window_title_matcher = {
          pattern = " %- Google Chrome – Matt %(miri%)$"
        }
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_true(result)
    end)

    it("should not match wrong profile", function()
      local mock_win = {
        title = function() return "Gmail - Google Chrome – Matthew (personal)" end
      }
      local matcher_config = {
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(bellroy%)$"
        }
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_false(result)
    end)

    it("should not match non-Chrome windows", function()
      local mock_win = {
        title = function() return "Terminal - Matthew (personal)" end
      }
      local matcher_config = {
        window_title_matcher = {
          pattern = " %- Google Chrome – Matthew %(personal%)$"
        }
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_false(result)
    end)

    it("should handle missing matcher gracefully", function()
      local mock_win = {
        title = function() return "Gmail - Google Chrome – Matthew (personal)" end
      }
      local matcher_config = {
        target_space = 6  -- No matcher, just configuration
      }

      local result = stay.evaluate_matcher(matcher_config, mock_win)
      assert.is_false(result)
    end)
  end)

  describe("Profile detection", function()
    it("should detect personal profile from window title", function()
      local mock_win = {
        title = function() return "Gmail - matthew.fallshaw@gmail.com - Google Chrome – Matthew (personal)" end
      }
      local profile_rules = {
        personal = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(personal%)$"
          },
          target_space = 6
        },
        bellroy = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(bellroy%)$"
          },
          target_space = 7
        }
      }

      local result = stay.detect_profile(mock_win, profile_rules)
      assert.are.equal("personal", result)
    end)

    it("should detect bellroy profile from window title", function()
      local mock_win = {
        title = function() return "Asana - Google Chrome – Matthew (bellroy)" end
      }
      local profile_rules = {
        personal = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(personal%)$"
          },
          target_space = 6
        },
        bellroy = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(bellroy%)$"
          },
          target_space = 7
        }
      }

      local result = stay.detect_profile(mock_win, profile_rules)
      assert.are.equal("bellroy", result)
    end)

    it("should detect miri profile from window title", function()
      local mock_win = {
        title = function() return "Research - Google Chrome – Matt (miri)" end
      }
      local profile_rules = {
        miri = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matt %(miri%)$"
          },
          target_space = 10
        }
      }

      local result = stay.detect_profile(mock_win, profile_rules)
      assert.are.equal("miri", result)
    end)

    it("should return nil for non-matching windows", function()
      local mock_win = {
        title = function() return "Terminal - bash" end
      }
      local profile_rules = {
        personal = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(personal%)$"
          },
          target_space = 6
        }
      }

      local result = stay.detect_profile(mock_win, profile_rules)
      assert.is_nil(result)
    end)

    it("should return first matching profile when multiple match", function()
      local mock_win = {
        title = function() return "Test - Google Chrome – Matthew (personal)" end
      }
      local profile_rules = {
        broad_personal = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew"  -- Broader pattern
          },
          target_space = 5
        },
        specific_personal = {
          window_title_matcher = {
            pattern = " %- Google Chrome – Matthew %(personal%)$"  -- More specific
          },
          target_space = 6
        }
      }

      -- Should return whichever profile is encountered first in pairs() iteration
      local result = stay.detect_profile(mock_win, profile_rules)
      assert.is_not_nil(result)
      assert.is_true(result == "broad_personal" or result == "specific_personal")
    end)

    it("should handle empty profile rules", function()
      local mock_win = {
        title = function() return "Gmail - Google Chrome – Matthew (personal)" end
      }
      local profile_rules = {}

      local result = stay.detect_profile(mock_win, profile_rules)
      assert.is_nil(result)
    end)
  end)

end)