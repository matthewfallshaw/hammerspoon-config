require 'spec.spec_helper'

describe("chrome-tabs", function()
  chrome_tabs = require("chrome_tabs")

  it("should have defined global ChromeWindow", function()
    assert.is_not_nil(ChromeWindow)
  end)
  it("should have defined global ChromeTab", function()
    assert.is_not_nil(ChromeTab)
  end)

  _applescript_fixture = {}

  function reset_fixtures()
    -- FIXTURES
    _applescript_fixture = {
      ["return all_windows_and_tabs()"] = {
        {
          windowId = 1001,
          windowIndex = 1,
          activeTabIndex = 2,
          windowTabs = {
            { tabId = 101,
              windowId = 1001,
              tabIndex = 1,
              tabTitle = "Original window: Tab 1",
              tabURL = "http://example.org/tab1/index.html" },
            { tabId = 102,
              windowId = 1001,
              tabIndex = 2,
              tabTitle = "Original window: Tab 2",
              tabURL = "http://example.org/tab2/index.html" },
          }
        },
        {
          windowId = 1002,
          windowIndex = 2,
          activeTabIndex = 1,
          windowTabs = {
            { tabId = 103,
              windowId = 1002,
              tabIndex = 1,
              tabTitle = "Doomed window: Tab 1",
              tabURL = "http://example.org/doom/doom/doom" },
          }
        },
      },
      ["return all_windows()"] = {
        { windowId = 2001,  -- new window
          windowIndex = 1,
          activeTabIndex = 1 },
        { windowId = 1001,
          windowIndex = 2,  -- changed windowIndex
          activeTabIndex = 1 },  -- changed activeTabIndex
      },
      ["return one_window_and_tabs(1001)"] = {
        windowId = 1001,
        windowIndex = 2,  -- new windowIndex
        activeTabIndex = 1,  -- new activeTabIndex
        windowTabs = {
          { tabId = 201,  -- new tab
            windowId = 1001,
            tabIndex = 1,
            tabTitle = "Original window: New tab",
            tabURL = "http://example.org/new_tab.html" },
          { tabId = 102,
            windowId = 1001,
            tabIndex = 2,
            tabTitle = "Original window: Tab 2",
            tabURL = "http://example.org/tab2/index.html" },
        },
      },
      ["return one_window_and_tabs(2001)"] = {  -- new window
        windowId = 2001,
        windowIndex = 2,
        activeTabIndex = 1,
        windowTabs = {
          { tabId = 202,  -- new tab
            windowId = 2001,
            tabIndex = 1,
            tabTitle = "New window: Tab 1",
            tabURL = "http://example.com/tab1/new_window.html" },
          { tabId = 203,  -- new tab
            windowId = 2001,
            tabIndex = 2,
            tabTitle = "New window: Tab 2",
            tabURL = "http://example.com/tab2/new_window.html" }
        },
      },
      ["focus_tab(2, find_window(1001))"] = true,
      ["focus_window(find_window(1001))"] = true,
    }
  end
  -- STUBS
  chrome_tabs._applescript = function(str)
    reset_fixtures()
    return _applescript_fixture[str]
  end


  describe("utility functions", function()
    describe("create_all_windows_and_tabs", function()
      it("should create expected ChromeWindows", function()
        assert.are.same({}, chrome_tabs.chromeWindows)  -- empty to start

        chrome_tabs._create_all_windows_and_tabs()

        -- ChromeWindow properties
        local fixture = _applescript_fixture["return all_windows_and_tabs()"][1]
        hs.fnutils.each({'windowId', 'windowIndex', 'activeTabIndex'}, function(prop)
          assert.are.equal(fixture[prop], chrome_tabs.chromeWindows[1001][prop])
        end)

        -- ChromeWindow.chromeTabs properties
        hs.fnutils.each(
            {'tabId', 'windowId', 'tabIndex', 'tabTitle', 'tabURL'},
            function(prop)
              assert.are.equal(
                  fixture.windowTabs[1][prop],
                  chrome_tabs.chromeWindows[1001].chromeTabs[101][prop])
              assert.are.equal(
                  fixture.windowTabs[2][prop],
                  chrome_tabs.chromeWindows[1001].chromeTabs[102][prop])
            end)
        assert.are.equal(102, chrome_tabs.chromeWindows[1001].activeTab.tabId)
        assert.are.equal(1001, chrome_tabs.chromeWindows[1001].activeTab.chromeWindow.windowId)
      end)
    end)

    describe("check_and_update_windows", function()
      setup(function()
        chrome_tabs._create_all_windows_and_tabs()

        local spy = spy.on(chrome_tabs, "_applescript")
        chrome_tabs._check_and_update_windows()
      end)

      it("should update properties for existing windows", function()
        assert.are.equal(1001, chrome_tabs.chromeWindows[1001].windowId)
        assert.are.equal(2, chrome_tabs.chromeWindows[1001].windowIndex)
        assert.are.equal(1, chrome_tabs.chromeWindows[1001].activeTabIndex)
        assert.are.equal(101, chrome_tabs.chromeWindows[1001].activeTab.tabId)
      end)

      it("should create new windows", function()
        assert.spy(chrome_tabs._applescript).was_called_with("return one_window_and_tabs(2001)")
      end)

      it("should destroy destroyed windows", function()
        assert.is_nil(chrome_tabs.chromeWindows[1002])
      end)
    end)

    describe("refresh_one_window for existing window", function()
      setup(function()
        chrome_tabs._create_all_windows_and_tabs()
        chrome_tabs._refresh_one_window(1001)
      end)

      it("should create any new ChromeTabs for ChromeWindow window_id", function()
        assert.are.equal(201, chrome_tabs.chromeWindows[1001].chromeTabs[201].tabId)
        assert.are.equal("Original window: New tab",
            chrome_tabs.chromeWindows[1001].chromeTabs[201].tabTitle)
      end)

      it("should remove any removed ChromeTabs for ChromeWindow window_id", function()
        assert.is_nil(chrome_tabs.chromeWindows[1001].chromeTabs[101])
      end)

      it("should update properties for ChromeWindow window_id", function()
        assert.are.equal(2, chrome_tabs.chromeWindows[1001].windowIndex)
        assert.are.equal(1, chrome_tabs.chromeWindows[1001].activeTabIndex)
      end)

      it("should update properties for any changed ChromeTabs for ChromeWindow window_id", function()
        local fixture = _applescript_fixture["return one_window_and_tabs(1001)"]
        hs.fnutils.each(
            {'tabId', 'windowId', 'tabIndex', 'tabTitle', 'tabURL'},
            function(prop)
              assert.are.equal(
                  fixture.windowTabs[1][prop],
                  chrome_tabs.chromeWindows[1001].chromeTabs[201][prop])
              assert.are.equal(
                  fixture.windowTabs[2][prop],
                  chrome_tabs.chromeWindows[1001].chromeTabs[102][prop])
            end)
      end)

      it("should update activeTab for ChromeWindow window_id", function()
        assert.are.equal(201, chrome_tabs.chromeWindows[1001].activeTab.tabId)
      end)
    end)

    describe("refresh_one_window for a new window", function()
      setup(function()
        chrome_tabs._create_all_windows_and_tabs()
        chrome_tabs._refresh_one_window(2001)
      end)

      it("should create a new window if ChromeWindow window_id doesn't already exist", function()
        -- ChromeWindow properties
        local fixture = _applescript_fixture["return one_window_and_tabs(2001)"]
        hs.fnutils.each({'windowId', 'windowIndex', 'activeTabIndex'}, function(prop)
          assert.are.equal(fixture[prop], chrome_tabs.chromeWindows[2001][prop])
        end)

        -- ChromeWindow.chromeTabs properties
        hs.fnutils.each(
            {'tabId', 'windowId', 'tabIndex', 'tabTitle', 'tabURL'},
            function(prop)
              assert.are.equal(
                  fixture.windowTabs[1][prop],
                  chrome_tabs.chromeWindows[2001].chromeTabs[202][prop])
              assert.are.equal(
                  fixture.windowTabs[2][prop],
                  chrome_tabs.chromeWindows[2001].chromeTabs[203][prop])
            end)
        assert.are.equal(202, chrome_tabs.chromeWindows[2001].activeTab.tabId)
      end)
    end)
  end)

  -- describe("ChromeTab", function()
  --   describe("find", function()
  --     it("finds the tab, whatever space it might be on", function()
  --       -- pending("...")
  --       -- ChromeTab:find({ title=" - Google Drive$", url="^https://drive.google.com/drive/" })
  --     end)
  --   end)
  --   describe("focus", function()
  --     it("focuses the tab, whatever space it might be on", function()
  --       -- pending("...")
  --       -- :focus()
  --     end)
  --   end)
  --   describe("chromeWindow", function()
  --     it("knows its chromeWindow", function()
  --       -- pending("...")
  --       -- .chromeWindow
  --     end)
  --   end)
  -- end)

end)
