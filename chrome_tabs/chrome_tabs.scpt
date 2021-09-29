#@osa-lang:AppleScript
on all_windows_and_tabs()
	tell application "Google Chrome"
		set _windows to {}
		set _window_index to 0
		repeat with a_window in (windows)
			set _window_index to _window_index + 1
			set _tabs to {}
			set _tab_index to 0
			repeat with a_tab in (tabs of a_window)
				set _tab_index to _tab_index + 1
				try
					set _url to URL of a_tab
					if _url is missing value then
						set _url to -1
					end if
				on error
					set _url to -1
				end try
				try
					set _title to title of a_tab
					if _title is missing value then
						set _title to -1
					end if
				on error
					set _title to -1
				end try
				set end of _tabs to {tabId:(id of a_tab), windowId:(id of a_window), tabIndex:_tab_index, tabURL:_url, tabTitle:_title}
			end repeat
			set end of _windows to {windowId:(id of a_window), windowIndex:_window_index, activeTabIndex:(active tab index of a_window), windowTabs:_tabs}
		end repeat
		return _windows
	end tell
end all_windows_and_tabs

on one_window_and_tabs(window_id)
	tell application "Google Chrome"
		set _tabs to {}
		set a_window to (first window whose id is window_id)
		set _window_index to (index of a_window)
		set _tab_index to 0
		repeat with a_tab in (tabs of a_window)
			set _tab_index to _tab_index + 1
			try
				set _url to URL of a_tab
				if _url is missing value then
					set _url to -1
				end if
			on error
				set _url to -1
			end try
			try
				set _title to title of a_tab
				if _title is missing value then
					set _title to -1
				end if
			on error
				set _title to -1
			end try
			set end of _tabs to {tabId:(id of a_tab), windowId:(id of a_window), tabIndex:_tab_index, tabURL:_url, tabTitle:_title}
		end repeat
		return {windowId:(id of a_window), windowIndex:_window_index, activeTabIndex:(active tab index of a_window), windowTabs:_tabs}
	end tell
end one_window_and_tabs

on all_windows()
	tell application "Google Chrome"
		set _windows to {}
		set _window_index to 0
		repeat with a_window in (windows)
			set _window_index to _window_index + 1
			set _window_id to (id of a_window)
			set end of _windows to {windowId:_window_id, windowIndex:_window_index, activeTabIndex:(active tab index of a_window)}
		end repeat
		return _windows
	end tell
end all_windows

on find_tab(tab_id)
	tell application "Google Chrome"
		set _window_index to 0
		repeat with a_window in (windows)
			set _window_index to _window_index + 1
			set _tab_index to 0
			repeat with a_tab in (tabs of a_window)
				set _tab_index to _tab_index + 1
				if (id of a_tab) is tab_id then
					set _found to true
					return {_tab_index, a_window}
				end if
			end repeat
		end repeat

		if _found is not true then
			error ("not found")
		end if

	end tell
end find_tab

on focus_tab(index_of_tab, window_of_tab)
	tell application "Google Chrome"
		set active tab index of window_of_tab to index_of_tab
		activate
		set index of window_of_tab to 1
		activate window_of_tab
		return true
	end tell
end focus_tab

on find_window(window_id)
	tell application "Google Chrome"
		return (first window whose id is window_id)
	end tell
end find_window

on focus_window(a_window)
	tell application "Google Chrome"
		activate
		set index of a_window to 1
		activate a_window
		return true
	end tell
end focus_window

(*
	log (properties of a_window)
	set _title to title of a_window as string
	tell application "System Events"
		tell process "Google Chrome"
			set frontmost to true
			try -- works, but raises an error
				set a_se_window to (first window whose title is _title)
				log (properties of a_se_window)
				perform action "AXRaise" of a_se_window
			end try
		end tell
	end tell
	*)
