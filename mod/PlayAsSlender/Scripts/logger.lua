-- PlayAsSlender File Logger & Safe Call Utilities
local Logger = {}

local LogPath = "PlayAsSlender.log"

-- Determine writable log path next to UE4SS or fallback to temp
local function ResolveLogPath()
    local candidates = {
        "ue4ss\\PlayAsSlender.log",
        "PlayAsSlender.log",
    }
    for _, p in ipairs(candidates) do
        local f = io.open(p, "a+")
        if f then
            f:close()
            return p
        end
    end
    return "PlayAsSlender.log"
end

function Logger.Init()
    LogPath = ResolveLogPath()
    local f = io.open(LogPath, "w+")
    if f then
        f:write(string.format("=== PlayAsSlender Log Initialized (%s) ===\n", os.date("%Y-%m-%d %H:%M:%S")))
        f:close()
    end
end

function Logger.Write(level, msg)
    local line = string.format("[%s][%s] %s", os.date("%H:%M:%S"), tostring(level), tostring(msg))
    print("[PlayAsSlender] " .. line .. "\n")
    local f = io.open(LogPath, "a+")
    if f then
        f:write(line .. "\n")
        f:close()
    end
end

function Logger.Info(msg)  Logger.Write("INFO", msg) end
function Logger.Warn(msg)  Logger.Write("WARN", msg) end
function Logger.Error(msg) Logger.Write("ERROR", msg) end
function Logger.Test(msg)  Logger.Write("TEST", msg) end

function Logger.GetLogPath()
    return LogPath
end

function Logger.SafeCall(tag, fn, ...)
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then
        Logger.Error(string.format("%s failed: %s", tostring(tag), tostring(a)))
        return false, nil
    end
    return true, a, b, c, d
end

function Logger.IsValidObj(obj)
    if obj == nil then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res == true
end

function Logger.SafeName(obj)
    if not Logger.IsValidObj(obj) then return "<invalid>" end
    local ok, s = pcall(function() return obj:GetFName():ToString() end)
    return ok and tostring(s) or "<err>"
end

function Logger.SafeFullName(obj)
    if not Logger.IsValidObj(obj) then return "<invalid>" end
    local ok, s = pcall(function() return obj:GetFullName() end)
    return ok and tostring(s) or "<err>"
end

return Logger
