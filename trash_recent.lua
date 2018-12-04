-- Trash recent downloads
local logger = hs.logger.new("Trash Recent Downloads")
logger.i("Trash recent downloads")

local const = {}
const.DOWNLOADS_DIRECTORY = "~/Downloads/"
const.TRASH_COMMAND = "/usr/local/bin/trash"
const.LOG_FILE = "/tmp/trash-most-recent.log"

local M = {}


-- Private

local function fileExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'file'
end

local function filePath(choice_text)
  local file_path = const.DOWNLOADS_DIRECTORY .. choice_text
  if fileExists(file_path) then
    return file_path
  else
    error("Erm… I can't find '".. file_path .."', which is strange.")
  end
end

function M._chooserCallback(choice)
  if choice == nil then
    -- user dismissed dialog, do nothing
    return nil
  else
    local file_path = filePath(choice.text)
    hs.execute(const.TRASH_COMMAND .." '".. file_path .."'")

    local log_message = "'".. file_path .."' moved to Trash"
    local logfile = io.open(const.LOG_FILE, 'a')
    logfile:write(log_message)
    logfile:close()

    logger.i(logger, log_message)
    hs.notify.new(nil, { title = "Download trashed", subTitle = log_message,
                         informativeText = choice.subText,
                         setIdImage = hs.image.imageFromName(hs.image.systemImageNames.TrashFull) }):send()
  end
end

function M._chooserFileList()
  local ret = {}
  local pipe = io.popen('/bin/ls -UltpTh '.. const.DOWNLOADS_DIRECTORY ..' | egrep -v "^total|/$"')
  for line in pipe:lines() do
    local size, creation_date, file_name =
      line:match("^[-bclsp][-rwSsxTt]+[ @]+%d+ +%w+ +%w+ +([%d.]+%w) +(%w+ +%d+ +[%d:]+ +%d+) +(.+)")
    if size and creation_date and file_name then
      local text = file_name
      local subText = creation_date .. ", " .. size
      local image = hs.image.iconForFile(const.DOWNLOADS_DIRECTORY .. file_name)
      table.insert(ret, { text = text, subText = subText, image = image })
    end
  end
  pipe:close()
  return ret
end

function M._rightClickCallback(choice_row)
  if choice_row == 0 then
    -- nothing to do, click didn't hit an option
    return nil
  else
    local rows = M._chooserFileList()
    local choice = rows[choice_row]
    local file_path = filePath(choice.text)
    hs.task.new("/usr/bin/qlmanage", nil, {"-p", file_path}):start()
  end
end


-- Public

function M.trashRecentDownload()
  local chooser = hs.chooser.new(M._chooserCallback)
  chooser:choices(M._chooserFileList)
  chooser:rightClickCallback(M._rightClickCallback)
  chooser:show()
end


if not fileExists(const.TRASH_COMMAND) then
  logger.e(const.TRASH_COMMAND .." not found. Try `brew install trash`")
  return nil
end

return M
