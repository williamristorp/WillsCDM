local addonName, addon = ...
addon = addon or {}

local Log = {}
Log.__index = Log

--- @enum Log.Level
Log.Level = {
    TRACE = 1,
    DEBUG = 2,
    INFO = 3,
    WARN = 4,
    ERROR = 5,
}

Log.enabled = true
Log.level = Log.Level.INFO
Log.prefix = nil
Log.enterCounts = {}

local OUTPUT = DEFAULT_CHAT_FRAME

local LEVEL_LABELS = {
    [Log.Level.TRACE] = "|cff888888TRACE|r",
    [Log.Level.DEBUG] = "|cff00ff00DEBUG|r",
    [Log.Level.INFO] = "|cff0000ffINFO|r",
    [Log.Level.WARN] = "|cffffff00WARN|r",
    [Log.Level.ERROR] = "|cffff0000ERROR|r",
}

function Log:ShouldLog(level)
    return self.enabled and level >= self.level
end

function Log:FormatMessage(level, ...)
    local label = LEVEL_LABELS[level]
    local prefix = self.prefix and string.format("[%s] ", self.prefix) or ""
    return string.format("%s [%s] %s", prefix, label, table.concat({ ... }, " "))
end

function Log:Log(level, ...)
    if self:ShouldLog(level) then
        local message = self:FormatMessage(level, ...)
        OUTPUT:AddMessage(message)
    end
end

function Log:Trace(...)
    self:Log(Log.Level.TRACE, ...)
end

function Log:Debug(...)
    self:Log(Log.Level.DEBUG, ...)
end

function Log:Info(...)
    self:Log(Log.Level.INFO, ...)
end

function Log:Warn(...)
    self:Log(Log.Level.WARN, ...)
end

function Log:Error(...)
    self:Log(Log.Level.ERROR, ...)
end

function Log:ShortenFilePath(path)
    return string.gsub(path, ".*WillsCDM%.lua]", "WillsCDM.lua")
end

--- This function is meant to be called at the beginning of a function to log when it's entered, along with the file and line number.
--- @param arg1 Log.Level|string? Optional log level or function name.
--- @param arg2 string? Optional function name if the first argument is a log level.
function Log:Enter(arg1, arg2)
    local level = Log.Level.TRACE
    local functionName = nil

    if type(arg1) == "number" then
        level = arg1
        functionName = arg2
    elseif type(arg1) == "string" then
        functionName = arg1
    end

    if not self:ShouldLog(level) then
        return
    end

    local info = debugstack(2, 1, 0)

    -- Trim "Interface/AddOns/WillsCDM/"
    info = string.gsub(info, "Interface/AddOns/WillsCDM/", "")

    -- Remove every after " in function"
    info = string.gsub(info, "in function.*", functionName or "")

    self.enterCounts[info] = (self.enterCounts[info] or 0) + 1
    local count = self.enterCounts[info]
    self:Log(level, string.format("Entering %s (count: %d)", info, count))
end

function Log:SetEnabled(enabled)
    self.enabled = enabled
end

function Log:SetLevel(level)
    self.level = level
end

function Log:SetPrefix(prefix)
    self.prefix = prefix
end

function Log:WithPrefix(prefix)
    local newLog = setmetatable({}, self)
    newLog.enabled = self.enabled
    newLog.level = self.level
    newLog.prefix = prefix
    return newLog
end

function Log:WithSubPrefix(subPrefix)
    local newPrefix = self.prefix and string.format("%s.%s", self.prefix, subPrefix) or subPrefix
    return self:WithPrefix(newPrefix)
end

function Log:GetEnterCounts()
    return self.enterCounts
end

addon.Log = Log
