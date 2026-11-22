-- PlayAsSlender Toggleable Destruction Hammer (3D Hand-Rigged Maul, GMod Chaos Physics Props, Teardown Multi-Chunk Fracture)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local HammerMgr = {}

local State = {
    Initialized    = false,
    World          = nil,
    Slender        = nil,
    Equipped       = false,
    Parts          = {},
    PartOffsets    = {},
    Pivot          = nil,
    PivotComp      = nil,
    SwingType      = nil,   -- "LIGHT" | "HEAVY" | nil
    SwingElapsed   = 0.0,
    SwingDuration  = 0.34,
    SwingHitDone   = false,
    OverrideRay    = nil,
    Cooldown       = 0.0,
    CooldownMax    = 0.48,
    FlashLight     = nil,
    FlashTimer     = 0.0,
    DebrisPool     = {},
    SimProps       = {},    -- compAddr -> { actor, comp }
    Cracked        = {},    -- compAddr -> { hp, actor, comp, scars = {} }
    Scars          = {},    -- crack/crater overlay actors
    DestroyedCount = 0,
    DetachedCount  = 0,
    ChunksSpawned  = 0,
}

local PATHS = {
    MESH_CUBE      = "/Engine/BasicShapes/Cube.Cube",
    MESH_CYLINDER  = "/Engine/BasicShapes/Cylinder.Cylinder",
    MESH_PLANK     = "/Game/Art/Environment/Props/IndustrialProps/Meshes/SM_WoodPlank.SM_WoodPlank",
    MESH_ROCK      = "/Game/Art/Environment/Props/Rocks/Meshes/Forest/SM_SmallGroundRock1.SM_SmallGroundRock1",
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
    DestroyArrayActors(State.Parts)
    DestroyArrayActors(State.DebrisPool)
    DestroyArrayActors(State.Scars)
    SafeDestroyActor(State.FlashLight)

    State.Initialized    = false
    State.World          = nil
    State.Slender        = nil
    State.Equipped       = false
    State.Parts          = {}
    State.PartOffsets    = {}
    State.Pivot          = nil
    State.PivotComp      = nil
    State.SwingType      = nil
    State.SwingElapsed   = 0.0
    State.SwingDuration  = 0.34
    State.SwingHitDone   = false
    State.OverrideRay    = nil
    State.Cooldown       = 0.0
    State.CooldownMax    = Config.HAMMER.SWING_COOLDOWN or 0.48
    State.FlashLight     = nil
    State.FlashTimer     = 0.0
    State.DebrisPool     = {}
    State.SimProps       = {}
    State.Cracked        = {}
    State.Scars          = {}
    State.DestroyedCount = 0
    State.DetachedCount  = 0
    State.ChunksSpawned  = 0
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

local function SpawnVisualPart(namePrefix, meshAsset, matAsset, relLoc, relRot, scaleVec)
    local world = State.World
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(State.PivotComp) then return nil end

    local slLoc = Bridge.GetActorLoc(State.Slender) or { X = 0, Y = 0, Z = 100 }
    local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", slLoc, 0.0)
    if not Logger.IsValidObj(actor) then return nil end

    local comp = GetStaticMeshComp(actor)
    if Logger.IsValidObj(comp) then
        pcall(function() comp:SetMobility(2) end) -- Movable
        pcall(function() comp:SetCollisionEnabled(0) end) -- NoCollision on player weapon rig
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

    -- Spawn unscaled empty root pivot actor (scale strictly 1,1,1 so attached parts never distort)
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

    -- 7-part Forged Sledgehammer / Demolition Maul centered around Right-Hand Grip (0, 0, 0)
    -- +Z = upward along shaft toward head; +X = striking direction
    SpawnVisualPart("GripWrap",   cylMesh,  matGrip,  { X = 0.0,   Y = 0.0, Z = 2.0  }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.058, Y = 0.058, Z = 0.28 })
    SpawnVisualPart("MainShaft",  cylMesh,  matShaft, { X = 0.0,   Y = 0.0, Z = 44.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.045, Y = 0.045, Z = 1.06 })
    SpawnVisualPart("Pommel",     cylMesh,  matHead,  { X = 0.0,   Y = 0.0, Z = -12.0},{ Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.075, Y = 0.075, Z = 0.06 })
    SpawnVisualPart("Collar",     cubeMesh, matHead,  { X = 0.0,   Y = 0.0, Z = 86.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.135, Y = 0.150, Z = 0.11 })
    SpawnVisualPart("HeadCore",   cubeMesh, matHead,  { X = 0.0,   Y = 0.0, Z = 93.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.450, Y = 0.220, Z = 0.220 })
    SpawnVisualPart("FrontPlate", cubeMesh, matSteel, { X = 23.5,  Y = 0.0, Z = 93.0 }, { Pitch = 0, Yaw = 0, Roll = 0 },  { X = 0.055, Y = 0.255, Z = 0.255 })
    SpawnVisualPart("BackWedge",  cubeMesh, matSteel, { X = -24.0, Y = 0.0, Z = 93.0 }, { Pitch = 45, Yaw = 0, Roll = 0 }, { X = 0.110, Y = 0.175, Z = 0.145 })

    Logger.Info(string.format("HammerMgr: Built 3D Sledgehammer rig (%d actors).", #State.Parts))
    return true
end

-- =========================================================
-- Material Classification & Destruction Sound
-- =========================================================
local function ClassifyMaterial(hitComp, hitActor)
    local compName = string.lower(Logger.SafeName(hitComp))
    local actName  = string.lower(Logger.SafeName(hitActor))
    local meshName = ""
    local matName  = ""
    local origMat  = nil

    if Logger.IsValidObj(hitComp) then
        pcall(function()
            local sm = hitComp.StaticMesh
            if Logger.IsValidObj(sm) then meshName = string.lower(Logger.SafeName(sm)) end
        end)
        pcall(function()
            origMat = hitComp:GetMaterial(0)
            if Logger.IsValidObj(origMat) then matName = string.lower(Logger.SafeName(origMat)) end
        end)
    end

    local blob = compName .. " " .. actName .. " " .. meshName .. " " .. matName
    local kind = "STONE"
    if string.find(blob, "glass") or string.find(blob, "window") or string.find(blob, "mirror") or string.find(blob, "pane") then
        kind = "GLASS"
    elseif string.find(blob, "bark") or string.find(blob, "tree") or string.find(blob, "conifer") or string.find(blob, "pine") or string.find(blob, "foliage") or string.find(blob, "bush") then
        kind = "TREE"
    elseif string.find(blob, "wood") or string.find(blob, "plank") or string.find(blob, "door") or string.find(blob, "crate")
        or string.find(blob, "chair") or string.find(blob, "table") or string.find(blob, "cabinet") or string.find(blob, "porch")
        or string.find(blob, "roof") or string.find(blob, "shingle") or string.find(blob, "fence") or string.find(blob, "trim")
        or string.find(blob, "beam") or string.find(blob, "sign") or string.find(blob, "bench") or string.find(blob, "floor") then
        kind = "WOOD"
    elseif string.find(blob, "metal") or string.find(blob, "steel") or string.find(blob, "iron") or string.find(blob, "chrome")
        or string.find(blob, "car") or string.find(blob, "truck") or string.find(blob, "van") or string.find(blob, "pipe")
        or string.find(blob, "barrel") or string.find(blob, "tank") or string.find(blob, "rail") or string.find(blob, "generator")
        or string.find(blob, "gate") or string.find(blob, "locker") or string.find(blob, "trash") then
        kind = "METAL"
    end

    local fallbackMat = nil
    if kind == "TREE" then
        fallbackMat = FirstValidAsset({ PATHS.MAT_BARK, PATHS.MAT_WOOD_DARK, PATHS.MAT_WOOD_OLD })
    elseif kind == "WOOD" then
        fallbackMat = FirstValidAsset({ PATHS.MAT_WOOD_SWAMP, PATHS.MAT_WOOD_OLD, PATHS.MAT_WOOD_DARK, PATHS.MAT_TRIM_DARK })
    elseif kind == "METAL" then
        fallbackMat = FirstValidAsset({ PATHS.MAT_METAL_DULL, PATHS.MAT_METAL, PATHS.MAT_CHROME })
    elseif kind == "GLASS" then
        fallbackMat = FirstValidAsset({ PATHS.MAT_CHROME, PATHS.MAT_METAL })
    else
        fallbackMat = FirstValidAsset({ PATHS.MAT_BRICK, PATHS.MAT_EXT_STONE, PATHS.MAT_STONE })
    end

    local debrisMat = (Logger.IsValidObj(origMat) and kind ~= "GLASS") and origMat or fallbackMat
    return kind, debrisMat, blob
end

local function PlayImpactSound(loc, kind, isHeavy)
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
        Bridge.PlaySound2D(State.World, Config.ASSETS.SOUND_DRAMATIC, 0.35, 0.65, { "Teleporter_Dramatic" })
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
                        if lc.SetAttenuationRadius then lc:SetAttenuationRadius(isHeavy and 420.0 or 260.0) end
                        if lc.SetLightColor then lc:SetLightColor({ R = 1.0, G = 0.72, B = 0.38, A = 1.0 }, true) end
                        lc:SetIntensity(isHeavy and 14000.0 or 7500.0)
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
-- UE5 Chaos Rigid-Body Physics & Teardown Debris Pool
-- =========================================================
local function EnableChaosPhysics(comp, massKg)
    if not Logger.IsValidObj(comp) then return false end
    pcall(function() comp:SetMobility(2) end)
    pcall(function() comp:SetCollisionProfileName(Bridge.FName("PhysicsActor"), true) end)
    pcall(function() comp:SetCollisionEnabled(3) end)
    -- Overlap Pawns (channel 3 = ECC_Pawn, 1 = ECR_Overlap) so scattered rubble never traps Slayer or Lauren
    pcall(function() comp:SetCollisionResponseToChannel(3, 1) end)
    pcall(function() comp:SetEnableGravity(true) end)
    pcall(function() comp:SetSimulatePhysics(true) end)
    pcall(function() comp:WakeAllRigidBodies() end)
    if massKg and massKg > 0 then
        pcall(function() comp:SetMassOverrideInKg(Bridge.FName("None"), massKg, true) end)
    end
    local sim = false
    pcall(function() sim = (comp:IsSimulatingPhysics(Bridge.FName("None")) == true) end)
    return sim
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
    local spin = angSpinDeg or 280.0
    pcall(function()
        comp:AddAngularImpulseInDegrees(
            Bridge.Vec((math.random() - 0.5) * 2.0 * spin, (math.random() - 0.5) * 2.0 * spin, (math.random() - 0.5) * 2.0 * spin),
            Bridge.FName("None"),
            true
        )
    end)
end

local function EvictOldDebrisIfFull()
    local maxDebris = Config.HAMMER.MAX_ACTIVE_DEBRIS or 90
    while #State.DebrisPool >= maxDebris do
        local old = table.remove(State.DebrisPool, 1)
        if old and Logger.IsValidObj(old.actor) then
            SafeDestroyActor(old.actor)
        end
    end
end

local function SpawnDebrisChunks(origin, normal, swingDir, kind, matAsset, count, spreadCm, baseImpulse)
    local world = State.World
    if not Logger.IsValidObj(world) or not origin then return 0 end

    local cubeMesh  = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    local cylMesh   = Bridge.LoadOrFindAsset(PATHS.MESH_CYLINDER)
    local plankMesh = Bridge.LoadOrFindAsset(PATHS.MESH_PLANK)
    local rockMesh  = Bridge.LoadOrFindAsset(PATHS.MESH_ROCK)
    if not Logger.IsValidObj(cubeMesh) then return 0 end

    local nrm = normal or { X = 0.0, Y = 0.0, Z = 1.0 }
    local dir = swingDir or { X = 1.0, Y = 0.0, Z = 0.1 }
    local spawned = 0

    for i = 1, (count or 8) do
        EvictOldDebrisIfFull()

        local jx = (math.random() - 0.5) * 2.0 * (spreadCm or 45.0)
        local jy = (math.random() - 0.5) * 2.0 * (spreadCm or 45.0)
        local jz = (math.random() - 0.5) * 2.0 * (spreadCm or 45.0)
        local pos = {
            X = origin.X + nrm.X * (16.0 + math.random() * 24.0) + jx,
            Y = origin.Y + nrm.Y * (16.0 + math.random() * 24.0) + jy,
            Z = origin.Z + nrm.Z * (16.0 + math.random() * 24.0) + jz,
        }

        local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", pos, math.random() * 360.0)
        if Logger.IsValidObj(actor) then
            local comp = GetStaticMeshComp(actor)
            if Logger.IsValidObj(comp) then
                local useMesh = cubeMesh
                local sx, sy, sz = 0.24, 0.24, 0.24
                if kind == "TREE" and Logger.IsValidObj(cylMesh) and i <= 3 then
                    useMesh = cylMesh
                    sx, sy, sz = 0.24, 0.24, 1.15
                elseif (kind == "WOOD" or kind == "TREE") and Logger.IsValidObj(plankMesh) and (i % 2 == 1) then
                    useMesh = plankMesh
                    local s = 0.35 + math.random() * 0.35
                    sx, sy, sz = s, s * 0.8, s
                elseif kind == "WOOD" then
                    sx = 0.42 + math.random() * 0.38
                    sy = 0.10 + math.random() * 0.10
                    sz = 0.06 + math.random() * 0.06
                elseif kind == "STONE" and Logger.IsValidObj(rockMesh) and (i % 3 == 0) then
                    useMesh = rockMesh
                    local s = 0.38 + math.random() * 0.42
                    sx, sy, sz = s, s, s
                elseif kind == "METAL" then
                    sx = 0.26 + math.random() * 0.28
                    sy = 0.22 + math.random() * 0.22
                    sz = 0.05 + math.random() * 0.05
                elseif kind == "GLASS" then
                    sx = 0.18 + math.random() * 0.20
                    sy = 0.16 + math.random() * 0.18
                    sz = 0.03
                else
                    -- Chunky Teardown block geometry
                    sx = 0.18 + math.random() * 0.26
                    sy = 0.16 + math.random() * 0.24
                    sz = 0.14 + math.random() * 0.22
                end

                pcall(function() comp:SetStaticMesh(useMesh) end)
                pcall(function()
                    comp:K2_SetRelativeRotation(Bridge.Rot((math.random() - 0.5) * 90.0, math.random() * 360.0, (math.random() - 0.5) * 90.0), false, {}, true)
                    comp:SetWorldScale3D(Bridge.Vec(sx, sy, sz))
                end)
                if Logger.IsValidObj(matAsset) then
                    pcall(function() comp:SetMaterial(0, matAsset) end)
                end

                local okSim = EnableChaosPhysics(comp, 14.0)
                if (not okSim) and useMesh ~= cubeMesh then
                    -- Guarantee Chaos collision by falling back to BasicShapes Cube if a StaticMesh lacked simple bounds
                    pcall(function() comp:SetStaticMesh(cubeMesh) end)
                    pcall(function() comp:SetWorldScale3D(Bridge.Vec(0.24, 0.20, 0.16)) end)
                    okSim = EnableChaosPhysics(comp, 14.0)
                end

                local speed = (baseImpulse or 620.0) * (0.65 + math.random() * 0.70)
                local iv = {
                    X = (dir.X * 0.55 + nrm.X * 0.45 + (math.random() - 0.5) * 0.75) * speed,
                    Y = (dir.Y * 0.55 + nrm.Y * 0.45 + (math.random() - 0.5) * 0.75) * speed,
                    Z = (dir.Z * 0.35 + nrm.Z * 0.35 + 0.35 + math.random() * 0.45) * speed,
                }
                ApplyChaosImpulse(comp, iv, nil, 460.0)
                table.insert(State.DebrisPool, { actor = actor, comp = comp, spawnedAt = os.clock() })
                spawned = spawned + 1
                State.ChunksSpawned = State.ChunksSpawned + 1
            else
                SafeDestroyActor(actor)
            end
        end
    end
    return spawned
end

local function ApplyRadialShockwave(origin, radius, strength, swingDir, ignoreActors)
    if not Logger.IsValidObj(State.World) or not origin then return 0 end
    local comps = Bridge.SphereOverlapComponents(State.World, origin, radius, ignoreActors)
    local pushed = 0
    local maxExtSmall = Config.HAMMER.SMALL_PROP_MAX_EXT or 145.0

    for _, c in ipairs(comps) do
        if Logger.IsValidObj(c) then
            local alreadySim = false
            pcall(function() alreadySim = (c:IsSimulatingPhysics(Bridge.FName("None")) == true) end)

            if not alreadySim then
                -- Auto-detach nearby small lose props inside heavy shockwaves!
                local _, ext = Bridge.GetComponentBounds(c)
                local cname = string.lower(Logger.SafeName(c))
                local isProt = string.find(cname, "landscape") or string.find(cname, "floor") or string.find(cname, "ground")
                    or string.find(cname, "pickup") or string.find(cname, "trigger") or string.find(cname, "collision")
                if ext and not isProt then
                    local maxE = math.max(ext.X, ext.Y, ext.Z)
                    if maxE > 4.0 and maxE <= maxExtSmall * 0.85 then
                        local ok = EnableChaosPhysics(c, 22.0)
                        if ok then
                            alreadySim = true
                            State.DetachedCount = State.DetachedCount + 1
                            local cAddr = Bridge.GetObjAddr(c)
                            if cAddr ~= 0 then State.SimProps[cAddr] = { comp = c } end
                        end
                    end
                end
            end

            if alreadySim then
                local orig = Bridge.GetComponentBounds(c)
                local dx = orig and (orig.X - origin.X) or swingDir.X
                local dy = orig and (orig.Y - origin.Y) or swingDir.Y
                local dz = orig and (orig.Z - origin.Z) or 0.0
                local dLen = math.sqrt(dx * dx + dy * dy + dz * dz)
                local rxN = (dLen > 1.0) and (dx / dLen) or swingDir.X
                local ryN = (dLen > 1.0) and (dy / dLen) or swingDir.Y
                local rzN = (dLen > 1.0) and (dz / dLen) or 0.2
                local blastVec = {
                    X = (rxN * 0.6 + swingDir.X * 0.4) * strength,
                    Y = (ryN * 0.6 + swingDir.Y * 0.4) * strength,
                    Z = (rzN * 0.25 + 0.42) * strength,
                }
                pcall(function() c:AddRadialImpulse(Bridge.Vec(origin.X, origin.Y, origin.Z), radius, strength, 1, true) end)
                ApplyChaosImpulse(c, blastVec, nil, 240.0)
                pushed = pushed + 1
            end
        end
    end
    return pushed
end

local function DisableComponentAndActor(comp)
    if not Logger.IsValidObj(comp) then return end
    pcall(function() comp:SetSimulatePhysics(false) end)
    pcall(function() comp:SetCollisionEnabled(0) end)
    pcall(function() comp:SetCollisionResponseToAllChannels(0) end)
    pcall(function() comp:SetHiddenInGame(true, false) end)
    pcall(function() comp:SetVisibility(false, true) end)
end

local function SpawnCrackScar(hitPoint, hitNormal)
    local world = State.World
    local cubeMesh = Bridge.LoadOrFindAsset(PATHS.MESH_CUBE)
    local darkMat  = FirstValidAsset({ PATHS.MAT_WOOD_DARK, PATHS.MAT_EXT_STONE, PATHS.MAT_METAL_DULL })
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(cubeMesh) or not hitPoint then return nil end

    local nrm = hitNormal or { X = 0, Y = 0, Z = 1 }
    local pos = { X = hitPoint.X + nrm.X * 2.0, Y = hitPoint.Y + nrm.Y * 2.0, Z = hitPoint.Z + nrm.Z * 2.0 }
    local rot = Bridge.RotatorFromVec(nrm.X, nrm.Y, nrm.Z)
    local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", pos, rot.Yaw)
    if not Logger.IsValidObj(actor) then return nil end

    local comp = GetStaticMeshComp(actor)
    if Logger.IsValidObj(comp) then
        pcall(function() comp:SetMobility(2) end)
        pcall(function() comp:SetCollisionEnabled(0) end)
        pcall(function() comp:SetStaticMesh(cubeMesh) end)
        if Logger.IsValidObj(darkMat) then
            pcall(function() comp:SetMaterial(0, darkMat) end)
        end
        pcall(function()
            actor:K2_SetActorLocationAndRotation(Bridge.Vec(pos.X, pos.Y, pos.Z), Bridge.Rot(rot.Pitch, rot.Yaw, rot.Roll + math.random() * 60.0), false, {}, true)
            comp:SetWorldScale3D(Bridge.Vec(0.05, 0.52 + math.random() * 0.25, 0.36 + math.random() * 0.24))
        end)
    end
    table.insert(State.Scars, actor)
    return actor
end

local function IsProtectedTarget(hitComp, hitActor, hitNormal, ext, origin)
    local compName = string.lower(Logger.SafeName(hitComp))
    local actName  = string.lower(Logger.SafeName(hitActor))
    local blob     = compName .. " " .. actName

    -- 1. Never break terrain, skyboxes, volumes, triggers, lights, navmesh, notes/pickups, generators, level checkpoints
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

    -- 2. Protect huge flat horizontal floors / sidewalks / ceilings directly underfoot
    if ext and hitNormal then
        local isFlatUp = math.abs(hitNormal.Z or 0) > 0.72
        if isFlatUp and ext.X > 180.0 and ext.Y > 180.0 and ext.Z < 60.0 then
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

-- =========================================================
-- Core Impact Resolver (5-Tier Destruction)
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
        if Logger.IsValidObj(s) then table.insert(ignore, s) end
    end
    return ignore
end

local function ResolveAimHit(world, slender, survivor, camCtrl, reachCm, overrideRay)
    local slLoc = Bridge.GetActorLoc(slender) or { X = 0, Y = 0, Z = 100 }
    local camPos, camRot, _ = nil, nil, nil
    if camCtrl and camCtrl.GetViewTransform then
        camPos, camRot, _ = camCtrl.GetViewTransform()
    end

    local traceStart, traceFwd
    if overrideRay and overrideRay.pos and overrideRay.fwd then
        traceStart = overrideRay.pos
        traceFwd   = overrideRay.fwd
    elseif camPos and camRot then
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
    local hit, info = Bridge.LineTrace(world, traceStart, endPos, ignore, 0, false)

    -- Forgiving fan rays for thin fences, railings, or narrow props
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
            local h2, i2 = Bridge.LineTrace(world, traceStart, eAlt, ignore, 0, false)
            if h2 and i2 then
                hit, info = h2, i2
                break
            end
        end
    end

    if hit and info and info.ImpactPoint then
        local maxSlReach = Config.HAMMER.MAX_SLENDER_REACH_CM or 640.0
        if Bridge.Dist(slLoc, info.ImpactPoint) <= maxSlReach then
            return true, info, traceFwd, ignore
        end
    end

    -- Fallback ground strike point if whiffing in open air near ground
    local airEnd = {
        X = slLoc.X + traceFwd.X * 195.0,
        Y = slLoc.Y + traceFwd.Y * 195.0,
        Z = slLoc.Z + traceFwd.Z * 195.0,
    }
    local gHit, gInfo = Bridge.LineTrace(world,
        { X = airEnd.X, Y = airEnd.Y, Z = airEnd.Z + 120.0 },
        { X = airEnd.X, Y = airEnd.Y, Z = airEnd.Z - 260.0 },
        ignore, 0, false)
    return false, (gHit and gInfo or nil), traceFwd, ignore, airEnd
end

local function PerformHammerImpact(isHeavy, world, slender, survivor, camCtrl, humanFear, overrideRay)
    local slLoc = Bridge.GetActorLoc(slender) or { X = 0, Y = 0, Z = 100 }
    local reach = Config.HAMMER.REACH_CM or 460.0
    local hit, info, swingDir, ignore, fallbackLoc = ResolveAimHit(world, slender, survivor, camCtrl, reach, overrideRay)

    -- Always check Survivor shock in close melee range
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

    local impactLoc = (hit and info and info.ImpactPoint) or (info and info.ImpactPoint) or fallbackLoc or {
        X = slLoc.X + swingDir.X * 180.0,
        Y = slLoc.Y + swingDir.Y * 180.0,
        Z = slLoc.Z + 20.0,
    }
    local impactNrm = (info and info.ImpactNormal) or { X = -swingDir.X, Y = -swingDir.Y, Z = 1.0 }

    -- Open-air whiff or out-of-reach swing
    if (not hit) or (not info) or (not Logger.IsValidObj(info.Component)) then
        if isHeavy then
            PlayImpactSound(impactLoc, "STONE", true)
            TriggerImpactFlash(impactLoc, true)
            if camCtrl and camCtrl.AddImpactShake then
                camCtrl.AddImpactShake(Config.HAMMER.SHAKE_HEAVY_CM or 18.0, Config.HAMMER.SHAKE_DURATION or 0.24)
            end
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, "STONE", FirstValidAsset({ PATHS.MAT_STONE, PATHS.MAT_WOOD_DARK }), 7, 55.0, 520.0)
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
        else
            Bridge.PlaySound2D(world, PATHS.SND_HANDLE, 0.35, 0.72, { "doorhandle" })
        end
        return
    end

    local hitComp  = info.Component
    local hitActor = info.Actor
    local compAddr = Bridge.GetObjAddr(hitComp)
    local kind, debrisMat, blob = ClassifyMaterial(hitComp, hitActor)
    local orig, ext, _ = Bridge.GetComponentBounds(hitComp)

    -- Sound + flash + camera punch
    PlayImpactSound(impactLoc, kind, isHeavy)
    TriggerImpactFlash(impactLoc, isHeavy)
    if camCtrl and camCtrl.AddImpactShake then
        camCtrl.AddImpactShake(
            isHeavy and (Config.HAMMER.SHAKE_HEAVY_CM or 18.0) or (Config.HAMMER.SHAKE_LIGHT_CM or 7.0),
            Config.HAMMER.SHAKE_DURATION or 0.24
        )
    end

    -- Tier 0: Already-simulating Chaos Rigid Body (GMod prop OR spawned Teardown chunk) -> bat or shatter!
    local isAlreadySim = false
    pcall(function() isAlreadySim = (hitComp:IsSimulatingPhysics(Bridge.FName("None")) == true) end)
    if isAlreadySim then
        if isHeavy then
            -- Heavy slam shatters physics props into smaller Teardown pieces!
            DisableComponentAndActor(hitComp)
            SpawnDebrisChunks(orig or impactLoc, impactNrm, swingDir, kind, debrisMat, 9, 32.0, 820.0)
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
            State.DestroyedCount = State.DestroyedCount + 1
            Logger.Info("HammerMgr: Shattered physics object " .. Logger.SafeName(hitComp))
        else
            -- LMB bats the live Chaos object dramatically across the room (GMod style!)
            local imp = Config.HAMMER.LIGHT_IMPULSE or 950.0
            ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = math.max(160.0, swingDir.Z * imp + 240.0) }, impactLoc, 480.0)
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, 2, 16.0, 360.0)
            Logger.Info("HammerMgr: Batted Chaos prop " .. Logger.SafeName(hitComp))
        end
        return
    end

    -- Tier 1: Instanced Foliage Trees / Bushes (chop & fell with tumbling bark logs!)
    local isISM = string.find(Logger.SafeFullName(hitComp), "InstancedStaticMesh", 1, true) ~= nil
    if not isISM then
        pcall(function() isISM = (hitComp.RemoveInstance ~= nil) end)
    end
    if isISM and info.Item ~= nil and tonumber(info.Item) and tonumber(info.Item) >= 0 then
        local idx = tonumber(info.Item)
        local removed = false
        pcall(function() removed = (hitComp:RemoveInstance(idx) == true) end)
        if removed then
            local treeChunks = isHeavy and 12 or 7
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, "TREE", debrisMat, treeChunks, 48.0, isHeavy and 720.0 or 460.0)
            if isHeavy then
                ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
            end
            State.DestroyedCount = State.DestroyedCount + 1
            Logger.Info(string.format("HammerMgr: Felled Foliage instance #%d on %s (%d chunks)", idx, Logger.SafeName(hitComp), treeChunks))
            return
        end
    end

    -- Check Protection Rules (Terrain, floors under feet, story pickups, lights, navmesh)
    local isProt, protReason = IsProtectedTarget(hitComp, hitActor, impactNrm, ext, orig)
    if isProt then
        local count = isHeavy and 8 or 4
        SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, count, 38.0, isHeavy and 560.0 or 320.0)
        if isHeavy then
            SpawnCrackScar(impactLoc, impactNrm)
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Crater impact on %s (%s)", Logger.SafeName(hitComp), tostring(protReason)))
        return
    end

    local maxExt = ext and math.max(ext.X, ext.Y, ext.Z) or 120.0
    local isDoorOrWindow = string.find(blob, "door", 1, true) or string.find(blob, "window", 1, true)
        or string.find(blob, "glass", 1, true) or string.find(blob, "shutter", 1, true)

    -- Tier 2: Giant Monolith Shells (> 720 cm half-extent) -> Surface Carving + Rubble Blast without vanishing whole terrain block
    if maxExt > (Config.HAMMER.GIANT_MESH_MIN_EXT or 720.0) then
        local count = isHeavy and 14 or 6
        SpawnCrackScar(impactLoc, impactNrm)
        SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, count, 60.0, isHeavy and 780.0 or 420.0)
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Carved giant surface %s (ext=%.0f)", Logger.SafeName(hitComp), maxExt))
        return
    end

    -- Tier 3: Doors & Windows -> Instant Splinter Break / Hinge Detach
    if isDoorOrWindow then
        local detached = false
        if maxExt <= (Config.HAMMER.MEDIUM_PROP_MAX_EXT or 420.0) and kind ~= "GLASS" then
            detached = EnableChaosPhysics(hitComp, 38.0)
        end
        if detached then
            local imp = isHeavy and (Config.HAMMER.HEAVY_IMPULSE or 1650.0) or (Config.HAMMER.LIGHT_IMPULSE or 950.0)
            ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = 220.0 }, impactLoc, 520.0)
            if compAddr ~= 0 then State.SimProps[compAddr] = { comp = hitComp } end
            State.DetachedCount = State.DetachedCount + 1
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, 5, 28.0, 520.0)
        else
            DisableComponentAndActor(hitComp)
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, isHeavy and 12 or 8, 42.0, 660.0)
            State.DestroyedCount = State.DestroyedCount + 1
        end
        if isHeavy then
            ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
        end
        Logger.Info(string.format("HammerMgr: Smashed door/window %s (detached=%s)", Logger.SafeName(hitComp), tostring(detached)))
        return
    end

    -- Tier 4: Small / Medium Standalone Props -> GMod Chaos Rigid-Body Detach! (Or Shatter on RMB if Heavy)
    local isTrimOrProp = string.find(blob, "trim", 1, true) or string.find(blob, "chair", 1, true)
        or string.find(blob, "table", 1, true) or string.find(blob, "crate", 1, true)
        or string.find(blob, "plank", 1, true) or string.find(blob, "bench", 1, true)
    local isWallLike = (not isTrimOrProp) and (
        string.find(blob, "wall", 1, true) or string.find(blob, "siding", 1, true)
        or string.find(blob, "cabin", 1, true) or string.find(blob, "porch", 1, true)
        or string.find(blob, "roof", 1, true) or string.find(blob, "pillar", 1, true)
        or string.find(blob, "brick", 1, true) or string.find(blob, "concrete", 1, true)
        or string.find(blob, "shed", 1, true)
    )

    if (not isWallLike) and maxExt <= (Config.HAMMER.SMALL_PROP_MAX_EXT or 145.0) and (not isHeavy) then
        local detached = EnableChaosPhysics(hitComp, math.max(12.0, maxExt * 0.35))
        if detached then
            local imp = Config.HAMMER.LIGHT_IMPULSE or 950.0
            ApplyChaosImpulse(hitComp, { X = swingDir.X * imp, Y = swingDir.Y * imp, Z = 240.0 }, impactLoc, 440.0)
            if compAddr ~= 0 then State.SimProps[compAddr] = { comp = hitComp } end
            State.DetachedCount = State.DetachedCount + 1
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, 3, 20.0, 420.0)
            Logger.Info(string.format("HammerMgr: GMod Chaos-detached %s (ext=%.0f)", Logger.SafeName(hitComp), maxExt))
            return
        end
        -- Fall through to Teardown Shatter if engine refused physics on that mesh
    end

    -- Tier 5: Modular Walls & Heavy Structures -> Crack (1st LMB) -> Full Breach + Teardown Chunk Explosion!
    local rec = (compAddr ~= 0) and State.Cracked[compAddr] or nil
    if (not isHeavy) and isWallLike then
        if not rec then
            rec = { hp = (Config.HAMMER.WALL_CRACKS_TO_BREAK or 2) - 1, comp = hitComp, scars = {} }
            if compAddr ~= 0 then State.Cracked[compAddr] = rec end
        else
            rec.hp = rec.hp - 1
        end
        if rec.hp > 0 then
            local scar = SpawnCrackScar(impactLoc, impactNrm)
            if scar then table.insert(rec.scars, scar) end
            SpawnDebrisChunks(impactLoc, impactNrm, swingDir, kind, debrisMat, 6, 36.0, 480.0)
            Logger.Info(string.format("HammerMgr: Cracked wall %s (remaining hits=%d)", Logger.SafeName(hitComp), rec.hp))
            return
        end
    end

    -- Full Destruction / Breach -> Hide structural mesh, clean any crack scars, erupt textured physics chunks!
    if rec and rec.scars then
        DestroyArrayActors(rec.scars)
    end
    if compAddr ~= 0 then State.Cracked[compAddr] = nil end

    DisableComponentAndActor(hitComp)
    local chunkMin = isHeavy and (Config.HAMMER.CHUNKS_HEAVY_MIN or 12) or (Config.HAMMER.CHUNKS_LIGHT_MIN or 6)
    local chunkMax = isHeavy and (Config.HAMMER.CHUNKS_HEAVY_MAX or 18) or (Config.HAMMER.CHUNKS_LIGHT_MAX or 9)
    local chunkCount = math.random(chunkMin, chunkMax)
    local spread = math.min(115.0, math.max(38.0, maxExt * 0.45))
    local chunkCenter = orig or impactLoc
    -- Clamp chunk center near impact so tall 250cm walls don't spawn half their bricks up on the roof out of sight
    if orig and impactLoc and Bridge.Dist(orig, impactLoc) > 150.0 then
        chunkCenter = {
            X = Bridge.Lerp(impactLoc.X, orig.X, 0.35),
            Y = Bridge.Lerp(impactLoc.Y, orig.Y, 0.35),
            Z = Bridge.Lerp(impactLoc.Z, orig.Z, 0.40),
        }
    end
    SpawnDebrisChunks(chunkCenter, impactNrm, swingDir, kind, debrisMat, chunkCount, spread, isHeavy and 880.0 or 540.0)

    if isHeavy then
        ApplyRadialShockwave(impactLoc, Config.HAMMER.HEAVY_RADIUS_CM or 340.0, Config.HAMMER.HEAVY_RADIAL_IMPULSE or 1150.0, swingDir, ignore)
    end
    State.DestroyedCount = State.DestroyedCount + 1
    Logger.Info(string.format("HammerMgr: BREACHED & SHATTERED %s into %d Teardown chunks! (kind=%s, ext=%.0f)",
        Logger.SafeName(hitComp), chunkCount, kind, maxExt))
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

    -- Anchor grip directly to SK_Slender01 hand_r bone, falling back safely to right shoulder offset
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

    -- Compute smooth animation pose (Idle vs Light Slash vs Heavy Overhead Slam)
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
            offFwd, offRight, offUp = Bridge.Lerp(8.0, 12.0, k), Bridge.Lerp(4.0, 26.0, k), Bridge.Lerp(2.0, 48.0, k)
            pPitch = Bridge.Lerp(pPitch, -14.0, k)
            pYaw   = bodyYaw + Bridge.Lerp(-12.0, 56.0, k)
            pRoll  = Bridge.Lerp(16.0, 48.0, k)
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
            offFwd, offRight, offUp = Bridge.Lerp(38.0, 8.0, k), Bridge.Lerp(-24.0, 4.0, k), Bridge.Lerp(28.0, 2.0, k)
            pPitch = Bridge.Lerp(-78.0 + camPitch * 0.55, -42.0 + camPitch * 0.45, k)
            pYaw   = bodyYaw + Bridge.Lerp(-64.0, -12.0, k)
            pRoll  = Bridge.Lerp(-44.0, 16.0, k)
        end
    elseif State.SwingType == "HEAVY" then
        local u = Bridge.Clamp(State.SwingElapsed / math.max(0.01, State.SwingDuration), 0.0, 1.0)
        if u < 0.34 then
            local k = u / 0.34
            k = k * k * (3.0 - 2.0 * k)
            offFwd, offRight, offUp = Bridge.Lerp(8.0, 6.0, k), Bridge.Lerp(4.0, 18.0, k), Bridge.Lerp(2.0, 92.0, k)
            pPitch = Bridge.Lerp(pPitch, 38.0, k)
            pYaw   = bodyYaw + Bridge.Lerp(-12.0, 8.0, k)
            pRoll  = Bridge.Lerp(16.0, 6.0, k)
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
            offFwd, offRight, offUp = Bridge.Lerp(44.0, 8.0, k), Bridge.Lerp(-4.0, 4.0, k), Bridge.Lerp(14.0, 2.0, k)
            pPitch = Bridge.Lerp(-108.0 + camPitch * 0.45, -42.0 + camPitch * 0.45, k)
            pYaw   = bodyYaw + Bridge.Lerp(-6.0, -12.0, k)
            pRoll  = Bridge.Lerp(4.0, 16.0, k)
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

    UpdateHammerTransform(slender, camCtrl)
end

return HammerMgr
