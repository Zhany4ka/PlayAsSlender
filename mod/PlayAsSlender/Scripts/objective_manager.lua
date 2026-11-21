-- PlayAsSlender Multi-Map Objective Manager (Level01 Prologue House & Level02 Eight Pages, Strict Non-Omniscience + Target Blacklist)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local ObjectiveManager = {}

local State = {
    Initialized    = false,
    MapKey         = "EIGHT_PAGES",
    HasNavMesh     = true,
    Pages          = {}, -- { id, actor, name, pos, collected, discovered, lastSeenAt }
    CollectedCount = 0,
    TotalCount     = 8,
    Zones          = {}, -- { id, name, center, isLandmark, pts = { { pos, lookAt, visited, blockedUntil } }, fullySearched }
    PlayerState    = nil,
    GameMode       = nil,
}

function ObjectiveManager.Reset()
    State.Initialized    = false
    State.MapKey         = "EIGHT_PAGES"
    State.HasNavMesh     = true
    State.Pages          = {}
    State.CollectedCount = 0
    State.TotalCount     = 8
    State.Zones          = {}
    State.PlayerState    = nil
    State.GameMode       = nil
end

local function ShortZoneName(rawName)
    local s = tostring(rawName or "Zone")
    s = s:gsub("^BP_LandmarkLarge_", "")
    s = s:gsub("^BP_LandmarkSmall_", "")
    s = s:gsub("^BP_Landmark_", "")
    s = s:gsub("^BP_", "")
    s = s:gsub("_%d+$", "")
    return s
end

local function GroundZonePoint(world, pos, ignore)
    local gHit, gz, norm = Bridge.GroundTrace(world, pos.X, pos.Y, pos.Z + 220.0, pos.Z - 600.0, ignore)
    if gHit and norm and norm.Z >= 0.50 then
        return { X = pos.X, Y = pos.Y, Z = gz + 92.0 }
    end
    return { X = pos.X, Y = pos.Y, Z = pos.Z }
end

local function BuildPerimeterPoints(world, centerPos, radius)
    local pts = {}
    local angles = { 0.0, math.pi * 0.5, math.pi, math.pi * 1.5 }
    for _, ang in ipairs(angles) do
        local cand = {
            X = centerPos.X + math.cos(ang) * radius,
            Y = centerPos.Y + math.sin(ang) * radius,
            Z = centerPos.Z,
        }
        local okN, proj = Bridge.ProjectPointToNav(world, cand, { X = 320.0, Y = 320.0, Z = 650.0 })
        if okN and proj then
            local duplicate = false
            for _, ex in ipairs(pts) do
                if Bridge.Dist2D(ex.pos, proj) < 220.0 then
                    duplicate = true
                    break
                end
            end
            if not duplicate then
                table.insert(pts, { pos = proj, lookAt = centerPos, visited = false, visitedAt = 0.0, blockedUntil = 0.0 })
            end
        end
    end
    if #pts == 0 then
        local okC, projC = Bridge.ProjectPointToNav(world, centerPos, { X = 550.0, Y = 550.0, Z = 700.0 })
        if okC and projC then
            table.insert(pts, { pos = projC, lookAt = centerPos, visited = false, visitedAt = 0.0, blockedUntil = 0.0 })
        end
    end
    return pts
end

local function InitLevel02EightPages(world, survivor)
    local rawPages = FindAllOf("BP_PickUp_TheEightPages_C") or {}
    for idx, pg in ipairs(rawPages) do
        if Logger.IsValidObj(pg) then
            local loc = Bridge.GetActorLoc(pg)
            if loc then
                table.insert(State.Pages, {
                    id         = idx,
                    actor      = pg,
                    name       = Logger.SafeName(pg),
                    pos        = loc,
                    collected  = false,
                    discovered = false,
                    lastSeenAt = 0.0,
                })
            end
        end
    end
    State.TotalCount = math.max(1, #State.Pages)
    Logger.Info("ObjectiveManager [Level02] indexed pages: " .. tostring(#State.Pages))

    -- Open starting perimeter gates immediately so Human AI is never confined inside a starting fence
    if Logger.IsValidObj(State.GameMode) then
        pcall(function() State.GameMode:RemoveGateways() end)
    end

    local survLoc = Bridge.GetActorLoc(survivor)
    local minX, maxX = 1e9, -1e9
    local minY, maxY = 1e9, -1e9
    local landmarks = FindAllOf("LandmarkActor") or {}
    local zoneId = 0

    for _, lm in ipairs(landmarks) do
        if Logger.IsValidObj(lm) then
            local loc = Bridge.GetActorLoc(lm)
            if loc then
                local okNav, proj = Bridge.ProjectPointToNav(world, loc, { X = 650.0, Y = 650.0, Z = 850.0 })
                local reachable = false
                if okNav and proj and survLoc then
                    if Bridge.Dist2D(survLoc, proj) < 400.0 then
                        reachable = true
                    else
                        local path = Bridge.FindNavPathPoints(world, survLoc, proj, survivor)
                        reachable = (path ~= nil and #path >= 2)
                    end
                end
                if reachable and proj then
                    zoneId = zoneId + 1
                    local zName = ShortZoneName(Logger.SafeName(lm))
                    local rad = string.find(Logger.SafeName(lm), "Large", 1, true) and 620.0 or 440.0
                    local pts = BuildPerimeterPoints(world, proj, rad)
                    table.insert(State.Zones, {
                        id            = zoneId,
                        name          = zName,
                        center        = proj,
                        isLandmark    = true,
                        pts           = pts,
                        fullySearched = false,
                    })
                    minX = math.min(minX, proj.X)
                    maxX = math.max(maxX, proj.X)
                    minY = math.min(minY, proj.Y)
                    maxY = math.max(maxY, proj.Y)
                end
            end
        end
    end

    -- Forest clearings inside playable bounds
    if #State.Zones >= 2 then
        local spanX = math.max(4000.0, maxX - minX)
        local spanY = math.max(4000.0, maxY - minY)
        local gridPts = {
            { X = minX + spanX * 0.25, Y = minY + spanY * 0.25, Z = survLoc and survLoc.Z or 9500.0 },
            { X = minX + spanX * 0.75, Y = minY + spanY * 0.25, Z = survLoc and survLoc.Z or 9500.0 },
            { X = minX + spanX * 0.50, Y = minY + spanY * 0.50, Z = survLoc and survLoc.Z or 9500.0 },
            { X = minX + spanX * 0.25, Y = minY + spanY * 0.75, Z = survLoc and survLoc.Z or 9500.0 },
            { X = minX + spanX * 0.75, Y = minY + spanY * 0.75, Z = survLoc and survLoc.Z or 9500.0 },
        }
        for cIdx, gCand in ipairs(gridPts) do
            local okN, proj = Bridge.ProjectPointToNav(world, gCand, { X = 800.0, Y = 800.0, Z = 1000.0 })
            if okN and proj then
                local nearLandmark = false
                for _, z in ipairs(State.Zones) do
                    if Bridge.Dist2D(z.center, proj) < 1600.0 then
                        nearLandmark = true
                        break
                    end
                end
                if not nearLandmark then
                    local path = survLoc and Bridge.FindNavPathPoints(world, survLoc, proj, survivor)
                    if path and #path >= 2 then
                        zoneId = zoneId + 1
                        table.insert(State.Zones, {
                            id            = zoneId,
                            name          = "ForestSector_" .. tostring(cIdx),
                            center        = proj,
                            isLandmark    = false,
                            pts           = { { pos = proj, lookAt = proj, visited = false, visitedAt = 0.0, blockedUntil = 0.0 } },
                            fullySearched = false,
                        })
                    end
                end
            end
        end
    end
end

local function UnlockAndOpenMainDoors(survivor)
    for _, door in ipairs(FindAllOf("BP_DoorBase_C") or {}) do
        if Logger.IsValidObj(door) then
            local dn = Logger.SafeName(door)
            if string.find(dn, "BP_Door_Main", 1, true) then
                pcall(function() door:SetState(survivor, 1, false) end)
                pcall(function() door:RequestStateChange(survivor, 1) end)
                pcall(function()
                    if Logger.IsValidObj(door.DoorCollisionAndNavigationBlocker) then
                        door.DoorCollisionAndNavigationBlocker:SetCollisionEnabled(0)
                    end
                end)
            end
        end
    end
end

local function InitLevel01Prologue(world, survivor)
    local ignore = Logger.IsValidObj(survivor) and { survivor } or {}
    local houseCenter = { X = 44200.0, Y = 60000.0, Z = 9100.0 }

    -- Index real 1F House & Yard objectives (excluding 2F, uphill garage, far off-map items, and windows)
    local allItems = FindAllOf("Item") or {}
    local collectCands = {}
    local clueCands = {}
    local cluePatterns = {
        "BP_Interact_AnsweringMachine",
        "BP_Interact_RadioMusic",
        "BP_Interact_PlayablePiano",
        "BP_Interact_CordlessPhone",
    }
    for _, item in ipairs(allItems) do
        if Logger.IsValidObj(item) then
            local cname = Logger.SafeName(item:GetClass())
            local loc = Bridge.GetActorLoc(item)
            if loc and loc.Z >= 8850.0 and loc.Z <= 9380.0 and Bridge.Dist2D(houseCenter, loc) <= 12000.0 then
                local distHC = Bridge.Dist2D(houseCenter, loc)
                if string.find(cname, "BP_Collect_", 1, true) ~= nil then
                    table.insert(collectCands, { actor = item, name = Logger.SafeName(item), pos = loc, d = distHC })
                else
                    for _, pat in ipairs(cluePatterns) do
                        if string.find(cname, pat, 1, true) ~= nil then
                            table.insert(clueCands, { actor = item, name = Logger.SafeName(item), pos = loc, d = distHC })
                            break
                        end
                    end
                end
            end
        end
    end
    table.sort(collectCands, function(a, b) return a.d < b.d end)
    table.sort(clueCands, function(a, b) return a.d < b.d end)

    local combined = {}
    for _, c in ipairs(collectCands) do table.insert(combined, c) end
    for _, c in ipairs(clueCands) do table.insert(combined, c) end

    for i, c in ipairs(combined) do
        table.insert(State.Pages, {
            id           = i,
            actor        = c.actor,
            name         = c.name,
            pos          = c.pos,
            approachPos  = nil,
            collected    = false,
            discovered   = false,
            lastSeenAt   = 0.0,
            blockedUntil = 0.0,
        })
    end
    State.TotalCount = math.max(1, #State.Pages)
    Logger.Info(string.format("ObjectiveManager [Level01_Prologue] indexed %d 1F candidate house objectives.", #State.Pages))

    -- Ensure House main front & back doors are unlocked, open, and clear of navigation blockers
    UnlockAndOpenMainDoors(survivor)

    -- Curated grounded exploration zones across Front Driveway, Porch, House 1F Rooms, Back Yard & Side Garden
    local rawZones = {
        {
            name = "FrontDriveway",
            isLandmark = true,
            pts = {
                { X = 42000.0, Y = 51750.0, Z = 9280.0 }, -- MissingPoster zone
                { X = 42650.0, Y = 54700.0, Z = 9180.0 },
                { X = 43600.0, Y = 56900.0, Z = 9080.0 },
            },
        },
        {
            name = "HouseEntryHall",
            isLandmark = true,
            pts = {
                { X = 44270.0, Y = 58050.0, Z = 9010.0 }, -- Front Porch
                { X = 44270.0, Y = 58800.0, Z = 9020.0 }, -- Main Hallway inside BP_Door_Main
                { X = 44780.0, Y = 59780.0, Z = 9020.0 }, -- Living table (Envelope1)
            },
        },
        {
            name = "HouseWestRooms",
            isLandmark = true,
            pts = {
                { X = 43450.0, Y = 59850.0, Z = 9020.0 },
                { X = 42950.0, Y = 60600.0, Z = 9020.0 }, -- BP_Door_Room5
                { X = 43380.0, Y = 61180.0, Z = 9020.0 }, -- Whiteboard / FuneralInv
                { X = 42540.0, Y = 61200.0, Z = 9020.0 }, -- Envelope2 / Radio room
            },
        },
        {
            name = "HouseEastRooms",
            isLandmark = true,
            pts = {
                { X = 45420.0, Y = 59750.0, Z = 9020.0 }, -- ThankYouNote / Piano area
                { X = 45050.0, Y = 60220.0, Z = 9020.0 }, -- BP_Door_Room3
                { X = 44880.0, Y = 61150.0, Z = 9020.0 }, -- BP_Door_Room4
                { X = 44200.0, Y = 61600.0, Z = 9020.0 }, -- Back hallway
            },
        },
        {
            name = "BackyardGarden",
            isLandmark = true,
            pts = {
                { X = 44200.0, Y = 62350.0, Z = 9020.0 }, -- Outside Back Porch
                { X = 47400.0, Y = 65100.0, Z = 9650.0 }, -- Garage/Backyard Envelope3 area
                { X = 47600.0, Y = 59800.0, Z = 9020.0 }, -- East house exterior path
                { X = 39800.0, Y = 59500.0, Z = 9050.0 }, -- West house exterior path
            },
        },
        {
            name = "OutskirtsYard",
            isLandmark = false,
            pts = {
                { X = 41500.0, Y = 65200.0, Z = 8900.0 },
                { X = 37600.0, Y = 72000.0, Z = 9100.0 },
                { X = 36550.0, Y = 76300.0, Z = 9280.0 }, -- Generator_5
            },
        },
    }

    for zIdx, rz in ipairs(rawZones) do
        local pts = {}
        local center = GroundZonePoint(world, rz.pts[1], ignore)
        for _, p in ipairs(rz.pts) do
            local gp = GroundZonePoint(world, p, ignore)
            table.insert(pts, { pos = gp, lookAt = center, visited = false, visitedAt = 0.0, blockedUntil = 0.0 })
        end
        table.insert(State.Zones, {
            id            = zIdx,
            name          = rz.name,
            center        = center,
            isLandmark    = rz.isLandmark,
            pts           = pts,
            fullySearched = false,
        })
    end
end

local function InitGenericMap(world, survivor, hasNavMesh)
    local survLoc = Bridge.GetActorLoc(survivor) or { X = 0.0, Y = 0.0, Z = 100.0 }
    local ignore = Logger.IsValidObj(survivor) and { survivor } or {}

    if State.MapKey == "ESCAPE" then
        UnlockAndOpenMainDoors(survivor)
    end

    local function GroundGeneric(pos)
        if not pos then return nil end
        if hasNavMesh then
            local okN, proj = Bridge.ProjectPointToNav(world, pos, { X = 400.0, Y = 400.0, Z = 900.0 })
            if okN and proj then return proj end
        end
        return GroundZonePoint(world, pos, ignore)
    end

    -- 1. Scan native Pages, Generators, and Priority Interactables (excluding ambient subtitle/UI/light/furniture triggers)
    local candidates = {}
    local seen = {}
    local function TryAddCand(act, kindLabel, prio)
        if not Logger.IsValidObj(act) then return end
        local fn = Logger.SafeFullName(act)
        if seen[fn] then return end
        seen[fn] = true
        local cn = Logger.SafeName(act:GetClass())
        local an = Logger.SafeName(act)
        local comb = string.lower(cn .. " " .. an)
        for _, bad in ipairs({
            "window", "door", "remover", "slender", "trigger", "volume",
            "subtitle", "flashlight", "battery", "light", "lamp", "switch",
            "lock", "keyhole", "camera", "cutscene", "sequence", "audio",
            "sound", "music", "radio", "tv", "ladder", "chair", "bed",
            "curtain", "fence", "gate", "spawn", "cinecamera", "levelsequence"
        }) do
            if string.find(comb, bad, 1, true) then
                return
            end
        end
        local loc = Bridge.GetActorLoc(act)
        if not loc then return end
        local dSurv = Bridge.Dist2D(loc, survLoc)
        if dSurv < 900.0 or dSurv > 35000.0 then return end
        for _, ex in ipairs(candidates) do
            if Bridge.Dist2D(ex.pos, loc) < 220.0 then return end
        end
        local snapped = GroundGeneric(loc) or loc
        table.insert(candidates, {
            actor   = act,
            pos     = snapped,
            rawPos  = loc,
            kind    = kindLabel,
            prio    = prio or 2,
            name    = an ~= "" and an or cn,
            dist    = dSurv,
        })
    end

    for _, clsName in ipairs({
        "BP_PickUp_TheEightPages_C",
        "BP_Page_C",
        "BP_InteractableGenerator_C",
        "BP_InteractableGenerator_Master_C",
        "BP_Interact_GasGenerator_C",
        "BP_Interact_AnsweringMachine_C",
        "BP_Interact_PlayablePiano_C",
        "BP_Interact_CordlessPhone_C",
    }) do
        for _, a in ipairs(FindAllOf(clsName) or {}) do
            TryAddCand(a, clsName, 1)
        end
    end
    for _, a in ipairs(FindAllOf("Item") or {}) do
        if Logger.IsValidObj(a) then
            local cn = Logger.SafeName(a:GetClass())
            if string.find(cn, "BP_Collect_", 1, true)
                or string.find(cn, "BP_Evidence", 1, true)
                or string.find(cn, "BP_Page", 1, true) then
                TryAddCand(a, cn, 1)
            end
        end
    end
    for _, a in ipairs(FindAllOf("BP_BaseInteractable_C") or {}) do
        TryAddCand(a, "BP_BaseInteractable_C", 2)
    end
    for _, a in ipairs(FindAllOf("Actor") or {}) do
        if #candidates >= 24 then break end
        if Logger.IsValidObj(a) then
            local cn = string.lower(Logger.SafeName(a:GetClass()))
            local isHigh = string.find(cn, "bp_collect", 1, true)
                or string.find(cn, "evidence", 1, true)
                or string.find(cn, "generator", 1, true)
            if isHigh
                or string.find(cn, "page", 1, true)
                or string.find(cn, "note", 1, true)
                or string.find(cn, "poster", 1, true)
                or string.find(cn, "interact", 1, true)
                or string.find(cn, "collect", 1, true)
                or string.find(cn, "scrap", 1, true)
                or string.find(cn, "diary", 1, true)
            then
                TryAddCand(a, "ActorScan", isHigh and 1 or 2)
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        return a.dist < b.dist
    end)

    local scanCap = hasNavMesh and 8 or 16
    for _, c in ipairs(candidates) do
        if #State.Pages >= scanCap then break end
        table.insert(State.Pages, {
            id           = #State.Pages + 1,
            actor        = c.actor,
            isSynthetic  = false,
            kind         = c.kind,
            name         = c.name,
            pos          = c.rawPos,
            approachPos  = c.pos,
            collected    = false,
            discovered   = false,
            lastSeenAt   = 0.0,
            blockedUntil = 0.0,
        })
    end

    -- 2. Build Exploration Zones from Pages + Landmarks + NavMesh/Radial samples
    local zoneSeeds = {}
    for _, p in ipairs(State.Pages) do
        table.insert(zoneSeeds, { name = p.name, isLandmark = true, pos = p.approachPos or p.pos })
    end
    for _, lm in ipairs(FindAllOf("BP_SlenderEventZone_C") or {}) do
        if #zoneSeeds >= 16 then break end
        local loc = Bridge.GetActorLoc(lm)
        if loc and Bridge.Dist2D(loc, survLoc) <= 30000.0 then
            table.insert(zoneSeeds, { name = Logger.SafeName(lm), isLandmark = true, pos = GroundGeneric(loc) or loc })
        end
    end
    if hasNavMesh then
        for _, rad in ipairs({ 1400.0, 2600.0, 4200.0, 6200.0 }) do
            for _ = 1, 5 do
                local okR, pt = Bridge.GetRandomReachablePoint(world, survLoc, rad)
                if okR and pt and Bridge.Dist2D(pt, survLoc) >= 450.0 then
                    table.insert(zoneSeeds, { name = "Sector_" .. tostring(#zoneSeeds + 1), isLandmark = false, pos = pt })
                end
            end
        end
    else
        for _, rad in ipairs({ 900.0, 1800.0, 3000.0 }) do
            for k = 0, 7 do
                local ang = (k * math.pi * 2.0) / 8.0
                local raw = { X = survLoc.X + math.cos(ang) * rad, Y = survLoc.Y + math.sin(ang) * rad, Z = survLoc.Z + 80.0 }
                local gp = GroundZonePoint(world, raw, ignore)
                if gp then
                    table.insert(zoneSeeds, { name = "Sector_" .. tostring(#zoneSeeds + 1), isLandmark = false, pos = gp })
                end
            end
        end
    end

    local keptZoneCenters = {}
    for _, s in ipairs(zoneSeeds) do
        if s.pos then
            local dup = false
            for _, kc in ipairs(keptZoneCenters) do
                if Bridge.Dist2D(kc, s.pos) < 550.0 then
                    dup = true
                    break
                end
            end
            if not dup then
                table.insert(keptZoneCenters, s.pos)
                local gp = GroundGeneric(s.pos) or s.pos
                table.insert(State.Zones, {
                    id            = #State.Zones + 1,
                    name          = tostring(s.name or ("Zone_" .. tostring(#State.Zones + 1))),
                    center        = gp,
                    isLandmark    = s.isLandmark == true,
                    pts           = {
                        { pos = gp, lookAt = survLoc, visited = false, visitedAt = 0.0, blockedUntil = 0.0 },
                    },
                    fullySearched = false,
                })
            end
        end
    end

    -- 3. Synthesize exploration checkpoints if fewer than 3 interactive objectives were indexed on NavMesh maps
    -- (Non-NavMesh maps synthesize onto verified walkable BFS nodes inside SnapZonesToWalkableGraph)
    if hasNavMesh and #State.Pages < 3 then
        for _, z in ipairs(State.Zones) do
            if #State.Pages >= 8 then break end
            local tooClose = false
            for _, p in ipairs(State.Pages) do
                if Bridge.Dist2D(p.pos, z.center) < 600.0 then
                    tooClose = true
                    break
                end
            end
            if not tooClose then
                table.insert(State.Pages, {
                    id           = #State.Pages + 1,
                    actor        = nil,
                    isSynthetic  = true,
                    kind         = "SYNTH_CHECKPOINT",
                    name         = z.name,
                    pos          = { X = z.center.X, Y = z.center.Y, Z = z.center.Z },
                    approachPos  = { X = z.center.X, Y = z.center.Y, Z = z.center.Z },
                    collected    = false,
                    discovered   = false,
                    lastSeenAt   = 0.0,
                    blockedUntil = 0.0,
                })
            end
        end
    end

    State.TotalCount = math.max(1, #State.Pages)
    Logger.Info(string.format("ObjectiveManager [%s] generic indexed %d objectives across %d zones",
        tostring(State.MapKey), #State.Pages, #State.Zones))
end

function ObjectiveManager.Init(world, survivor, playerState, gameMode, mapKey, hasNavMesh)
    ObjectiveManager.Reset()
    if not Logger.IsValidObj(world) then return false end

    State.PlayerState = playerState
    State.GameMode    = gameMode
    State.MapKey      = mapKey or "EIGHT_PAGES"
    State.HasNavMesh  = (hasNavMesh == true)

    if Logger.IsValidObj(gameMode) then
        pcall(function() gameMode.bEndMatchViaScoreAmount = false end)
    end
    if Logger.IsValidObj(playerState) then
        pcall(function() playerState:SetScore(0.0) end)
    end

    if State.MapKey == "PROLOGUE" then
        InitLevel01Prologue(world, survivor)
    elseif State.MapKey == "EIGHT_PAGES" then
        InitLevel02EightPages(world, survivor)
    else
        InitGenericMap(world, survivor, State.HasNavMesh)
    end

    State.Initialized = true
    Logger.Info(string.format("ObjectiveManager ready (%s): %d objectives, %d zones",
        State.MapKey, State.TotalCount, #State.Zones))
    return true
end

local function IsObjectiveValid(p)
    if not p or p.collected then return false end
    if p.isSynthetic then
        return p.pos ~= nil
    end
    return Logger.IsValidObj(p.actor)
end

-- STRICT NON-OMNISCIENCE: Only human_perception.lua inspects GetRawUncollectedPages() via FOV + LineTrace!
function ObjectiveManager.GetRawUncollectedPages()
    local list = {}
    for _, p in ipairs(State.Pages) do
        if IsObjectiveValid(p) then
            table.insert(list, p)
        end
    end
    return list
end

function ObjectiveManager.MarkPageDiscovered(pageId, nowClock)
    for _, p in ipairs(State.Pages) do
        if p.id == pageId and not p.collected then
            local firstTime = not p.discovered
            p.discovered = true
            p.lastSeenAt = nowClock or os.clock()
            return firstTime, p
        end
    end
    return false, nil
end

function ObjectiveManager.GetKnownUncollectedPages()
    local list = {}
    for _, p in ipairs(State.Pages) do
        if p.discovered and IsObjectiveValid(p) then
            table.insert(list, p)
        end
    end
    return list
end

function ObjectiveManager.BlacklistPage(pageId, durationSec)
    local now = os.clock()
    local untilT = now + (durationSec or 30.0)
    for _, p in ipairs(State.Pages) do
        if p.id == pageId then
            p.blockedUntil = untilT
            Logger.Info(string.format("ObjectiveManager blacklisted Objective #%d (%s) for %.0fs",
                pageId, tostring(p.name), durationSec or 30.0))
            return true
        end
    end
    return false
end

function ObjectiveManager.GetNearestKnownPage(fromPos)
    if not fromPos then return nil, 1e9 end
    local best, bestD = nil, 1e9
    local now = os.clock()
    for _, p in ipairs(State.Pages) do
        if p.discovered and (p.blockedUntil or 0.0) <= now and IsObjectiveValid(p) then
            local d = Bridge.Dist(fromPos, p.pos)
            if d < bestD then
                best, bestD = p, d
            end
        end
    end
    return best, bestD
end

function ObjectiveManager.SnapZonesToWalkableGraph(humanNav, world)
    if State.HasNavMesh or not humanNav then return end
    local mapTag = tostring(State.MapKey or "GENERIC")
    local snapZ  = (State.MapKey == "PROLOGUE") and 180.0 or 260.0
    local keptZones = {}
    local keptPtsTotal = 0
    for _, z in ipairs(State.Zones) do
        local newPts = {}
        for _, pt in ipairs(z.pts or {}) do
            local node = humanNav.GetNearestWalkableNode(pt.pos, 700.0, snapZ)
            if node and node.pos then
                local dup = false
                for _, ex in ipairs(newPts) do
                    if Bridge.Dist2D(ex.pos, node.pos) < 200.0 then
                        dup = true
                        break
                    end
                end
                if not dup then
                    table.insert(newPts, {
                        pos          = { X = node.pos.X, Y = node.pos.Y, Z = node.pos.Z },
                        lookAt       = pt.lookAt or node.pos,
                        visited      = false,
                        visitedAt    = 0.0,
                        blockedUntil = 0.0,
                    })
                end
            end
        end
        if #newPts > 0 then
            z.pts = newPts
            z.center = newPts[1].pos
            z.fullySearched = false
            table.insert(keptZones, z)
            keptPtsTotal = keptPtsTotal + #newPts
        else
            Logger.Warn(string.format("ObjectiveManager dropped unreachable zone on %s: %s", mapTag, tostring(z.name)))
        end
    end
    State.Zones = keptZones

    local walkNodes = humanNav.GetWalkableNodes and humanNav.GetWalkableNodes() or {}
    local startPos  = (walkNodes[1] and walkNodes[1].pos) or nil

    local function CopyPos(v)
        return { X = v.X, Y = v.Y, Z = v.Z }
    end

    local function MinDist2DToPts(pos, list, field)
        local best = 1e9
        for _, item in ipairs(list) do
            local pt = field and item[field] or item
            if pt then
                local d = Bridge.Dist2D(pos, pt)
                if d < best then best = d end
            end
        end
        return best
    end

    local function PickFarthestWalkNode(existingPts, existingField, minStart, minSpacing, maxDz)
        local bestNode, bestScore = nil, -1.0
        for _, n in ipairs(walkNodes) do
            local dStart = startPos and Bridge.Dist2D(n.pos, startPos) or 1e9
            local dz     = startPos and math.abs(n.pos.Z - startPos.Z) or 0.0
            if dStart >= minStart and dz <= maxDz then
                local minEx = (#existingPts > 0) and MinDist2DToPts(n.pos, existingPts, existingField) or dStart
                if minEx >= minSpacing and minEx > bestScore then
                    bestScore = minEx
                    bestNode  = n
                end
            end
        end
        return bestNode
    end

    if State.MapKey ~= "PROLOGUE" and #walkNodes >= 5 and #State.Zones < 5 then
        local targetZones = math.min(6, #walkNodes)
        while #State.Zones < targetZones do
            local bn = PickFarthestWalkNode(State.Zones, "center", 450.0, 650.0, 320.0)
                or PickFarthestWalkNode(State.Zones, "center", 300.0, 450.0, 380.0)
            if not bn then break end
            table.insert(State.Zones, {
                id            = #State.Zones + 1,
                name          = tostring(bn.name or ("Sector_" .. tostring(#State.Zones + 1))),
                center        = CopyPos(bn.pos),
                isLandmark    = false,
                pts           = {
                    { pos = CopyPos(bn.pos), lookAt = startPos and CopyPos(startPos) or CopyPos(bn.pos), visited = false, visitedAt = 0.0, blockedUntil = 0.0 },
                },
                fullySearched = false,
            })
            keptPtsTotal = keptPtsTotal + 1
        end
    end

    Logger.Info(string.format("ObjectiveManager snapped %s zones to walkable graph: %d zones, %d points",
        mapTag, #State.Zones, keptPtsTotal))

    if world and humanNav.GetSameRoomApproachNode then
        local keptPages = {}
        local isGenericNonNav = (State.MapKey ~= "PROLOGUE")
        for _, p in ipairs(State.Pages) do
            if #keptPages >= 8 then break end
            if not p.isSynthetic then
                local node = humanNav.GetSameRoomApproachNode(world, p.pos, 330.0, p.actor)
                if node and node.pos then
                    local okSpacing = true
                    if isGenericNonNav and startPos then
                        local dStart = Bridge.Dist2D(node.pos, startPos)
                        local minSep = (#keptPages > 0) and MinDist2DToPts(node.pos, keptPages, "approachPos") or 1e9
                        if dStart < 750.0 or minSep < 450.0 then
                            okSpacing = false
                            Logger.Info(string.format("ObjectiveManager skipped too-close %s item: %s (dStart=%.0fcm sep=%.0fcm)",
                                mapTag, tostring(p.name), dStart, minSep))
                        end
                    end
                    if okSpacing then
                        p.approachPos = CopyPos(node.pos)
                        p.id = #keptPages + 1
                        table.insert(keptPages, p)
                    end
                else
                    local _, nd = humanNav.GetNearestWalkableNode(p.pos, 2000.0, 400.0)
                    Logger.Info(string.format("ObjectiveManager skipped unreachable %s item: %s @ (%.0f,%.0f,%.0f) nearestNode=%.0fcm",
                        mapTag, tostring(p.name), p.pos.X, p.pos.Y, p.pos.Z, tonumber(nd) or -1.0))
                end
            end
        end

        -- Guarantee >= 5 (or 6 on large graphs) well-spaced synthetic checkpoints on generic non-NavMesh maps
        if isGenericNonNav and #walkNodes > 0 and #keptPages < 5 then
            local targetCount = (#walkNodes >= 150) and 6 or 5
            while #keptPages < targetCount do
                local bn = PickFarthestWalkNode(keptPages, "pos", 1000.0, 650.0, 260.0)
                    or PickFarthestWalkNode(keptPages, "pos", 750.0, 450.0, 320.0)
                    or PickFarthestWalkNode(keptPages, "pos", 450.0, 300.0, 400.0)
                if not bn then break end
                table.insert(keptPages, {
                    id           = #keptPages + 1,
                    actor        = nil,
                    isSynthetic  = true,
                    kind         = "SYNTH_CHECKPOINT",
                    name         = tostring(bn.name or ("Checkpoint_" .. tostring(#keptPages + 1))),
                    pos          = CopyPos(bn.pos),
                    approachPos  = CopyPos(bn.pos),
                    collected    = false,
                    discovered   = false,
                    lastSeenAt   = 0.0,
                    blockedUntil = 0.0,
                })
            end
        end

        State.Pages = keptPages
        State.TotalCount = math.max(1, #State.Pages)
        Logger.Info(string.format("ObjectiveManager validated %s objectives on walkable graph: %d reachable objectives",
            mapTag, #State.Pages))
    end
end

function ObjectiveManager.GetPageById(pageId)
    for _, p in ipairs(State.Pages) do
        if p.id == pageId then return p end
    end
    return nil
end

function ObjectiveManager.GetExplorationZones()
    return State.Zones
end

function ObjectiveManager.BlacklistZonePoint(zoneId, ptIdx, durationSec)
    local now = os.clock()
    local untilT = now + (durationSec or 45.0)
    for _, z in ipairs(State.Zones) do
        if z.id == zoneId and z.pts[ptIdx] then
            z.pts[ptIdx].blockedUntil = untilT
            Logger.Info(string.format("ObjectiveManager blacklisted %s[%d] for %.0fs", z.name, ptIdx, durationSec or 45.0))
            return true
        end
    end
    return false
end

function ObjectiveManager.GetNextAvailablePointIndex(zone, startIdx)
    if not zone or not zone.pts then return nil end
    local now = os.clock()
    local n = #zone.pts
    for off = 0, n - 1 do
        local idx = (( (startIdx or 1) - 1 + off ) % n) + 1
        local pt = zone.pts[idx]
        if pt and (not pt.visited) and (pt.blockedUntil or 0.0) <= now then
            return idx
        end
    end
    return nil
end

function ObjectiveManager.MarkZonePointVisited(zoneId, ptIdx, nowClock)
    local now = nowClock or os.clock()
    for _, z in ipairs(State.Zones) do
        if z.id == zoneId then
            if z.pts[ptIdx] then
                z.pts[ptIdx].visited = true
                z.pts[ptIdx].visitedAt = now
            end
            local allDone = (ObjectiveManager.GetNextAvailablePointIndex(z, 1) == nil)
            z.fullySearched = allDone
            return allDone
        end
    end
    return false
end

function ObjectiveManager.RefreshSearchedZonesIfNeeded()
    local now = os.clock()
    for _, z in ipairs(State.Zones) do
        if (not z.fullySearched) and ObjectiveManager.GetNextAvailablePointIndex(z, 1) ~= nil then
            return
        end
    end
    for _, z in ipairs(State.Zones) do
        z.fullySearched = false
        for _, pt in ipairs(z.pts) do
            pt.visited = false
            if (pt.blockedUntil or 0.0) < now then pt.blockedUntil = 0.0 end
        end
    end
    Logger.Info("ObjectiveManager: Cycled exploration zones for remaining objectives.")
end

function ObjectiveManager.GetNextBestZone(humanPos, dangerZones, excludeZoneId)
    ObjectiveManager.RefreshSearchedZonesIfNeeded()
    local bestZone, bestScore = nil, 1e9
    for _, z in ipairs(State.Zones) do
        if (not z.fullySearched) and z.id ~= excludeZoneId and ObjectiveManager.GetNextAvailablePointIndex(z, 1) ~= nil then
            local dist = Bridge.Dist2D(humanPos, z.center)
            local penalty = 0.0
            if not z.isLandmark then
                penalty = penalty + 750.0
            end
            if dangerZones then
                for _, dz in ipairs(dangerZones) do
                    local dd = Bridge.Dist2D(z.center, dz.pos)
                    if dd < (dz.radius or 2200.0) then
                        penalty = penalty + 5500.0 * (dz.intensity or 1.0) * (1.0 - dd / (dz.radius or 2200.0))
                    end
                end
            end
            local score = dist + penalty
            if score < bestScore then
                bestScore = score
                bestZone = z
            end
        end
    end
    return bestZone
end

function ObjectiveManager.CollectPage(world, survivor, pageId, bypassDistCheck)
    local p = ObjectiveManager.GetPageById(pageId)
    if not IsObjectiveValid(p) then
        return false, "InvalidOrAlreadyCollected"
    end

    if not bypassDistCheck and Logger.IsValidObj(survivor) then
        local hLoc = Bridge.GetActorLoc(survivor)
        if not hLoc then return false, "NoSurvivorLoc" end
        local d2D = Bridge.Dist2D(hLoc, p.pos)
        local dZ  = math.abs(hLoc.Z - p.pos.Z)
        local atApproach = p.approachPos and (Bridge.Dist2D(hLoc, p.approachPos) <= 95.0)
        if dZ > 220.0 or d2D > 380.0 or (d2D > (Config.HUMAN.INTERACT_DISTANCE + 70.0) and not atApproach) then
            return false, "TooFar"
        end
    end

    local pg = p.actor
    p.collected = true
    State.CollectedCount = State.CollectedCount + 1

    if Logger.IsValidObj(pg) then
        pcall(function() pg:OnItemInteracted(survivor) end)
        pcall(function() pg:ToggleInteractivity(false) end)
        pcall(function() pg.bAvailableForPickup = false end)
        pcall(function() pg:SetActorHiddenInGame(true) end)
        pcall(function() pg:SetActorEnableCollision(false) end)
    end

    if not bypassDistCheck then
        local sndPlayed = false
        if Logger.IsValidObj(pg) then
            pcall(function()
                if Logger.IsValidObj(pg.PickupSound) then
                    sndPlayed = Bridge.PlaySoundObj2D(world, pg.PickupSound, 0.75, 1.0)
                elseif Logger.IsValidObj(pg.SoundOnInteracted) then
                    sndPlayed = Bridge.PlaySoundObj2D(world, pg.SoundOnInteracted, 0.75, 1.0)
                end
            end)
        end
        if not sndPlayed then
            Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_PAGE_GRAB, 0.65, 1.0, { "pagegrab_Cue", "pagegrab", "Paper", "Page" })
        end
    end

    if Logger.IsValidObj(State.PlayerState) then
        pcall(function() State.PlayerState:SetScore(State.CollectedCount * 1.0) end)
    end
    if State.CollectedCount == 1 and State.MapKey == "EIGHT_PAGES" and Logger.IsValidObj(State.GameMode) then
        pcall(function() State.GameMode:RemoveGateways() end)
    end

    Logger.Info(string.format("Objective #%d (%s) collected! Progress: %d / %d",
        pageId, tostring(p.name), State.CollectedCount, State.TotalCount))
    return true, State.CollectedCount
end

function ObjectiveManager.GetCollectedCount() return State.CollectedCount end
function ObjectiveManager.GetTotalCount()     return State.TotalCount end

function ObjectiveManager.GetKnownCount()
    local c = 0
    for _, p in ipairs(State.Pages) do
        if p.discovered and not p.collected then c = c + 1 end
    end
    return c
end

return ObjectiveManager
