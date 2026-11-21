-- PlayAsSlender Native GameInstanceLoadingScreen & LevelInfo Override (Nano Banana Art + Russian Texts)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local LoadingScreenMgr = {}

local State = {
    Textures       = {}, -- key ("forest"|"house"|"sketch") -> UTexture2D
    VanillaGI      = nil,
    VanillaLI      = {}, -- fullName -> snapshot table
    AppliedMod     = false,
    LastAppliedKey = nil,
}

local function SafeReadText(ft)
    local out = nil
    local ok = pcall(function()
        local ktl = Bridge.GetClass("/Script/Engine.Default__KismetTextLibrary")
        if Logger.IsValidObj(ktl) and ft ~= nil then
            local fs = ktl:Conv_TextToString(ft)
            if type(fs) == "userdata" and fs.ToString then
                out = tostring(fs:ToString() or "")
            elseif fs ~= nil then
                out = tostring(fs)
            end
        end
    end)
    if ok and type(out) == "string" then
        return out
    end
    return ""
end

local function ExtractAssetPath(obj)
    if not Logger.IsValidObj(obj) then return nil end
    local fn = Logger.SafeFullName(obj)
    if fn == "" or string.find(fn, "/Engine/Transient", 1, true) then
        return nil
    end
    local path = fn:match("^[^%s]+%s+(.+)$") or fn
    if path == "" or string.find(path, "/Engine/Transient", 1, true) then
        return nil
    end
    return path
end

local function SetBrushTexture(brush, tex, w, h)
    if not brush or not Logger.IsValidObj(tex) then return false end
    local ok = pcall(function()
        brush.ResourceObject = tex
        pcall(function()
            brush.ImageSize = { X = w or 1920.0, Y = h or 1080.0 }
        end)
        pcall(function()
            brush.DrawAs = 3 -- ESlateBrushDrawType::Image
        end)
        pcall(function()
            brush.Tiling = 0 -- ESlateBrushTileType::NoTile
        end)
    end)
    return ok
end

local function GetGameInstance(world)
    local gi = nil
    if Logger.IsValidObj(world) then
        pcall(function()
            local gs = Bridge.GetGameplayStatics()
            if Logger.IsValidObj(gs) then
                gi = gs:GetGameInstance(world)
            end
        end)
    end
    if not Logger.IsValidObj(gi) then
        gi = (FindAllOf("BP_ProjectXGameInstance_C") or {})[1]
    end
    if not Logger.IsValidObj(gi) then
        gi = (FindAllOf("GameInstance") or {})[1]
    end
    return gi
end

function LoadingScreenMgr.EnsureTextures(world)
    local krl = Bridge.GetClass("/Script/Engine.Default__KismetRenderingLibrary")
    if not Logger.IsValidObj(krl) then
        Logger.Warn("LoadingScreenMgr: KismetRenderingLibrary unavailable")
        return false, false
    end
    local loadedCount = 0
    local anyNew = false
    for key, imgPath in pairs(Config.LOADING_IMAGES) do
        local cur = State.Textures[key]
        if not Logger.IsValidObj(cur) then
            local ok, tex = pcall(function()
                return krl:ImportFileAsTexture2D(world, imgPath)
            end)
            if ok and Logger.IsValidObj(tex) then
                State.Textures[key] = tex
                loadedCount = loadedCount + 1
                anyNew = true
                Logger.Info("LoadingScreenMgr: Imported texture [" .. tostring(key) .. "] from " .. tostring(imgPath))
            else
                Logger.Warn("LoadingScreenMgr: Failed importing texture [" .. tostring(key) .. "] from " .. tostring(imgPath))
            end
        else
            loadedCount = loadedCount + 1
        end
    end
    return loadedCount > 0, anyNew
end

function LoadingScreenMgr.GetTextures()
    return State.Textures
end

local function IsNonGameplayLevelInfo(li)
    local fn = Logger.SafeFullName(li)
    local act = ""
    local pid = ""
    pcall(function() act = tostring(li.ActivityName or "") end)
    pcall(function() pid = tostring(li.PresenceId or "") end)
    if string.find(fn, "LI_MainMenu", 1, true)
        or string.find(fn, "LI_Level99Menu", 1, true)
        or string.find(fn, "LI_WelcomeScreen", 1, true)
        or pid == "mainmenu"
        or pid == "idle"
    then
        return true
    end
    return false
end

local LEVELINFO_TO_TOKEN = {
    LI_Level01 = "Level01_Prologue",
    LI_Level02 = "Level02_TheEightPages",
    LI_Level03 = "Level03_IntoTheAbyss",
    LI_Level04 = "Level04_Flashback",
    LI_Level05 = "Level05_TheArrival",
    LI_Level06 = "Level06_Escape",
    LI_Level07 = "Level07_Memories",
    LI_Level08 = "Level08_Homestead",
    LI_Level09 = "Level09_Genesis",
    LI_Level10 = "Level10",
    LI_Level99 = "Level99_Haunted",
}

local function ResolveChapterForLevelInfo(li)
    local fn = Logger.SafeFullName(li)
    for prefix, tok in pairs(LEVELINFO_TO_TOKEN) do
        if string.find(fn, prefix, 1, true) then
            local cfg = Config.FindChapterByToken(tok)
            if cfg then return cfg end
        end
    end
    local act = ""
    pcall(function() act = tostring(li.ActivityName or "") end)
    if act ~= "" then
        for _, ch in ipairs(Config.CHAPTERS) do
            if string.find(ch.token, act, 1, true) or string.find(ch.title:gsub("%s+", ""), act, 1, true) then
                return ch
            end
        end
    end
    return nil
end

local function SnapshotVanilla(gi)
    if State.VanillaGI then return end
    local snapGI = {
        bgPath  = nil,
        bgW     = 4.0,
        bgH     = 4.0,
        bgDraw  = 3,
        genBgs  = {},
        genDesc = {},
        defName = SafeReadText(gi.DefaultLevelName),
        defAuth = SafeReadText(gi.DefaultAuthorName),
        defDesc = SafeReadText(gi.DefaultDescription),
        defMapD = SafeReadText(gi.DefaultMapDescription),
        defSize = SafeReadText(gi.DefaultLevelSize),
    }
    pcall(function()
        local br = gi.LoadingScreenBackground
        snapGI.bgPath = ExtractAssetPath(br.ResourceObject)
        snapGI.bgW    = (br.ImageSize and br.ImageSize.X) or 4.0
        snapGI.bgH    = (br.ImageSize and br.ImageSize.Y) or 4.0
        snapGI.bgDraw = br.DrawAs or 3
    end)
    pcall(function()
        local arr = gi.GenericLoadingScreenBackgrounds
        local n = arr and #arr or 0
        snapGI.genBgElemType = "empty"
        for i = 1, n do
            local b = arr[i]
            if Logger.IsValidObj(b) then
                snapGI.genBgElemType = "UObject:" .. Logger.SafeName(b:GetClass())
                snapGI.genBgs[i] = { isObj = true, path = ExtractAssetPath(b) }
            else
                local rec = { isObj = false, path = nil, w = 1920.0, h = 1080.0, draw = 3 }
                local okB = pcall(function()
                    rec.path = ExtractAssetPath(b.ResourceObject)
                    rec.w    = (b.ImageSize and b.ImageSize.X) or 1920.0
                    rec.h    = (b.ImageSize and b.ImageSize.Y) or 1080.0
                    rec.draw = b.DrawAs or 3
                end)
                snapGI.genBgElemType = okB and "SlateBrush" or "unknown"
                snapGI.genBgs[i] = rec
            end
        end
    end)
    pcall(function()
        local arr = gi.GenericLevelDescriptions
        local n = arr and #arr or 0
        for i = 1, n do
            snapGI.genDesc[i] = SafeReadText(arr[i])
        end
    end)
    State.VanillaGI = snapGI

    pcall(function()
        local list = gi.LevelInfoList
        local n = list and #list or 0
        for i = 1, n do
            local li = list[i]
            if Logger.IsValidObj(li) then
                local key = Logger.SafeFullName(li)
                if key ~= "" and not State.VanillaLI[key] then
                    local rec = {
                        bDisplayLevelInfo  = false,
                        bRandomBg          = true,
                        bRandomDesc        = true,
                        texPath            = nil,
                        bgPath             = nil,
                        bgW                = 32.0,
                        bgH                = 32.0,
                        bgDraw             = 3,
                        mapName            = SafeReadText(li.MapName),
                        mapSize            = SafeReadText(li.MapSize),
                        authorName         = SafeReadText(li.AuthorName),
                        descText           = SafeReadText(li.DescriptionText),
                        mapDesc            = SafeReadText(li.MapDescription),
                    }
                    pcall(function() rec.bDisplayLevelInfo = (li.bDisplayLevelInfoOnLoadingScreen == true) end)
                    pcall(function() rec.bRandomBg = (li.bUseRandomizedLoadingScreenBackground == true) end)
                    pcall(function() rec.bRandomDesc = (li.bUseRandomizedDescription == true) end)
                    pcall(function() rec.texPath = ExtractAssetPath(li.LoadingScreenTexture) end)
                    pcall(function()
                        local br = li.LoadingScreenBackground
                        rec.bgPath = ExtractAssetPath(br.ResourceObject)
                        rec.bgW    = (br.ImageSize and br.ImageSize.X) or 32.0
                        rec.bgH    = (br.ImageSize and br.ImageSize.Y) or 32.0
                        rec.bgDraw = br.DrawAs or 3
                    end)
                    State.VanillaLI[key] = rec
                end
            end
        end
    end)
end

function LoadingScreenMgr.ApplyModLoadingScreens(world, mapCfgOrKey)
    local gi = GetGameInstance(world)
    if not Logger.IsValidObj(gi) then
        Logger.Warn("LoadingScreenMgr.ApplyModLoadingScreens: GameInstance not found")
        return false
    end

    local _, anyNew = LoadingScreenMgr.EnsureTextures(world)
    if anyNew then
        State.AppliedLI = false
    end
    SnapshotVanilla(gi)

    local mapCfg = nil
    if type(mapCfgOrKey) == "table" then
        mapCfg = mapCfgOrKey
    elseif type(mapCfgOrKey) == "string" then
        mapCfg = Config.FindChapterByToken(mapCfgOrKey)
    end

    local prefKey = (mapCfg and mapCfg.loadingKey) or "sketch"
    local prefTex = State.Textures[prefKey] or State.Textures.forest or State.Textures.house or State.Textures.sketch
    if not Logger.IsValidObj(prefTex) then
        Logger.Warn("LoadingScreenMgr: No Nano Banana loading texture available!")
        return false
    end

    local titleStr = (mapCfg and mapCfg.loadingTitle) or Config.LOADING_SCREENS.DEFAULT_TITLE
    local descStr  = (mapCfg and mapCfg.loadingDesc)  or Config.LOADING_SCREENS.DEFAULT_DESC

    pcall(function() gi:UpdateUseLoadingScreen(true) end)
    pcall(function() SetBrushTexture(gi.LoadingScreenBackground, prefTex, 1920.0, 1080.0) end)

    -- Keep all 3 custom artworks pinned inside GenericLoadingScreenBackgrounds
    local orderedTex = {
        prefTex,
        State.Textures.forest or prefTex,
        State.Textures.house  or prefTex,
        State.Textures.sketch or prefTex,
    }
    local genKindLogged = false
    pcall(function()
        local arr = gi.GenericLoadingScreenBackgrounds
        local n = arr and #arr or 0
        for i = 1, n do
            local pick = orderedTex[((i - 1) % #orderedTex) + 1]
            local elem = arr[i]
            if Logger.IsValidObj(elem) then
                if not genKindLogged then
                    genKindLogged = true
                    Logger.Info("LoadingScreenMgr: GenericLoadingScreenBackgrounds elemType=UObject:" .. Logger.SafeName(elem:GetClass()))
                end
                pcall(function() arr[i] = pick end)
            else
                if not genKindLogged then
                    genKindLogged = true
                    Logger.Info("LoadingScreenMgr: GenericLoadingScreenBackgrounds elemType=" .. tostring(type(elem)))
                end
                local okBr = SetBrushTexture(elem, pick, 1920.0, 1080.0)
                if not okBr then
                    pcall(function() arr[i] = pick end)
                end
            end
        end
    end)

    local subStr = Config.LOADING_SCREENS.DEFAULT_SUBTITLE or "ЦЕЛЬ: ВЫСЛЕДИТЬ И СЛОМИТЬ ВЫЖИВШЕГО"
    pcall(function() gi.DefaultLevelName = FText(titleStr) end)
    pcall(function() gi.DefaultAuthorName = FText(Config.LOADING_SCREENS.DEFAULT_MODE_TAG) end)
    pcall(function() gi.DefaultLevelSize = FText(Config.LOADING_SCREENS.DEFAULT_SIZE_TAG) end)
    pcall(function() gi.DefaultDescription = FText(subStr) end)
    pcall(function() gi.DefaultMapDescription = FText(descStr) end)

    pcall(function()
        local arr = gi.GenericLevelDescriptions
        local n = arr and #arr or 0
        local tips = Config.LOADING_SCREENS.GENERIC_TIPS
        for i = 1, n do
            arr[i] = FText(tips[((i - 1) % #tips) + 1])
        end
    end)

    local liUpdated = 0
    local sampleLogged = false
    if not State.AppliedLI then
        pcall(function()
            local list = gi.LevelInfoList
            local n = list and #list or 0
            for i = 1, n do
                local li = list[i]
                if Logger.IsValidObj(li) and not IsNonGameplayLevelInfo(li) then
                    local ch = ResolveChapterForLevelInfo(li)
                    local liTex = (ch and State.Textures[ch.loadingKey]) or prefTex
                    local liTitle = (ch and ch.loadingTitle) or titleStr
                    local liDesc  = (ch and ch.loadingDesc)  or descStr

                    pcall(function() li.bDisplayLevelInfoOnLoadingScreen = true end)
                    pcall(function() li.bUseRandomizedLoadingScreenBackground = false end)
                    pcall(function() li.bUseRandomizedDescription = false end)
                    pcall(function() li.LoadingScreenTexture = liTex end)
                    pcall(function() SetBrushTexture(li.LoadingScreenBackground, liTex, 1920.0, 1080.0) end)
                    pcall(function() li.MapName = FText(liTitle) end)
                    pcall(function() li.AuthorName = FText(Config.LOADING_SCREENS.DEFAULT_MODE_TAG) end)
                    pcall(function() li.MapSize = FText(Config.LOADING_SCREENS.DEFAULT_SIZE_TAG) end)
                    pcall(function() li.DescriptionText = FText(subStr) end)
                    pcall(function() li.MapDescription = FText(liDesc) end)
                    if (not sampleLogged) and ((not mapCfg) or (ch and ch.token == mapCfg.token)) then
                        sampleLogged = true
                        Logger.Info(string.format(
                            "LoadingScreenMgr: Sample LI=%s bDisplay=%s Tex=%s MapName='%s'",
                            Logger.SafeName(li),
                            tostring(li.bDisplayLevelInfoOnLoadingScreen),
                            Logger.SafeName(li.LoadingScreenTexture),
                            SafeReadText(li.MapName)))
                    end
                    liUpdated = liUpdated + 1
                end
            end
            State.AppliedLI = true
        end)
    end

    State.AppliedMod = true
    State.LastAppliedKey = prefKey
    Logger.Info(string.format("LoadingScreenMgr: Applied Nano Banana loading screens (pref=%s, LevelInfoUpdated=%d)", prefKey, liUpdated))
    return true
end

function LoadingScreenMgr.RestoreVanilla(world)
    if not State.AppliedMod or not State.VanillaGI then return false end
    local gi = GetGameInstance(world)
    if not Logger.IsValidObj(gi) then return false end

    local function ResolveAssetOrNil(path)
        if not path or path == "" then return nil end
        local obj = Bridge.LoadOrFindAsset(path)
        if Logger.IsValidObj(obj) then return obj end
        return nil
    end

    local vgi = State.VanillaGI
    pcall(function()
        local br = gi.LoadingScreenBackground
        local ro = ResolveAssetOrNil(vgi.bgPath)
        br.ResourceObject = ro
        pcall(function() br.ImageSize = { X = vgi.bgW, Y = vgi.bgH } end)
        pcall(function() br.DrawAs = vgi.bgDraw end)
    end)
    pcall(function()
        local arr = gi.GenericLoadingScreenBackgrounds
        local n = arr and #arr or 0
        for i = 1, n do
            local rec = vgi.genBgs[i]
            if rec then
                local ro = ResolveAssetOrNil(rec.path)
                if rec.isObj then
                    if Logger.IsValidObj(ro) then
                        pcall(function() arr[i] = ro end)
                    end
                else
                    pcall(function()
                        arr[i].ResourceObject = ro
                        arr[i].ImageSize = { X = rec.w, Y = rec.h }
                        arr[i].DrawAs = rec.draw
                    end)
                end
            end
        end
    end)
    pcall(function()
        local arr = gi.GenericLevelDescriptions
        local n = arr and #arr or 0
        for i = 1, n do
            if vgi.genDesc[i] ~= nil then
                arr[i] = FText(vgi.genDesc[i])
            end
        end
    end)
    pcall(function() gi.DefaultLevelName = FText(vgi.defName or "") end)
    pcall(function() gi.DefaultAuthorName = FText(vgi.defAuth or "") end)
    pcall(function() gi.DefaultDescription = FText(vgi.defDesc or "") end)
    pcall(function() gi.DefaultMapDescription = FText(vgi.defMapD or "") end)
    pcall(function() gi.DefaultLevelSize = FText(vgi.defSize or "") end)

    pcall(function()
        local list = gi.LevelInfoList
        local n = list and #list or 0
        for i = 1, n do
            local li = list[i]
            if Logger.IsValidObj(li) then
                local rec = State.VanillaLI[Logger.SafeFullName(li)]
                if rec then
                    pcall(function() li.bDisplayLevelInfoOnLoadingScreen = rec.bDisplayLevelInfo end)
                    pcall(function() li.bUseRandomizedLoadingScreenBackground = rec.bRandomBg end)
                    pcall(function() li.bUseRandomizedDescription = rec.bRandomDesc end)
                    pcall(function() li.LoadingScreenTexture = ResolveAssetOrNil(rec.texPath) end)
                    pcall(function()
                        local br = li.LoadingScreenBackground
                        br.ResourceObject = ResolveAssetOrNil(rec.bgPath)
                        br.ImageSize = { X = rec.bgW, Y = rec.bgH }
                        br.DrawAs = rec.bgDraw
                    end)
                    pcall(function() li.MapName = FText(rec.mapName or "") end)
                    pcall(function() li.MapSize = FText(rec.mapSize or "") end)
                    pcall(function() li.AuthorName = FText(rec.authorName or "") end)
                    pcall(function() li.DescriptionText = FText(rec.descText or "") end)
                    pcall(function() li.MapDescription = FText(rec.mapDesc or "") end)
                end
            end
        end
    end)

    State.Textures       = {}
    State.AppliedMod     = false
    State.AppliedLI      = false
    State.LastAppliedKey = nil
    Logger.Info("LoadingScreenMgr: Restored vanilla loading screens (path-resolved)")
    return true
end

function LoadingScreenMgr.IsApplied()
    return State.AppliedMod
end

return LoadingScreenMgr
