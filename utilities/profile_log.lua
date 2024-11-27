local pp = {
    log = nil,
    startTime = nil,
    filePath = hs.fs.pathToAbsolute("~/Downloads/log.log") or os.getenv("HOME") .. "/Downloads/log.log"
}

-- Start profiling
function pp:start()
    self.log = {}
    self.startTime = hs.timer.secondsSinceEpoch()
    table.insert(self.log, {"System Time", "Elapsed Time", "Message"}) -- CSV headers
end

-- Log a message with a timestamp (silent noop if not started)
function pp:logMessage(message)
    if not self.startTime or not self.log then
        return -- Silent noop
    end
    local now = hs.timer.secondsSinceEpoch()
    local elapsed = now - self.startTime
    table.insert(self.log, {
        os.date("%Y-%m-%d %H:%M:%S", math.floor(now)),
        string.format("%.6f", elapsed),
        message
    })
end

-- Alias for easy use
pp.__call = function(self, message)
    self:logMessage(message)
end

-- Write log to file and stop profiling (silent noop if not started)
function pp:stop()
    if not self.startTime or not self.log then
        return -- Silent noop
    end
    local file = io.open(self.filePath, "w")
    if not file then
        error("Unable to open log file at " .. self.filePath)
    end
    for _, line in ipairs(self.log) do
        file:write(table.concat(line, ",") .. "\n")
    end
    file:close()
    self.log = nil
    self.startTime = nil
end

return setmetatable(pp, pp)