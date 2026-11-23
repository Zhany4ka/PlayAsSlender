-- PlayAsSlender V2 Toggleable Demolition Hammer
-- Features:
--   - Hidden by default; toggle with [R] (TOGGLE_HAMMER), rigged in SK_Slender01 hand_r
--   - Paired Double-Layer Wall Sandwich Resolver (eliminates one-sided transparent ghost walls)
--   - In-Place Volume Grid Fracture (100% solid Cube slabs matching original surface materials; no disappearing props)
--   - Jagged Splintered Breach Framing capping exposed double-wall edges & overhead joists
--   - GMod Chaos Rigid-Body prop detachment/batting + Foliage tree felling + Hit-stop & Staggered Cascade Audio
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")
local WallBreach = require("hammer_wall_breach")

local HammerMgr = {}

local State = {
    Initialized       = false,
    World             = nil,
    Slender           = nil,
    Equipped          = false,
    Parts             = {},
    Pivot             = nil,
    PivotComp         = nil,
    SwingType         = nil,   -- "LIGHT" | "HEAVY" | nil
    SwingElapsed      = 0.0,
    SwingDuration     = 0.34,
    SwingHitDone      = false,
    HitStopTimer      = 0.0,
    OverrideRay       = nil,
    Cooldown          = 0.0,
    CooldownMax       = 0.48,
    FlashLight        = nil,
    FlashTimer        = 0.0,
    DebrisPool        = {},    -- persistent heavy Chaos slabs/props { actor, comp, spawnedAt }
    SplinterPool      = {},    -- short-lived impact grit/splinters { actor, comp, expiresAt }
    BreachFrames      = {},    -- jagged wall opening framing actors { actor }
    DelayedSounds     = {},    -- staggered cascade audio events { at, loc, path, fb, vol, pitch }
    SimProps          = {},    -- compAddr -> { comp }
    Cracked           = {},    -- compAddr -> { hp, comp }
    Scars             = {},    -- crack/crater overlays { actor, surface }
    DestroyedCount    = 0,
    DetachedCount     = 0,
    ChunksSpawned     = 0,
    PairedWallsBroken = 0,
}

local PATHS = {
    MESH_CUBE      = "/Engine/BasicShapes/Cube.Cube",
    MESH_CYLINDER  = "/Engine/BasicShapes/Cylinder.Cylinder",
    MAT_WHITE_WOOD = "/Game/ThirdPartyAssets/RetroFarmhouse/Materials/MI_WhiteWood.MI_WhiteWood",
    MAT_WALLPAPER  = "/Game/ThirdPartyAssets/RetroFarmhouse/Materials/MI_Wallpapers_A.MI_Wallpapers_A",
    MAT_WOOD_OLD   = "/Game/ThirdPartyAssets/RetroFarmhouse/Materials/MI_WoodOld.MI_WoodOld",
    MAT_WOOD_DARK  = "/Game/ThirdPartyAssets/RetroFarmhouse/Materials/MI_PlanksDirty_dark.MI_PlanksDirty_dark",
    MAT_WOOD_SWAMP = "/Game/ThirdPartyAssets/Swamp/Materials/Swamp_Wood_Plank1.Swamp_Wood_Plank1",
    MAT_TRIM_DARK  = "/Game/Art/Environment/Props/Structures/Materials/MaterialInstances/MI_Trim_Wood_DarkBrown.MI_Trim_Wood_DarkBrown",
    MAT_METAL      = "/Game/ThirdPartyAssets/Swamp/Materials/M_Metal_Inst1.M_Metal_Inst1",
    MAT_METAL_DULL = "/Game/Art/Environment/Props/Structures/Materials/MaterialInstances/MI_Trim_Metal_Dull_Grey.MI_Trim_Metal_Dull_Grey",
    MAT_CHROME     = "/Game/ThirdPartyAssets/1980s_Cars_Pack/Materials_shared/MI_Metal_Chrome.MI_Metal_Chrome",
    MAT_STONE      = "/Game/Art/Environment/Props/Rocks/Materials/MaterialInstances/Forest/MI_Rock_RiverStones.MI_Rock_RiverStones",
    MAT_BRICK      = "/Game/Art/Environment/Props/Slender/Materials/MI_BrickPile_B_Grey.MI_BrickPile_B_Grey",
    MAT_EXT_STONE  = "/Game/Art/Environment/Props/Slender/Materials/MI_ExteriorStone.MI_ExteriorStone",
    MAT_BARK       = "/Game/Art/Environment/ConiferForestCollection/Materials/Trees/MTL_CF_ConiferBarkA.MTL_CF_ConiferBarkA",
    SND_CAR_SLAM   = "/Game/Audio/Slender/CarDoorClosing_Cue.CarDoorClosing_Cue",
    SND_DOOR_SLAM  = "/Game/Audio/Ambiance/Doors/DoorClose_Cue.DoorClose_Cue",
    SND_HANDLE     = "/Game/Audio/Slender/doorhandle_Cue.doorhandle_Cue",
    SND_GATE_CREAK = "/Game/Audio/Slender/gateScream_Cue.gateScream_Cue",
}

local function SafeDestroyActor(actor)
    if Logger.IsValidObj(actor) then
        pcall(function() actor:K2_DestroyActor() end)
    end
end

local function DestroyArrayActors(arr)
    if type(arr) ~= "table" then return end
    for i = #arr, 1, -1 do
        local entry = arr[i]
        local actor = (type(entry) == "table") and entry.actor or entry
        SafeDestroyActor(actor)
        arr[i] = nil
    end
end

function HammerMgr.Reset()
    WallBreach.Reset()
    DestroyArrayActors(State.Parts)
    DestroyArrayActors(State.DebrisPool)
    DestroyArrayActors(State.SplinterPool)
    DestroyArrayActors(State.BreachFrames)
    DestroyArrayActors(State.Scars)
    SafeDestroyActor(State.FlashLight)

    State.Initialized       = false
    State.World             = nil
    State.Slender           = nil
    State.Equipped          = false
    State.Parts             = {}
    State.Pivot             = nil
    State.PivotComp         = nil
    State.SwingType         = nil
    State.SwingElapsed      = 0.0
    State.SwingDuration     = 0.34
    State.SwingHitDone      = false
    State.HitStopTimer      = 0.0
    State.OverrideRay       = nil
    State.Cooldown          = 0.0
    State.CooldownMax       = Config.HAMMER.SWING_COOLDOWN or 0.48
    State.FlashLight        = nil
    State.FlashTimer        = 0.0
    State.DebrisPool        = {}
    State.SplinterPool      = {}
    State.BreachFrames      = {}
    State.DelayedSounds     = {}
    State.SimProps          = {}
    State.Cracked           = {}
    State.Scars             = {}
    State.DestroyedCount    = 0
    State.DetachedCount     = 0
    State.ChunksSpawned     = 0
    State.PairedWallsBroken = 0
end

function HammerMgr.Init(world, slender)
    HammerMgr.Reset()
    State.World       = world
    State.Slender     = slender
    State.Initialized = true
end

function HammerMgr.IsEquipped()
    return State.Equipped == true
end

function HammerMgr.IsVisible()
    if not State.Equipped or #State.Parts == 0 then return false end
    for _, p in ipairs(State.Parts) do
        if Logger.IsValidObj(p) then
            local vis = false
            pcall(function()
                if p.bHidden ~= nil then
                    vis = (p.bHidden == false)
                else
                    vis = true
                end
            end)
            if vis then return true end
        end
    end
    return false
end

function HammerMgr.GetUiState()
    return {
        equipped  = State.Equipped == true,
        cd        = math.max(0.0, State.Cooldown or 0.0),
        cdMax     = State.CooldownMax or (Config.HAMMER.SWING_COOLDOWN or 0.48),
        swinging  = (State.SwingType ~= nil),
        destroyed = State.DestroyedCount or 0,
        detached  = State.DetachedCount or 0,
        debris    = #State.DebrisPool,
    }
end

function HammerMgr.GetDebugStats()
    return {
        equipped          = State.Equipped == true,
        destroyed         = State.DestroyedCount or 0,
        detached          = State.DetachedCount or 0,
        pairedWallsBroken = State.PairedWallsBroken or 0,
        breachFrames      = #State.BreachFrames,
        debris            = #State.DebrisPool,
        splinters         = #State.SplinterPool,
        scars             = #State.Scars,
        chunksSpawned     = State.ChunksSpawned or 0,
    }
end

function HammerMgr.LogPoolDiagnostics(refLoc, maxShow)
    local total = #State.DebrisPool
    local simCnt, nearCnt = 0, 0
    for i = 1, total do
        local entry = State.DebrisPool[i]
        local c = entry and entry.comp
        local a = entry and entry.actor
        if Logger.IsValidObj(a) and Logger.IsValidObj(c) then
            local sim, mob, col, hidden, smName, matName = false, -1, -1, false, "nil", "nil"
            pcall(function() sim = (c:IsSimulatingPhysics(Bridge.FName("None")) == true) end)
            pcall(function() mob = tonumber(c.Mobility) or -1 end)
            pcall(function() col = tonumber(c:GetCollisionEnabled()) or -1 end)
            pcall(function() hidden = (a.bHidden == true) end)
            pcall(function() if c.StaticMesh then smName = Logger.SafeName(c.StaticMesh) end end)
            pcall(function() local m = c:GetMaterial(0); if m then matName = Logger.SafeName(m) end end)
            local pos = Bridge.GetActorLoc(a) or Bridge.GetComponentBounds(c)
            local dist = (pos and refLoc) and Bridge.Dist(pos, refLoc) or -1.0
            if sim then simCnt = simCnt + 1 end
            if sim and dist >= 0 and dist <= 450.0 then nearCnt = nearCnt + 1 end
            if i > total - (maxShow or 12) then
                Logger.Info(string.format("  Debris[%d] sm=%s mat=%s mob=%d col=%d hid=%s sim=%s dist=%.1f pos=(%.0f,%.0f,%.0f)",
                    i, smName, matName, mob, col, tostring(hidden), tostring(sim), dist,
                    pos and pos.X or 0, pos and pos.Y or 0, pos and pos.Z or 0))
            end
        end
    end
    return simCnt, nearCnt
end

local function FirstValidAsset(list)
    for _, path in ipairs(list) do
        local obj = Bridge.LoadOrFindAsset(path)
        if Logger.IsValidObj(obj) then return obj end
    end
    return nil
end

local function GetStaticMeshComp(actor)
    if not Logger.IsValidObj(actor) then return nil end
    local comp = nil
    pcall(function() comp = actor.StaticMeshComponent end)
    if Logger.IsValidObj(comp) then return comp end
    pcall(function() comp = actor.RootComponent end)
    return Logger.IsValidObj(comp) and comp or nil
end

local function SpawnVisualPart(meshAsset, matAsset, relLoc, relRot, scaleVec)
    local world = State.World
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(State.PivotComp) then return nil end

    local slLoc = Bridge.GetActorLoc(State.Slender) or { X = 0, Y = 0, Z = 100 }
    local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", slLoc, 0.0)
    if not Logger.IsValidObj(actor) then return nil end

    local comp = GetStaticMeshComp(actor)
    if Logger.IsValidObj(comp) then
        pcall(function() comp:SetMobility(2) end)
        pcall(function() comp:SetCollisionEnabled(0) end)
        pcall(function() comp:SetCollisionResponseToAllChannels(0) end)
        if Logger.IsValidObj(meshAsset) then
            pcall(function() comp:SetStaticMesh(meshAsset) end)
        end
        if Logger.IsValidObj(matAsset) then
            pcall(function() comp:SetMaterial(0, matAsset) end)
        end
        pcall(function()
            comp:K2_AttachToComponent(State.PivotComp, Bridge.FName("None"), 0, 0, 0, false)
            comp:K2_SetRelativeLocationAndRotation(
                Bridge.Vec(relLoc.X, relLoc.Y, relLoc.Z),
                Bridge.Rot(relRot.Pitch, relRot.Yaw, relRot.Roll),
                false, {}, true
            )
            if comp.SetRelativeScale3D then
                comp:SetRelativeScale3D(Bridge.Vec(scaleVec.X, scaleVec.Y, scaleVec.Z))
            end
            comp:SetWorldScale3D(Bridge.Vec(scaleVec.X, scaleVec.Y, scaleVec.Z))
        end)
    end
    pcall(function() actor:SetActorEnableCollision(false) end)
    pcall(function() actor:SetActorHiddenInGame(not State.Equipped) end)
    table.insert(State.Parts, actor)
    return actor
end

local function SetRigVisible(visible)
    for _, actor in ipairs(State.Parts) do
        if Logger.IsValidObj(actor) then
            pcall(function() actor:SetActorHiddenInGame(not visible) end)
            pcall(function() actor:SetActorEnableCollision(false) end)
        end
    end
end

local function EnsureRig()
    if #State.Parts > 0 and Logger.IsValidObj(State.Pivot) and Logger.IsValidObj(State.PivotComp) then
        return true
    end
    DestroyArrayActors(State.Parts)
    State.Parts = {}
    State.Pivot = nil
    State.PivotComp = nil

    if not Logger.IsValidObj(State.World) or not Logger.IsValidObj(State.Slender) then
        return false
    end

    local cubeMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    local cylMesh  = Bridge.LoadOrFindAsset(PATHS.MESH_CYLINDER)
    if not Logger.IsValidObj(cubeMesh) or not Logger.IsValidObj(cylMesh) then
        Logger.Warn("HammerMgr: BasicShapes Cube/Cylinder unavailable; cannot build 3D Hammer rig.")
        return false
    end

    local matShaft  = FirstValidAsset({ PATHS.MAT_WOOD_SWAMP, PATHS.MAT_WOOD_OLD, PATHS.MAT_TRIM_DARK, PATHS.MAT_BARK })
    local matGrip   = FirstValidAsset({ PATHS.MAT_WOOD_DARK, PATHS.MAT_TRIM_DARK, PATHS.MAT_WOOD_OLD })
    local matHead   = FirstValidAsset({ PATHS.MAT_METAL_DULL, PATHS.MAT_METAL, PATHS.MAT_EXT_STONE, PATHS.MAT_STONE })
    local matSteel  = FirstValidAsset({ PATHS.MAT_CHROME, PATHS.MAT_METAL, PATHS.MAT_METAL_DULL })

    local slLoc = Bridge.GetActorLoc(State.Slender) or { X = 0, Y = 0, Z = 100 }
    local pivot = Bridge.SpawnActorDeferred(State.World, "/Script/Engine.StaticMeshActor", slLoc, 0.0)
    if not Logger.IsValidObj(pivot) then return false end

    local pComp = GetStaticMeshComp(pivot)
    if not Logger.IsValidObj(pComp) then
        SafeDestroyActor(pivot)
        return false
    end
    pcall(function() pComp:SetMobility(2) end)
    pcall(function() pComp:SetCollisionEnabled(0) end)
    pcall(function() pComp:SetWorldScale3D(Bridge.Vec(1.0, 1.0, 1.0)) end)
    pcall(function() pivot:SetActorEnableCollision(false) end)
    pcall(function() pivot:SetActorHiddenInGame(not State.Equipped) end)

    State.Pivot     = pivot
    State.PivotComp = pComp
    table.insert(State.Parts, pivot)

    -- 7-part Forged Sledgehammer / Demolition Maul around Right-Hand Grip (0, 0, 0)
    SpawnVisualPart(cylMesh,  matGrip,  { X = 0.0,   Y = 0.0, Z = 2.0  }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.058, Y = 0.058, Z = 0.28 })
    SpawnVisualPart(cylMesh,  matShaft, { X = 0.0,   Y = 0.0, Z = 44.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.045, Y = 0.045, Z = 1.06 })
    SpawnVisualPart(cylMesh,  matHead,  { X = 0.0,   Y = 0.0, Z = -12.0},{ Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.075, Y = 0.075, Z = 0.06 })
    SpawnVisualPart(cubeMesh, matHead,  { X = 0.0,   Y = 0.0, Z = 86.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.135, Y = 0.150, Z = 0.11 })
    SpawnVisualPart(cubeMesh, matHead,  { X = 0.0,   Y = 0.0, Z = 93.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.450, Y = 0.220, Z = 0.220 })
    SpawnVisualPart(cubeMesh, matSteel, { X = 23.5,  Y = 0.0, Z = 93.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.055, Y = 0.255, Z = 0.255 })
    SpawnVisualPart(cubeMesh, matSteel, { X = -24.0, Y = 0.0, Z = 93.0 }, { Pitch = 45, Yaw = 0, Roll = 0 }, { X = 0.110, Y = 0.175, Z = 0.145 })

    Logger.Info(string.format("HammerMgr: Built 3D Sledgehammer rig (%d actors).", #State.Parts))
    return true
end

-- =========================================================
-- Material Safety Filter, Classification & Cascade Audio
-- =========================================================
local function IsSafeOpaqueMaterial(mat)
    if not Logger.IsValidObj(mat) then return false end
    local mname = string.lower(Logger.SafeName(mat) .. " " .. Logger.SafeFullName(mat))
    local reject = {
        "decal", "translucent", "transparent", "glass", "masked",
        "foliage", "billboard", "alpha", "shadow", "debug", "invisible", "peel",
    }
    for _, kw in ipairs(reject) do
        if string.find(mname, kw, 1, true) then
            return false
        end
    end
    return true
end

local function FallbackMaterialFor(kind, blob)
    if kind == "TREE" then
        return FirstValidAsset({ PATHS.MAT_BARK, PATHS.MAT_WOOD_DARK, PATHS.MAT_WOOD_OLD })
    elseif kind == "WOOD" then
        if blob and (string.find(blob, "wall_out", 1, true) or string.find(blob, "siding", 1, true)) then
            return FirstValidAsset({ PATHS.MAT_WHITE_WOOD, PATHS.MAT_WOOD_OLD, PATHS.MAT_WOOD_SWAMP })
        elseif blob and string.find(blob, "wall_in", 1, true) then
            return FirstValidAsset({ PATHS.MAT_WALLPAPER, PATHS.MAT_WHITE_WOOD, PATHS.MAT_WOOD_OLD })
        end
        return FirstValidAsset({ PATHS.MAT_WOOD_OLD, PATHS.MAT_WOOD_SWAMP, PATHS.MAT_WHITE_WOOD, PATHS.MAT_TRIM_DARK })
    elseif kind == "METAL" then
        return FirstValidAsset({ PATHS.MAT_METAL_DULL, PATHS.MAT_METAL, PATHS.MAT_CHROME })
    elseif kind == "GLASS" then
        return FirstValidAsset({ PATHS.MAT_CHROME, PATHS.MAT_METAL_DULL })
    end
    return FirstValidAsset({ PATHS.MAT_BRICK, PATHS.MAT_EXT_STONE, PATHS.MAT_STONE })
end

local function ClassifyMaterial(hitComp, hitActor)
    local compName = string.lower(Logger.SafeName(hitComp))
    local actName  = string.lower(Logger.SafeName(hitActor))
    local meshName = ""
    local matName  = ""
    local safeMat  = nil

    if Logger.IsValidObj(hitComp) then
        pcall(function()
            local sm = hitComp.StaticMesh
            if Logger.IsValidObj(sm) then meshName = string.lower(Logger.SafeName(sm)) end
        end)
        for slotIdx = 0, 1 do
            local candidate = nil
            pcall(function() candidate = hitComp:GetMaterial(slotIdx) end)
            if IsSafeOpaqueMaterial(candidate) then
                safeMat = candidate
                matName = string.lower(Logger.SafeName(candidate))
                break
            elseif Logger.IsValidObj(candidate) and matName == "" then
                matName = string.lower(Logger.SafeName(candidate))
            end
        end
    end

    local blob = compName .. " " .. actName .. " " .. meshName .. " " .. matName
    local kind = "STONE"
    if string.find(blob, "glass") or string.find(blob, "window") or string.find(blob, "mirror")
        or string.find(blob, "%f[%a]pane%f[%A]") then
        kind = "GLASS"
    elseif string.find(blob, "bark") or string.find(blob, "tree") or string.find(blob, "conifer") or string.find(blob, "pine") or string.find(blob, "foliage") or string.find(blob, "bush") then
        kind = "TREE"
    elseif string.find(blob, "wood") or string.find(blob, "plank") or string.find(blob, "door") or string.find(blob, "crate")
        or string.find(blob, "chair") or string.find(blob, "table") or string.find(blob, "cabinet") or string.find(blob, "porch")
        or string.find(blob, "roof") or string.find(blob, "shingle") or string.find(blob, "fence") or string.find(blob, "trim")
        or string.find(blob, "beam") or string.find(blob, "sign") or string.find(blob, "bench") or string.find(blob, "floor")
        or string.find(blob, "wall_out") or string.find(blob, "wall_in") or string.find(blob, "shelf") or string.find(blob, "bed")
        or string.find(blob, "sofa") then
        kind = "WOOD"
    elseif string.find(blob, "metal") or string.find(blob, "steel") or string.find(blob, "iron") or string.find(blob, "chrome")
        or string.find(blob, "car") or string.find(blob, "truck") or string.find(blob, "van") or string.find(blob, "pipe")
        or string.find(blob, "barrel") or string.find(blob, "tank") or string.find(blob, "rail") or string.find(blob, "generator")
        or string.find(blob, "gate") or string.find(blob, "locker") or string.find(blob, "trash") then
        kind = "METAL"
    end

    local debrisMat = safeMat or FallbackMaterialFor(kind, blob)
    return kind, debrisMat, blob
end

local function PlayImpactSound(loc, kind, isHeavy, withCascade)
    if not Logger.IsValidObj(State.World) then return end
    local pitch = isHeavy and (0.72 + math.random() * 0.14) or (0.90 + math.random() * 0.22)
    local vol   = isHeavy and 1.15 or 0.88

    if kind == "WOOD" or kind == "TREE" then
        if not Bridge.PlaySoundAtLocation(State.World, PATHS.SND_DOOR_SLAM, loc, vol, pitch, { "DoorClose_Cue", "wood" }) then
            Bridge.PlaySound2D(State.World, PATHS.SND_DOOR_SLAM, vol * 0.7, pitch, { "DoorClose_Cue" })
        end
    else
        if not Bridge.PlaySoundAtLocation(State.World, PATHS.SND_CAR_SLAM, loc, vol, pitch, { "CarDoorClosing_Cue", "DoorClose_Cue" }) then
            Bridge.PlaySound2D(State.World, PATHS.SND_CAR_SLAM, vol * 0.7, pitch, { "CarDoorClosing_Cue" })
        end
    end

    if isHeavy and Config.ASSETS and Config.ASSETS.SOUND_DRAMATIC then
        Bridge.PlaySound2D(State.World, Config.ASSETS.SOUND_DRAMATIC, 0.32, 0.65, { "Teleporter_Dramatic" })
    end

    if withCascade and loc then
        local now = os.clock()
        table.insert(State.DelayedSounds, {
            at    = now + 0.11,
            loc   = { X = loc.X, Y = loc.Y, Z = loc.Z },
            path  = (kind == "WOOD" or kind == "TREE") and PATHS.SND_DOOR_SLAM or PATHS.SND_CAR_SLAM,
            fb    = { "DoorClose_Cue", "CarDoorClosing_Cue" },
            vol   = isHeavy and 0.75 or 0.50,
            pitch = 1.12 + math.random() * 0.20,
        })
        table.insert(State.DelayedSounds, {
            at    = now + 0.26,
            loc   = { X = loc.X, Y = loc.Y, Z = loc.Z },
            path  = (kind == "WOOD" or kind == "TREE") and PATHS.SND_GATE_CREAK or PATHS.SND_DOOR_SLAM,
            fb    = { "gateScream_Cue", "DoorClose_Cue" },
            vol   = isHeavy and 0.55 or 0.35,
            pitch = 0.76 + math.random() * 0.16,
        })
    end
end

local function TriggerImpactFlash(loc, isHeavy)
    if not Logger.IsValidObj(State.World) or not loc then return end
    if not Logger.IsValidObj(State.FlashLight) then
        local ptCls = Bridge.GetClass("/Script/Engine.PointLight")
        if Logger.IsValidObj(ptCls) then
            State.FlashLight = Bridge.SpawnActorDeferred(State.World, ptCls, loc, 0.0)
            if Logger.IsValidObj(State.FlashLight) then
                pcall(function()
                    local lc = State.FlashLight.PointLightComponent or State.FlashLight.RootComponent
                    if Logger.IsValidObj(lc) then
                        lc:SetMobility(2)
                        lc:SetCastShadows(false)
                        if lc.SetAttenuationRadius then lc:SetAttenuationRadius(isHeavy and 440.0 or 260.0) end
                        if lc.SetLightColor then lc:SetLightColor({ R = 1.0, G = 0.72, B = 0.38, A = 1.0 }, true) end
                        lc:SetIntensity(isHeavy and 15000.0 or 7500.0)
                    end
                end)
            end
        end
    end
    if Logger.IsValidObj(State.FlashLight) then
        pcall(function()
            State.FlashLight:K2_SetActorLocation(Bridge.Vec(loc.X, loc.Y, loc.Z), false, {}, true)
            local lc = State.FlashLight.PointLightComponent or State.FlashLight.RootComponent
            if Logger.IsValidObj(lc) then
                if lc.SetAttenuationRadius then lc:SetAttenuationRadius(isHeavy and 440.0 or 260.0) end
                lc:SetIntensity(isHeavy and 15000.0 or 7500.0)
                lc:SetVisibility(true, true)
            end
        end)
        State.FlashTimer = isHeavy and 0.14 or 0.08
    end
end

-- =========================================================
-- UE5 Chaos Rigid-Body Physics & Pool Helpers
-- =========================================================
local function EnableChaosPhysics(comp, massKg)
    if not Logger.IsValidObj(comp) then return false end
    pcall(function() comp:SetMobility(2) end)
    pcall(function() comp:SetCollisionEnabled(3) end)
    pcall(function() comp:SetSimulatePhysics(true) end)
    local sim = false
    pcall(function() sim = (comp:IsSimulatingPhysics(Bridge.FName("None")) == true) end)
    if sim then
        pcall(function() comp:SetCollisionProfileName(Bridge.FName("PhysicsActor"), true) end)
        pcall(function() comp:SetCollisionEnabled(3) end)
        -- Players and camera pass through loose rubble, while hammer visibility traces can hit it again.
        pcall(function() comp:SetCollisionResponseToChannel(2, 1) end) -- ECC_Pawn, Overlap
        pcall(function() comp:SetCollisionResponseToChannel(3, 2) end) -- ECC_Visibility, Block
        pcall(function() comp:SetCollisionResponseToChannel(4, 1) end) -- ECC_Camera, Overlap
        pcall(function() comp:SetEnableGravity(true) end)
        pcall(function() comp:WakeAllRigidBodies() end)
        if massKg and massKg > 0 then
            pcall(function() comp:SetMassOverrideInKg(Bridge.FName("None"), massKg, true) end)
        end
    end
    return sim
end

local function DisableSiblingCollisionBlockers(comp)
    if not Logger.IsValidObj(comp) then return end
    local owner = nil
    pcall(function() owner = comp:GetOwner() end)
    if not Logger.IsValidObj(owner) then return end
    local compOrig = Bridge.GetComponentBounds(comp)
    local ownerName = string.lower(Logger.SafeName(owner))
    local isDoorContainer = ownerName:find("door", 1, true) or ownerName:find("gate", 1, true)
        or ownerName:find("cabinet", 1, true) or ownerName:find("cupboard", 1, true)
        or ownerName:find("locker", 1, true) or ownerName:find("closet", 1, true)
        or ownerName:find("chest", 1, true) or ownerName:find("window", 1, true)
    local primClass = Bridge.GetClass("/Script/Engine.PrimitiveComponent")
    if not primClass then return end
    local compAddr = Bridge.GetObjAddr(comp)
    local function HandlePart(p)
        if not Logger.IsValidObj(p) or Bridge.GetObjAddr(p) == compAddr then return end
        local hidden, hasMesh = false, false
        pcall(function()
            hidden = (p.bHiddenInGame == true) or (p.bVisible == false)
            hasMesh = Logger.IsValidObj(p.StaticMesh)
        end)
        if not hidden and hasMesh then return end
        local pname = string.lower(Logger.SafeName(p))
        if not (pname:find("collision", 1, true) or pname:find("blocker", 1, true)
            or pname:find("nav", 1, true) or ((not hasMesh) and pname:find("box", 1, true))) then
            return
        end
        if (not isDoorContainer) and compOrig then
            local po = Bridge.GetComponentBounds(p)
            if po and Bridge.Dist(po, compOrig) > 220.0 then return end
        end
        pcall(function() p:SetCollisionEnabled(0) end)
        pcall(function() p:SetCollisionResponseToAllChannels(0) end)
    end
    pcall(function()
        local parts = owner:K2_GetComponentsByClass(primClass)
        if type(parts) == "table" then
            for _, entry in ipairs(parts) do HandlePart(Bridge.ResolveObjectParam(entry)) end
        elseif parts then
            parts:ForEach(function(_, entry) HandlePart(Bridge.ResolveObjectParam(entry)) end)
        end
    end)
end

local function TryDetachProp(comp, massKg)
    local mobility, collision
    pcall(function() mobility = comp.Mobility end)
    pcall(function() collision = comp:GetCollisionEnabled() end)
    if EnableChaosPhysics(comp, massKg) then
        DisableSiblingCollisionBlockers(comp)
        return true
    end
    if collision then pcall(function() comp:SetCollisionEnabled(collision) end) end
    if mobility then pcall(function() comp:SetMobility(mobility) end) end
    return false
end

local function ApplyChaosImpulse(comp, impulseVec, hitLoc, angSpinDeg)
    if not Logger.IsValidObj(comp) then return end
    local iv = Bridge.Vec(impulseVec.X, impulseVec.Y, impulseVec.Z)
    local okAt = false
    if hitLoc then
        okAt = pcall(function()
            comp:AddVelocityChangeImpulseAtLocation(iv, Bridge.Vec(hitLoc.X, hitLoc.Y, hitLoc.Z), Bridge.FName("None"))
        end)
    end
    if not okAt then
        pcall(function() comp:AddImpulse(iv, Bridge.FName("None"), true) end)
    end
    local spin = angSpinDeg or 260.0
    pcall(function()
        comp:AddAngularImpulseInDegrees(
            Bridge.Vec((math.random() - 0.5) * 2.0 * spin, (math.random() - 0.5) * 2.0 * spin, (math.random() - 0.5) * 2.0 * spin),
            Bridge.FName("None"),
            true
        )
    end)
end

local function DisableComponentAndActor(comp)
    if not Logger.IsValidObj(comp) then return end
    pcall(function() comp:SetSimulatePhysics(false) end)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() comp:SetCollisionResponseToAllChannels(0) end)
    pcall(function() comp:SetHiddenInGame(true, false) end)
    pcall(function() comp:SetVisibility(false, false) end)
    DisableSiblingCollisionBlockers(comp)
end

local function EvictOldEntry(pool, maxCap)
    maxCap = math.max(1, math.floor(maxCap))
    while #pool >= maxCap do
        local old = table.remove(pool, 1)
        if old then
            local a = (type(old) == "table") and old.actor or old
            SafeDestroyActor(a)
        end
    end
end

local function SpawnChaosCube(pos, rot, scaleVec, matAsset, massKg, impulseVec, spinDeg, toSplinterPool)
    local world = State.World
    local cubeMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(cubeMesh) or not pos then return nil end

    local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", pos, rot and rot.Yaw or 0.0)
    if not Logger.IsValidObj(actor) then return nil end

    local comp = GetStaticMeshComp(actor)
    if not Logger.IsValidObj(comp) then
        SafeDestroyActor(actor)
        return nil
    end

    pcall(function() comp:SetMobility(2) end)
    local meshOK, assigned = pcall(function() return comp:SetStaticMesh(cubeMesh) end)
    if not meshOK or assigned == false then
        SafeDestroyActor(actor)
        return nil
    end
    local transformOK = pcall(function()
        comp:K2_SetRelativeRotation(Bridge.Rot(rot and rot.Pitch or 0.0, rot and rot.Yaw or 0.0, rot and rot.Roll or 0.0), false, {}, true)
        if comp.SetRelativeScale3D then
            comp:SetRelativeScale3D(Bridge.Vec(scaleVec.X, scaleVec.Y, scaleVec.Z))
        end
        comp:SetWorldScale3D(Bridge.Vec(scaleVec.X, scaleVec.Y, scaleVec.Z))
    end)
    if Logger.IsValidObj(matAsset) then
        pcall(function() comp:SetMaterial(0, matAsset) end)
    end

    if not transformOK or not EnableChaosPhysics(comp, massKg or 22.0) then
        SafeDestroyActor(actor)
        return nil
    end
    if impulseVec then
        ApplyChaosImpulse(comp, impulseVec, nil, spinDeg or 280.0)
    end

    if toSplinterPool then
        EvictOldEntry(State.SplinterPool, Config.HAMMER.MAX_ACTIVE_SPLINTERS or 55)
        table.insert(State.SplinterPool, { actor = actor, comp = comp, expiresAt = os.clock() + 4.5 })
    else
        EvictOldEntry(State.DebrisPool, Config.HAMMER.MAX_ACTIVE_DEBRIS or 160)
        table.insert(State.DebrisPool, { actor = actor, comp = comp, address = Bridge.GetObjAddr(comp), spawnedAt = os.clock() })
        State.ChunksSpawned = State.ChunksSpawned + 1
    end
    return actor
end

local function SpawnSplinters(origin, normal, swingDir, kind, matAsset, count, spreadCm, baseImpulse)
    if not origin then return 0 end
    local nrm = normal or { X = 0.0, Y = 0.0, Z = 1.0 }
    local dir = swingDir or { X = 1.0, Y = 0.0, Z = 0.0 }
    local darkMat = FirstValidAsset({ PATHS.MAT_WOOD_DARK, PATHS.MAT_WOOD_OLD })
    local n = 0

    for i = 1, (count or 8) do
        local jx = (math.random() - 0.5) * 2.0 * (spreadCm or 28.0)
        local jy = (math.random() - 0.5) * 2.0 * (spreadCm or 28.0)
        local jz = (math.random() - 0.5) * 2.0 * (spreadCm or 28.0)
        local pos = {
            X = origin.X + nrm.X * 14.0 + jx,
            Y = origin.Y + nrm.Y * 14.0 + jy,
            Z = origin.Z + nrm.Z * 14.0 + jz,
        }
        local rot = { Pitch = (math.random() - 0.5) * 90.0, Yaw = math.random() * 360.0, Roll = (math.random() - 0.5) * 90.0 }
        local sc
        if kind == "WOOD" or kind == "TREE" then
            sc = { X = 0.18 + math.random() * 0.22, Y = 0.05 + math.random() * 0.04, Z = 0.04 + math.random() * 0.03 }
        elseif kind == "METAL" then
            sc = { X = 0.14 + math.random() * 0.14, Y = 0.10 + math.random() * 0.10, Z = 0.03 }
        else
            sc = { X = 0.08 + math.random() * 0.10, Y = 0.08 + math.random() * 0.09, Z = 0.07 + math.random() * 0.08 }
        end

        local speed = (baseImpulse or 340.0) * (0.65 + math.random() * 0.70)
        local iv = {
            X = (dir.X * 0.50 + nrm.X * 0.50 + (math.random() - 0.5) * 0.90) * speed,
            Y = (dir.Y * 0.50 + nrm.Y * 0.50 + (math.random() - 0.5) * 0.90) * speed,
            Z = (dir.Z * 0.25 + nrm.Z * 0.30 + 0.45 + math.random() * 0.45) * speed,
        }
        local isWood = kind == "WOOD" or kind == "TREE"
        local useMat = (isWood and i % 3 == 0 and darkMat) or matAsset
        if SpawnChaosCube(pos, rot, sc, useMat, 5.0, iv, 520.0, true) then
            n = n + 1
        end
    end
    return n
end

-- =========================================================
-- In-Place Volume Grid Fracture (Zero Disappearing Objects!)
-- =========================================================
local function SampleSafeGroundZ(world, x, y, topRefZ, ignoreActors)
    local hit, info = Bridge.LineTrace(world,
        { X = x, Y = y, Z = topRefZ + 120.0 },
        { X = x, Y = y, Z = topRefZ - 420.0 },
        ignoreActors or {}, 0, false)
    if hit and info and info.ImpactPoint then
        return info.ImpactPoint.Z
    end
    return nil
end

local function FractureBoundsToChaosGrid(orig, ext, matFront, matBack, kind, impactPoint, swingDir, isHeavy, isWall, thinAxis, ignoreActors, sourceActor)
    if not orig or not ext then return 0 end
    local world = State.World
    if not Logger.IsValidObj(world) then return 0 end

    local dir = swingDir or { X = 1.0, Y = 0.0, Z = 0.0 }
    local imp = impactPoint or orig
    local woodStudyMat = FirstValidAsset({ PATHS.MAT_WOOD_OLD, PATHS.MAT_WOOD_SWAMP, PATHS.MAT_WOOD_DARK })
    local spawned = 0

    local centerImp = isHeavy and (Config.HAMMER.FRACTURE_CENTER_IMPULSE or 480.0) or 340.0
    local edgeImp   = Config.HAMMER.FRACTURE_EDGE_IMPULSE or 190.0
    -- The source remains intact until valid replacement bodies exist.
    local groundIgnore = ignoreActors
    if Logger.IsValidObj(sourceActor) then
        groundIgnore = {}
        for _, actor in ipairs(ignoreActors or {}) do table.insert(groundIgnore, actor) end
        table.insert(groundIgnore, sourceActor)
    end
    local groundZ   = SampleSafeGroundZ(world, imp.X, imp.Y, math.min(orig.Z + ext.Z, imp.Z + 80.0), groundIgnore)
        or (orig.Z - ext.Z)

    if isWall and thinAxis then
        -- Teardown-style 4x4 Wall Collapse + 4 Broken Studs, zero cell overlap & split inward/outward pile
        local wideExt = (thinAxis == "X") and ext.Y or ext.X
        local breachW = math.min(wideExt * 2.0, 245.0)
        local breachH = math.min(ext.Z * 2.0, 230.0)

        local origWide = (thinAxis == "X") and orig.Y or orig.X
        local impWide  = (thinAxis == "X") and imp.Y or imp.X
        local wCenter  = origWide
        if wideExt * 2.0 > 260.0 then
            wCenter = Bridge.Clamp(impWide, origWide - wideExt + breachW * 0.5, origWide + wideExt - breachW * 0.5)
        end

        local bottomZ = math.max(orig.Z - ext.Z, groundZ)
        local topZ    = orig.Z + ext.Z
        local zCenter = Bridge.Clamp(math.max(bottomZ + breachH * 0.5 + 4.0, imp.Z), bottomZ + breachH * 0.5 + 4.0, math.max(bottomZ + breachH * 0.5 + 4.0, topZ - breachH * 0.5))

        local cols, rows = 4, 4
        local cellW = breachW / cols
        local cellH = breachH / rows
        local maxRadius = math.max(90.0, math.sqrt((breachW * 0.5) ^ 2 + (breachH * 0.5) ^ 2))

        for r = 0, rows - 1 do
            for c = 0, cols - 1 do
                local wPos = wCenter - breachW * 0.5 + (c + 0.5) * cellW
                local chunkH = cellH * (0.68 + math.random() * 0.08)
                local chunkW = cellW * (0.68 + math.random() * 0.08)
                local thickCm = 16.0 + math.random() * 5.0
                local zPos = math.max(groundZ + chunkH * 0.5 + 6.0, zCenter - breachH * 0.5 + (r + 0.5) * cellH)

                local pos, sc
                if thinAxis == "X" then
                    pos = { X = orig.X + ((r % 2 == 0) and -12.0 or 12.0), Y = wPos, Z = zPos }
                    sc  = { X = thickCm / 100.0, Y = chunkW / 100.0, Z = chunkH / 100.0 }
                else
                    pos = { X = wPos, Y = orig.Y + ((r % 2 == 0) and -12.0 or 12.0), Z = zPos }
                    sc  = { X = chunkW / 100.0, Y = thickCm / 100.0, Z = chunkH / 100.0 }
                end

                local slabMat = (((r + c) % 2 == 0) and matFront) or (matBack or matFront)
                local dImp = Bridge.Dist(pos, imp)
                local centerWeight = Bridge.Clamp(1.0 - (dImp / maxRadius), 0.0, 1.0)
                local speed = Bridge.Lerp(edgeImp * 0.72, centerImp * 0.68, centerWeight) * (0.8 + math.random() * 0.35)
                -- Spill alternating slabs both outward toward yard/camera & inward so rubble piles right in front of breach
                local pushSign = ((r + c) % 2 == 0) and 1.0 or -0.75
                local spreadSide = (math.random() - 0.5) * 140.0
                local iv = {
                    X = dir.X * speed * pushSign + ((thinAxis == "Y") and spreadSide or 0.0),
                    Y = dir.Y * speed * pushSign + ((thinAxis == "X") and spreadSide or 0.0),
                    Z = 75.0 + math.random() * 145.0,
                }
                local rot = { Pitch = (math.random() - 0.5) * 5.0, Yaw = (math.random() - 0.5) * 6.0, Roll = (math.random() - 0.5) * 5.0 }
                if SpawnChaosCube(pos, rot, sc, slabMat, 30.0, iv, 190.0, false) then
                    spawned = spawned + 1
                end
            end
        end

        -- 4 Internal Snapped Timber Studs spilling across the rubble pile
        for sIdx = 1, (kind == "WOOD" and 4 or 0) do
            local wPos = wCenter + (sIdx - 2.5) * (breachW * 0.21)
            local zPos = math.max(groundZ + 48.0, zCenter + (math.random() - 0.5) * 60.0)
            local pos = (thinAxis == "X")
                and { X = orig.X + ((sIdx % 2 == 0) and 14.0 or -14.0), Y = wPos, Z = zPos }
                or  { X = wPos, Y = orig.Y + ((sIdx % 2 == 0) and 14.0 or -14.0), Z = zPos }
            local sc  = { X = 0.09, Y = 0.09, Z = 0.80 }
            local rot = { Pitch = (math.random() - 0.5) * 18.0, Yaw = math.random() * 180.0, Roll = (math.random() - 0.5) * 18.0 }
            local pushSign = (sIdx % 2 == 0) and 1.0 or -0.8
            local iv = { X = dir.X * 190.0 * pushSign + (math.random() - 0.5) * 110.0, Y = dir.Y * 190.0 * pushSign + (math.random() - 0.5) * 110.0, Z = 90.0 + math.random() * 110.0 }
            if SpawnChaosCube(pos, rot, sc, woodStudyMat or matFront, 18.0, iv, 240.0, false) then
                spawned = spawned + 1
            end
        end
        return spawned
    end

    -- General Prop / Door / Porch / Concrete / Furniture Grid Collapse
    local fullX = math.max(24.0, math.min(250.0, ext.X * 2.0))
    local fullY = math.max(24.0, math.min(250.0, ext.Y * 2.0))
    local fullZ = math.max(24.0, math.min(230.0, ext.Z * 2.0))

    local nx = (fullX >= fullY and fullX >= fullZ) and 3 or ((fullX > 55.0) and 2 or 1)
    local ny = (fullY >= fullX and fullY >= fullZ) and 3 or ((fullY > 55.0) and 2 or 1)
    local nz = (fullZ >= fullX and fullZ >= fullY) and 3 or ((fullZ > 55.0) and 2 or 1)
    if (nx * ny * nz) < 8 then
        if fullX >= fullY then nx = math.max(nx, 2); ny = math.max(ny, 2); nz = math.max(nz, 2)
        else ny = math.max(ny, 2); nx = math.max(nx, 2); nz = math.max(nz, 2) end
    end

    local cx = fullX / nx
    local cy = fullY / ny
    local cz = fullZ / nz
    local minRad = math.max(30.0, math.max(fullX, fullY, fullZ) * 0.55)
    local baseLiftZ = math.max(orig.Z - fullZ * 0.5, groundZ + 6.0)

    for ix = 0, nx - 1 do
        for iy = 0, ny - 1 do
            for iz = 0, nz - 1 do
                local hX = cx * 0.72
                local hY = cy * 0.72
                local hZ = math.max(14.0, cz * 0.72)
                local px = orig.X - fullX * 0.5 + (ix + 0.5) * cx
                local py = orig.Y - fullY * 0.5 + (iy + 0.5) * cy
                local pz = math.max(baseLiftZ + (iz + 0.5) * math.max(cz, hZ * 1.15), groundZ + hZ * 0.55 + 6.0)
                local pos = { X = px, Y = py, Z = pz }

                local sc = {
                    X = math.max(0.11, hX / 100.0),
                    Y = math.max(0.11, hY / 100.0),
                    Z = math.max(0.12, hZ / 100.0),
                }
                local dx, dy = px - imp.X, py - imp.Y
                local dLen = math.max(1.0, math.sqrt(dx * dx + dy * dy))
                local cWeight = Bridge.Clamp(1.0 - (Bridge.Dist(pos, imp) / minRad), 0.0, 1.0)
                local speed = Bridge.Lerp(edgeImp * 0.60, centerImp * 0.52, cWeight) * (0.75 + math.random() * 0.40)

                local iv = {
                    X = (dir.X * 0.35 + (dx / dLen) * 0.65) * speed + (math.random() - 0.5) * 65.0,
                    Y = (dir.Y * 0.35 + (dy / dLen) * 0.65) * speed + (math.random() - 0.5) * 65.0,
                    Z = 110.0 + math.random() * 145.0,
                }
                local rot = { Pitch = (math.random() - 0.5) * 6.0, Yaw = (math.random() - 0.5) * 10.0, Roll = (math.random() - 0.5) * 6.0 }
                local useMat = (((ix + iy + iz) % 3 == 0) and matBack) or matFront
                if SpawnChaosCube(pos, rot, sc, useMat, 22.0, iv, 210.0, false) then
                    spawned = spawned + 1
                end
            end
        end
    end
    return spawned
end

-- =========================================================
-- Jagged Broken Wall Cavity Framing (No Paper-Thin Edges!)
-- =========================================================
local function SpawnBreachFrame(orig, ext, thinAxis, impactPoint)
    local world = State.World
    local cubeMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    local matFrame = FirstValidAsset({ PATHS.MAT_WOOD_DARK, PATHS.MAT_WOOD_OLD, PATHS.MAT_TRIM_DARK })
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(cubeMesh) or not orig or not ext or not thinAxis then
        return 0
    end

    local imp = impactPoint or orig
    local wideExt = (thinAxis == "X") and ext.Y or ext.X
    local fullW   = wideExt * 2.0
    local origWide = (thinAxis == "X") and orig.Y or orig.X
    local bottomZ = orig.Z - ext.Z
    local topZ    = orig.Z + ext.Z

    -- Place vertical edge jambs flush at the TRUE remaining outer wall panel edges (never mid-doorway!)
    local leftW   = origWide - wideExt + 5.0
    local rightW  = origWide + wideExt - 5.0
    local botFrmZ = bottomZ
    local topFrmZ = math.min(topZ - 8.0, bottomZ + 295.0)
    local jamHScale = math.max(0.80, (topFrmZ - botFrmZ) / 100.0)
    local jamMidZ   = (topFrmZ + botFrmZ) * 0.5
    local wallSpanScale = 0.42

    local frameSpecs = {}
    for _, wPos in ipairs({ leftW, rightW }) do
        local pos = (thinAxis == "X") and { X = orig.X, Y = wPos, Z = jamMidZ } or { X = wPos, Y = orig.Y, Z = jamMidZ }
        local sc  = (thinAxis == "X") and { X = wallSpanScale, Y = 0.11, Z = jamHScale } or { X = 0.11, Y = wallSpanScale, Z = jamHScale }
        table.insert(frameSpecs, { pos = pos, rot = { Pitch = (math.random() - 0.5) * 3.0, Yaw = (math.random() - 0.5) * 4.0, Roll = (math.random() - 0.5) * 3.0 }, sc = sc })
    end

    -- Short jagged splintered horizontal stubs jutting slightly inward from LEFT & RIGHT edges + bottom sill shard (no floating bar across doorway!)
    for _, edgeSign in ipairs({ -1.0, 1.0 }) do
        local stubLen = 0.55 + math.random() * 0.25
        local wStub = (edgeSign < 0) and (leftW + stubLen * 44.0) or (rightW - stubLen * 44.0)
        local zStub = botFrmZ + 120.0 + (math.random() - 0.5) * 40.0
        local pStub = (thinAxis == "X") and { X = orig.X, Y = wStub, Z = zStub } or { X = wStub, Y = orig.Y, Z = zStub }
        local scStub = (thinAxis == "X") and { X = wallSpanScale * 0.78, Y = stubLen, Z = 0.08 } or { X = stubLen, Y = wallSpanScale * 0.78, Z = 0.08 }
        table.insert(frameSpecs, { pos = pStub, rot = { Pitch = (math.random() - 0.5) * 14.0, Yaw = (math.random() - 0.5) * 10.0, Roll = (math.random() - 0.5) * 14.0 }, sc = scStub })
    end

    for k = -1, 1 do
        local wStud = origWide + k * (fullW * 0.22) + (math.random() - 0.5) * 16.0
        local hangLen = 0.30 + math.random() * 0.22
        local pStud = (thinAxis == "X")
            and { X = orig.X + (math.random() - 0.5) * 14.0, Y = wStud, Z = topZ - hangLen * 44.0 }
            or  { X = wStud, Y = orig.Y + (math.random() - 0.5) * 14.0, Z = topZ - hangLen * 44.0 }
        table.insert(frameSpecs, {
            pos = pStud,
            rot = { Pitch = (math.random() - 0.5) * 18.0, Yaw = math.random() * 35.0, Roll = (math.random() - 0.5) * 18.0 },
            sc  = { X = 0.09, Y = 0.09, Z = hangLen },
        })
    end
    local sillPos = (thinAxis == "X") and { X = orig.X, Y = Bridge.Clamp(imp.Y, leftW + 40.0, rightW - 40.0), Z = botFrmZ + 4.0 } or { X = Bridge.Clamp(imp.X, leftW + 40.0, rightW - 40.0), Y = orig.Y, Z = botFrmZ + 4.0 }
    local sillSc  = (thinAxis == "X") and { X = wallSpanScale * 0.85, Y = 1.15, Z = 0.08 } or { X = 1.15, Y = wallSpanScale * 0.85, Z = 0.08 }
    table.insert(frameSpecs, { pos = sillPos, rot = { Pitch = 0.0, Yaw = (math.random() - 0.5) * 6.0, Roll = 0.0 }, sc = sillSc })

    local created = 0
    for _, sp in ipairs(frameSpecs) do
        EvictOldEntry(State.BreachFrames, Config.HAMMER.MAX_BREACH_FRAMES or 64)
        local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", sp.pos, sp.rot.Yaw)
        if Logger.IsValidObj(actor) then
            local comp = GetStaticMeshComp(actor)
            if Logger.IsValidObj(comp) then
                pcall(function() comp:SetMobility(2) end)
                pcall(function() comp:SetCollisionEnabled(0) end)
                pcall(function() comp:SetCollisionResponseToAllChannels(0) end)
                pcall(function() comp:SetStaticMesh(cubeMesh) end)
                if Logger.IsValidObj(matFrame) then
                    pcall(function() comp:SetMaterial(0, matFrame) end)
                end
                pcall(function()
                    actor:K2_SetActorLocationAndRotation(Bridge.Vec(sp.pos.X, sp.pos.Y, sp.pos.Z), Bridge.Rot(sp.rot.Pitch, sp.rot.Yaw, sp.rot.Roll), false, {}, true)
                    if comp.SetRelativeScale3D then comp:SetRelativeScale3D(Bridge.Vec(sp.sc.X, sp.sc.Y, sp.sc.Z)) end
                    comp:SetWorldScale3D(Bridge.Vec(sp.sc.X, sp.sc.Y, sp.sc.Z))
                end)
                table.insert(State.BreachFrames, { actor = actor })
                created = created + 1
            else
                SafeDestroyActor(actor)
            end
        end
    end
    return created
end

-- =========================================================
-- Double-Layer Wall Sandwich & Protection Resolvers
-- =========================================================
local function IsProtectedTarget(hitComp, hitActor, hitNormal, ext, origin, instanced)
    local compName = string.lower(Logger.SafeName(hitComp))
    local actName  = string.lower(Logger.SafeName(hitActor))
    local meshName = ""
    local hidden = false
    pcall(function()
        hidden = hitComp.bHiddenInGame == true or hitComp.bVisible == false or (hitActor and hitActor.bHidden == true)
        meshName = string.lower(Logger.SafeName(hitComp.StaticMesh))
    end)
    if hidden then return true, "hidden_component" end
    local actorClass = ""
    if Logger.IsValidObj(hitActor) then
        pcall(function() actorClass = string.lower(Logger.SafeName(hitActor:GetClass())) end)
    end
    local actorType = actName .. " " .. actorClass
    for _, role in ipairs({ "bp_collect_", "bp_evidence", "bp_interact_answeringmachine", "bp_interact_radiomusic",
            "bp_interact_playablepiano", "bp_interact_cordlessphone", "bp_backgate_level1" }) do
        if actorType:find(role, 1, true) then return true, "story_object" end
    end
    -- These placed doors are opened by the prologue script at specific stages.
    local doorName = actName:gsub("_%d+$", ""):gsub("_c$", "")
    if doorName == "bp_door_main" or doorName == "bp_door_main2" or doorName == "bp_door_room14_locked" then
        return true, "story_door"
    end
    local blob = compName .. " " .. actName .. " " .. meshName

    local forbidden = {
        "landscape", "heightfield", "terrain", "sky", "fog", "cloud", "water", "ocean", "river",
        "volume", "trigger", "recastnavmesh", "navmesh", "playerstart", "levelsequence",
        "bp_pickup", "pickup", "page", "note", "flashlight", "battery", "generator",
        "oaksidesign", "oaksidegate", "checkpoint", "lightcomponent", "audiocomponent",
    }
    for _, kw in ipairs(forbidden) do
        if string.find(blob, kw, 1, true) then
            return true, "protected_" .. kw
        end
    end

    if ext and hitNormal then
        local isFlatUp = math.abs(hitNormal.Z or 0) > 0.72
        if not instanced and isFlatUp and ext.X > 180.0 and ext.Y > 180.0 and ext.Z < 60.0 then
            return true, "protected_floor"
        end
        if string.find(blob, "floor", 1, true) or string.find(blob, "road", 1, true) or string.find(blob, "sidewalk", 1, true) then
            if math.max(ext.X, ext.Y) > 160.0 then
                return true, "protected_floor_name"
            end
        end
    end

    return false, nil
end

local function DetectWallThinAxis(ext, impactNormal)
    if ext then
        if ext.X < ext.Y * 0.55 then return "X" end
        if ext.Y < ext.X * 0.55 then return "Y" end
    end
    if impactNormal then
        return (math.abs(impactNormal.X or 0) >= math.abs(impactNormal.Y or 0)) and "X" or "Y"
    end
    return "X"
end

local function IsInstancedComponent(comp)
    local class = Bridge.GetClass("/Script/Engine.InstancedStaticMeshComponent")
    if class then
        local ok, instanced = pcall(function() return comp:IsA(class) end)
        if ok then return instanced end
    end
    local className = Logger.SafeFullName(comp):match("^%S+") or ""
    return className:find("InstancedStaticMesh", 1, true) ~= nil
end

local function IsVisibleMesh(comp, owner)
    if not Logger.IsValidObj(owner) or IsInstancedComponent(comp) or WallBreach.IsRemnant(comp) then return false end
    local ok, visible = pcall(function()
        return comp.bVisible ~= false and comp.bHiddenInGame ~= true and owner.bHidden ~= true
            and Logger.IsValidObj(comp.StaticMesh)
    end)
    return ok and visible
end

local function FindCoplanarWallGroup(hitComp, hitActor, orig, ext, impactPoint, impactNormal, ignore)
    local world = State.World
    if not Logger.IsValidObj(world) or not orig or not ext then return {}, {}, nil, nil end

    local thinAxis = DetectWallThinAxis(ext, impactNormal)
    local wideAxis = thinAxis == "X" and "Y" or "X"
    local widthExt, depthExt = ext[wideAxis], ext[thinAxis]
    local isCompoundShell = (math.max(ext.X, ext.Y, ext.Z) > (Config.HAMMER.GIANT_MESH_MIN_EXT or 720.0))
    if (not isCompoundShell) and (ext.Z < 55 or depthExt > math.min(68, widthExt * 0.45)) then
        return {}, {}, nil, nil
    end

    local searchOrig = isCompoundShell and (impactPoint or orig) or orig
    local searchWideExt = isCompoundShell and 130.0 or widthExt
    local searchDepthExt = isCompoundShell and 24.0 or depthExt
    local searchZExt = isCompoundShell and math.min(ext.Z, 150.0) or ext.Z

    local pairedWalls, attachedTrim, backMat = {}, {}, nil
    local seen = { [Bridge.GetObjAddr(hitComp)] = true }
    local function Consider(c)
        local addr = Bridge.GetObjAddr(c)
        if addr == 0 or seen[addr] then return end
        seen[addr] = true
        local owner = c:GetOwner()
        if not IsVisibleMesh(c, owner) or c:IsSimulatingPhysics(Bridge.FName("None")) then return end
        local co, ce = Bridge.GetComponentBounds(c)
        if not co or not ce or IsProtectedTarget(c, owner, { Z = 1 }, ce, co) then return end
        local dThin, dWide, dZ = math.abs(co[thinAxis] - searchOrig[thinAxis]), math.abs(co[wideAxis] - searchOrig[wideAxis]), math.abs(co.Z - searchOrig.Z)
        local depthTolerance = math.max(Config.HAMMER.WALL_PAIR_THIN_TOL_CM or 82, searchDepthExt + ce[thinAxis] + 48)
        if dThin > depthTolerance then return end

        local overlapsImpactWide, overlapsImpactZ
        if impactPoint then
            overlapsImpactWide = math.abs(impactPoint[wideAxis] - co[wideAxis]) <= (ce[wideAxis] + 28.0)
            overlapsImpactZ    = math.abs(impactPoint.Z - co.Z) <= (ce.Z + 28.0)
        else
            overlapsImpactWide = dWide <= searchWideExt + 35.0
            overlapsImpactZ    = dZ <= searchZExt + 35.0
        end

        -- Classify the component's mesh. Many unrelated pieces share the same house actor and plaster material.
        local name = string.lower(Logger.SafeName(c) .. " " .. Logger.SafeName(c.StaticMesh))
        local isTrim = name:find("trim", 1, true) or name:find("baseboard", 1, true) or name:find("peel", 1, true)
            or name:find("decal", 1, true) or name:find("switch", 1, true) or name:find("thermostat", 1, true)
            or name:find("painting", 1, true) or name:find("molding", 1, true) or name:find("outlet", 1, true)
        if isTrim then
            if math.max(ce.X, ce.Y, ce.Z) <= 220 and dWide <= (searchWideExt + ce[wideAxis] + 35) and dZ <= (searchZExt + ce.Z + 35) then
                if (not isCompoundShell) or Bridge.Dist(co, searchOrig) <= 320.0 then
                    table.insert(attachedTrim, { comp = c, owner = owner, blob = name, orig = co, ext = ce })
                end
            end
            return
        end
        local wallName = name:find("wall", 1, true) or name:find("siding", 1, true)
            or name:find("plaster", 1, true) or name:find("patch", 1, true)
            or name:find("drywall", 1, true) or name:find("panel", 1, true)
            or name:find("brick", 1, true) or name:find("partition", 1, true)
            or name:find("cabin", 1, true) or name:find("barn", 1, true)
            or name:find("shed", 1, true) or name:find("corrugated", 1, true)
        if not wallName or ce.Z < 55 or ce[thinAxis] > math.min(68, math.max(ce[wideAxis] * 0.48, 32)) then return end
        -- Twin back face must cover the struck impact region without engulfing neighboring upper-floor or mega structures.
        if (not overlapsImpactWide) or (not overlapsImpactZ) then return end
        if ce[wideAxis] > math.max(searchWideExt * 1.65 + 65.0, 520.0) or ce.Z > math.max(searchZExt * 1.48 + 65.0, 420.0) then return end
        local _, mat = ClassifyMaterial(c, owner)
        table.insert(pairedWalls, { comp = c, owner = owner, name = Logger.SafeName(owner), mat = mat, orig = co, ext = ce })
        if not backMat and Logger.IsValidObj(mat) then backMat = mat end
    end

    local radius = math.sqrt(searchWideExt * searchWideExt + searchZExt * searchZExt) + searchDepthExt + 55
    for _, c in ipairs(Bridge.SphereOverlapComponents(world, searchOrig, radius, ignore)) do Consider(c) end

    -- Render-only skins can have NoCollision. Query their owning blueprint without scanning every level component.
    if Logger.IsValidObj(hitActor) then
        pcall(function()
            local parts = hitActor:K2_GetComponentsByClass(Bridge.GetClass("/Script/Engine.StaticMeshComponent"))
            if type(parts) == "table" then
                for _, entry in ipairs(parts) do Consider(Bridge.ResolveObjectParam(entry)) end
            elseif parts then
                parts:ForEach(function(_, entry) Consider(Bridge.ResolveObjectParam(entry)) end)
            end
        end)
    end
    if impactPoint and impactNormal then
        local excluded = {}
        for _, actor in ipairs(ignore or {}) do table.insert(excluded, actor) end
        if Logger.IsValidObj(hitActor) then table.insert(excluded, hitActor) end
        local maxPierce = math.max(92.0, searchDepthExt * 2.0 + 58.0)
        local startPos = {
            X = impactPoint.X + impactNormal.X * 10.0,
            Y = impactPoint.Y + impactNormal.Y * 10.0,
            Z = impactPoint.Z + impactNormal.Z * 10.0,
        }
        local endPos = {
            X = impactPoint.X - impactNormal.X * maxPierce,
            Y = impactPoint.Y - impactNormal.Y * maxPierce,
            Z = impactPoint.Z - impactNormal.Z * maxPierce,
        }
        for _ = 1, 3 do
            local hit, info = Bridge.LineTrace(world, startPos, endPos, excluded, 0, false)
            if not hit or not info or not Logger.IsValidObj(info.Component) then break end
            Consider(info.Component)
            if Logger.IsValidObj(info.Actor) then
                table.insert(excluded, info.Actor)
            else
                break
            end
            if info.ImpactPoint then
                startPos = {
                    X = info.ImpactPoint.X - impactNormal.X * 4.0,
                    Y = info.ImpactPoint.Y - impactNormal.Y * 4.0,
                    Z = info.ImpactPoint.Z - impactNormal.Z * 4.0,
                }
            end
        end
    end
    return pairedWalls, attachedTrim, thinAxis, backMat
end

local function ApplyRadialShockwave(origin, radius, strength, swingDir, ignoreActors)
    if not Logger.IsValidObj(State.World) or not origin or radius <= 0 then return 0 end
    local props = Bridge.SphereOverlapComponents(State.World, origin, radius, ignoreActors)
    local seen, pushed = {}, 0
    local maxExtSmall = (Config.HAMMER.SMALL_PROP_MAX_EXT or 145) * 0.85
    local staticActorClass = Bridge.GetClass("/Script/Engine.StaticMeshActor")

    local function Push(c)
        local addr = Bridge.GetObjAddr(c)
        if addr == 0 or seen[addr] then return end
        seen[addr] = true
        local owner = c:GetOwner()
        if not IsVisibleMesh(c, owner) or c:GetCollisionEnabled() == 0 then return end
        local center, ext = Bridge.GetComponentBounds(c)
        if not center or not ext or IsProtectedTarget(c, owner, { Z = 1 }, ext, center) then return end
        local distance = Bridge.Dist(center, origin)
        if distance >= radius then return end
        if not c:IsSimulatingPhysics(Bridge.FName("None")) then
            local maxExtent = math.max(ext.X, ext.Y, ext.Z)
            if maxExtent <= 4 or maxExtent > maxExtSmall or not staticActorClass or not owner:IsA(staticActorClass) then return end
            local name = string.lower(Logger.SafeName(c) .. " " .. Logger.SafeName(c.StaticMesh))
            if name:find("wall", 1, true) or name:find("door", 1, true) or name:find("frame", 1, true)
                or name:find("floor", 1, true) or name:find("ground", 1, true) or name:find("roof", 1, true)
                or name:find("beam", 1, true) or name:find("post", 1, true) or name:find("trim", 1, true)
                or name:find("stair", 1, true) or name:find("collision", 1, true) then return end
            -- Do not pull furniture through an intact intervening wall.
            if distance > 12 then
                local traceStart = {}
                for _, axis in ipairs({ "X", "Y", "Z" }) do
                    traceStart[axis] = origin[axis] + (center[axis] - origin[axis]) * (6 / distance)
                end
                local hit, info = Bridge.LineTrace(State.World, traceStart, center, ignoreActors, 0, false)
                if hit and (not info or Bridge.GetObjAddr(info.Component) ~= addr) then return end
            end
            if not TryDetachProp(c, 22) then return end
            State.SimProps[addr] = { comp = c }
            State.DetachedCount = State.DetachedCount + 1
        end
        local remaining = 1 - distance / radius
        local speed = strength * remaining
        local inv = 1 / math.max(distance, 1)
        local impulse = {
            X = ((center.X - origin.X) * inv * 0.65 + swingDir.X * 0.35) * speed,
            Y = ((center.Y - origin.Y) * inv * 0.65 + swingDir.Y * 0.35) * speed,
            Z = ((center.Z - origin.Z) * inv * 0.25 + 0.42) * speed,
        }
        ApplyChaosImpulse(c, impulse, nil, 240 * remaining)
        pushed = pushed + 1
    end

    for _, c in ipairs(props) do Push(c) end
    return pushed
end

local function ClearSurfaceScars(address)
    if not address or address == 0 then return end
    for i = #State.Scars, 1, -1 do
        local scar = State.Scars[i]
        if scar.surface == address then
            SafeDestroyActor(scar.actor)
            table.remove(State.Scars, i)
        end
    end
end

local function TrackScar(actor, surface)
    EvictOldEntry(State.Scars, Config.HAMMER.MAX_ACTIVE_SCARS or 64)
    table.insert(State.Scars, { actor = actor, surface = surface })
end

local function SpawnStarburstCracks(hitPoint, hitNormal, surface)
    local world = State.World
    local cubeMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    local darkMat  = FirstValidAsset({ PATHS.MAT_WOOD_DARK, PATHS.MAT_EXT_STONE, PATHS.MAT_METAL_DULL })
    local woodMat  = FirstValidAsset({ PATHS.MAT_WOOD_OLD, PATHS.MAT_WOOD_SWAMP })
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(cubeMesh) or not hitPoint then return {} end

    local nrm = hitNormal or { X = 0, Y = 0, Z = 1 }
    local basePos = { X = hitPoint.X + nrm.X * 2.5, Y = hitPoint.Y + nrm.Y * 2.5, Z = hitPoint.Z + nrm.Z * 2.5 }
    local baseRot = Bridge.RotatorFromVec(nrm.X, nrm.Y, nrm.Z)
    local created = {}

    -- 5 Radiating Jagged Starburst Fracture Cracks
    local angles = { 0.0, 34.0, -38.0, 74.0, -76.0 }
    for idx, ang in ipairs(angles) do
        local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", basePos, baseRot.Yaw)
        if Logger.IsValidObj(actor) then
            local comp = GetStaticMeshComp(actor)
            if Logger.IsValidObj(comp) then
                pcall(function() comp:SetMobility(2) end)
                pcall(function() comp:SetCollisionEnabled(0) end)
                pcall(function() comp:SetStaticMesh(cubeMesh) end)
                if Logger.IsValidObj(darkMat) then pcall(function() comp:SetMaterial(0, darkMat) end) end
                local scZ = (idx == 1) and 0.95 or (0.55 + math.random() * 0.42)
                local scY = 0.055 + math.random() * 0.035
                pcall(function()
                    actor:K2_SetActorLocationAndRotation(Bridge.Vec(basePos.X, basePos.Y, basePos.Z), Bridge.Rot(baseRot.Pitch, baseRot.Yaw, ang), false, {}, true)
                    if comp.SetRelativeScale3D then comp:SetRelativeScale3D(Bridge.Vec(0.04, scY, scZ)) end
                    comp:SetWorldScale3D(Bridge.Vec(0.04, scY, scZ))
                end)
                TrackScar(actor, surface)
                table.insert(created, actor)
            else
                SafeDestroyActor(actor)
            end
        end
    end

    -- 3 Protruding Wood Splinters poking outward from the crack
    for _ = 1, 3 do
        local p = { X = basePos.X + (math.random() - 0.5) * 16.0, Y = basePos.Y + (math.random() - 0.5) * 16.0, Z = basePos.Z + (math.random() - 0.5) * 24.0 }
        local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", p, baseRot.Yaw)
        if Logger.IsValidObj(actor) then
            local comp = GetStaticMeshComp(actor)
            if Logger.IsValidObj(comp) then
                pcall(function() comp:SetMobility(2) end)
                pcall(function() comp:SetCollisionEnabled(0) end)
                pcall(function() comp:SetStaticMesh(cubeMesh) end)
                if Logger.IsValidObj(woodMat) then pcall(function() comp:SetMaterial(0, woodMat) end) end
                pcall(function()
                    actor:K2_SetActorLocationAndRotation(
                        Bridge.Vec(p.X, p.Y, p.Z),
                        Bridge.Rot(baseRot.Pitch + (math.random() - 0.5) * 35.0, baseRot.Yaw + (math.random() - 0.5) * 35.0, math.random() * 90.0),
                        false, {}, true
                    )
                    comp:SetWorldScale3D(Bridge.Vec(0.28 + math.random() * 0.16, 0.04, 0.03))
                end)
                TrackScar(actor, surface)
                table.insert(created, actor)
            else
                SafeDestroyActor(actor)
            end
        end
    end

    return created
end

-- =========================================================
-- Aim Trace & Core 5-Tier Destruction Resolver
-- =========================================================
local function BuildIgnoreList(slender, survivor)
    local ignore = {}
    if Logger.IsValidObj(slender)  then table.insert(ignore, slender)  end
    if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end
    if Logger.IsValidObj(State.FlashLight) then table.insert(ignore, State.FlashLight) end
    for _, p in ipairs(State.Parts) do
        if Logger.IsValidObj(p) then table.insert(ignore, p) end
    end
    for _, s in ipairs(State.Scars) do
        if Logger.IsValidObj(s.actor) then table.insert(ignore, s.actor) end
    end
    for _, splinter in ipairs(State.SplinterPool) do
        if Logger.IsValidObj(splinter.actor) then table.insert(ignore, splinter.actor) end
    end
    for _, bf in ipairs(State.BreachFrames) do
        if bf and Logger.IsValidObj(bf.actor) then table.insert(ignore, bf.actor) end
    end
    return ignore
end

local function IsInvisibleBlockerComponent(comp, actor)
    if not Logger.IsValidObj(comp) or IsInstancedComponent(comp) or WallBreach.IsRemnant(comp) then
        return false
    end
    local hidden, hasMesh = false, false
    pcall(function()
        hidden = (comp.bHiddenInGame == true) or (comp.bVisible == false)
        if actor and actor.bHidden == true then hidden = true end
        hasMesh = Logger.IsValidObj(comp.StaticMesh)
    end)
    if hidden then return true end
    if not hasMesh then
        local cname = string.lower(Logger.SafeName(comp))
        if cname:find("box", 1, true) or cname:find("collision", 1, true)
            or cname:find("blocker", 1, true) or cname:find("capsule", 1, true)
            or cname:find("sphere", 1, true) or cname:find("trigger", 1, true) then
            return true
        end
    end
    return false
end

local function FindSiblingVisibleHit(actor, startPos, endPos, impactPt, ignoreComp)
    if not Logger.IsValidObj(actor) then return nil end
    local smClass = Bridge.GetClass("/Script/Engine.StaticMeshComponent")
    if not smClass then return nil end
    local ignoreAddr = Bridge.GetObjAddr(ignoreComp)
    local bestComp, bestDist, bestLoc, bestNrm = nil, 999999.0, nil, nil
    local function CheckPart(c)
        if not Logger.IsValidObj(c) or Bridge.GetObjAddr(c) == ignoreAddr then return end
        if not IsVisibleMesh(c, actor) then return end
        local colEn = 0
        pcall(function() colEn = tonumber(c:GetCollisionEnabled()) or 0 end)
        if colEn == 0 then return end
        local hl, hn, outHit = {}, {}, {}
        local ok, didHit = pcall(function()
            return c:K2_LineTraceComponent(
                Bridge.Vec(startPos.X, startPos.Y, startPos.Z),
                Bridge.Vec(endPos.X, endPos.Y, endPos.Z),
                false, false, false, hl, hn, {}, outHit
            )
        end)
        if ok and didHit then
            local loc = (hl and hl.X) and { X = hl.X, Y = hl.Y, Z = hl.Z }
                or (outHit and outHit.ImpactPoint and { X = outHit.ImpactPoint.X, Y = outHit.ImpactPoint.Y, Z = outHit.ImpactPoint.Z })
                or impactPt
            local d = loc and Bridge.Dist(startPos, loc) or 999999.0
            if d < bestDist then
                bestDist = d
                bestComp = c
                bestLoc = loc
                bestNrm = (hn and hn.X) and { X = hn.X, Y = hn.Y, Z = hn.Z } or nil
            end
        end
    end
    pcall(function()
        local parts = actor:K2_GetComponentsByClass(smClass)
        if type(parts) == "table" then
            for _, entry in ipairs(parts) do CheckPart(Bridge.ResolveObjectParam(entry)) end
        elseif parts then
            parts:ForEach(function(_, entry) CheckPart(Bridge.ResolveObjectParam(entry)) end)
        end
    end)
    if bestComp then
        return {
            Actor = actor,
            Component = bestComp,
            ImpactPoint = bestLoc or impactPt,
            ImpactNormal = bestNrm,
            Distance = bestDist,
        }
    end
    return nil
end

local function TracePastInvisibleBlockers(world, startPos, endPos, ignore)
    local localIgnore = {}
    for _, a in ipairs(ignore or {}) do localIgnore[#localIgnore + 1] = a end
    for _ = 1, 5 do
        local hit, info = Bridge.LineTrace(world, startPos, endPos, localIgnore, 0, false)
        if not hit or not info or not Logger.IsValidObj(info.Component) then
            return hit, info
        end
        if not IsInvisibleBlockerComponent(info.Component, info.Actor) then
            return hit, info
        end
        local siblingInfo = FindSiblingVisibleHit(info.Actor, startPos, endPos, info.ImpactPoint, info.Component)
        if siblingInfo then
            siblingInfo.ImpactNormal = siblingInfo.ImpactNormal or info.ImpactNormal
            return true, siblingInfo
        end
        if Logger.IsValidObj(info.Actor) then
            table.insert(localIgnore, info.Actor)
        else
            return hit, info
        end
    end
    return false, nil
end

local function ResolveAimHit(world, slender, survivor, camCtrl, reachCm, overrideRay)
    local slLoc = Bridge.GetActorLoc(slender) or { X = 0, Y = 0, Z = 100 }
    local camPos, camRot, _ = nil, nil, nil
    if camCtrl and camCtrl.GetViewTransform then
        camPos, camRot, _ = camCtrl.GetViewTransform()
    end

    local traceStart, traceFwd
    local fromCamera = false
    if overrideRay and overrideRay.pos and overrideRay.fwd then
        traceStart = overrideRay.pos
        traceFwd   = overrideRay.fwd
    elseif camPos and camRot then
        fromCamera = true
        local fx, fy, fz = Bridge.ForwardFromRot(camRot.Pitch, camRot.Yaw)
        traceFwd = { X = fx, Y = fy, Z = fz }
        local startDist = math.max(90.0, Bridge.Dist(camPos, slLoc) - 45.0)
        traceStart = {
            X = camPos.X + fx * startDist,
            Y = camPos.Y + fy * startDist,
            Z = camPos.Z + fz * startDist,
        }
    else
        local yaw = camCtrl and camCtrl.GetYaw and camCtrl.GetYaw() or 0.0
        local fx, fy, fz = Bridge.ForwardFromRot(-8.0, yaw)
        traceFwd   = { X = fx, Y = fy, Z = fz }
        traceStart = { X = slLoc.X, Y = slLoc.Y, Z = slLoc.Z + 80.0 }
    end

    local ignore = BuildIgnoreList(slender, survivor)
    local endPos = {
        X = traceStart.X + traceFwd.X * reachCm,
        Y = traceStart.Y + traceFwd.Y * reachCm,
        Z = traceStart.Z + traceFwd.Z * reachCm,
    }
    local hit, info = TracePastInvisibleBlockers(world, traceStart, endPos, ignore)

    if not hit then
        local yaw = camRot and camRot.Yaw or (camCtrl and camCtrl.GetYaw and camCtrl.GetYaw() or 0.0)
        local rx, ry, _ = Bridge.RightFromYaw(yaw)
        local offsets = {
            { X = rx * 28.0,  Y = ry * 28.0,  Z = -12.0 },
            { X = -rx * 28.0, Y = -ry * 28.0, Z = -12.0 },
            { X = 0.0,        Y = 0.0,        Z = -48.0 },
        }
        for _, off in ipairs(offsets) do
            local eAlt = { X = endPos.X + off.X, Y = endPos.Y + off.Y, Z = endPos.Z + off.Z }
            local h2, i2 = TracePastInvisibleBlockers(world, traceStart, eAlt, ignore)
            if h2 and i2 then
                hit, info = h2, i2
                break
            end
        end
    end

    if fromCamera then
        -- The shoulder camera selects a point. The hammer must reach it from the character's side of any cover.
        local chest = { X = slLoc.X, Y = slLoc.Y, Z = slLoc.Z + 80.0 }
        local aimPoint = (hit and info and info.ImpactPoint) or endPos
        local bodyHit, bodyInfo = TracePastInvisibleBlockers(world, chest, aimPoint, ignore)
        if bodyHit then hit, info = bodyHit, bodyInfo end
    end

    if hit and info and info.ImpactPoint then
        local maxSlReach = Config.HAMMER.MAX_SLENDER_REACH_CM or 640.0
        if Bridge.Dist(slLoc, info.ImpactPoint) <= maxSlReach then
            return true, info, traceFwd, ignore
        end
    end

    return false, nil, traceFwd, ignore
end

local function PerformHammerImpact(isHeavy, world, slender, survivor, camCtrl, humanFear, overrideRay)
    local slLoc = Bridge.GetActorLoc(slender) or { X = 0, Y = 0, Z = 100 }
    local reach = Config.HAMMER.REACH_CM or 460.0
    local hit, info, swingDir, ignore = ResolveAimHit(world, slender, survivor, camCtrl, reach, overrideRay)

    -- Survivor melee shock
    if Logger.IsValidObj(survivor) and humanFear then
        local survLoc = Bridge.GetActorLoc(survivor)
        if survLoc then
            local sDist = Bridge.Dist(slLoc, survLoc)
            local hitPointDist = (hit and info and info.ImpactPoint) and Bridge.Dist(info.ImpactPoint, survLoc) or 9999.0
            if sDist <= 285.0 or (isHeavy and hitPointDist <= (Config.HAMMER.HEAVY_RADIUS_CM or 340.0)) then
                local spike = isHeavy and (Config.HAMMER.SURVIVOR_HEAVY_FEAR or 38.0) or (Config.HAMMER.SURVIVOR_HIT_FEAR or 26.0)
                if humanFear.ApplyTerrifySpike then
                    humanFear.ApplyTerrifySpike(spike)
                    Logger.Info(string.format("HammerMgr: Shocked Survivor (+%.1f fear, dist=%.0fcm)", spike, sDist))
                end
            end
        end
    end

    -- The swing already played its movement sound. All impact effects need contact.
    if not hit or not info or not info.ImpactPoint or not Logger.IsValidObj(info.Component) then return end
    local impactLoc = info.ImpactPoint
    local impactNrm = info.ImpactNormal or { X = -swingDir.X, Y = -swingDir.Y, Z = -swingDir.Z }

    local hitComp  = info.Component
    local hitActor = info.Actor
    local compAddr = Bridge.GetObjAddr(hitComp)
    local kind, debrisMat, blob = ClassifyMaterial(hitComp, hitActor)
    local orig, ext, _ = Bridge.GetComponentBounds(hitComp)

    -- Impact feel: Hit-Stop + Sound + Flash + Camera Shake
    State.HitStopTimer = isHeavy and (Config.HAMMER.HITSTOP_HEAVY_SEC or 0.065) or (Config.HAMMER.HITSTOP_LIGHT_SEC or 0.04)
    TriggerImpactFlash(impactLoc, isHeavy)
    if camCtrl and camCtrl.AddImpactShake then
        camCtrl.AddImpactShake(
            isHeavy and (Config.HAMMER.SHAKE_HEAVY_CM or 18.0) or (Config.HAMMER.SHAKE_LIGHT_CM or 7.0),
            Config.HAMMER.SHAKE_DURATION or 0.24
        )
    end

    -- Protected actors and instanced meshes must be resolved before touching shared physics state.
    local instanced = IsInstancedComponent(hitComp)
    local isProt, protReason = IsProtectedTarget(hitComp, hitActor, impactNrm, ext, orig, instanced)
    if isProt then
        PlayImpactSound(impactLoc, kind, isHeavy, isHeavy)
        SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, isHeavy and 12 or 7, 36.0, isHeavy and 440.0 or 260.0)
        if isHeavy then
            SpawnStarburstCracks(impactLoc, impactNrm)
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Protected crater on %s (%s)", Logger.SafeName(hitComp), tostring(protReason)))
        return
    end

    if instanced then
        local idx = tonumber(info.Item)
        local ok, count = pcall(function() return hitComp:GetInstanceCount() end)
        if not idx or idx % 1 ~= 0 or idx < 0 or not ok or type(count) ~= "number" or idx >= count then
            PlayImpactSound(impactLoc, kind, isHeavy, false)
            return
        end
        local treeMesh = string.lower(Logger.SafeName(hitComp.StaticMesh))
        local hasTrunk = treeMesh:find("tree", 1, true) or treeMesh:find("pine", 1, true)
            or treeMesh:find("conifer", 1, true) or treeMesh:find("birch", 1, true)
            or treeMesh:find("spruce", 1, true) or treeMesh:find("trunk", 1, true)
        local removed, success = pcall(function() return hitComp:RemoveInstance(idx) end)
        if not removed or not success then
            PlayImpactSound(impactLoc, kind, isHeavy, false)
            return
        end
        local impactKind = hasTrunk and "TREE" or kind
        if not hasTrunk and kind == "TREE" and (treeMesh:find("rock", 1, true) or treeMesh:find("stone", 1, true)) then
            impactKind = "STONE"
        end
        PlayImpactSound(impactLoc, impactKind, isHeavy, true)
        local treeLogs = 0
        if hasTrunk then
            local cylMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CYLINDER)
            local barkMat = FirstValidAsset({ PATHS.MAT_BARK, PATHS.MAT_WOOD_DARK })
            for logIdx = 1, (isHeavy and 4 or 3) do
                if not Logger.IsValidObj(cylMesh) then break end
                local pos = { X = impactLoc.X, Y = impactLoc.Y, Z = impactLoc.Z + (logIdx - 1) * 92 }
                local log = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", pos, math.random() * 360)
                local comp = GetStaticMeshComp(log)
                local valid = Logger.IsValidObj(comp) and pcall(function()
                    comp:SetMobility(2)
                    if not comp:SetStaticMesh(cylMesh) and not Logger.IsValidObj(comp.StaticMesh) then error("missing trunk mesh") end
                    comp:SetWorldScale3D(Bridge.Vec(0.24, 0.24, 0.85))
                    if Logger.IsValidObj(barkMat) then comp:SetMaterial(0, barkMat) end
                end)
                if valid and EnableChaosPhysics(comp, 34) then
                    EvictOldEntry(State.DebrisPool, Config.HAMMER.MAX_ACTIVE_DEBRIS or 160)
                    ApplyChaosImpulse(comp, { X = swingDir.X * 260, Y = swingDir.Y * 260, Z = 160 + logIdx * 40 }, nil, 180)
                    table.insert(State.DebrisPool, { actor = log, comp = comp, address = Bridge.GetObjAddr(comp), spawnedAt = os.clock() })
                    State.ChunksSpawned = State.ChunksSpawned + 1
                    treeLogs = treeLogs + 1
                else
                    SafeDestroyActor(log)
                end
            end
        end
        SpawnSplinters(impactLoc, impactNrm, swingDir, impactKind, debrisMat, isHeavy and 12 or 8, 36, 380)
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680, swingDir, ignore)
        end
        State.DestroyedCount = State.DestroyedCount + 1
        Logger.Info(string.format("HammerMgr: Broke instance %d of %s (%d trunk logs)", idx, treeMesh, treeLogs))
        return
    end

    -- Tier 0: Already-simulating Chaos Rigid Body (GMod prop OR collapsed Teardown chunk) -> bat or shatter in place!
    local isAlreadySim = false
    pcall(function() isAlreadySim = (hitComp:IsSimulatingPhysics(Bridge.FName("None")) == true) end)
    if isAlreadySim then
        PlayImpactSound(impactLoc, kind, isHeavy, isHeavy)
        if isHeavy then
            -- A second blow reduces a loose chunk to grit instead of making larger chunks from it.
            for i, piece in ipairs(State.DebrisPool) do
                if compAddr ~= 0 and (piece.address or Bridge.GetObjAddr(piece.comp)) == compAddr then
                    local dust = SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 4, 12.0, 220.0)
                    if dust > 0 then
                        SafeDestroyActor(piece.actor)
                        table.remove(State.DebrisPool, i)
                    end
                    return
                end
            end
            local gridCount = FractureBoundsToChaosGrid(orig or impactLoc, ext or { X = 35, Y = 35, Z = 35 }, debrisMat, debrisMat, kind, impactLoc, swingDir, true, false, nil, ignore, hitActor)
            if gridCount == 0 then return end
            DisableComponentAndActor(hitComp)
            State.SimProps[compAddr] = nil
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 10, 28.0, 440.0)
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
            State.DestroyedCount = State.DestroyedCount + 1
            Logger.Info(string.format("HammerMgr: Shattered Chaos prop %s into %d solid pieces", Logger.SafeName(hitComp), gridCount))
        else
            local imp = Config.HAMMER.LIGHT_IMPULSE or 560.0
            ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = math.max(140.0, swingDir.Z * imp + 180.0) }, impactLoc, 340.0)
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 6, 18.0, 320.0)
            Logger.Info("HammerMgr: Batted Chaos prop " .. Logger.SafeName(hitComp))
        end
        return
    end

    local maxExt = ext and math.max(ext.X, ext.Y, ext.Z) or 120.0
    local isTrimOrProp = string.find(blob, "trim", 1, true) or string.find(blob, "chair", 1, true)
        or string.find(blob, "table", 1, true) or string.find(blob, "crate", 1, true)
        or string.find(blob, "plank", 1, true) or string.find(blob, "bench", 1, true)
        or string.find(blob, "shelf", 1, true) or string.find(blob, "cabinet", 1, true)
        or string.find(blob, "fence", 1, true) or string.find(blob, "barrel", 1, true)
        or string.find(blob, "bed", 1, true) or string.find(blob, "sofa", 1, true)
    local isWallLike = (not isTrimOrProp) and (
        string.find(blob, "wall", 1, true) or string.find(blob, "siding", 1, true)
        or string.find(blob, "drywall", 1, true) or string.find(blob, "cabin", 1, true)
        or string.find(blob, "porch", 1, true) or string.find(blob, "roof", 1, true)
        or string.find(blob, "pillar", 1, true) or string.find(blob, "brick", 1, true)
        or string.find(blob, "concrete", 1, true) or string.find(blob, "shed", 1, true)
        or string.find(blob, "patch", 1, true)
    )
    local isDoorOrWindow = (not isWallLike) and (
        string.find(blob, "door", 1, true) or string.find(blob, "window", 1, true)
        or string.find(blob, "glass", 1, true) or string.find(blob, "shutter", 1, true)
    )

local function DetachOrDisableTrims(attachedTrim, swingDir)
    if type(attachedTrim) ~= "table" then return 0 end
    local count = 0
    for _, at in ipairs(attachedTrim) do
        local isDecalOrPeel = string.find(at.blob, "peel", 1, true) or string.find(at.blob, "decal", 1, true)
        if not isDecalOrPeel and TryDetachProp(at.comp, 14.0) then
            local tAddr = Bridge.GetObjAddr(at.comp)
            if tAddr ~= 0 then State.SimProps[tAddr] = { comp = at.comp } end
            ApplyChaosImpulse(at.comp, { X = swingDir.X * 260.0 + (math.random() - 0.5) * 140.0, Y = swingDir.Y * 260.0 + (math.random() - 0.5) * 140.0, Z = 160.0 }, at.orig, 260.0)
            State.DetachedCount = State.DetachedCount + 1
        else
            DisableComponentAndActor(at.comp)
        end
        count = count + 1
    end
    return count
end

    -- Broad upright panels retain their solid sides and lintel around a local opening.
    local panel = WallBreach.Describe(hitComp, orig, impactNrm, blob)
    if panel then
        local oldKind, oldMat = WallBreach.Material(hitComp)
        kind, debrisMat = oldKind or kind, oldMat or debrisMat
        local isRemnant = WallBreach.IsRemnant(hitComp)
        local rec = State.Cracked[compAddr]
        if (not isHeavy) and (not isRemnant) and compAddr ~= 0 then
            if not rec then
                rec = {hp = Config.HAMMER.WALL_CRACKS_TO_BREAK or 2, comp = hitComp}
                State.Cracked[compAddr] = rec
            end
            rec.hp = math.max(0, rec.hp - 1)
            if rec.hp > 0 then
                local scarList = SpawnStarburstCracks(impactLoc, impactNrm, compAddr)
                PlayImpactSound(impactLoc, kind, false, false)
                SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 6, 18, 280)
                Logger.Info(string.format("HammerMgr: Cracked wall %s (starburst scars=%d, remaining=%d)", Logger.SafeName(hitComp), #scarList, rec.hp))
                return
            end
        end
        local cut, layers, breachTrims = WallBreach.Open(world, hitComp, panel, impactLoc, impactNrm,
            debrisMat, kind, isHeavy, ignore, ClassifyMaterial, IsProtectedTarget)
        if cut then
            local chunks = 0
            local rows, cols = isHeavy and 3 or 2, isHeavy and 4 or 3
            local w, h = cut.width / cols, cut.height / rows
            for row = 1, rows do
                for col = 1, cols do
                    local u = (col - 0.5) * w - cut.width/2
                    local z = (row - 0.5) * h - cut.height/2
                    local pos = Bridge.Vec(cut.center.X + u*cut.ux, cut.center.Y + u*cut.uy, cut.center.Z + z)
                    local scale = Bridge.Vec(w*0.0085, math.min(24, cut.depth)*0.0085, h*0.0085)
                    local speed = (isHeavy and 260 or 160) * (0.75 + math.random()*0.45)
                    local impulse = Bridge.Vec(swingDir.X*speed + cut.ux*u, swingDir.Y*speed + cut.uy*u, 90 + math.random()*90)
                    local pieceMat = layers[(chunks % #layers)+1].mat or debrisMat
                    if SpawnChaosCube(pos, Bridge.Rot(0,cut.yaw,0), scale, pieceMat, 16, impulse, 160, false) then
                        chunks = chunks + 1
                    end
                end
            end
            for _, layer in ipairs(layers) do
                ClearSurfaceScars(layer.id)
                State.Cracked[layer.id] = nil
                DisableSiblingCollisionBlockers(layer.comp)
            end
            local trimsCut = DetachOrDisableTrims(breachTrims, swingDir)
            State.DestroyedCount = State.DestroyedCount + 1
            State.PairedWallsBroken = State.PairedWallsBroken + #layers - 1
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, isHeavy and 9 or 5, 22, 320)
            PlayImpactSound(impactLoc, kind, isHeavy, true)
            if isHeavy then
                ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680, swingDir, ignore)
            end
            Logger.Info(string.format("HammerMgr: Local breach %.0f x %.0f cm (layers=%d, trims=%d, chunks=%d)",
                cut.width, cut.height, #layers, trimsCut, chunks))
            return
        end
        -- If local doorway cutting failed (e.g. cutout window mesh or remnant pool cap), fall through to full collapse instead of becoming unbreakable.
    end

    -- Giant natural terrain/rocks remain surface-carved, while multi-wall building shells (<=2200cm) can be breached.
    local isGiantEnv = string.find(blob, "rock", 1, true) or string.find(blob, "cliff", 1, true)
        or string.find(blob, "mountain", 1, true) or string.find(blob, "boulder", 1, true)
        or string.find(blob, "terrain", 1, true) or string.find(blob, "landscape", 1, true)
        or string.find(blob, "ground", 1, true) or string.find(blob, "road", 1, true)
        or string.find(blob, "hill", 1, true) or string.find(blob, "cave", 1, true)
        or string.find(blob, "floor", 1, true)
    local isStructuralShell = (not isGiantEnv) and (maxExt <= 2200.0) and (
        isWallLike
        or string.find(blob, "house", 1, true) or string.find(blob, "building", 1, true)
        or string.find(blob, "barn", 1, true) or string.find(blob, "fence", 1, true)
        or string.find(blob, "wood", 1, true) or string.find(blob, "panel", 1, true)
        or string.find(blob, "plaster", 1, true) or string.find(blob, "metal", 1, true)
    )
    if maxExt > (Config.HAMMER.GIANT_MESH_MIN_EXT or 720.0) and (not isStructuralShell) then
        PlayImpactSound(impactLoc, kind, isHeavy, isHeavy)
        SpawnStarburstCracks(impactLoc, impactNrm)
        local nChunks = isHeavy and 10 or 5
        for _ = 1, nChunks do
            local p = { X = impactLoc.X + impactNrm.X * 18.0 + (math.random() - 0.5) * 45.0, Y = impactLoc.Y + impactNrm.Y * 18.0 + (math.random() - 0.5) * 45.0, Z = impactLoc.Z + impactNrm.Z * 18.0 + (math.random() - 0.5) * 45.0 }
            local s = 0.22 + math.random() * 0.24
            SpawnChaosCube(p, { Pitch = math.random() * 90, Yaw = math.random() * 360, Roll = math.random() * 90 }, { X = s, Y = s, Z = s * 0.8 }, debrisMat, 18.0,
                { X = (swingDir.X * 0.4 + impactNrm.X * 0.6) * 320.0, Y = (swingDir.Y * 0.4 + impactNrm.Y * 0.6) * 320.0, Z = 180.0 + math.random() * 140.0 }, 340.0, false)
        end
        SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 10, 42.0, 420.0)
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Carved giant surface %s (ext=%.0f)", Logger.SafeName(hitComp), maxExt))
        return
    end

    -- Tier 3: Doors & Windows -> Hinge Chaos Detach on Light, In-Place Splinter Grid Collapse on Heavy or Non-Sim!
    if isDoorOrWindow then
        PlayImpactSound(impactLoc, kind, isHeavy, true)
        local detached = false
        if (not isHeavy) and maxExt <= (Config.HAMMER.MEDIUM_PROP_MAX_EXT or 420.0) and kind ~= "GLASS" then
            detached = TryDetachProp(hitComp, 38.0)
        end
        if detached then
            local imp = Config.HAMMER.LIGHT_IMPULSE or 560.0
            ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = 180.0 }, impactLoc, 340.0)
            if compAddr ~= 0 then State.SimProps[compAddr] = { comp = hitComp } end
            State.DetachedCount = State.DetachedCount + 1
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 8, 28.0, 380.0)
        else
            local chunks = FractureBoundsToChaosGrid(orig or impactLoc, ext or { X = 45, Y = 45, Z = 100 }, debrisMat, FallbackMaterialFor(kind, blob), kind, impactLoc, swingDir, isHeavy, false, nil, ignore, hitActor)
            if chunks == 0 then return end
            DisableComponentAndActor(hitComp)
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 10, 36.0, 420.0)
            State.DestroyedCount = State.DestroyedCount + 1
        end
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Smashed door/window %s (detached=%s)", Logger.SafeName(hitComp), tostring(detached)))
        return
    end

    -- Check Props vs Modular Walls & Heavy Structures
    -- (isTrimOrProp and isWallLike already computed above so wall_*_doorNarrow meshes never misroute as doors!)

    -- Tier 4: Standalone Props -> GMod Chaos Rigid-Body Detach (LMB) OR Proportional In-Place Grid Shatter (RMB / Fallback)
    if (not isWallLike) and maxExt <= (Config.HAMMER.MEDIUM_PROP_MAX_EXT or 420.0) then
        if (not isHeavy) and maxExt <= (Config.HAMMER.SMALL_PROP_MAX_EXT or 145.0) then
            local detached = TryDetachProp(hitComp, math.max(14.0, maxExt * 0.35))
            if detached then
                PlayImpactSound(impactLoc, kind, false, false)
                local imp = Config.HAMMER.LIGHT_IMPULSE or 560.0
                ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = 190.0 }, impactLoc, 340.0)
                if compAddr ~= 0 then State.SimProps[compAddr] = { comp = hitComp } end
                State.DetachedCount = State.DetachedCount + 1
                SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 7, 24.0, 320.0)
                Logger.Info(string.format("HammerMgr: GMod Chaos-detached %s (ext=%.0f)", Logger.SafeName(hitComp), maxExt))
                return
            end
        end

        -- Shatter prop cleanly IN PLACE into interlocking solid pieces matching its exact volume!
        PlayImpactSound(impactLoc, kind, isHeavy, true)
        local gridChunks = FractureBoundsToChaosGrid(orig or impactLoc, ext or { X = 40, Y = 40, Z = 40 }, debrisMat, FallbackMaterialFor(kind, blob), kind, impactLoc, swingDir, isHeavy, false, nil, ignore, hitActor)
        if gridChunks == 0 then return end
        DisableComponentAndActor(hitComp)
        SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 10, 34.0, 420.0)
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
        end
        State.DestroyedCount = State.DestroyedCount + 1
        Logger.Info(string.format("HammerMgr: Shattered prop %s in-place into %d grid chunks", Logger.SafeName(hitComp), gridChunks))
        return
    end

    -- Tier 5: Modular Walls & Heavy Structures -> Starburst Crack (LMB Hit 1) -> Full Double-Layer Breach + Framing + 4x4 Collapse!
    local rec = (compAddr ~= 0) and State.Cracked[compAddr] or nil
    if (not isHeavy) and (isWallLike or isStructuralShell) then
        if not rec then
            rec = { hp = (Config.HAMMER.WALL_CRACKS_TO_BREAK or 2) - 1, comp = hitComp }
            if compAddr ~= 0 then State.Cracked[compAddr] = rec end
        else
            rec.hp = rec.hp - 1
        end
        if rec.hp > 0 then
            PlayImpactSound(impactLoc, kind, false, false)
            local scarList = SpawnStarburstCracks(impactLoc, impactNrm, compAddr)
            SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, 9, 32.0, 360.0)
            Logger.Info(string.format("HammerMgr: Cracked wall %s (starburst scars=%d, remaining=%d)", Logger.SafeName(hitComp), #scarList, rec.hp))
            return
        end
    end

    -- Full Wall / Structure Collapse
    PlayImpactSound(impactLoc, kind, isHeavy, true)

    -- 1. Resolve Coplanar Paired Wall Sandwich + Attached Trims BEFORE hiding hitComp!
    local pairedWalls, attachedTrim, thinAxis, backMat = {}, {}, nil, nil
    if ext and (isWallLike or isStructuralShell or string.find(blob, "wall", 1, true)
        or string.find(blob, "siding", 1, true) or string.find(blob, "drywall", 1, true)
        or string.find(blob, "patch", 1, true) or string.find(blob, "plaster", 1, true)) then
        pairedWalls, attachedTrim, thinAxis, backMat = FindCoplanarWallGroup(hitComp, hitActor, orig, ext, impactLoc, impactNrm, ignore)
    end

    local fractureOrig = orig or impactLoc
    local fractureExt  = ext or { X = 120, Y = 20, Z = 120 }
    if maxExt > 450.0 and orig and ext then
        thinAxis = thinAxis or DetectWallThinAxis(nil, impactNrm)
        local wideAxis = (thinAxis == "X") and "Y" or "X"
        local halfZ = math.min(ext.Z, 130.0)
        fractureOrig = {
            X = impactLoc.X,
            Y = impactLoc.Y,
            Z = Bridge.Clamp(impactLoc.Z, orig.Z - ext.Z + halfZ, orig.Z + ext.Z - halfZ),
        }
        fractureExt = {
            [thinAxis] = 16.0,
            [wideAxis] = 120.0,
            Z = halfZ,
        }
    end

    local isUprightWall = (thinAxis ~= nil and fractureExt and fractureExt.Z >= 75.0)
    local wallChunks = FractureBoundsToChaosGrid(fractureOrig, fractureExt, debrisMat, backMat or FallbackMaterialFor(kind, "wall_in"), kind, impactLoc, swingDir, isHeavy, isUprightWall, thinAxis, ignore, hitActor)
    if wallChunks == 0 then return end
    ClearSurfaceScars(compAddr)
    if compAddr ~= 0 then State.Cracked[compAddr] = nil end

    -- 2. Disable front wall AND all coplanar paired inner/outer wall twins in the SAME frame (no transparent ghost walls!)
    DisableComponentAndActor(hitComp)
    for _, pw in ipairs(pairedWalls) do
        local pAddr = Bridge.GetObjAddr(pw.comp)
        if pAddr ~= 0 then
            ClearSurfaceScars(pAddr)
            State.Cracked[pAddr] = nil
        end
        DisableComponentAndActor(pw.comp)
        State.PairedWallsBroken = State.PairedWallsBroken + 1
    end

    -- 3. Rip baseboards / trims / wall switches off into Chaos physics (or hide decals/peels)
    local trimsCut = DetachOrDisableTrims(attachedTrim, swingDir)

    -- 4. Spawn jagged broken wood framing capping the exposed cavity edges (if upright wall)
    local frameCount = 0
    if (kind == "WOOD" or isWallLike or isStructuralShell) and thinAxis and fractureExt and fractureExt.Z >= 75.0 then
        frameCount = SpawnBreachFrame(fractureOrig, fractureExt, thinAxis, impactLoc)
    end

    -- 5. Finish the opening with fast surface fragments.
    SpawnSplinters(impactLoc, impactNrm, swingDir, kind, debrisMat, isHeavy and 14 or 9, 44.0, 440.0)

    if isHeavy then
        ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 680.0, swingDir, ignore)
    end
    State.DestroyedCount = State.DestroyedCount + 1
    Logger.Info(string.format(
        "HammerMgr: BREACHED %s (pairedTwins=%d, trimsDetached=%d, frames=%d, solidChunks=%d, kind=%s)",
        Logger.SafeName(hitComp), #pairedWalls, trimsCut, frameCount, wallChunks, kind))
end

-- =========================================================
-- 3D Hand Pose & Swing Transform Driver
-- =========================================================
local function UpdateHammerTransform(slender, camCtrl)
    if not State.Equipped or not Logger.IsValidObj(State.Pivot) or not Logger.IsValidObj(slender) then
        return
    end

    local slLoc = Bridge.GetActorLoc(slender)
    if not slLoc then return end

    local meshComp = nil
    pcall(function() meshComp = slender.Mesh end)

    local bodyYaw = (camCtrl and camCtrl.GetYaw and camCtrl.GetYaw()) or 0.0
    pcall(function()
        local r = slender:K2_GetActorRotation()
        if r and type(r.Yaw) == "number" then bodyYaw = r.Yaw end
    end)

    local fx, fy, _ = Bridge.ForwardFromRot(0.0, bodyYaw)
    local rx, ry, _ = Bridge.RightFromYaw(bodyYaw)
    local anchor = {
        X = slLoc.X + rx * 28.0 + fx * 18.0,
        Y = slLoc.Y + ry * 28.0 + fy * 18.0,
        Z = slLoc.Z + 12.0,
    }
    if Logger.IsValidObj(meshComp) and meshComp.GetSocketLocation then
        local okH, hLoc = pcall(function() return meshComp:GetSocketLocation(Bridge.FName("hand_r")) end)
        if okH and hLoc and hLoc.X then
            local hTable = { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z }
            if Bridge.Dist(hTable, slLoc) < 280.0 then
                anchor = hTable
            end
        end
    end

    local camPitch = -8.0
    if camCtrl and camCtrl.GetViewTransform then
        local _, camRot, _ = camCtrl.GetViewTransform()
        if camRot and type(camRot.Pitch) == "number" then
            camPitch = Bridge.Clamp(camRot.Pitch, -55.0, 45.0)
        end
    end

    local offFwd, offRight, offUp = 10.0, 6.0, 4.0
    local pPitch = -42.0 + camPitch * 0.45
    local pYaw   = bodyYaw - 24.0
    local pRoll  = 22.0

    if State.SwingType == "LIGHT" then
        local u = Bridge.Clamp(State.SwingElapsed / math.max(0.01, State.SwingDuration), 0.0, 1.0)
        if u < 0.25 then
            local k = u / 0.25
            k = k * k * (3.0 - 2.0 * k)
            offFwd, offRight, offUp = Bridge.Lerp(10.0, 12.0, k), Bridge.Lerp(6.0, 26.0, k), Bridge.Lerp(4.0, 48.0, k)
            pPitch = Bridge.Lerp(pPitch, -14.0, k)
            pYaw   = bodyYaw + Bridge.Lerp(-24.0, 56.0, k)
            pRoll  = Bridge.Lerp(22.0, 48.0, k)
        elseif u < 0.56 then
            local k = (u - 0.25) / 0.31
            k = 1.0 - (1.0 - k) * (1.0 - k)
            offFwd, offRight, offUp = Bridge.Lerp(12.0, 38.0, k), Bridge.Lerp(26.0, -24.0, k), Bridge.Lerp(48.0, 28.0, k)
            pPitch = Bridge.Lerp(-14.0, -78.0 + camPitch * 0.55, k)
            pYaw   = bodyYaw + Bridge.Lerp(56.0, -64.0, k)
            pRoll  = Bridge.Lerp(48.0, -44.0, k)
        else
            local k = (u - 0.56) / 0.44
            k = k * k * (3.0 - 2.0 * k)
            offFwd, offRight, offUp = Bridge.Lerp(38.0, 10.0, k), Bridge.Lerp(-24.0, 6.0, k), Bridge.Lerp(28.0, 4.0, k)
            pPitch = Bridge.Lerp(-78.0 + camPitch * 0.55, -42.0 + camPitch * 0.45, k)
            pYaw   = bodyYaw + Bridge.Lerp(-64.0, -24.0, k)
            pRoll  = Bridge.Lerp(-44.0, 22.0, k)
        end
    elseif State.SwingType == "HEAVY" then
        local u = Bridge.Clamp(State.SwingElapsed / math.max(0.01, State.SwingDuration), 0.0, 1.0)
        if u < 0.34 then
            local k = u / 0.34
            k = k * k * (3.0 - 2.0 * k)
            offFwd, offRight, offUp = Bridge.Lerp(10.0, 6.0, k), Bridge.Lerp(6.0, 18.0, k), Bridge.Lerp(4.0, 92.0, k)
            pPitch = Bridge.Lerp(pPitch, 38.0, k)
            pYaw   = bodyYaw + Bridge.Lerp(-24.0, 8.0, k)
            pRoll  = Bridge.Lerp(22.0, 6.0, k)
        elseif u < 0.54 then
            local k = (u - 0.34) / 0.20
            k = k * k
            offFwd, offRight, offUp = Bridge.Lerp(6.0, 44.0, k), Bridge.Lerp(18.0, -4.0, k), Bridge.Lerp(92.0, 14.0, k)
            pPitch = Bridge.Lerp(38.0, -108.0 + camPitch * 0.45, k)
            pYaw   = bodyYaw + Bridge.Lerp(8.0, -6.0, k)
            pRoll  = Bridge.Lerp(6.0, 4.0, k)
        else
            local k = (u - 0.54) / 0.46
            k = k * k * (3.0 - 2.0 * k)
            offFwd, offRight, offUp = Bridge.Lerp(44.0, 10.0, k), Bridge.Lerp(-4.0, 6.0, k), Bridge.Lerp(14.0, 4.0, k)
            pPitch = Bridge.Lerp(-108.0 + camPitch * 0.45, -42.0 + camPitch * 0.45, k)
            pYaw   = bodyYaw + Bridge.Lerp(-6.0, -24.0, k)
            pRoll  = Bridge.Lerp(4.0, 22.0, k)
        end
    end

    local finalLoc = {
        X = anchor.X + fx * offFwd + rx * offRight,
        Y = anchor.Y + fy * offFwd + ry * offRight,
        Z = anchor.Z + offUp,
    }
    pcall(function()
        State.Pivot:K2_SetActorLocationAndRotation(
            Bridge.Vec(finalLoc.X, finalLoc.Y, finalLoc.Z),
            Bridge.Rot(pPitch, pYaw, pRoll),
            false, {}, true
        )
    end)
end

-- =========================================================
-- Equip / Trigger / Tick Update
-- =========================================================
function HammerMgr.SetEquipped(enable)
    local want = (enable == true)
    if want then
        if not EnsureRig() then
            State.Equipped = false
            return false
        end
    end
    State.Equipped = want
    if not want then
        State.SwingType    = nil
        State.SwingElapsed = 0.0
        State.SwingHitDone = false
        State.HitStopTimer = 0.0
        State.OverrideRay  = nil
    end
    SetRigVisible(want)

    if Logger.IsValidObj(State.World) then
        Bridge.PlaySound2D(State.World, PATHS.SND_HANDLE, want and 0.60 or 0.42, want and 0.85 or 1.15, { "doorhandle" })
    end
    Logger.Info("HammerMgr: Hammer " .. (want and "EQUIPPED" or "STOWED"))
    return State.Equipped
end

function HammerMgr.Toggle()
    return HammerMgr.SetEquipped(not State.Equipped)
end

function HammerMgr.TriggerSwing(isHeavy, overrideRay)
    if not State.Equipped then return false end
    if State.SwingType ~= nil or State.Cooldown > 0.0 then return false end

    local heavy = (isHeavy == true)
    State.SwingType     = heavy and "HEAVY" or "LIGHT"
    State.SwingElapsed  = 0.0
    State.SwingDuration = heavy and (Config.HAMMER.HEAVY_DURATION or 0.54) or (Config.HAMMER.SWING_DURATION or 0.34)
    State.SwingHitDone  = false
    State.HitStopTimer  = 0.0
    State.OverrideRay   = overrideRay
    State.CooldownMax   = heavy and (Config.HAMMER.HEAVY_COOLDOWN or 1.65) or (Config.HAMMER.SWING_COOLDOWN or 0.48)
    State.Cooldown      = State.CooldownMax

    if Logger.IsValidObj(State.World) then
        Bridge.PlaySound2D(State.World, PATHS.SND_HANDLE, 0.38, heavy and 0.55 or 0.82, { "doorhandle" })
    end
    return true
end

function HammerMgr.Update(world, pc, dt, slender, survivor, camCtrl, humanFear, freezeControls)
    if not State.Initialized then return end
    State.World   = world
    State.Slender = slender

    local now = os.clock()

    -- Sweep expired short-lived splinters
    for i = #State.SplinterPool, 1, -1 do
        local sp = State.SplinterPool[i]
        if sp and sp.expiresAt and now >= sp.expiresAt then
            SafeDestroyActor(sp.actor)
            table.remove(State.SplinterPool, i)
        end
    end

    -- Fire staggered rubble cascade sounds
    for i = #State.DelayedSounds, 1, -1 do
        local ds = State.DelayedSounds[i]
        if ds and now >= ds.at then
            Bridge.PlaySoundAtLocation(world, ds.path, ds.loc, ds.vol, ds.pitch, ds.fb)
            table.remove(State.DelayedSounds, i)
        end
    end

    -- Decay temporary impact light
    if State.FlashTimer > 0.0 then
        State.FlashTimer = math.max(0.0, State.FlashTimer - dt)
        if State.FlashTimer <= 0.0 and Logger.IsValidObj(State.FlashLight) then
            pcall(function()
                local lc = State.FlashLight.PointLightComponent or State.FlashLight.RootComponent
                if Logger.IsValidObj(lc) then
                    lc:SetIntensity(0.0)
                    lc:SetVisibility(false, true)
                end
            end)
        end
    end

    if State.Cooldown > 0.0 then
        State.Cooldown = math.max(0.0, State.Cooldown - dt)
    end

    if (not freezeControls) and Logger.IsValidObj(pc) then
        local toggleKey = Config.KEYS.TOGGLE_HAMMER or "R"
        if Bridge.WasKeyJustPressed(pc, toggleKey) then
            HammerMgr.Toggle()
        end

        if State.Equipped and State.SwingType == nil and State.Cooldown <= 0.0 then
            local heavyKey = Config.KEYS.HAMMER_HEAVY or "RightMouseButton"
            local lightKey = Config.KEYS.HAMMER_SWING or "LeftMouseButton"
            if Bridge.WasKeyJustPressed(pc, heavyKey) then
                HammerMgr.TriggerSwing(true, nil)
            elseif Bridge.WasKeyJustPressed(pc, lightKey) then
                HammerMgr.TriggerSwing(false, nil)
            end
        end
    end

    if State.SwingType ~= nil then
        if State.HitStopTimer > 0.0 then
            State.HitStopTimer = math.max(0.0, State.HitStopTimer - dt)
        else
            State.SwingElapsed = State.SwingElapsed + dt
            local hitPhase = (State.SwingType == "HEAVY")
                and (Config.HAMMER.HEAVY_HIT_PHASE or 0.48)
                or  (Config.HAMMER.SWING_HIT_PHASE or 0.42)

            if (not State.SwingHitDone) and State.SwingElapsed >= (State.SwingDuration * hitPhase) then
                State.SwingHitDone = true
                local isHeavy = (State.SwingType == "HEAVY")
                local ray = State.OverrideRay
                State.OverrideRay = nil
                PerformHammerImpact(isHeavy, world, slender, survivor, camCtrl, humanFear, ray)
            end

            if State.SwingElapsed >= State.SwingDuration then
                State.SwingType    = nil
                State.SwingElapsed = 0.0
                State.SwingHitDone = false
            end
        end
    end

    UpdateHammerTransform(slender, camCtrl)
end

return HammerMgr
