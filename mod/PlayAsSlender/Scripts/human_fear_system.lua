-- PlayAsSlender Human Fear System (LOS Distance/Gaze, Ambush Shock, Trauma, Dread Aura, Terrify, Breakdown)
local Config          = require("config")
local Logger          = require("logger")
local Bridge          = require("ue_bridge")
local HumanPerception = require("human_perception")

local HumanFear = {}

local State = {
    Fear             = 0.0,
    PeakFear         = 0.0,
    CriticalTimer    = 0.0,
    EncounterCount   = 0,
    LastEncounterAt  = -999.0,
    LastAmbushAt     = -999.0,
    PrevHasLOS       = false,
    Accum            = 0.0,
    AmbushesLanded   = 0,
}

function HumanFear.Reset()
    State.Fear            = 0.0
    State.PeakFear        = 0.0
    State.CriticalTimer   = 0.0
    State.EncounterCount  = 0
    State.LastEncounterAt = -999.0
    State.LastAmbushAt    = -999.0
    State.PrevHasLOS      = false
    State.Accum           = 0.0
    State.AmbushesLanded  = 0
end

function HumanFear.GetFear()          return State.Fear end
function HumanFear.GetPeakFear()      return State.PeakFear end
function HumanFear.GetCriticalTimer() return State.CriticalTimer end
function HumanFear.GetAmbushCount()   return State.AmbushesLanded end
function HumanFear.IsBrokenDown()     return State.CriticalTimer >= Config.HUMAN.FEAR_CRITICAL_TIME end

function HumanFear.ForceSetFearForTest(val, critTime)
    State.Fear = Bridge.Clamp(val or 0.0, 0.0, 100.0)
    State.PeakFear = math.max(State.PeakFear, State.Fear)
    if critTime ~= nil then
        State.CriticalTimer = critTime
    end
end

function HumanFear.ApplyTerrifySpike(amount)
    local delta = tonumber(amount) or 25.0
    State.Fear = Bridge.Clamp(State.Fear + delta, 0.0, 100.0)
    State.PeakFear = math.max(State.PeakFear, State.Fear)
end

local function ResolveStageNum(stageNumOpt)
    local s = tonumber(stageNumOpt)
    if s and s >= 1 then
        return math.floor(s)
    end
    local okOm, ObjectiveManager = pcall(require, "objective_manager")
    if okOm and ObjectiveManager and ObjectiveManager.GetCollectedCount and ObjectiveManager.GetTotalCount then
        local c = tonumber(ObjectiveManager.GetCollectedCount()) or 0
        local t = tonumber(ObjectiveManager.GetTotalCount()) or 8
        if (t >= 2 and c >= (t - 1)) or c >= 7 then
            return 4
        elseif c <= 1 then
            return 1
        elseif c <= 4 then
            return 2
        elseif c <= 6 then
            return 3
        end
        return 4
    end
    return 1
end

local function StepFear(dtStep, survivor, mem, dreadActive, aiState, slenderPos, stageNumOpt)
    local now = os.clock()
    local dist = mem.SlenderDist or 99999.0
    local dreadNearby = dreadActive and (dist <= Config.ABILITIES.DREAD_RANGE)
    local stageNum = ResolveStageNum(stageNumOpt)
    local stageMult = (stageNum > 1) and (1.0 + 0.07 * (stageNum - 1)) or 1.0

    if mem.HasLOS then
        -- Count discrete encounter when regaining LOS after a break
        if not State.PrevHasLOS then
            if (now - State.LastEncounterAt) <= 30.0 then
                State.EncounterCount = math.min(3, State.EncounterCount + 1)
            else
                State.EncounterCount = 0
            end
            State.LastEncounterAt = now

            -- Ambush shock if previously hidden for >6s & close (<22m)
            if mem.TimeSinceLastSawSlender > 6.0 and dist < 2200.0 and (now - State.LastAmbushAt) >= 8.0 then
                State.LastAmbushAt = now
                State.AmbushesLanded = State.AmbushesLanded + 1
                local proxT = 1.0 - Bridge.Clamp((dist - 400.0) / 1800.0, 0.0, 1.0)
                local ambushShock = Bridge.Lerp(10.0, 16.0, proxT)
                State.Fear = Bridge.Clamp(State.Fear + ambushShock, 0.0, 100.0)
                Logger.Info(string.format("Ambush Shock! +%.1f Fear (dist=%.0fcm)", ambushShock, dist))
            end
        end

        -- Distance curve: 5/s @ 4000cm -> 24/s @ 350cm
        local distT = 1.0 - Bridge.Clamp((dist - 350.0) / (4000.0 - 350.0), 0.0, 1.0)
        local baseRate = Bridge.Lerp(5.0, 24.0, distT * distT * (3.0 - 2.0 * distT))

        -- Gaze centrality (0.75..1.35x)
        local gazeT = Bridge.Clamp((mem.GazeDot - 0.60) / 0.40, 0.0, 1.0)
        local gazeMult = Bridge.Lerp(0.75, 1.35, gazeT)

        -- Repeat-encounter trauma multiplier (up to +45%)
        local traumaMult = 1.0 + 0.15 * State.EncounterCount

        State.Fear = Bridge.Clamp(State.Fear + baseRate * gazeMult * traumaMult * stageMult * dtStep, 0.0, 100.0)
    elseif mem.SixthSenseTriggered and dist <= Config.HUMAN.SIXTH_SENSE_RADIUS then
        State.Fear = Bridge.Clamp(State.Fear + 12.0 * dtStep, 0.0, 100.0)
    elseif mem.PeripheralGlimpse then
        State.Fear = Bridge.Clamp(State.Fear + 3.5 * dtStep, 0.0, 100.0)
    end

    -- Psychic Dread aura (E ability)
    if dreadNearby then
        local drRate = mem.HasLOS and Config.ABILITIES.DREAD_FEAR_PER_SEC or (Config.ABILITIES.DREAD_FEAR_PER_SEC * 0.52)
        State.Fear = Bridge.Clamp(State.Fear + drRate * stageMult * dtStep, 0.0, 100.0)
        HumanPerception.NotifyDreadPresence(slenderPos, dist, mem.HasLOS)
    end

    -- Natural decay when safe & unseen
    if (not mem.HasLOS) and (not dreadNearby) and (not mem.SixthSenseTriggered) and mem.TimeSinceLastSawSlender >= Config.HUMAN.FEAR_DECAY_DELAY then
        local decay = (aiState == "Recovering") and Config.HUMAN.FEAR_RECOVER_RATE or Config.HUMAN.FEAR_DECAY_RATE
        State.Fear = math.max(0.0, State.Fear - decay * dtStep)
    end

    -- Psychological breakdown threshold: requires Fear >= 98 AND Slender pressing within 16m for FEAR_CRITICAL_TIME
    if State.Fear >= 98.0 and dist <= Config.HUMAN.FEAR_PRESSURE_RANGE then
        State.CriticalTimer = State.CriticalTimer + dtStep
    else
        State.CriticalTimer = math.max(0.0, State.CriticalTimer - dtStep * 2.5)
    end

    State.PeakFear = math.max(State.PeakFear, State.Fear)
    State.PrevHasLOS = mem.HasLOS

    -- Keep vanilla survivor.Sanity at 100 so vanilla low-sanity screen glitches/static never trigger on Slenderman's viewport
    if Logger.IsValidObj(survivor) then
        pcall(function() survivor.Sanity = 100.0 end)
    end
end

function HumanFear.Update(dt, survivor, mem, dreadActive, aiState, slenderPos, forceNow, stageNum)
    State.Accum = State.Accum + dt
    local interval = 1.0 / Config.RATES.FEAR_HZ
    if forceNow or State.Accum >= interval then
        local step = forceNow and math.max(dt, interval) or State.Accum
        State.Accum = 0.0
        StepFear(step, survivor, mem or HumanPerception.GetMemory(), dreadActive, aiState, slenderPos, stageNum)
    end
    return State.Fear
end

return HumanFear
