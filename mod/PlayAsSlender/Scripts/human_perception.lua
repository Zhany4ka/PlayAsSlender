-- PlayAsSlender Human Perception & Bounded Memory (Non-Omniscient FOV, LOS Occlusion, Sixth-Sense, Danger Zones)
local Config           = require("config")
local Logger           = require("logger")
local Bridge           = require("ue_bridge")
local ObjectiveManager = require("objective_manager")

local HumanPerception = {}

local Memory = {
    HasLOS                  = false,
    SlenderVisibleTime      = 0.0,
    TimeSinceLastSawSlender = 999.0,
    LastKnownSlenderPos     = nil,
    LastKnownSlenderAt      = 0.0,
    SlenderDist             = 99999.0,
    GazeDot                 = 0.0,
    PeripheralGlimpse       = false,
    SixthSenseTriggered     = false,
    SuspicionLevel          = 0.0,
    LastSuspicionPos        = nil,
    LastSuspicionReason     = "None",
    DangerZones             = {}, -- { pos, radius, intensity, expiresAt }
    UpdateAccum             = 0.0,
}

function HumanPerception.Reset()
    Memory.HasLOS                  = false
    Memory.SlenderVisibleTime      = 0.0
    Memory.TimeSinceLastSawSlender = 999.0
    Memory.LastKnownSlenderPos     = nil
    Memory.LastKnownSlenderAt      = 0.0
    Memory.SlenderDist             = 99999.0
    Memory.GazeDot                 = 0.0
    Memory.PeripheralGlimpse       = false
    Memory.SixthSenseTriggered     = false
    Memory.SuspicionLevel          = 0.0
    Memory.LastSuspicionPos        = nil
    Memory.LastSuspicionReason     = "None"
    Memory.DangerZones             = {}
    Memory.UpdateAccum             = 0.0
end

function HumanPerception.GetMemory()
    return Memory
end

function HumanPerception.GetDangerZones()
    return Memory.DangerZones
end

function HumanPerception.ConsumeSuspicion(amount)
    Memory.SuspicionLevel = math.max(0.0, Memory.SuspicionLevel - (amount or 0.4))
end

function HumanPerception.AddDangerZone(pos, radius, intensity, durationSec)
    if not pos then return end
    local now = os.clock()
    local r = radius or 2200.0
    local inten = intensity or 1.0
    local exp = now + (durationSec or 45.0)
    for _, dz in ipairs(Memory.DangerZones) do
        if Bridge.Dist2D(dz.pos, pos) < 1100.0 then
            dz.pos.X = (dz.pos.X + pos.X) * 0.5
            dz.pos.Y = (dz.pos.Y + pos.Y) * 0.5
            dz.intensity = math.min(2.0, math.max(dz.intensity, inten) + 0.15)
            dz.expiresAt = math.max(dz.expiresAt, exp)
            return
        end
    end
    table.insert(Memory.DangerZones, {
        pos       = { X = pos.X, Y = pos.Y, Z = pos.Z },
        radius    = r,
        intensity = inten,
        expiresAt = exp,
    })
end

function HumanPerception.NotifyDreadPresence(slPos, dist, hasDirectLOS)
    if not slPos then return end
    Memory.SuspicionLevel = math.min(1.0, Memory.SuspicionLevel + (hasDirectLOS and 0.45 or 0.25))
    -- Dread creates a vague directional unease (jittered unless directly seen)
    local j = hasDirectLOS and 0.0 or 380.0
    Memory.LastSuspicionPos = {
        X = slPos.X + (math.sin(os.clock() * 7.3) * j),
        Y = slPos.Y + (math.cos(os.clock() * 5.9) * j),
        Z = slPos.Z,
    }
    Memory.LastSuspicionReason = "PsychicDread"
end

function HumanPerception.NotifyTerrify(slPos)
    if not slPos then return end
    Memory.SuspicionLevel = 1.0
    Memory.LastKnownSlenderPos = { X = slPos.X, Y = slPos.Y, Z = slPos.Z }
    Memory.LastKnownSlenderAt  = os.clock()
    Memory.LastSuspicionPos    = Memory.LastKnownSlenderPos
    Memory.LastSuspicionReason = "Terrified"
    HumanPerception.AddDangerZone(slPos, 2400.0, 1.4, 50.0)
end

local function EvaluateStep(world, dtStep, survivor, slender, humanForward, currentFear, canDiscoverObjectives)
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(survivor) then return end
    local hLoc = Bridge.GetActorLoc(survivor)
    if not hLoc then return end
    local eyePos = { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z + 65.0 }
    local fwd = humanForward or { X = 1.0, Y = 0.0, Z = 0.0 }

    -- Prune expired DangerZones & decay Suspicion naturally
    local now = os.clock()
    local kept = {}
    for _, dz in ipairs(Memory.DangerZones) do
        if dz.expiresAt > now then
            table.insert(kept, dz)
        end
    end
    Memory.DangerZones = kept
    Memory.SuspicionLevel = math.max(0.0, Memory.SuspicionLevel - 0.22 * dtStep)
    Memory.PeripheralGlimpse = false
    Memory.SixthSenseTriggered = false

    local ignoreSlender = { survivor }
    if Logger.IsValidObj(slender) then table.insert(ignoreSlender, slender) end

    -- 1. Evaluate Slenderman visibility (STRICTLY gated by range + FOV + LineTraceSingle occlusion!)
    local sawThisStep = false
    if Logger.IsValidObj(slender) then
        local sLoc = Bridge.GetActorLoc(slender)
        if sLoc then
            local targetPos = { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z + 55.0 }
            local dist = Bridge.Dist(eyePos, targetPos)
            Memory.SlenderDist = dist

            local dx = targetPos.X - eyePos.X
            local dy = targetPos.Y - eyePos.Y
            local hLen = math.sqrt(dx * dx + dy * dy)
            local gazeDot = (hLen > 1.0) and ((dx / hLen) * fwd.X + (dy / hLen) * fwd.Y) or 1.0
            Memory.GazeDot = gazeDot

            local fovCos     = math.cos(math.rad(Config.HUMAN.FOV_HALF_ANGLE_DEG))
            local periphCos  = math.cos(math.rad(72.0))

            local inPrimaryFOV = (dist <= Config.HUMAN.SLENDER_VISION_RANGE) and (gazeDot >= fovCos)
            local inPeriphFOV  = (dist <= 1650.0) and (gazeDot >= periphCos)
            local inSixthSense = (dist <= Config.HUMAN.SIXTH_SENSE_RADIUS)

            if inPrimaryFOV or inPeriphFOV or inSixthSense then
                local clearLOS = Bridge.HasLineOfSight(world, eyePos, targetPos, ignoreSlender, slender)
                -- Also check upper chest/head ray in case waist foliage clipped
                if not clearLOS and inPrimaryFOV then
                    clearLOS = Bridge.HasLineOfSight(
                        world,
                        eyePos,
                        { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z + 92.0 },
                        ignoreSlender,
                        slender
                    )
                end

                if clearLOS then
                    if inPrimaryFOV then
                        sawThisStep = true
                        Memory.HasLOS = true
                        Memory.SlenderVisibleTime = Memory.SlenderVisibleTime + dtStep
                        Memory.TimeSinceLastSawSlender = 0.0
                        Memory.LastKnownSlenderPos = { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z }
                        Memory.LastKnownSlenderAt  = now
                        Memory.SuspicionLevel      = 1.0
                        Memory.LastSuspicionPos    = Memory.LastKnownSlenderPos
                        Memory.LastSuspicionReason = "DirectSight"
                        HumanPerception.AddDangerZone(sLoc, 2200.0, 1.2, 45.0)
                    elseif inSixthSense then
                        Memory.SixthSenseTriggered = true
                        Memory.SuspicionLevel = math.min(1.0, Memory.SuspicionLevel + 0.85)
                        Memory.LastSuspicionPos = { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z }
                        Memory.LastSuspicionReason = "SixthSense"
                    elseif inPeriphFOV then
                        Memory.PeripheralGlimpse = true
                        Memory.SuspicionLevel = math.min(1.0, Memory.SuspicionLevel + 0.55 * dtStep * 4.0)
                        Memory.LastSuspicionPos = { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z }
                        Memory.LastSuspicionReason = "PeripheralGlimpse"
                    end
                end
            end
        end
    end

    if not sawThisStep then
        Memory.HasLOS = false
        Memory.SlenderVisibleTime = 0.0
        Memory.TimeSinceLastSawSlender = Memory.TimeSinceLastSawSlender + dtStep
        -- Slightly soften stale memory if Human is in high panic/disorientation
        if (currentFear or 0.0) >= 70.0 and Memory.LastKnownSlenderPos and Memory.TimeSinceLastSawSlender > 4.0 then
            Memory.LastKnownSlenderPos.X = Memory.LastKnownSlenderPos.X + math.sin(now * 2.1) * 18.0 * dtStep
            Memory.LastKnownSlenderPos.Y = Memory.LastKnownSlenderPos.Y + math.cos(now * 1.7) * 18.0 * dtStep
        end
    end

    -- Entering a remembered danger zone also bumps subtle caution
    for _, dz in ipairs(Memory.DangerZones) do
        if Bridge.Dist2D(hLoc, dz.pos) < 850.0 and not sawThisStep then
            Memory.SuspicionLevel = math.min(0.65, Memory.SuspicionLevel + 0.12 * dtStep)
            if not Memory.LastSuspicionPos then
                Memory.LastSuspicionPos = dz.pos
                Memory.LastSuspicionReason = "DangerZoneUnease"
            end
            break
        end
    end

    -- 2. Non-omniscient Page discovery (FOV + range + LineTraceSingle)
    -- Note: Pages are taped flush onto tree trunks/walls, so a ray reaching within 60cm of the page without
    -- hitting an earlier intervening barrier confirms the surface holding the page is directly visible.
    if canDiscoverObjectives ~= false then
        local pageFovCos = math.cos(math.rad(65.0))
        for _, p in ipairs(ObjectiveManager.GetRawUncollectedPages()) do
            local distP = Bridge.Dist(eyePos, p.pos)
            if distP <= Config.HUMAN.PAGE_VISION_RANGE then
                local dx = p.pos.X - eyePos.X
                local dy = p.pos.Y - eyePos.Y
                local dz = (p.pos.Z + 12.0) - eyePos.Z
                local len = math.sqrt(dx * dx + dy * dy + dz * dz)
                if len > 1.0 then
                    local dot = (dx / len) * fwd.X + (dy / len) * fwd.Y
                    if dot >= pageFovCos or distP <= 240.0 then
                        local targetPt = { X = p.pos.X, Y = p.pos.Y, Z = p.pos.Z + 8.0 }
                        local pageLOS, hitInfo = Bridge.HasLineOfSight(world, eyePos, targetPt, ignoreSlender, p.actor)
                        if (not pageLOS) and hitInfo and hitInfo.Distance then
                            local segLen = Bridge.Dist(eyePos, targetPt)
                            if hitInfo.Distance >= (segLen - 60.0) then
                                pageLOS = true
                            end
                        end
                        if pageLOS then
                            local first = ObjectiveManager.MarkPageDiscovered(p.id, now)
                            if first then
                                Logger.Info(string.format("Human spotted Page #%d via FOV+LOS @ dist=%.0fcm!", p.id, distP))
                            end
                        end
                    end
                end
            end
        end
    end
end

function HumanPerception.Update(world, dt, survivor, slender, humanForward, currentFear, forceNow, canDiscoverObjectives)
    Memory.UpdateAccum = Memory.UpdateAccum + dt
    local interval = 1.0 / Config.RATES.PERCEPTION_HZ
    if forceNow or Memory.UpdateAccum >= interval then
        local step = forceNow and math.max(dt, interval) or Memory.UpdateAccum
        Memory.UpdateAccum = 0.0
        EvaluateStep(world, step, survivor, slender, humanForward, currentFear, canDiscoverObjectives)
    end
    return Memory
end

return HumanPerception
