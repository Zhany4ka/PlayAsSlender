-- PlayAsSlender Human AI Finite State Machine (9 States, Anti-PingPong Evasion, Mobile Recovery, Smart Objective Routing)
local Config           = require("config")
local Logger           = require("logger")
local Bridge           = require("ue_bridge")
local HumanVisuals     = require("human_visuals")
local ObjectiveManager = require("objective_manager")
local HumanNav         = require("human_navigation")
local HumanPerception  = require("human_perception")
local HumanFear        = require("human_fear_system")

local HumanAI = {}

local State = {
    CurrentState     = "Exploring",
    PrevState        = "None",
    LastReason       = "Match Start",
    StateTimer       = 0.0,
    FsmAccum         = 0.0,
    Stamina          = Config.HUMAN.STAMINA_MAX,
    ScanPhase        = 0.0,
    GoalLabel        = "Initializing",
    EscapeMinDist    = 2800.0,
    LastJukeTime     = 0.0,
    RecoverGoalSet   = false,

    -- Exploration / Searching context
    CurZone          = nil,
    CurPtIdx         = 1,
    TargetPageId     = nil,
    InteractProgress = 0.0,
    EscapeTarget     = nil,
}

function HumanAI.Reset(mapCfg)
    State.CurrentState     = "Exploring"
    State.PrevState        = "None"
    State.LastReason       = "Match Start"
    State.StateTimer       = 0.0
    State.FsmAccum         = 0.0
    State.Stamina          = Config.HUMAN.STAMINA_MAX
    State.ScanPhase        = 0.0
    State.GoalLabel        = "Exploring"
    State.EscapeMinDist    = (mapCfg and mapCfg.escapeMinDist) or 2800.0
    State.LastJukeTime     = 0.0
    State.RecoverGoalSet   = false
    State.CurZone          = nil
    State.CurPtIdx         = 1
    State.TargetPageId     = nil
    State.InteractProgress = 0.0
    State.EscapeTarget     = nil
end

function HumanAI.GetState()            return State.CurrentState end
function HumanAI.GetStamina()          return State.Stamina end
function HumanAI.GetGoalLabel()        return State.GoalLabel end
function HumanAI.GetTransitionReason() return State.LastReason end

function HumanAI.Transition(newState, reason)
    if State.CurrentState == newState then return end
    State.PrevState    = State.CurrentState
    State.CurrentState = newState
    State.LastReason   = reason or "FSM Rule"
    State.StateTimer   = 0.0
    State.RecoverGoalSet = false
    Logger.Info(string.format("HumanAI Transition: %s -> %s (%s)", State.PrevState, newState, State.LastReason))
end

function HumanAI.OnTerrified(slenderPos)
    HumanPerception.NotifyTerrify(slenderPos)
    if State.CurrentState == "Interacting" then
        State.InteractProgress = 0.0
        State.TargetPageId = nil
    end
    HumanAI.Transition("Panicking", "Terrified by Slenderman")
end

local function PageNavPos(pg)
    return (pg and pg.approachPos) or (pg and pg.pos)
end

local function IsInInteractRange(hLoc, pg)
    local pPos = (pg and pg.pos) and pg.pos or pg
    if not pPos then return false end
    if Bridge.Dist2D(hLoc, pPos) <= Config.HUMAN.INTERACT_DISTANCE and math.abs(hLoc.Z - pPos.Z) <= 210.0 then
        return true
    end
    if type(pg) == "table" and pg.approachPos then
        if Bridge.Dist2D(hLoc, pg.approachPos) <= 75.0
            and Bridge.Dist2D(hLoc, pPos) <= 380.0
            and math.abs(hLoc.Z - pPos.Z) <= 210.0 then
            return true
        end
    end
    return false
end

local function TryApproachKnownPage(world, hLoc, dzs, ai, interactReason)
    local nearKnown = ObjectiveManager.GetNearestKnownPage(hLoc)
    if not nearKnown then return false end
    if IsInInteractRange(hLoc, nearKnown) then
        State.TargetPageId     = nearKnown.id
        State.InteractProgress = 0.0
        HumanNav.Stop(ai)
        HumanAI.Transition("Interacting", interactReason .. tostring(nearKnown.id))
        return true
    end
    State.GoalLabel = "Approaching Obj #" .. tostring(nearKnown.id)
    if HumanNav.SetGoal(world, hLoc, PageNavPos(nearKnown), dzs, false, ai) then
        State.TargetPageId = nearKnown.id
    else
        ObjectiveManager.BlacklistPage(nearKnown.id, 45.0)
        State.TargetPageId = nil
    end
    return true
end

local function AdvanceExplorationPoint(hLoc, dangerZones, excludeId)
    if State.CurZone then
        local nextIdx = ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, (State.CurPtIdx or 0) + 1)
        if nextIdx and nextIdx ~= State.CurPtIdx then
            State.CurPtIdx = nextIdx
            return true
        end
        excludeId = excludeId or State.CurZone.id
    end
    State.CurZone  = ObjectiveManager.GetNextBestZone(hLoc, dangerZones, excludeId)
    State.CurPtIdx = State.CurZone and (ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, 1) or 1) or 1
    return State.CurZone ~= nil
end

local function SetExploreGoal(world, hLoc, dangerZones, excludeId, ai)
    if HumanFear.GetFear() < 45.0 then
        local knownPg = ObjectiveManager.GetNearestKnownPage(hLoc)
        if knownPg then
            if HumanNav.SetGoal(world, hLoc, PageNavPos(knownPg), dangerZones, false, ai) then
                State.TargetPageId = knownPg.id
                State.GoalLabel = "Known Objective #" .. tostring(knownPg.id)
                return true
            else
                ObjectiveManager.BlacklistPage(knownPg.id, 45.0)
                State.TargetPageId = nil
            end
        end
    end

    State.TargetPageId = nil
    local maxTries = math.max(3, #ObjectiveManager.GetExplorationZones() + 2)
    for _ = 1, maxTries do
        if (not State.CurZone) or State.CurZone.fullySearched or (excludeId and State.CurZone.id == excludeId) then
            State.CurZone  = ObjectiveManager.GetNextBestZone(hLoc, dangerZones, excludeId)
            State.CurPtIdx = State.CurZone and (ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, 1) or 1) or 1
        end
        if not State.CurZone then break end

        local pt = State.CurZone.pts and State.CurZone.pts[State.CurPtIdx]
        if pt then
            if HumanNav.SetGoal(world, hLoc, pt.pos, dangerZones, false, ai) then
                State.GoalLabel = string.format("%s [%d/%d]", State.CurZone.name, State.CurPtIdx, #State.CurZone.pts)
                return true
            else
                ObjectiveManager.BlacklistZonePoint(State.CurZone.id, State.CurPtIdx, 45.0)
                if not AdvanceExplorationPoint(hLoc, dangerZones, excludeId) then
                    break
                end
            end
        else
            excludeId = State.CurZone.id
            State.CurZone = nil
        end
    end
    return false
end

local function AssignEscapeGoal(world, hLoc, threatPos, dzs, lateralDeg, force, ai, excludePos)
    local target = HumanNav.PickEscapeGoal(world, hLoc, threatPos, dzs, lateralDeg, excludePos)
    if target and not HumanNav.SetGoal(world, hLoc, target, dzs, force, ai) then
        HumanNav.BlacklistNearestNode(target, 25.0)
        target = HumanNav.PickEscapeGoal(world, hLoc, threatPos, dzs, lateralDeg, target)
        if target then
            HumanNav.SetGoal(world, hLoc, target, dzs, true, ai)
        end
    end
    State.EscapeTarget = target
    return target
end

local function EvaluateFSM(world, survivor, ai, slender)
    local hLoc = Bridge.GetActorLoc(survivor)
    if not hLoc then return end

    local mem  = HumanPerception.GetMemory()
    local fear = HumanFear.GetFear()
    local dzs  = HumanPerception.GetDangerZones()
    local st   = State.CurrentState
    local now  = os.clock()

    -- High-priority threat transitions (ZERO ping-pong into Suspicious when already alert/scared!)
    if st ~= "Panicking" and st ~= "Escaping" then
        local recentChase = (mem.TimeSinceLastSawSlender < 22.0) or (fear >= 28.0)
        if (mem.HasLOS and (fear >= 35.0 or mem.SlenderDist < 2300.0 or recentChase))
            or mem.SixthSenseTriggered
            or (fear >= 70.0 and mem.TimeSinceLastSawSlender < 2.5) then
            State.InteractProgress = 0.0
            State.TargetPageId     = nil
            HumanAI.Transition("Panicking", mem.SixthSenseTriggered and "SixthSense Close" or "Direct Slender Threat")
            return
        elseif (not recentChase) and (mem.HasLOS or mem.PeripheralGlimpse or mem.SuspicionLevel >= 0.48)
            and st ~= "Suspicious" and st ~= "Investigating" then
            if st == "Interacting" then
                State.InteractProgress = 0.0
            end
            HumanAI.Transition("Suspicious", mem.LastSuspicionReason or "Suspicion Trigger")
            return
        elseif recentChase and (mem.SuspicionLevel >= 0.65) and (st == "Recovering") then
            -- Feel Psychic Dread / threat while recovering -> break out into Escaping immediately rather than freezing/turning around
            AssignEscapeGoal(world, hLoc, mem.LastSuspicionPos or Bridge.GetActorLoc(slender) or hLoc, dzs, 90.0, true, ai, nil)
            HumanAI.Transition("Escaping", "Alert Relocation (" .. tostring(mem.LastSuspicionReason) .. ")")
            return
        end
    end

    -- State behaviors
    if st == "Exploring" then
        local nearKnown = ObjectiveManager.GetNearestKnownPage(hLoc)
        if nearKnown and IsInInteractRange(hLoc, nearKnown) then
            State.TargetPageId     = nearKnown.id
            State.InteractProgress = 0.0
            HumanNav.Stop(ai)
            HumanAI.Transition("Interacting", "Reached Objective #" .. tostring(nearKnown.id))
            return
        end
        if State.CurZone and Bridge.Dist2D(hLoc, State.CurZone.center) < 900.0 then
            HumanAI.Transition("Searching", "Arrived @ " .. State.CurZone.name)
            return
        end
        SetExploreGoal(world, hLoc, dzs, nil, ai)

    elseif st == "Searching" then
        if TryApproachKnownPage(world, hLoc, dzs, ai, "Spotted Objective #") then
            return
        end
        State.TargetPageId = nil

        if not State.CurZone then
            HumanAI.Transition("Exploring", "No Active Zone")
            return
        end
        local pt = State.CurZone.pts and State.CurZone.pts[State.CurPtIdx]
        if pt then
            State.GoalLabel = string.format("Inspect %s [%d/%d]", State.CurZone.name, State.CurPtIdx, #State.CurZone.pts)
            if not HumanNav.SetGoal(world, hLoc, pt.pos, dzs, false, ai) then
                ObjectiveManager.BlacklistZonePoint(State.CurZone.id, State.CurPtIdx, 45.0)
                if not AdvanceExplorationPoint(hLoc, dzs, nil) then
                    HumanAI.Transition("Exploring", "No Reachable Point")
                    return
                end
                pt = State.CurZone and State.CurZone.pts and State.CurZone.pts[State.CurPtIdx]
                if pt then
                    HumanNav.SetGoal(world, hLoc, pt.pos, dzs, false, ai)
                end
            end
            if pt and Bridge.Dist2D(hLoc, pt.pos) < 210.0 and State.StateTimer >= 0.45 then
                local doneZone = ObjectiveManager.MarkZonePointVisited(State.CurZone.id, State.CurPtIdx, now)
                State.StateTimer = 0.0
                local nextIdx = ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, State.CurPtIdx + 1)
                if doneZone or not nextIdx then
                    local oldId = State.CurZone.id
                    State.CurZone = ObjectiveManager.GetNextBestZone(hLoc, dzs, oldId)
                    State.CurPtIdx = State.CurZone and (ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, 1) or 1) or 1
                    HumanAI.Transition("Exploring", "Finished Searching Zone")
                else
                    State.CurPtIdx = nextIdx
                end
            end
        else
            HumanAI.Transition("Exploring", "Zone Complete")
        end

    elseif st == "Suspicious" then
        State.GoalLabel = "Quick Scan"
        HumanNav.Stop(ai)
        if mem.HasLOS and (fear >= 32.0 or mem.SlenderDist < 2300.0) then
            HumanAI.Transition("Panicking", "Confirmed Slenderman!")
        elseif State.StateTimer >= 0.95 then
            HumanPerception.ConsumeSuspicion(0.55)
            -- Investigate only if calm AND no recent chase, otherwise resume smart exploration
            if fear < 25.0 and mem.TimeSinceLastSawSlender >= 25.0
                and mem.LastSuspicionPos and mem.SuspicionLevel >= 0.30
                and Bridge.Dist2D(hLoc, mem.LastSuspicionPos) > 450.0
                and Bridge.Dist2D(hLoc, mem.LastSuspicionPos) < 1800.0 then
                HumanAI.Transition("Investigating", "Checking Unfamiliar Cue")
            else
                HumanAI.Transition("Exploring", "Area Clear After Scan")
            end
        end

    elseif st == "Investigating" then
        local invPos = mem.LastSuspicionPos
        State.GoalLabel = "Cautious Check"
        if mem.HasLOS or fear >= 30.0 then
            HumanAI.Transition("Panicking", "Ambush During Investigation")
            return
        end
        if TryApproachKnownPage(world, hLoc, dzs, ai, "Found Obj #") then
            return
        end
        State.TargetPageId = nil
        if (not invPos) or State.StateTimer >= 5.0 or Bridge.Dist2D(hLoc, invPos) < 300.0 then
            HumanPerception.ConsumeSuspicion(0.75)
            HumanAI.Transition("Exploring", "Investigation Concluded")
        else
            if not HumanNav.SetGoal(world, hLoc, invPos, dzs, false, ai) then
                HumanPerception.ConsumeSuspicion(0.75)
                HumanAI.Transition("Exploring", "Cue Unreachable")
            end
        end

    elseif st == "Interacting" then
        State.GoalLabel = "Collecting #" .. tostring(State.TargetPageId or 0)
        HumanNav.Stop(ai)
        if State.InteractProgress >= Config.HUMAN.INTERACT_DURATION then
            if State.TargetPageId then
                ObjectiveManager.CollectPage(world, survivor, State.TargetPageId, false)
            end
            State.InteractProgress = 0.0
            State.TargetPageId = nil
            HumanAI.Transition("Exploring", "Objective Collected!")
        end

    elseif st == "Panicking" then
        State.GoalLabel = "PANIC FLIGHT"
        local threatPos = mem.LastKnownSlenderPos or Bridge.GetActorLoc(slender) or hLoc
        if (not State.EscapeTarget) or State.StateTimer < 0.25 then
            AssignEscapeGoal(world, hLoc, threatPos, dzs, 90.0, true, ai, nil)
        end
        if State.StateTimer >= 1.15 then
            HumanAI.Transition("Escaping", "Breakout into Evasive Escape")
        end

    elseif st == "Escaping" then
        local threatPos = mem.LastKnownSlenderPos or Bridge.GetActorLoc(slender) or hLoc
        State.GoalLabel = "Evading Threat"
        -- Dynamic lateral juking if Slenderman closes in during chase
        local needJuke = (mem.SlenderDist < 1100.0 and (now - State.LastJukeTime) >= 1.4)
        if needJuke then State.LastJukeTime = now end

        if (not State.EscapeTarget) or Bridge.Dist2D(hLoc, State.EscapeTarget) < 280.0 or mem.HasLOS or needJuke then
            AssignEscapeGoal(world, hLoc, threatPos, dzs, needJuke and 90.0 or nil, needJuke, ai, nil)
        end

        -- Commit to escape long enough to truly gain safe distance (>= 5.0s elapsed AND broke LOS for 5.0s AND safe dist)
        if State.StateTimer >= 5.0
            and (not mem.HasLOS)
            and mem.TimeSinceLastSawSlender >= 5.0
            and (mem.SlenderDist or 9999.0) >= State.EscapeMinDist then
            HumanAI.Transition("Recovering", "Safe Distance Gained")
        elseif State.StateTimer >= 14.0 and fear >= 75.0 and (not mem.HasLOS) then
            HumanAI.Transition("Lost", "Disoriented After Prolonged Chase")
        end

    elseif st == "Recovering" then
        -- Mobile recovery: keep walking toward a safe unvisited landmark away from DangerZones (never freeze & stare!)
        State.GoalLabel = "Moving to Safe Zone"
        if not State.RecoverGoalSet then
            State.RecoverGoalSet = true
            State.CurZone = ObjectiveManager.GetNextBestZone(hLoc, dzs, nil)
            State.CurPtIdx = State.CurZone and (ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, 1) or 1) or 1
            SetExploreGoal(world, hLoc, dzs, nil, ai)
        end
        if mem.HasLOS then
            if (mem.SlenderDist or 9999.0) < 1200.0 or fear >= 65.0 then
                HumanAI.Transition("Panicking", "Close Threat During Recovery")
            else
                AssignEscapeGoal(world, hLoc, mem.LastKnownSlenderPos or Bridge.GetActorLoc(slender) or hLoc, dzs, 90.0, true, ai, nil)
                HumanAI.Transition("Escaping", "Evading From Recovery")
            end
        elseif State.StateTimer >= 3.2 then
            HumanAI.Transition("Exploring", "Recovered Composure")
        end

    elseif st == "Lost" then
        State.GoalLabel = "Re-orienting Bearings"
        HumanNav.Stop(ai)
        if State.StateTimer >= 2.2 then
            State.CurZone = ObjectiveManager.GetNextBestZone(hLoc, dzs, nil)
            State.CurPtIdx = State.CurZone and (ObjectiveManager.GetNextAvailablePointIndex(State.CurZone, 1) or 1) or 1
            HumanAI.Transition("Exploring", "Found Bearings Again")
        end
    end
end

local function SafeUpdateLights(world, slender)
    if HumanVisuals.UpdateLights then
        local ok, err = pcall(HumanVisuals.UpdateLights, world, slender, nil)
        if not ok then
            Logger.Warn("HumanVisuals.UpdateLights error: " .. tostring(err))
        end
    end
end

function HumanAI.Update(world, dt, survivor, ai, slender, abilities, frozen, canDiscoverObjectives)
    if not Logger.IsValidObj(survivor) or not Logger.IsValidObj(ai) then return end
    if frozen then
        HumanNav.Stop(ai)
        SafeUpdateLights(world, slender)
        return
    end

    State.StateTimer = State.StateTimer + dt
    State.ScanPhase  = State.ScanPhase + dt
    local mem = HumanPerception.GetMemory()

    local humanFwd = select(1, HumanVisuals.GetForward())
    HumanPerception.Update(world, dt, survivor, slender, humanFwd, HumanFear.GetFear(), false, canDiscoverObjectives)
    local dreadActive = abilities and abilities.IsDreadActive and abilities.IsDreadActive() or false
    local slPos = Bridge.GetActorLoc(slender)
    HumanFear.Update(dt, survivor, mem, dreadActive, State.CurrentState, slPos, false)

    local fear = HumanFear.GetFear()

    -- Stamina & speed control
    local isSprinting = false
    local desiredSpeed = Config.HUMAN.WALK_SPEED
    if fear >= 95.0 and HumanFear.GetCriticalTimer() > 0.5 then
        desiredSpeed = Config.HUMAN.BREAKDOWN_SPEED
    elseif State.CurrentState == "Panicking" or State.CurrentState == "Escaping" then
        if State.Stamina > 12.0 then
            isSprinting = true
            desiredSpeed = (State.CurrentState == "Panicking") and Config.HUMAN.PANIC_SPEED or Config.HUMAN.SPRINT_SPEED
        else
            desiredSpeed = Config.HUMAN.CAUTIOUS_SPEED
        end
    elseif State.CurrentState == "Investigating" or State.CurrentState == "Searching" or State.CurrentState == "Recovering" then
        desiredSpeed = Config.HUMAN.CAUTIOUS_SPEED
    elseif State.CurrentState == "Suspicious" or State.CurrentState == "Interacting" or State.CurrentState == "Lost" then
        desiredSpeed = Config.HUMAN.WALK_SPEED
    end

    if isSprinting then
        local drain = (State.CurrentState == "Panicking") and Config.HUMAN.STAMINA_DRAIN_PANIC or Config.HUMAN.STAMINA_DRAIN_RUN
        State.Stamina = math.max(0.0, State.Stamina - drain * dt)
    elseif State.CurrentState == "Recovering" or State.CurrentState == "Suspicious" or State.CurrentState == "Lost" then
        State.Stamina = math.min(Config.HUMAN.STAMINA_MAX, State.Stamina + Config.HUMAN.STAMINA_RECOVER_REST * dt)
    else
        State.Stamina = math.min(Config.HUMAN.STAMINA_MAX, State.Stamina + Config.HUMAN.STAMINA_RECOVER_WALK * dt)
    end
    HumanVisuals.SetMoveSpeed(desiredSpeed)
    pcall(function() survivor.Stamina = State.Stamina end)

    State.FsmAccum = State.FsmAccum + dt
    if State.FsmAccum >= (1.0 / Config.RATES.FSM_HZ) then
        State.FsmAccum = 0.0
        EvaluateFSM(world, survivor, ai, slender)
    end

    local st = State.CurrentState
    if st == "Interacting" then
        State.InteractProgress = State.InteractProgress + dt
        local pg = State.TargetPageId and ObjectiveManager.GetPageById(State.TargetPageId) or nil
        if pg then
            local hLoc = Bridge.GetActorLoc(survivor)
            if hLoc then
                local lookYaw = Bridge.YawFromVec(pg.pos.X - hLoc.X, pg.pos.Y - hLoc.Y)
                HumanVisuals.AimToward(lookYaw, -5.0, dt, 10.0)
            end
        end
    elseif st == "Suspicious" or st == "Lost" then
        local baseYaw = select(2, HumanVisuals.GetForward())
        if mem.LastSuspicionPos and st == "Suspicious" then
            local hLoc = Bridge.GetActorLoc(survivor)
            if hLoc then
                baseYaw = Bridge.YawFromVec(mem.LastSuspicionPos.X - hLoc.X, mem.LastSuspicionPos.Y - hLoc.Y)
            end
        end
        local sweep = math.sin(State.ScanPhase * 3.2) * 55.0
        HumanVisuals.AimToward(baseYaw + sweep, -4.0, dt, 6.5)
    else
        local _, steer, stuckNeedsNewGoal = HumanNav.UpdateMovement(world, dt, survivor, ai, slender, HumanPerception.GetDangerZones())
        if stuckNeedsNewGoal then
            local hLoc = Bridge.GetActorLoc(survivor)
            local dzs  = HumanPerception.GetDangerZones()
            if hLoc then
                if st == "Escaping" or st == "Panicking" then
                    local threatPos = mem.LastKnownSlenderPos or slPos or hLoc
                    local failedTarget = State.EscapeTarget
                    if failedTarget then
                        HumanNav.BlacklistNearestNode(failedTarget, 25.0)
                    end
                    AssignEscapeGoal(world, hLoc, threatPos, dzs, 90.0, true, ai, failedTarget)
                elseif State.TargetPageId then
                    ObjectiveManager.BlacklistPage(State.TargetPageId, 45.0)
                    State.TargetPageId = nil
                    local oldZoneId = State.CurZone and State.CurZone.id or nil
                    State.CurZone = nil
                    if st == "Searching" then
                        HumanAI.Transition("Exploring", "Switching Zone After Blocked Objective")
                    end
                    SetExploreGoal(world, hLoc, dzs, oldZoneId, ai)
                else
                    local oldZoneId = State.CurZone and State.CurZone.id or nil
                    if State.CurZone then
                        ObjectiveManager.BlacklistZonePoint(oldZoneId, State.CurPtIdx, 45.0)
                    end
                    State.CurZone = nil
                    if st == "Searching" then
                        HumanAI.Transition("Exploring", "Switching Zone After Blocked Point")
                    end
                    SetExploreGoal(world, hLoc, dzs, oldZoneId, ai)
                end
            end
        elseif steer and steer.Yaw then
            local aimYaw = steer.Yaw
            if st == "Searching" and State.CurZone then
                local hLoc = Bridge.GetActorLoc(survivor)
                if hLoc then
                    local towardCenter = Bridge.YawFromVec(State.CurZone.center.X - hLoc.X, State.CurZone.center.Y - hLoc.Y)
                    aimYaw = towardCenter + math.sin(State.ScanPhase * 2.4) * 42.0
                end
            elseif st == "Exploring" then
                aimYaw = steer.Yaw + math.sin(State.ScanPhase * 1.6) * 24.0
            elseif st == "Recovering" then
                aimYaw = steer.Yaw + math.sin(State.ScanPhase * 2.0) * 28.0
            elseif st == "Panicking" then
                aimYaw = steer.Yaw + math.sin(State.ScanPhase * 7.5) * 9.0
            end
            HumanVisuals.AimToward(aimYaw, -4.0, dt, (st == "Panicking" or st == "Escaping") and 11.0 or 7.0)
        end
    end

    SafeUpdateLights(world, slender)
end

return HumanAI
