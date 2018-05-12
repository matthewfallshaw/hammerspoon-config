-- Trash recent downloads
local logger = hs.logger.new("Trash Recent Downloads")
logger.i("Trash recent downloads")

DOWNLOADS_DIRECTORY = "~/Downloads/"
TRASH_COMMAND = "/usr/local/bin/trash"
LOG_FILE = "/tmp/trash-most-recent.log"

M = {}

function M.trashRecentDownload()
  local chooser = hs.chooser.new(M._ChooserCallback)
  chooser:choices(M._chooserFileList)
  chooser:show()
end


-- Private

function M._ChooserCallback(choice)
  if choice == nil then
    -- user dismissed dialog, do nothing
    return nil
  end

  local file_path = DOWNLOADS_DIRECTORY .. choice.text
  if M._fileExists(file_path) then
    hs.execute(TRASH_COMMAND .." '".. file_path .."'")
    local log_message = "'".. file_path .."' moved to Trash"

    local logfile = io.open(LOG_FILE, 'a')
    logfile:write(log_message)
    logfile:close()

    logger.i(logger, log_message)
  else
    logger.w("Erm… I can't find '".. file_path .."', which is strange.")
  end
end

function M._chooserFileList()
  local ret = {}
  local pipe = io.popen('/bin/ls -UltpTh '.. DOWNLOADS_DIRECTORY ..' | egrep -v "^total|/$"')
  for line in pipe:lines() do
    local size, creation_date, file_name = line:match("^[-bclsp][-rwSsxTt]+[ @]+%d+ +%w+ +%w+ +([%d.]+%w) +(%w+ +%d+ +[%d:]+ +%d+) +(.+)")
    if size and creation_date and file_name then
      local text = file_name
      local subText = creation_date .. ", " .. size
      local image = hs.image.iconForFile(DOWNLOADS_DIRECTORY .. file_name)
      table.insert(ret, { text = text, subText = subText, image = image })
    end
  end
  pipe:close()
  return ret
end

function M._fileExists(filepath)
  return hs.fs.attributes(filepath, 'mode') == 'file'
end

if not M._fileExists(TRASH_COMMAND) then
  loger.e(TRASH_COMMAND .." not found. Try `brew install trash`")
  return nil
end

return M
