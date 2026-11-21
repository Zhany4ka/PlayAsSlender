-- PlayAsSlender Abilities (Q Teleport, E Psychic Dread, F Active Terrify)
local Config      = require("config")
local Logger      = require("logger")
local Bridge      = require("ue_bridge")
local SlenderCtrl = require("slender_controller")
local CameraCtrl  = require("camera_controller")
local Overlay     = require("debug_overlay")

local okOM, ObjectiveManager = pcall(require, "objective_manager")
if not okOM then ObjectiveManager = nil end
local okHP, HumanPerception = pcall(require, "human_perception")
if not okHP then HumanPerception = nil end

local Abilities = {}

local State = {
    CooldownTeleport = 0.0,
    CooldownDread    = 0.0,
    CooldownTerrify  = 0.0,
    DreadActiveLeft  = 0.0,
    TentacleShowLeft = 0.0,
    TerrifyFlash     = 0.0,
    TeleportsUsed    = 0,
    ScaresLanded     = 0,
    InterceptsLanded = 0,
}

function Abilities.Reset()
    State.CooldownTeleport = 0.0
    State.CooldownDread    = 0.0
    State.CooldownTerrify  = 0.0
    State.DreadActiveLeft  = 0.0
    State.TentacleShowLeft = 0.0
    State.TerrifyFlash     = 0.0
    State.TeleportsUsed    = 0
    State.ScaresLanded     = 0
    State.InterceptsLanded = 0
end

function Abilities.GetCooldowns()
    return State.CooldownTeleport, State.CooldownDread, State.CooldownTerrify, (State.DreadActiveLeft > 0.0)
end

function Abilities.GetUiState()
    return {
        cdTp         = State.CooldownTeleport,
        cdTpMax      = Config.ABILITIES.TELEPORT_COOLDOWN,
        cdDr         = State.CooldownDread,
        cdDrMax      = Config.ABILITIES.DREAD_COOLDOWN,
        cdTr         = State.CooldownTerrify,
        cdTrMax      = Config.ABILITIES.TERRIFY_COOLDOWN,
        dreadActive  = (State.DreadActiveLeft > 0.0),
        dreadRem     = State.DreadActiveLeft,
        dreadMax     = Config.ABILITIES.DREAD_DURATION,
        terrifyFlash = State.TerrifyFlash,
    }
end

function Abilities.GetStats()
    return State.TeleportsUsed, State.ScaresLanded, State.InterceptsLanded
end

function Abilities.IsDreadActive()
    return State.DreadActiveLeft > 0.0
end

-- Validate teleport destination: ground snap, obstacle clearance, and Human LOS pop-in check
function Abilities.ValidateTeleportDest(world, candXY, refZ, slender, survivor, humanForward)
    local ignore = {}
    if Logger.IsValidObj(slender)  then table.insert(ignore, slender)  end
    if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end

    local traceRefZ = (candXY and candXY.Z) or refZ
    local gHit, gz, gNorm = Bridge.GroundTrace(world, candXY.X, candXY.Y, traceRefZ + 320.0, traceRefZ - 1600.0, ignore)
    if not gHit or not gNorm then
        return false, nil, "No solid ground at target"
    end
    if gNorm.Z < 0.65 then
        return false, nil, "Surface too steep"
    end

    local finalPos = { X = candXY.X, Y = candXY.Y, Z = gz + Config.SLENDER.CAPSULE_HALF_HEIGHT }

    -- Upward headroom clearance check
    local headHit = Bridge.LineTrace(world, { X = finalPos.X, Y = finalPos.Y, Z = gz + 20.0 }, { X = finalPos.X, Y = finalPos.Y, Z = gz + 225.0 }, ignore, 0, false)
    if headHit then
        return false, nil, "Blocked: Low ceiling or obstacle"
    end

    -- 8-directional radial obstacle clearance check around capsule
    local r = Config.SLENDER.CAPSULE_RADIUS + 12.0
    for k = 0, 7 do
        local ang = (k * math.pi) / 4.0
        local ox  = math.cos(ang) * r
        local oy  = math.sin(ang) * r
        for _, zOff in ipairs({ 35.0, 120.0 }) do
            local p0 = { X = finalPos.X, Y = finalPos.Y, Z = gz + zOff }
            local p1 = { X = finalPos.X + ox, Y = finalPos.Y + oy, Z = gz + zOff }
            if Bridge.LineTrace(world, p0, p1, ignore, 0, false) then
                return false, nil, "Blocked: Obstacle at destination"
            end
        end
    end

    -- Check Human direct LOS: forbid cheap close-range frontal pop-in or spawning inside/on top of Human
    if Logger.IsValidObj(survivor) then
        local hLoc = Bridge.GetActorLoc(survivor)
        if hLoc then
            local dist3D = Bridge.Dist(finalPos, hLoc)
            local dist2D = Bridge.Dist2D(finalPos, hLoc)
            if dist3D < 260.0 or dist2D < 240.0 then
                return false, nil, "Too close to Human"
            end
            if dist3D < Config.ABILITIES.TELEPORT_LOS_BLOCK_DIST and humanForward then
                local toDestX = finalPos.X - hLoc.X
                local toDestY = finalPos.Y - hLoc.Y
                local len = math.sqrt(toDestX * toDestX + toDestY * toDestY)
                if len > 1.0 then
                    local dot = (toDestX / len) * humanForward.X + (toDestY / len) * humanForward.Y
                    if dot > 0.45 then -- within ~63 deg frontal cone
                        local eyeH = { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z + 65.0 }
                        local clearLOS = Bridge.HasLineOfSight(world, eyeH, { X = finalPos.X, Y = finalPos.Y, Z = gz + 170.0 }, ignore, nil)
                            or Bridge.HasLineOfSight(world, eyeH, { X = finalPos.X, Y = finalPos.Y, Z = gz + 115.0 }, ignore, nil)
                        if clearLOS then
                            return false, nil, "Blocked: Human is watching that spot"
                        end
                    end
                end
            end
        end
    end

    return true, finalPos, "OK"
end

function Abilities.TryTeleport(world, slender, survivor, humanForward, overrideTargetPos)
    if State.CooldownTeleport > 0.05 then
        Overlay.ShowToast(string.format("Teleport on cooldown (%.1fs)", State.CooldownTeleport), 1.5)
        return false, "Cooldown"
    end
    if not Logger.IsValidObj(slender) then return false, "NoSlender" end

    local slPos = Bridge.GetActorLoc(slender)
    if not slPos then return false, "NoPos" end

    local validPos, reason = nil, "No valid destination"
    local ok = false

    if overrideTargetPos then
        ok, validPos, reason = Abilities.ValidateTeleportDest(world, overrideTargetPos, slPos.Z, slender, survivor, humanForward)
    else
        local camPos, camFwd = CameraCtrl.GetViewRay()
        local horizLen = math.sqrt(camFwd.X * camFwd.X + camFwd.Y * camFwd.Y)
        local dirX = horizLen > 0.05 and (camFwd.X / horizLen) or 1.0
        local dirY = horizLen > 0.05 and (camFwd.Y / horizLen) or 0.0

        local traceStart = {
            X = camPos.X + camFwd.X * 260.0,
            Y = camPos.Y + camFwd.Y * 260.0,
            Z = camPos.Z + camFwd.Z * 260.0,
        }
        local traceEnd = {
            X = slPos.X + camFwd.X * Config.ABILITIES.TELEPORT_MAX_DIST,
            Y = slPos.Y + camFwd.Y * Config.ABILITIES.TELEPORT_MAX_DIST,
            Z = slPos.Z + camFwd.Z * Config.ABILITIES.TELEPORT_MAX_DIST,
        }
        local ignore = {}
        if Logger.IsValidObj(slender)  then table.insert(ignore, slender)  end
        if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end

        local cands = {}
        local hit, info = Bridge.LineTrace(world, traceStart, traceEnd, ignore, 0, false)
        if hit and info and info.ImpactPoint then
            table.insert(cands, {
                X = info.ImpactPoint.X - dirX * 90.0,
                Y = info.ImpactPoint.Y - dirY * 90.0,
                Z = info.ImpactPoint.Z,
            })
        end
        for _, distStep in ipairs({ Config.ABILITIES.TELEPORT_MAX_DIST, 2400.0, 1600.0, 950.0 }) do
            local raw = { X = slPos.X + dirX * distStep, Y = slPos.Y + dirY * distStep, Z = slPos.Z }
            local okNav, proj = Bridge.ProjectPointToNav(world, raw, { X = 400.0, Y = 400.0, Z = 900.0 })
            table.insert(cands, okNav and proj or raw)
        end

        for _, cand in ipairs(cands) do
            if Bridge.Dist2D(slPos, cand) >= Config.ABILITIES.TELEPORT_MIN_DIST then
                local cok, vpos, rsn = Abilities.ValidateTeleportDest(world, cand, slPos.Z, slender, survivor, humanForward)
                if cok then
                    ok, validPos, reason = true, vpos, rsn
                    break
                else
                    reason = rsn
                end
            end
        end
    end

    if not ok then
        Overlay.ShowToast(reason, 2.0)
        Logger.Info("Teleport rejected: " .. tostring(reason))
        return false, reason
    end

    local newYaw = CameraCtrl.GetYaw()
    if Logger.IsValidObj(survivor) then
        local hLoc = Bridge.GetActorLoc(survivor)
        if hLoc then
            newYaw = Bridge.YawFromVec(hLoc.X - validPos.X, hLoc.Y - validPos.Y)
        end
    end

    SlenderCtrl.SetPositionSafe(world, validPos, newYaw)
    CameraCtrl.NotifyTeleport()
    State.CooldownTeleport = Config.ABILITIES.TELEPORT_COOLDOWN
    State.TeleportsUsed    = State.TeleportsUsed + 1
    Bridge.PlaySound2D(world, Config.ASSETS.SOUND_FAR_SIGHT, 0.55, 1.0, { "Teleporter_Far", "Teleporter" })
    Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_STATIC_GLITCH, 0.45, 1.0, { "staticglitch" })
    Logger.Info(string.format("Teleported to (%.1f, %.1f, %.1f)", validPos.X, validPos.Y, validPos.Z))
    return true, "OK"
end

function Abilities.TryPsychicDread(world)
    if State.CooldownDread > 0.05 then
        Overlay.ShowToast(string.format("Psychic Dread on cooldown (%.1fs)", State.CooldownDread), 1.5)
        return false
    end
    State.CooldownDread    = Config.ABILITIES.DREAD_COOLDOWN
    State.DreadActiveLeft  = Config.ABILITIES.DREAD_DURATION
    State.TentacleShowLeft = math.max(State.TentacleShowLeft, Config.ABILITIES.DREAD_DURATION)
    SlenderCtrl.SetTentaclesVisible(true)
    Bridge.PlaySound2D(world, Config.ASSETS.SOUND_MED_SIGHT, 0.58, 0.95, { "Teleporter_Medium", "Teleporter" })
    Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_TENTACLES, 0.60, 1.0, { "tentacles_Cue", "tentacles" })
    Overlay.ShowToast("Psychic Dread Unleashed!", 2.0)
    Logger.Info("Ability activated: Psychic Dread")
    return true
end

function Abilities.TryTerrify(world, slender, survivor, fearSystem, humanAI)
    if State.CooldownTerrify > 0.05 then
        Overlay.ShowToast(string.format("Terrify on cooldown (%.1fs)", State.CooldownTerrify), 1.5)
        return false
    end
    if not Logger.IsValidObj(slender) or not Logger.IsValidObj(survivor) then return false end

    local slPos = Bridge.GetActorLoc(slender)
    local hLoc  = Bridge.GetActorLoc(survivor)
    if not slPos or not hLoc then return false end

    local dist = Bridge.Dist(slPos, hLoc)
    if dist > Config.ABILITIES.TERRIFY_RANGE then
        Overlay.ShowToast("Terrify failed: Human is out of range", 2.0)
        return false
    end

    local hasLOS = Bridge.HasLineOfSight(
        world,
        { X = slPos.X, Y = slPos.Y, Z = slPos.Z + 70.0 },
        { X = hLoc.X,  Y = hLoc.Y,  Z = hLoc.Z + 65.0 },
        { slender, survivor },
        nil
    )
    if not hasLOS and dist > Config.ABILITIES.TERRIFY_PROXIMITY_NO_LOS then
        Overlay.ShowToast("Terrify failed: Blocked by obstacle", 2.0)
        return false
    end

    -- Distance-weighted Fear spike (balanced: never instant-kills from calm)
    local t = 1.0 - Bridge.Clamp(dist / Config.ABILITIES.TERRIFY_RANGE, 0.0, 1.0)
    local spike = Bridge.Lerp(Config.ABILITIES.TERRIFY_FEAR_MIN, Config.ABILITIES.TERRIFY_FEAR_MAX, t)

    -- Bonus Fear + Intercept tracking when interrupting interaction or catching Survivor near an objective
    local isIntercept = (humanAI and humanAI.GetState and humanAI.GetState() == "Interacting") == true
    if (not isIntercept) and ObjectiveManager and ObjectiveManager.GetRawUncollectedPages then
        for _, pg in ipairs(ObjectiveManager.GetRawUncollectedPages() or {}) do
            if pg and pg.pos and Bridge.Dist(hLoc, pg.pos) <= 500.0 then
                isIntercept = true
                break
            end
        end
    end
    if isIntercept then
        State.InterceptsLanded = State.InterceptsLanded + 1
        spike = spike + 6.0
    end

    if fearSystem and fearSystem.ApplyTerrifySpike then
        fearSystem.ApplyTerrifySpike(spike)
    end
    if humanAI and humanAI.OnTerrified then
        humanAI.OnTerrified(slPos)
    end

    State.CooldownTerrify  = Config.ABILITIES.TERRIFY_COOLDOWN
    State.TentacleShowLeft = math.max(State.TentacleShowLeft, 3.0)
    State.TerrifyFlash     = 1.0
    State.ScaresLanded     = State.ScaresLanded + 1
    SlenderCtrl.SetTentaclesVisible(true)
    Bridge.PlaySound2D(world, Config.ASSETS.SOUND_DRAMATIC, 0.85, 1.0, { "Teleporter_Dramatic", "Teleporter" })
    local toastMsg = isIntercept
        and string.format("Objective Interrupted! (+%.0f Fear)", spike)
        or  string.format("Terrified Human (+%.0f Fear)!", spike)
    Overlay.ShowToast(toastMsg, 2.2)
    Logger.Info(string.format("Ability activated: Terrify dist=%.0f spike=%.1f intercept=%s", dist, spike, tostring(isIntercept)))
    return true
end

function Abilities.Update(world, pc, dt, slender, survivor, humanForward, fearSystem, humanAI)
    local dreadActiveNow = (State.DreadActiveLeft > 0.0)
    if State.CooldownTeleport > 0.0 then State.CooldownTeleport = math.max(0.0, State.CooldownTeleport - dt) end
    if State.CooldownDread    > 0.0 then State.CooldownDread    = math.max(0.0, State.CooldownDread    - dt) end
    if State.CooldownTerrify  > 0.0 then
        local extraTerrifyCd = 0.0
        if dreadActiveNow then
            local mem = (HumanPerception and HumanPerception.GetMemory) and HumanPerception.GetMemory() or nil
            local unseen = not (mem and mem.HasLOS)
            local dist = nil
            if Logger.IsValidObj(slender) and Logger.IsValidObj(survivor) then
                local slPos = Bridge.GetActorLoc(slender)
                local hLoc  = Bridge.GetActorLoc(survivor)
                if slPos and hLoc then
                    dist = Bridge.Dist(slPos, hLoc)
                end
            end
            if (not dist) and mem then
                dist = mem.SlenderDist
            end
            if unseen and dist and dist >= 800.0 and dist <= 2400.0 then
                extraTerrifyCd = dt * 0.25
            end
        end
        State.CooldownTerrify = math.max(0.0, State.CooldownTerrify - dt - extraTerrifyCd)
    end
    if State.DreadActiveLeft  > 0.0 then State.DreadActiveLeft  = math.max(0.0, State.DreadActiveLeft  - dt) end
    if State.TerrifyFlash     > 0.0 then State.TerrifyFlash     = math.max(0.0, State.TerrifyFlash - dt / 1.4) end

    if State.TentacleShowLeft > 0.0 then
        State.TentacleShowLeft = math.max(0.0, State.TentacleShowLeft - dt)
        if State.TentacleShowLeft <= 0.0 then
            SlenderCtrl.SetTentaclesVisible(false)
        end
    end

    if Bridge.WasKeyJustPressed(pc, Config.KEYS.TELEPORT) then
        Abilities.TryTeleport(world, slender, survivor, humanForward, nil)
    elseif Bridge.WasKeyJustPressed(pc, Config.KEYS.PSYCHIC_DREAD) then
        Abilities.TryPsychicDread(world)
    elseif Bridge.WasKeyJustPressed(pc, Config.KEYS.TERRIFY) then
        Abilities.TryTerrify(world, slender, survivor, fearSystem, humanAI)
    end
end

return Abilities
