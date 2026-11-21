-- PlayAsSlender Persistent Campaign Progression Manager
-- Saves unlock state next to UE4SS (PlayAsSlender_progress.ini) so installer syncs preserve progress.
local Config = require("config")
local Logger = require("logger")

local ProgressionMgr = {}

local DEFAULT_ORDER = {
    "Level01_Prologue",
    "Level02_TheEightPages",
    "Level03_IntoTheAbyss",
    "Level04_Flashback",
    "Level05_TheArrival",
    "Level06_Escape",
    "Level07_Memories",
    "Level08_Homestead",
    "Level09_Genesis",
}

local State = {
    FilePath    = nil,
    UnlockedMax = 1,
    Order       = {},
    Initialized = false,
}

local function ResolveProgressPath()
    if State.FilePath and State.FilePath ~= "" then
        return State.FilePath
    end
    local candidates = {
        "ue4ss\\PlayAsSlender_progress.ini",
        "PlayAsSlender_progress.ini",
    }
    for _, p in ipairs(candidates) do
        local f = io.open(p, "a+")
        if f then
            f:close()
            State.FilePath = p
            return p
        end
    end
    State.FilePath = "PlayAsSlender_progress.ini"
    return State.FilePath
end

local function CopyDefaultOrder()
    local out = {}
    for i, tok in ipairs(DEFAULT_ORDER) do
        out[i] = tok
    end
    return out
end

local function SplitComma(s)
    local out = {}
    for item in tostring(s or ""):gmatch("[^,]+") do
        local trim = item:gsub("^%s+", ""):gsub("%s+$", "")
        if trim ~= "" then
            table.insert(out, trim)
        end
    end
    return out
end

function ProgressionMgr.Save()
    local p = ResolveProgressPath()
    local f = io.open(p, "w+")
    if not f then
        Logger.Warn("ProgressionMgr: Could not write progress file: " .. tostring(p))
        return false
    end
    if #State.Order == 0 then
        State.Order = CopyDefaultOrder()
    end
    f:write(string.format("unlocked_max=%d\n", math.max(1, tonumber(State.UnlockedMax) or 1)))
    f:write("order=" .. table.concat(State.Order, ",") .. "\n")
    f:close()
    return true
end

function ProgressionMgr.Init()
    State.UnlockedMax = 1
    State.Order       = CopyDefaultOrder()

    local p = ResolveProgressPath()
    local f = io.open(p, "r")
    local hasFileData = false
    if f then
        local content = f:read("*a") or ""
        f:close()
        for line in content:gmatch("[^\r\n]+") do
            local clean = line:gsub("^%s+", ""):gsub("%s+$", "")
            local k, v = clean:match("^([%w_]+)%s*=%s*(.+)$")
            if k == "unlocked_max" then
                local n = math.floor(tonumber(v) or 1)
                State.UnlockedMax = math.max(1, math.min(9, n))
                hasFileData = true
            elseif k == "order" then
                local parsed = SplitComma(v)
                if #parsed == 9 then
                    State.Order = parsed
                end
            end
        end
    end

    if not hasFileData then
        ProgressionMgr.Save()
    end
    State.Initialized = true
    Logger.Info(string.format("ProgressionMgr ready: unlocked_max=%d file=%s", State.UnlockedMax, tostring(p)))
    return State.UnlockedMax
end

function ProgressionMgr.Reset(maxVal)
    local n = math.floor(tonumber(maxVal) or 1)
    State.UnlockedMax = math.max(1, math.min(9, n))
    if #State.Order == 0 then
        State.Order = CopyDefaultOrder()
    end
    ProgressionMgr.Save()
    Logger.Info("ProgressionMgr reset: unlocked_max=" .. tostring(State.UnlockedMax))
    return State.UnlockedMax
end

function ProgressionMgr.SyncCampaignOrder(tokens)
    if type(tokens) ~= "table" or #tokens ~= 9 then return false end
    local changed = (#State.Order ~= 9)
    if not changed then
        for i = 1, 9 do
            if State.Order[i] ~= tokens[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        local copy = {}
        for i = 1, 9 do copy[i] = tokens[i] end
        State.Order = copy
        ProgressionMgr.Save()
        Logger.Info("ProgressionMgr synced chapter order: " .. table.concat(State.Order, ", "))
    end
    return changed
end

function ProgressionMgr.GetUnlockedMax()
    if not State.Initialized then ProgressionMgr.Init() end
    return State.UnlockedMax
end

function ProgressionMgr.GetOrder()
    if not State.Initialized then ProgressionMgr.Init() end
    return State.Order
end

function ProgressionMgr.GetChapterIndex(token)
    if not State.Initialized then ProgressionMgr.Init() end
    local s = tostring(token or "")
    if s == "" then return nil end
    if s == "Level01_HouseAndYard" or s == "PROLOGUE_YARD" then
        s = "Level01_Prologue"
    end
    for idx, tok in ipairs(State.Order) do
        if tok == s or string.find(s, tok, 1, true) or string.find(tok, s, 1, true) then
            return idx
        end
    end
    return nil
end

function ProgressionMgr.IsIndexUnlocked(idx)
    if not State.Initialized then ProgressionMgr.Init() end
    if not idx or idx < 1 then return false end
    return idx <= State.UnlockedMax
end

function ProgressionMgr.IsChapterUnlocked(token)
    local idx = ProgressionMgr.GetChapterIndex(token)
    if not idx then
        -- Non-campaign / custom maps remain playable if entered explicitly
        return true
    end
    return ProgressionMgr.IsIndexUnlocked(idx)
end

function ProgressionMgr.GetNextChapter(mapCfg)
    if not mapCfg then return nil end
    local idx = ProgressionMgr.GetChapterIndex(mapCfg.token)
    if not idx or idx >= #State.Order then
        return nil
    end
    local nextTok = State.Order[idx + 1]
    return Config.FindChapterByToken(nextTok)
end

function ProgressionMgr.OnMatchEnded(mapCfg, resultStr)
    if not State.Initialized then ProgressionMgr.Init() end
    if not mapCfg then return false, nil end
    local idx = ProgressionMgr.GetChapterIndex(mapCfg.token)
    if resultStr == "SLENDER_WIN" then
        local newlyUnlocked = false
        if idx and idx >= State.UnlockedMax and idx < #State.Order then
            State.UnlockedMax = idx + 1
            ProgressionMgr.Save()
            newlyUnlocked = true
            Logger.Info(string.format("ProgressionMgr: VICTORY on [%d:%s] -> Unlocked [%d:%s] (unlocked_max=%d)",
                idx, tostring(mapCfg.token), idx + 1, tostring(State.Order[idx + 1]), State.UnlockedMax))
        else
            Logger.Info(string.format("ProgressionMgr: VICTORY on [%s:%s] (unlocked_max=%d)",
                tostring(idx or "?"), tostring(mapCfg.token), State.UnlockedMax))
        end
        return newlyUnlocked, ProgressionMgr.GetNextChapter(mapCfg)
    end
    Logger.Info(string.format("ProgressionMgr: Match ended [%s] on %s -> unlocked_max remains %d",
        tostring(resultStr), tostring(mapCfg.token), State.UnlockedMax))
    return false, nil
end

return ProgressionMgr
