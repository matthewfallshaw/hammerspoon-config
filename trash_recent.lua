-- Trash recent downloads
local logger = hs.logger.new("Trash Recent Downloads")
logger.i("Trash recent downloads")

-- Module definition with configuration
local M = {
  -- Public configuration (can be modified by users)
  config = {
    -- File system paths
    downloadsDirectory = "~/Downloads/",
    trashCommand = nil,  -- Optional: User can specify their preferred trash command

    -- Temporary files and caching
    logFile = hs.fs.temporaryDirectory() .. "trash-most-recent.log",
    previewCacheDir = hs.fs.temporaryDirectory() .. "hs-trash-recent-previews/",

    -- Preview configuration
    previewSize = "400",           -- Size in pixels for thumbnail previews in chooser
    previewMaxWidth = 800,        -- Maximum width of the preview window
    previewMaxHeight = 600,       -- Maximum height of the preview window
    previewMargin = 20,           -- Margin around the preview window
    previewGap = 10,             -- Gap between chooser and preview window
    previewBgColor = "#222",    -- Background color of preview window

    -- UI behavior
    pollInterval = 0.1,          -- Seconds between selection checks
  },

  -- Private state
  _preview_cache = {},          -- Cache of generated previews
  _current_chooser = nil,       -- Current chooser instance
  _last_selected = nil,         -- Last selected item
  _selection_timer = nil,       -- Timer for checking selection changes
  _preview_window = nil,        -- Preview window instance
  _pending_tasks = {},          -- Track running qlmanage tasks
}

-- Find the trash command (pure function)
local function findTrashCommand(preferred_command)
  -- First try user's preferred command if specified
  if preferred_command then
    if hs.fs.attributes(preferred_command, 'mode') == 'file' then
      return preferred_command
    end
    -- If preferred command is specified but doesn't exist, log it
    logger.w(string.format("Specified trash command '%s' not found", preferred_command))
  end

  -- Common locations to check
  local possible_paths = {
    "/opt/homebrew/bin/trash",
    "/usr/local/bin/trash",
    "/usr/bin/trash"
  }

  -- Check explicit paths
  for _, path in ipairs(possible_paths) do
    if hs.fs.attributes(path, 'mode') == 'file' then
      if preferred_command then
        logger.i(string.format("Using alternative trash command found at '%s'", path))
      end
      return path
    end
  end

  -- Try PATH
  local which_result = io.popen("which trash 2>/dev/null"):read("*a"):gsub("%s+$", "")
  if which_result ~= "" and hs.fs.attributes(which_result, 'mode') == 'file' then
    if preferred_command then
      logger.i(string.format("Using alternative trash command found at '%s'", which_result))
    end
    return which_result
  end

  -- No working trash command found
  if preferred_command then
    logger.e(string.format("Neither specified trash command '%s' nor any alternatives found", preferred_command))
  else
    logger.e("Could not find 'trash' command. Please install it (e.g., `brew install trash` or via your package manager)")
  end
  return nil
end

-- Initialize with found trash command
local trashCommand = findTrashCommand(M.config.trashCommand)
if not trashCommand then
  return nil
end

-- Private functions for file operations
local function fileExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'file'
end

local function ensurePreviewCacheDir()
  if not fileExists(M.config.previewCacheDir) then
    os.execute("mkdir -p " .. M.config.previewCacheDir)
  end
end

local function cleanupPreviewCache()
  -- Terminate any pending preview generation tasks
  for _, task in pairs(M._pending_tasks) do
    task:terminate()
  end
  M._pending_tasks = {}

  os.execute("rm -rf " .. M.config.previewCacheDir .. "*")
  M._preview_cache = {}
  if M._selection_timer then
    M._selection_timer:stop()
    M._selection_timer = nil
  end
  if M._preview_window then
    M._preview_window:delete()
    M._preview_window = nil
  end
end

local function getPreviewPath(file_path, is_fallback)
  local file_name = file_path:match(".*/(.+)$")
  if is_fallback then
    return M.config.previewCacheDir .. file_name .. ".fallback.png"
  else
    return M.config.previewCacheDir .. file_name .. ".png"
  end
end

local function getCachedPreview(file_path)
  local ql_path = getPreviewPath(file_path, false)
  if fileExists(ql_path) then
    return hs.image.imageFromPath(ql_path)
  end
  return nil
end

local function filePath(choice_text)
  local file_path = M.config.downloadsDirectory .. choice_text
  if fileExists(file_path) then
    return file_path
  else
    error("Erm... I can't find '".. file_path .."', which is rather perplexing! 🤔")
  end
end

-- Preview window management
local function positionPreviewWindow()
  if not M._preview_window then return end

  -- Find the chooser window
  local chooserWindow = nil
  for _, win in ipairs(hs.window.allWindows()) do
    if win:application():name() == "Hammerspoon" and win:title() == "Chooser" then
      chooserWindow = win
      break
    end
  end

  if chooserWindow then
    local frame = chooserWindow:frame()
    local screen = chooserWindow:screen():frame()

    -- Calculate available space to the right of the chooser
    local available_width = screen.x + screen.w - (frame.x + frame.w + M.config.previewGap)
    local available_height = screen.h - frame.y

    -- Scale preview to fit available space while maintaining aspect ratio
    local preview_width = math.min(M.config.previewMaxWidth, available_width - M.config.previewMargin)
    local preview_height = math.min(M.config.previewMaxHeight, available_height - M.config.previewMargin)

    -- Ensure preview doesn't go off screen
    local preview_x = math.min(frame.x + frame.w + M.config.previewGap,
                             screen.x + screen.w - preview_width - M.config.previewGap)

    M._preview_window:frame({
      x = preview_x,
      y = frame.y,
      w = preview_width,
      h = preview_height
    })
  end
end

local function showPreview(file_path, use_fallback)
  logger.i("Showing preview for: " .. file_path)

  -- Create or get preview window
  if not M._preview_window then
    logger.i("Creating new preview window")
    M._preview_window = hs.webview.new({x = 0, y = 0, w = M.config.previewMaxWidth, h = M.config.previewMaxHeight}, {
      developerExtrasEnabled = false,
      suppressesIncrementalRendering = false
    })
    M._preview_window:windowStyle("utility")
    M._preview_window:level(hs.drawing.windowLevels.floating)
    M._preview_window:allowTextEntry(false)
    M._preview_window:behavior(hs.drawing.windowBehaviors.canJoinAllSpaces +
                             hs.drawing.windowBehaviors.stationary)
  end

  -- Determine which preview to show
  local preview_path
  if use_fallback then
    preview_path = getPreviewPath(file_path, true)
    -- Generate fallback icon if it doesn't exist
    if not fileExists(preview_path) then
      local icon = hs.image.iconForFile(file_path)
      if icon then
        icon:saveToFile(preview_path)
      end
    end
  else
    preview_path = getPreviewPath(file_path, false)
  end

  if fileExists(preview_path) then
    local preview_url = "file://" .. preview_path:gsub("^~", os.getenv("HOME"))

    -- Create HTML file
    local html = string.format([[
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          body { margin: 0; padding: 0; background: %s; height: 100vh; display: flex; justify-content: center; align-items: center; }
          img { max-width: 100%%; max-height: 100%%; object-fit: contain; }
        </style>
      </head>
      <body>
        <img src="%s" alt="Preview">
      </body>
      </html>
    ]], M.config.previewBgColor, preview_url)

    local html_path = M.config.previewCacheDir .. "preview.html"
    local f = io.open(html_path, "w")
    f:write(html)
    f:close()

    local html_url = "file://" .. html_path
    M._preview_window:url(html_url)

    if not M._preview_window:isVisible() then
      M._preview_window:show()
      M._current_chooser:show()  -- Ensure chooser stays focused
    end

    positionPreviewWindow()
  end
end

local function generatePreviewAsync(file_path)
  ensurePreviewCacheDir()

  -- Show fallback immediately
  showPreview(file_path, true)

  -- Try to generate QL preview
  local preview_path = getPreviewPath(file_path, false)

  local task = hs.task.new("/usr/bin/qlmanage",
    function(exitCode, stdOut, stdErr)
      -- Remove task from pending list when it completes
      M._pending_tasks[file_path] = nil

      if exitCode == 0 and M._current_chooser and fileExists(preview_path) then
        local currentRow = M._current_chooser:selectedRow()
        M._current_chooser:refreshChoicesCallback()
        M._current_chooser:selectedRow(currentRow)
        showPreview(file_path, false)  -- Show QL preview
      else
        logger.i("Using fallback preview (QL preview not available)")
      end
    end,
    {"-t", "-s", M.config.previewSize, "-o", M.config.previewCacheDir, file_path})

  -- Track the task
  M._pending_tasks[file_path] = task
  task:start()
end

-- Chooser callbacks
function M._chooserCallback(choice)
  if choice == nil then
    cleanupPreviewCache()
    return nil
  else
    local file_path = filePath(choice.text)
    os.execute(trashCommand .." '".. file_path .."'")

    local log_message = "'".. file_path .."' moved to Trash"
    local logfile = io.open(M.config.logFile, 'a')
    logfile:write(log_message)
    logfile:close()

    logger.i(log_message)
    hs.notify.new(nil, {
      title = "Download trashed",
      subTitle = log_message,
      informativeText = choice.subText,
      setIdImage = hs.image.imageFromName(hs.image.systemImageNames.TrashFull)
    }):send()

    cleanupPreviewCache()
  end
end

function M._chooserFileList()
  local ret = {}
  local pipe = io.popen('/bin/ls -UltpTh '.. M.config.downloadsDirectory ..' | egrep -v "^total|/$"')
  for line in pipe:lines() do
    local size, creation_date, file_name =
      line:match("^[-bclsp][-rwSsxTt]+[ @]+%d+ +%w+ +%w+ +([%d.]+%w) +(%w+ +%d+ +[%d:]+ +%d+) +(.+)")
    if size and creation_date and file_name then
      local text = file_name
      local subText = creation_date .. ", " .. size
      local file_path = M.config.downloadsDirectory .. file_name
      -- Use QL preview if available, otherwise use icon
      local image = getCachedPreview(file_path) or hs.image.iconForFile(file_path)
      table.insert(ret, { text = text, subText = subText, image = image })
    end
  end
  pipe:close()
  return ret
end

function M._rightClickCallback(choice_row)
  if choice_row == 0 then return nil end

  local rows = M._chooserFileList()
  local choice = rows[choice_row]
  local file_path = filePath(choice.text)
  hs.task.new("/usr/bin/qlmanage", nil, {"-p", file_path}):start()
end

-- Public interface
function M.trashRecentDownload()
  local chooser = hs.chooser.new(M._chooserCallback)
  M._current_chooser = chooser
  chooser:choices(M._chooserFileList)
  chooser:rightClickCallback(M._rightClickCallback)

  -- Track selection changes
  M._last_selected = nil
  M._selection_timer = hs.timer.new(M.config.pollInterval, function()
    local current = chooser:selectedRowContents()
    if current and current.text ~= M._last_selected then
      M._last_selected = current.text
      local file_path = M.config.downloadsDirectory .. current.text
      if not getCachedPreview(file_path) then
        generatePreviewAsync(file_path)
      else
        showPreview(file_path)
      end
    end
  end):start()

  chooser:show()
end

return M

