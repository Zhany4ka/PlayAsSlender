-- PlayAsSlender Slenderman Controller (Multi-Map Spawn, Idle/Walk AnimSequence, Collision-Safe Movement)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local SlenderCtrl = {}

local State = {
    Actor         = nil,
    MeshComp      = nil,
    TentacleGroup = nil,
    TentacleComps = {},
    IdleAnim      = nil,
    WalkAnim      = nil,
    AnimState     = "None",
    Yaw           = 0.0,
    IsMoving      = false,
    IsSprinting   = false,
    TentaclesOn   = false,
    Doors         = {},
    LastDoorCheck = 0.0,
}

function SlenderCtrl.Reset()
    State.Actor         = nil
    State.MeshComp      = nil
    State.TentacleGroup = nil
    State.TentacleComps = {}
    State.IdleAnim      = nil
    State.WalkAnim      = nil
    State.AnimState     = "None"
    State.Yaw           = 0.0
    State.IsMoving      = false
    State.IsSprinting   = false
    State.TentaclesOn   = false
    State.Doors         = {}
    State.LastDoorCheck = 0.0
end

function SlenderCtrl.GetActor()     return State.Actor end
function SlenderCtrl.GetMeshComp()  return State.MeshComp end
function SlenderCtrl.GetAnimState() return State.AnimState end

function SlenderCtrl.GetLocation()
    return Bridge.GetActorLoc(State.Actor)
end

function SlenderCtrl.SetTentaclesVisible(visible)
    local vis = (visible == true)
    State.TentaclesOn = vis
    if Logger.IsValidObj(State.TentacleGroup) then
        pcall(function()
            State.TentacleGroup:SetHiddenInGame(not vis, true)
            State.TentacleGroup:SetVisibility(vis, true)
        end)
    end
    for _, comp in ipairs(State.TentacleComps) do
        if Logger.IsValidObj(comp) then
            pcall(function()
                comp:SetHiddenInGame(not vis, true)
                comp:SetVisibility(vis, true)
            end)
        end
    end
end

local function ApplyAnimState(moving)
    if not Logger.IsValidObj(State.MeshComp) then return end
    local targetState = moving and "WalkAnim" or "IdleAnim"
    if State.AnimState == targetState then return end
    local seq = moving and (State.WalkAnim or State.IdleAnim) or State.IdleAnim
    if Logger.IsValidObj(seq) then
        -- PlayAnimation internally switches USkeletalMeshComponent to AnimationSingleNode in UE5.3; try multiple clean fallbacks
        local ok, err = pcall(function() State.MeshComp:PlayAnimation(seq, true) end)
        if not ok then
            local ok2, err2 = pcall(function()
                State.MeshComp:SetAnimationMode(1)
                State.MeshComp:SetAnimation(seq)
                State.MeshComp:Play(true)
            end)
            if not ok2 then
                Logger.Warn(string.format("PlayAnim(%s) failed: %s / %s", targetState, tostring(err), tostring(err2)))
                return
            end
        end
        State.AnimState = targetState
    end
end

local function IsOpenGroundSpot(world, pt, ignore, indoorFallback)
    local gHit, gz, norm = Bridge.GroundTrace(world, pt.X, pt.Y, pt.Z + 320.0, pt.Z - 700.0, ignore)
    if (not gHit) or (not norm) or norm.Z < 0.72 then
        return false, nil
    end
    -- Open headroom (340cm outdoors, or 245cm for indoor tunnels/rooms when falling back)
    local headHeight = indoorFallback and 245.0 or 340.0
    local skyHit = Bridge.LineTrace(world, { X = pt.X, Y = pt.Y, Z = gz + 40.0 }, { X = pt.X, Y = pt.Y, Z = gz + headHeight }, ignore, 0, false)
    if skyHit then return false, nil end
    -- Radial obstacle clearance (avoid spawning overlapping trees/walls)
    local radClear = indoorFallback and 48.0 or 58.0
    for k = 0, 7 do
        local ang = (k * math.pi) / 4.0
        local ox  = math.cos(ang) * radClear
        local oy  = math.sin(ang) * radClear
        local p0  = { X = pt.X, Y = pt.Y, Z = gz + 60.0 }
        local p1  = { X = pt.X + ox, Y = pt.Y + oy, Z = gz + 60.0 }
        if Bridge.LineTrace(world, p0, p1, ignore, 0, false) then
            return false, nil
        end
    end
    return true, { X = pt.X, Y = pt.Y, Z = gz + Config.SLENDER.CAPSULE_HALF_HEIGHT }
end

-- Find open ground at [minDist..maxDist] from Human start (works outdoors & indoors, with/without NavMesh)
local function ChooseForestOrYardSpawn(world, survivorLoc, survivorActor, mapCfg, hasNavMesh)
    local ignore = Logger.IsValidObj(survivorActor) and { survivorActor } or {}
    local minD = (mapCfg and mapCfg.spawnDistMin) or Config.SLENDER.SPAWN_DIST_MIN
    local maxD = (mapCfg and mapCfg.spawnDistMax) or Config.SLENDER.SPAWN_DIST_MAX

    for _, indoorPass in ipairs({ false, true }) do
        if hasNavMesh then
            for _, radius in ipairs({ maxD, (minD + maxD) * 0.5, minD, 1600.0, 950.0 }) do
                for _ = 1, 16 do
                    local ok, pt = Bridge.GetRandomReachablePoint(world, survivorLoc, radius)
                    if ok and pt then
                        local minReq = indoorPass and 750.0 or (minD * 0.68)
                        local d = Bridge.Dist2D(pt, survivorLoc)
                        if d >= minReq then
                            local openOk, validPos = IsOpenGroundSpot(world, pt, ignore, indoorPass)
                            if openOk then return validPos end
                        end
                    end
                end
            end
        end

        -- Non-NavMesh / Fallback radial sampling around Survivor
        local survYaw = (Logger.IsValidObj(survivorActor) and Bridge.GetActorRot(survivorActor) or { Yaw = 84.0 }).Yaw
        local sfx, sfy = Bridge.ForwardFromRot(0.0, survYaw)
        local passes = (mapCfg and mapCfg.key == "PROLOGUE") and { true, false } or { false }
        local radiiList = indoorPass and { 2400.0, 1600.0, 1100.0, 750.0 } or { maxD, (minD + maxD) * 0.5, minD, 1600.0 }
        for _, preferBehind in ipairs(passes) do
            for _, radius in ipairs(radiiList) do
                for k = 0, 15 do
                    local ang = (k * math.pi * 2.0) / 16.0
                    local dot = math.cos(ang) * sfx + math.sin(ang) * sfy
                    if (not preferBehind) or dot < 0.0 then
                        local cand = {
                            X = survivorLoc.X + math.cos(ang) * radius,
                            Y = survivorLoc.Y + math.sin(ang) * radius,
                            Z = survivorLoc.Z + 120.0,
                        }
                        if hasNavMesh then
                            local okP, proj = Bridge.ProjectPointToNav(world, cand, { X = 450.0, Y = 450.0, Z = 800.0 })
                            if okP and proj then cand = proj end
                        end
                        local openOk, validPos = IsOpenGroundSpot(world, cand, ignore, indoorPass)
                        if openOk then return validPos end
                    end
                end
            end
        end
    end

    return { X = survivorLoc.X + 1800.0, Y = survivorLoc.Y - 1200.0, Z = survivorLoc.Z + Config.SLENDER.CAPSULE_HALF_HEIGHT }
end

-- Preload Slender mesh, AnimBP & AnimSequences safely across both Level01 & Level02
local function ResolveSlenderAssets(world)
    local skAsset  = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_MESH)
    local animCls  = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_ANIM_BP)
    local idleAnim = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_IDLE_ANIM)
    local walkAnim = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_WALK_ANIM)

    if not Logger.IsValidObj(skAsset) or not Logger.IsValidObj(idleAnim) then
        local tmp = Bridge.SpawnActorDeferred(world, Config.ASSETS.SLENDER_CLASS, { X = 0.0, Y = 0.0, Z = -25000.0 }, 0.0)
        if Logger.IsValidObj(tmp) then
            pcall(function()
                local tm = tmp.Mesh
                if Logger.IsValidObj(tm) then
                    if not Logger.IsValidObj(skAsset) then skAsset = tm:GetSkinnedAsset() end
                    if not Logger.IsValidObj(animCls) then animCls = tm.AnimClass end
                end
            end)
            pcall(function()
                local tc = tmp:GetController()
                if Logger.IsValidObj(tc) then
                    pcall(function() tc:UnPossess() end)
                    pcall(function() tc:K2_DestroyActor() end)
                end
            end)
            pcall(function() tmp:K2_DestroyActor() end)
        end
    end

    if not Logger.IsValidObj(skAsset)  then skAsset  = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_MESH) end
    if not Logger.IsValidObj(animCls)  then animCls  = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_ANIM_BP) end
    if not Logger.IsValidObj(idleAnim) then idleAnim = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_IDLE_ANIM) end
    if not Logger.IsValidObj(walkAnim) then walkAnim = Bridge.LoadOrFindAsset(Config.ASSETS.SLENDER_WALK_ANIM) end

    -- Fallback search inside loaded AnimSequences if paths differ
    if not Logger.IsValidObj(idleAnim) or not Logger.IsValidObj(walkAnim) then
        for _, a in ipairs(FindAllOf("AnimSequence") or {}) do
            if Logger.IsValidObj(a) then
                local fn = Logger.SafeFullName(a)
                if (not Logger.IsValidObj(idleAnim)) and string.find(fn, "Thriller_Idle_Modified", 1, true) then
                    idleAnim = a
                elseif (not Logger.IsValidObj(walkAnim)) and string.find(fn, "Sad_Walk", 1, true) then
                    walkAnim = a
                end
            end
        end
    end

    return skAsset, animCls, idleAnim, walkAnim
end

function SlenderCtrl.Init(world, survivor, mapCfg, hasNavMesh)
    SlenderCtrl.Reset()
    if not Logger.IsValidObj(world) then return false end

    -- Neutralize and destroy any vanilla spawners / AI / Slender actors
    for _, sp in ipairs(FindAllOf("BP_AISpawner_C") or {}) do
        if Logger.IsValidObj(sp) then
            Logger.Info("Disabling vanilla AI spawner: " .. Logger.SafeName(sp))
            pcall(function() sp.RequiredScore = 999 end)
            pcall(function() sp:SetActorTickEnabled(false) end)
            pcall(function() sp:SetActorEnableCollision(false) end)
            pcall(function() sp:K2_DestroyActor() end)
        end
    end
    for _, tc in ipairs(FindAllOf("BP_TeleporterAIController_C") or {}) do
        if Logger.IsValidObj(tc) then
            pcall(function() tc:UnPossess() end)
            pcall(function() tc:K2_DestroyActor() end)
        end
    end
    for _, ts in ipairs(FindAllOf("BP_SlenderMan_Forest_C") or {}) do
        if Logger.IsValidObj(ts) then
            pcall(function() ts:K2_DestroyActor() end)
        end
    end
    -- Also preload Dramatic audio cue early for abilities
    Bridge.LoadOrFindAsset(Config.ASSETS.SOUND_DRAMATIC)

    local PrologueStory = require("prologue_story")
    local skAsset, animCls, idleAnim, walkAnim = ResolveSlenderAssets(world)
    local survLoc = Bridge.GetActorLoc(survivor) or { X = 42400.0, Y = 54200.0, Z = 9350.0 }
    local spawnLoc = (mapCfg and mapCfg.key == "PROLOGUE" and PrologueStory.IsActive())
        and PrologueStory.GetInitialSlenderSpawn(world, survLoc, survivor)
        or ChooseForestOrYardSpawn(world, survLoc, survivor, mapCfg, hasNavMesh == true)
    local faceYaw  = Bridge.YawFromVec(survLoc.X - spawnLoc.X, survLoc.Y - spawnLoc.Y)

    local slender = Bridge.SpawnActorDeferred(world, "/Script/Engine.Character", spawnLoc, faceYaw)
    if not Logger.IsValidObj(slender) then
        Logger.Error("SlenderCtrl.Init: Failed to spawn /Script/Engine.Character")
        return false
    end

    pcall(function()
        local cap = slender.CapsuleComponent
        if Logger.IsValidObj(cap) then
            cap:SetCapsuleSize(Config.SLENDER.CAPSULE_RADIUS, Config.SLENDER.CAPSULE_HALF_HEIGHT, true)
            if mapCfg and mapCfg.key == "PROLOGUE" and Logger.IsValidObj(survivor) then
                if cap.IgnoreActorWhenMoving then cap:IgnoreActorWhenMoving(survivor, true) end
                local survCap = survivor.CapsuleComponent
                if Logger.IsValidObj(survCap) and survCap.IgnoreActorWhenMoving then
                    survCap:IgnoreActorWhenMoving(slender, true)
                end
            end
        end
    end)

    pcall(function()
        local cmc = slender.CharacterMovement
        if Logger.IsValidObj(cmc) then
            cmc.GravityScale = 0.0
            cmc:SetMovementMode(0, 0)
        end
    end)

    pcall(function()
        local mesh = slender.Mesh
        if Logger.IsValidObj(mesh) then
            State.MeshComp = mesh
            State.IdleAnim = idleAnim
            State.WalkAnim = walkAnim

            if mesh.SetSkinnedAssetAndUpdate and Logger.IsValidObj(skAsset) then
                pcall(function() mesh:SetSkinnedAssetAndUpdate(skAsset, true) end)
            elseif mesh.SetSkeletalMeshAsset and Logger.IsValidObj(skAsset) then
                pcall(function() mesh:SetSkeletalMeshAsset(skAsset, true) end)
            end

            pcall(function() mesh:K2_SetRelativeLocation({ X = 0.0, Y = 0.0, Z = -Config.SLENDER.CAPSULE_HALF_HEIGHT }, false, {}, true) end)
            pcall(function() mesh:K2_SetRelativeRotation({ Pitch = 0.0, Yaw = -90.0, Roll = 0.0 }, false, {}, true) end)
            pcall(function()
                mesh:SetOnlyOwnerSee(false)
                mesh:SetOwnerNoSee(false)
                mesh:SetHiddenInGame(false, true)
                mesh:SetVisibility(true, true)
                mesh:SetCastShadow(true)
                mesh:Activate(true)
                if mesh.ReregisterComponent then mesh:ReregisterComponent() end
            end)

            if Logger.IsValidObj(idleAnim) then
                ApplyAnimState(false)
            end
            if State.AnimState == "None" and Logger.IsValidObj(animCls) then
                local okBp, errBp = pcall(function() mesh:SetAnimInstanceClass(animCls) end)
                State.AnimState = okBp and "AnimBP" or ("Err:" .. tostring(errBp))
            end

            Logger.Info(string.format("Slender Mesh ready: Skinned=%s AnimMode=%s Idle=%s Walk=%s",
                Logger.SafeName(mesh:GetSkinnedAsset()), State.AnimState,
                Logger.SafeName(idleAnim), Logger.SafeName(walkAnim)))
        end
    end)

    pcall(function() slender:SetActorHiddenInGame(false) end)

    -- Attach real 3D Slenderman tentacles (SM_Tentacle_01..04) hidden until Psychic Dread / Terrify
    local attachedTentacles = 0
    local scCls  = Bridge.GetClass("/Script/Engine.SceneComponent")
    local smcCls = Bridge.GetClass("/Script/Engine.StaticMeshComponent")
    local tMat   = Bridge.LoadOrFindAsset(Config.UI_ASSETS.TENTACLE_MATERIAL)
    if Logger.IsValidObj(scCls) and Logger.IsValidObj(smcCls) and Logger.IsValidObj(State.MeshComp) then
        local gLoc = Config.UI_ASSETS.TENTACLE_GROUP_LOC
        local gRot = Config.UI_ASSETS.TENTACLE_GROUP_ROT
        local idXform = {
            Rotation    = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
            Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
            Scale3D     = { X = 1.0, Y = 1.0, Z = 1.0 },
        }
        local grp = nil
        pcall(function() grp = slender:AddComponentByClass(scCls, true, idXform, false) end)
        if Logger.IsValidObj(grp) then
            pcall(function()
                grp:K2_AttachToComponent(State.MeshComp, Bridge.FName("None"), 0, 0, 0, false)
                grp:K2_SetRelativeLocation(gLoc, false, {}, true)
                grp:K2_SetRelativeRotation(gRot, false, {}, true)
                if Config.UI_ASSETS.TENTACLE_GROUP_SCALE then
                    grp:SetRelativeScale3D(Config.UI_ASSETS.TENTACLE_GROUP_SCALE)
                end
                grp:SetHiddenInGame(true, true)
                grp:SetVisibility(false, true)
            end)
            State.TentacleGroup = grp

            for _, meshPath in ipairs(Config.UI_ASSETS.TENTACLE_MESHES) do
                local sm = Bridge.LoadOrFindAsset(meshPath)
                if Logger.IsValidObj(sm) then
                    local tc = nil
                    pcall(function() tc = slender:AddComponentByClass(smcCls, true, idXform, false) end)
                    if Logger.IsValidObj(tc) then
                        pcall(function()
                            tc:K2_AttachToComponent(grp, Bridge.FName("None"), 0, 0, 0, false)
                            tc:SetStaticMesh(sm)
                            if Logger.IsValidObj(tMat) then tc:SetMaterial(0, tMat) end
                            tc:SetCollisionEnabled(0)
                            tc:SetCollisionResponseToAllChannels(0)
                            tc:SetGenerateOverlapEvents(false)
                            tc:SetCastShadow(true)
                            tc:SetOnlyOwnerSee(false)
                            tc:SetOwnerNoSee(false)
                            tc:SetHiddenInGame(true, true)
                            tc:SetVisibility(false, true)
                        end)
                        table.insert(State.TentacleComps, tc)
                        attachedTentacles = attachedTentacles + 1
                    end
                end
            end
        end
    end

    State.Actor = slender
    State.Yaw   = faceYaw

    -- Neutralize all vanilla AI threats (Teleporter/Slender, Chaser, Charlie) on any chapter except our own pawn
    local neutralized = 0
    for _, enemyCls in ipairs({
        "BP_Teleporter_C",
        "BP_Chaser_C",
        "BP_Chaser_TheArrivalBasement_C",
        "BP_Charlie_C",
        "BP_CharlieHouse_C",
        "BP_HouseChaseCharlie_C",
        "BP_BasementCharlie_C",
        "BP_ChapelCharlie_C",
        "BP_CharlieField_C",
        "BP_Charlie_Hospital_C",
        "BP_Charlie_Cellar_C",
        "BP_Charlie_TheArrivalHall_C",
        "BP_Charlie_TheArrivalInvisibleMonster_C",
    }) do
        for _, foe in ipairs(FindAllOf(enemyCls) or {}) do
            if Logger.IsValidObj(foe) and foe ~= slender then
                pcall(function()
                    local fc = foe:GetController()
                    if Logger.IsValidObj(fc) then
                        fc:UnPossess()
                        fc:Destroy()
                    end
                end)
                pcall(function() foe:SetActorHiddenInGame(true) end)
                pcall(function() foe:SetActorEnableCollision(false) end)
                pcall(function() foe:SetActorTickEnabled(false) end)
                pcall(function() foe:K2_SetActorLocation({ X = 0.0, Y = 0.0, Z = -55000.0 }, false, {}, true) end)
                neutralized = neutralized + 1
            end
        end
    end
    if neutralized > 0 then
        Logger.Info("SlenderController neutralized vanilla enemies: " .. tostring(neutralized))
    end
    State.Doors = {}
    for _, d in ipairs(FindAllOf("BP_DoorBase_C") or {}) do
        if Logger.IsValidObj(d) then
            local loc = Bridge.GetActorLoc(d)
            if loc then
                table.insert(State.Doors, { actor = d, pos = loc, opened = false })
            end
        end
    end

    Logger.Info(string.format("SlenderController ready @ (%.1f, %.1f, %.1f) dist=%.1fm Yaw=%.1f Tentacles=%d",
        spawnLoc.X, spawnLoc.Y, spawnLoc.Z, Bridge.Dist2D(spawnLoc, survLoc) / 100.0, faceYaw, attachedTentacles))
    return true, spawnLoc, faceYaw
end

local function ResolveHorizontalMove(world, curPos, dirX, dirY, moveDist, ignore)
    local r = Config.SLENDER.CAPSULE_RADIUS
    local probeHeights = { -15.0, 50.0 }
    local vx, vy = dirX * moveDist, dirY * moveDist

    for _, dz in ipairs(probeHeights) do
        local startP = { X = curPos.X, Y = curPos.Y, Z = curPos.Z + dz }
        local endP   = { X = curPos.X + vx + dirX * r, Y = curPos.Y + vy + dirY * r, Z = curPos.Z + dz }
        local hit, info = Bridge.LineTrace(world, startP, endP, ignore, "Pawn", false)
        if hit and info and info.ImpactNormal then
            local norm = info.ImpactNormal
            if math.abs(norm.Z) < 0.55 then
                local nLen = math.sqrt(norm.X * norm.X + norm.Y * norm.Y)
                if nLen > 0.01 then
                    local nx2 = norm.X / nLen
                    local ny2 = norm.Y / nLen
                    local dot = vx * nx2 + vy * ny2
                    if dot < 0.0 then
                        vx = vx - dot * nx2
                        vy = vy - dot * ny2
                    end
                end
            end
        end
    end

    local finalDist = math.sqrt(vx * vx + vy * vy)
    if finalDist > 0.5 then
        local fx = vx / finalDist
        local fy = vy / finalDist
        local checkStart = { X = curPos.X, Y = curPos.Y, Z = curPos.Z + 10.0 }
        local checkEnd   = { X = curPos.X + vx + fx * (r * 0.75), Y = curPos.Y + vy + fy * (r * 0.75), Z = curPos.Z + 10.0 }
        local hit2, info2 = Bridge.LineTrace(world, checkStart, checkEnd, ignore, "Pawn", false)
        if hit2 and info2 and info2.ImpactNormal and math.abs(info2.ImpactNormal.Z) < 0.55 then
            return curPos.X, curPos.Y, false
        end
    end

    return curPos.X + vx, curPos.Y + vy, true
end

function SlenderCtrl.MoveDirection(world, mx, my, dt, sprint, survivor)
    if not Logger.IsValidObj(State.Actor) then return false end
    local mLen = math.sqrt(mx * mx + my * my)
    if mLen < 0.001 then return false end
    mx = mx / mLen
    my = my / mLen

    State.IsMoving    = true
    State.IsSprinting = (sprint == true)
    ApplyAnimState(true)

    local speed = State.IsSprinting and Config.SLENDER.SPRINT_SPEED or Config.SLENDER.WALK_SPEED
    local stepDist = speed * dt

    local curPos = Bridge.GetActorLoc(State.Actor)
    if not curPos then return false end

    local ignore = { State.Actor }
    if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end

    local nextX, nextY, moved = ResolveHorizontalMove(world, curPos, mx, my, stepDist, ignore)
    local targetZ = curPos.Z

    local gHit, gz, gNorm = Bridge.GroundTrace(
        world,
        nextX,
        nextY,
        curPos.Z + Config.SLENDER.MAX_STEP_HEIGHT,
        curPos.Z - 400.0,
        ignore, "Pawn"
    )
    if gHit and gNorm then
        if gNorm.Z >= 0.50 then
            local desiredZ = gz + Config.SLENDER.CAPSULE_HALF_HEIGHT
            local dz = desiredZ - curPos.Z
            if dz > Config.SLENDER.MAX_STEP_HEIGHT then
                nextX, nextY = curPos.X, curPos.Y
                targetZ = curPos.Z
            else
                targetZ = Bridge.Lerp(curPos.Z, desiredZ, math.min(1.0, 18.0 * dt))
            end
        else
            nextX, nextY = curPos.X, curPos.Y
        end
    end

    local targetYaw = Bridge.YawFromVec(mx, my)
    State.Yaw = Bridge.LerpAngle(State.Yaw, targetYaw, math.min(1.0, Config.SLENDER.ROTATE_INTERP * dt))

    pcall(function()
        State.Actor:K2_SetActorLocationAndRotation(
            { X = nextX, Y = nextY, Z = targetZ },
            { Pitch = 0.0, Yaw = State.Yaw, Roll = 0.0 },
            false, {}, true
        )
    end)
    return moved
end

local function OpenNearbyDoorsForSlender()
    local now = os.clock()
    if (now - State.LastDoorCheck) < 0.25 or #State.Doors == 0 or not Logger.IsValidObj(State.Actor) then return end
    State.LastDoorCheck = now
    local slLoc = Bridge.GetActorLoc(State.Actor)
    if not slLoc then return end
    for _, dEntry in ipairs(State.Doors) do
        local door = dEntry.actor
        if (not dEntry.opened) and Logger.IsValidObj(door) then
            if Bridge.Dist2D(slLoc, dEntry.pos) <= 155.0 and math.abs(slLoc.Z - dEntry.pos.Z) <= 180.0 then
                local PrologueStory = require("prologue_story")
                local dn = Logger.SafeName(door)
                local openAI = true
                pcall(function() openAI = (door.bOpenableByAI ~= false) end)
                local st = 0
                pcall(function() st = door:GetState() end)
                if string.find(dn, "BP_Door_Main", 1, true) and st ~= 3 then openAI = true end
                if string.find(dn, "Locked", 1, true) or st == 3 then openAI = false end
                if PrologueStory.ShouldBlockDoorAI and PrologueStory.ShouldBlockDoorAI(door) then openAI = false end
                if openAI and st ~= 1 then
                    dEntry.opened = true
                    pcall(function() door:SetState(State.Actor, 1, false) end)
                    pcall(function() door:RequestStateChange(State.Actor, 1) end)
                    pcall(function()
                        if Logger.IsValidObj(door.DoorCollisionAndNavigationBlocker) then
                            door.DoorCollisionAndNavigationBlocker:SetCollisionEnabled(0)
                        end
                    end)
                end
            end
        end
    end
end

function SlenderCtrl.Update(world, pc, dt, camYaw, survivor, freezeMovement)
    if not Logger.IsValidObj(State.Actor) or not Logger.IsValidObj(pc) then return end
    if freezeMovement then
        State.IsMoving = false
        ApplyAnimState(false)
        return
    end

    OpenNearbyDoorsForSlender()

    local fwdIn   = (Bridge.IsKeyDown(pc, Config.KEYS.FORWARD)  and 1 or 0) - (Bridge.IsKeyDown(pc, Config.KEYS.BACKWARD) and 1 or 0)
    local rightIn = (Bridge.IsKeyDown(pc, Config.KEYS.RIGHT)    and 1 or 0) - (Bridge.IsKeyDown(pc, Config.KEYS.LEFT)     and 1 or 0)

    if fwdIn == 0 and rightIn == 0 then
        State.IsMoving    = false
        State.IsSprinting = false
        ApplyAnimState(false)
        return
    end

    local fx, fy, _ = Bridge.ForwardFromRot(0.0, camYaw)
    local rx, ry, _ = Bridge.RightFromYaw(camYaw)
    local mx = fx * fwdIn + rx * rightIn
    local my = fy * fwdIn + ry * rightIn

    local sprint = Bridge.IsKeyDown(pc, Config.KEYS.SPRINT)
    SlenderCtrl.MoveDirection(world, mx, my, dt, sprint, survivor)
end

function SlenderCtrl.SetPositionSafe(world, pos, faceYaw)
    if not Logger.IsValidObj(State.Actor) or not pos then return false end
    if faceYaw then State.Yaw = faceYaw end
    local ok = pcall(function()
        State.Actor:K2_SetActorLocationAndRotation(
            pos,
            { Pitch = 0.0, Yaw = State.Yaw, Roll = 0.0 },
            false, {}, true
        )
    end)
    return ok
end

return SlenderCtrl
