-- PlayAsSlender/Scripts/prologue_story.lua
-- Authentic 5-Stage Chapter 1 (Level01_Prologue) Story & AI State Machine.
-- STRICTLY scoped to PROLOGUE (mapCfg.key == "PROLOGUE"); leaves all other chapters untouched.

local Config = require("config")
local Bridge = require("ue_bridge")
local Logger = require("logger")

local PrologueStory = {}

local STAGE = {
    ROAD_TO_HOUSE        = 1,
    FIND_FLASHLIGHT      = 2,
    KATES_ROOM_2F        = 3,
    EXIT_BACK_DOOR       = 4,
    NIGHT_FOREST_TO_PARK = 5,
}
PrologueStory.STAGE = STAGE

local STAGE_NAMES = {
    [1] = "STAGE 1/5: ROAD TO KATE'S HOUSE",
    [2] = "STAGE 2/5: FIND FLASHLIGHT (1F)",
    [3] = "STAGE 3/5: INSPECT KATE'S ROOM (2F)",
    [4] = "STAGE 4/5: ESCAPE BACK DOOR",
    [5] = "STAGE 5/5: REACH OAKSIDE PARK",
}

local CAR_SPAWN = { X = 23996.1, Y = 19980.9, Z = 17471.2, Yaw = 25.0 }

local ROAD_AMBUSH_SPOTS = {
    { X = 24756.0, Y = 25198.0, Z = 17230.5 },
    { X = 24897.0, Y = 25148.5, Z = 17189.5 },
}

local BACKYARD_TRANSFER_SPOTS = {
    { X = 43600.0, Y = 64500.0, Z = 9112.8 },
    { X = 43850.0, Y = 64350.0, Z = 9112.8 },
}

local HOUSE_PORCH_GOAL      = { X = 44270.0, Y = 58050.0, Z = 9010.0 }
local HOUSE_INTERIOR_ANCHOR = { X = 44270.0, Y = 58800.0, Z = 9110.0 }
local FRONT_DOOR_POS        = { X = 44270.0, Y = 58398.0, Z = 9010.0 }
local BACK_DOOR_POS         = { X = 44193.0, Y = 61884.0, Z = 9011.0 }
local STAIR_FOOT_POS        = { X = 44240.0, Y = 59100.0, Z = 9108.0 }
local STAIR_TOP_POS         = { X = 44240.0, Y = 60340.0, Z = 9715.5 }
local KATES_ROOM_POS        = { X = 41265.0, Y = 61150.0, Z = 9715.5 }
local KATES_NOTE_FALLBACK   = { X = 41104.6, Y = 61307.9, Z = 9794.4 }
local BACK_GATE_POS         = { X = 42231.3, Y = 66684.1, Z = 8994.9 }
local TRAILHEAD_POS         = { X = 42220.0, Y = 67200.0, Z = 9018.0 }
local TRIGGERBOX1_FALLBACK  = { X = 81705.0, Y = 84710.0, Z = 7105.0 }

-- Stage 1: Vanilla Car beside fallen tree -> Dirt Road through woods -> Kate's House Porch
local ROAD_WAYPOINTS = {
    { X = 23958.0, Y = 20504.0, Z = 17130.0 },
    { X = 23937.0, Y = 20983.0, Z = 17112.0 },
    { X = 24510.0, Y = 22462.0, Z = 17006.0 },
    { X = 24972.0, Y = 23961.0, Z = 17018.0 },
    { X = 25320.0, Y = 25000.0, Z = 16928.0 },
    { X = 25779.0, Y = 26297.0, Z = 16686.0 },
    { X = 26159.0, Y = 27297.0, Z = 16658.0 },
    { X = 26494.0, Y = 28285.0, Z = 16793.0 },
    { X = 26945.0, Y = 28639.0, Z = 16767.0 },
    { X = 28379.0, Y = 27610.0, Z = 16170.0 },
    { X = 29753.0, Y = 26492.0, Z = 15676.0 },
    { X = 30202.0, Y = 26061.0, Z = 15441.0 },
    { X = 31754.0, Y = 25981.0, Z = 15036.0 },
    { X = 32421.0, Y = 27911.0, Z = 14854.0 },
    { X = 33818.0, Y = 30202.0, Z = 14077.0 },
    { X = 35251.0, Y = 31485.0, Z = 13743.0 },
    { X = 37066.0, Y = 32216.0, Z = 13459.0 },
    { X = 39337.0, Y = 32515.0, Z = 12982.0 },
    { X = 40973.0, Y = 33947.0, Z = 12616.0 },
    { X = 42504.0, Y = 35235.0, Z = 12341.0 },
    { X = 44128.0, Y = 35670.0, Z = 12164.0 },
    { X = 45831.0, Y = 35720.0, Z = 12064.0 },
    { X = 47815.0, Y = 34777.0, Z = 11852.0 },
    { X = 49697.0, Y = 34010.0, Z = 11628.0 },
    { X = 50708.0, Y = 33644.0, Z = 11450.0 },
    { X = 52236.0, Y = 33790.0, Z = 11142.0 },
    { X = 53833.0, Y = 34722.0, Z = 10861.0 },
    { X = 55956.0, Y = 35928.0, Z = 10583.0 },
    { X = 57858.0, Y = 36903.0, Z = 9867.0 },
    { X = 59527.0, Y = 37236.0, Z = 9100.0 },
    { X = 60848.0, Y = 38226.0, Z = 8302.0 },
    { X = 62285.0, Y = 41182.0, Z = 7452.0 },
    { X = 61771.0, Y = 44382.0, Z = 7402.0 },
    { X = 59940.0, Y = 46699.0, Z = 7583.0 },
    { X = 57844.0, Y = 47659.0, Z = 8148.0 },
    { X = 54705.0, Y = 48484.0, Z = 8712.0 },
    { X = 53137.0, Y = 49459.0, Z = 8658.0 },
    { X = 51168.0, Y = 52126.0, Z = 8892.0 },
    { X = 49643.0, Y = 53167.0, Z = 8968.0 },
    { X = 47081.0, Y = 52842.0, Z = 8932.0 },
    { X = 44482.0, Y = 52695.0, Z = 8950.0 },
    { X = 42315.0, Y = 53053.0, Z = 8967.0 },
    { X = 41737.0, Y = 53489.0, Z = 8966.0 },
    { X = 41603.0, Y = 54458.0, Z = 8999.0 },
    { X = 41894.0, Y = 56115.0, Z = 9038.0 },
    { X = 42126.0, Y = 57564.0, Z = 9024.0 },
    { X = 42255.0, Y = 58371.0, Z = 9000.0 },
    { X = 44270.0, Y = 58050.0, Z = 9010.0 },
}

-- Stage 3: Staircase up -> 2F Hallway -> BP_Door_Room14_Locked -> Kate's Bedroom
local STAIR_TO_KATE_WAYPOINTS = {
    { X = 44240.0, Y = 59100.0, Z = 9108.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59320.0, Z = 9139.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59560.0, Z = 9307.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59800.0, Z = 9475.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 60040.0, Z = 9643.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 60340.0, Z = 9715.5, narrow = true, stairs = true },
    { X = 43600.0, Y = 60340.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 42400.0, Y = 60340.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 41265.0, Y = 60360.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 41265.0, Y = 60605.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 41265.0, Y = 61150.0, Z = 9715.5, narrow = true, floor2 = true },
}

-- Stage 4A: Kate's Bedroom -> 2F Hallway -> Down Staircase -> 1F Stair Foot
local KATE_DOWN_TO_1F_WAYPOINTS = {
    { X = 41265.0, Y = 60605.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 41265.0, Y = 60360.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 42400.0, Y = 60340.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 43600.0, Y = 60340.0, Z = 9715.5, narrow = true, floor2 = true },
    { X = 44240.0, Y = 60340.0, Z = 9715.5, narrow = true, stairs = true },
    { X = 44240.0, Y = 60040.0, Z = 9643.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59800.0, Z = 9475.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59560.0, Z = 9307.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59320.0, Z = 9139.0, narrow = true, stairs = true },
    { X = 44240.0, Y = 59100.0, Z = 9108.0, narrow = true, stairs = true },
}

-- Stage 4C: Back Porch (outside BP_Door_Main2) -> Backyard -> Open Back Gate -> Trailhead
local BACKYARD_TO_GATE_WAYPOINTS = {
    { X = 44193.0, Y = 62400.0, Z = 9100.0, narrow = true },
    { X = 43200.0, Y = 64600.0, Z = 9100.0 },
    { X = 42231.0, Y = 66684.0, Z = 8995.0, narrow = true },
    { X = 42220.0, Y = 67200.0, Z = 9018.0, narrow = true },
}

-- Stage 5: Night Forest Trail -> Gen2 -> Creek Bridge -> Burnt House / Gen3 -> Park Ext -> Guardhouse -> TriggerBox_1
local FOREST_TO_PARK_WAYPOINTS = {
    -- B1_GateToGen2 (182.5m)
    { X = 42400.0, Y = 67200.0, Z = 9018.0 },
    { X = 44400.0, Y = 68000.0, Z = 8900.0 },
    { X = 46400.0, Y = 68800.0, Z = 8750.0 },
    { X = 48800.0, Y = 69600.0, Z = 8400.0 },
    { X = 50800.0, Y = 71600.0, Z = 8000.0 },
    { X = 52000.0, Y = 73200.0, Z = 7700.0 },
    { X = 54400.0, Y = 73600.0, Z = 7400.0 },
    { X = 57600.0, Y = 73200.0, Z = 7024.0, landmark = "Gen2" },
    -- Path2_Gen2_To_Burnt (281.8m) including Creek Bridge
    { X = 60600.0, Y = 72900.0, Z = 6750.0 },
    { X = 63000.0, Y = 72000.0, Z = 6500.0 },
    { X = 65400.0, Y = 71400.0, Z = 6250.0 },
    { X = 67200.0, Y = 72000.0, Z = 6100.0 },
    { X = 68400.0, Y = 72300.0, Z = 6020.0, narrow = true },
    { X = 68400.0, Y = 71700.0, Z = 5955.0, narrow = true, bridge = true },
    { X = 68400.0, Y = 70500.0, Z = 5955.0, narrow = true, bridge = true },
    { X = 69600.0, Y = 69900.0, Z = 6020.0 },
    { X = 72000.0, Y = 69300.0, Z = 6100.0 },
    { X = 75000.0, Y = 68400.0, Z = 6180.0 },
    { X = 78000.0, Y = 67500.0, Z = 6220.0 },
    { X = 81000.0, Y = 66600.0, Z = 6247.0, landmark = "Gen3" },
    -- Path3_Burnt_To_ParkExt (183.3m)
    { X = 81300.0, Y = 66600.0, Z = 6250.0 },
    { X = 81300.0, Y = 68700.0, Z = 6400.0 },
    { X = 81000.0, Y = 70500.0, Z = 6550.0 },
    { X = 81900.0, Y = 71400.0, Z = 6650.0 },
    { X = 81000.0, Y = 73200.0, Z = 6800.0 },
    { X = 80400.0, Y = 75000.0, Z = 6920.0 },
    { X = 81000.0, Y = 77400.0, Z = 7020.0 },
    { X = 79800.0, Y = 79200.0, Z = 7080.0 },
    { X = 79500.0, Y = 81000.0, Z = 7120.0 },
    { X = 78600.0, Y = 81900.0, Z = 7150.0 },
    { X = 78300.0, Y = 82200.0, Z = 7165.0 },
    { X = 78000.0, Y = 82500.0, Z = 7175.0, narrow = true, landmark = "ParkEntry" },
    -- Guardhouse Entry -> TriggerBox_1 (exact 150cm BFS corridor waypoints to clear turnstile without clipping)
    { X = 78600.0, Y = 83100.0, Z = 7180.0, narrow = true, guardhouse = true },
    { X = 78600.0, Y = 84600.0, Z = 7185.0, narrow = true, guardhouse = true },
    { X = 78900.0, Y = 84750.0, Z = 7190.0, narrow = true, guardhouse = true },
    { X = 79200.0, Y = 85050.0, Z = 7190.0, narrow = true, guardhouse = true },
    { X = 81000.0, Y = 85050.0, Z = 7192.0, narrow = true, guardhouse = true },
    { X = 81150.0, Y = 84600.0, Z = 7195.6, narrow = true, guardhouse = true },
    { X = 81300.0, Y = 84450.0, Z = 7195.6, narrow = true, guardhouse = true },
    { X = 81300.0, Y = 84300.0, Z = 7195.6, narrow = true, guardhouse = true },
    { X = 81450.0, Y = 84450.0, Z = 7195.6, narrow = true, guardhouse = true },
    { X = 81600.0, Y = 84600.0, Z = 7195.6, narrow = true, guardhouse = true },
    { X = 81750.0, Y = 84750.0, Z = 7195.6, narrow = true, guardhouse = true, landmark = "ParkGate" },
}

local State = {
    Active              = false,
    Stage               = STAGE.ROAD_TO_HOUSE,
    SubPhase            = "ROAD_WALK",
    GoalLabel           = "Walk Dirt Road to Kate's House",
    WpIdx               = 1,
    FlashlightPickedUp  = false,
    KatesRoomInspected  = false,
    KatesNoteCollected  = false,
    NightTriggered      = false,
    ScreamPlayed        = false,
    BackDoorUnlocked    = false,
    BackGateOpened      = false,
    SlenderTransferred  = false,
    ParkGateReached     = false,
    InspectTimer        = 0.0,
    EvadeTimer          = 0.0,
    EvadeBacktrack      = false,
    SideSign            = 1,
    StuckTimer          = 0.0,
    StuckCount          = 0,
    LastCheckPos        = nil,
    AmbientElapsed      = 0.0,
    LastFlashEnsure     = 0.0,
    HouseGoalCooldown   = 0.0,
    Gen2Triggered       = false,
    Gen3Triggered       = false,
    HouseStage2Solved   = false,
    HouseStage2Wps      = nil,
    -- Cached world actors
    FrontDoor           = nil,
    BackDoor            = nil,
    KatesDoor           = nil,
    BackGate            = nil,
    KatesPage           = nil,
    ActiveFlashlight    = nil,
    AllFlashlights      = {},
    TriggerBox1         = nil,
    TriggerBox2         = nil,
    LightingInterp      = nil,
    LevelScript         = nil,
    HouseScript         = nil,
    ScreamCue           = nil,
    Generators          = {},
}

function PrologueStory.Reset()
    State.Active             = false
    State.Stage              = STAGE.ROAD_TO_HOUSE
    State.SubPhase           = "ROAD_WALK"
    State.GoalLabel          = "Walk Dirt Road to Kate's House"
    State.WpIdx              = 1
    State.FlashlightPickedUp = false
    State.KatesRoomInspected = false
    State.KatesNoteCollected = false
    State.NightTriggered     = false
    State.ScreamPlayed       = false
    State.BackDoorUnlocked   = false
    State.BackGateOpened     = false
    State.SlenderTransferred = false
    State.ParkGateReached    = false
    State.InspectTimer       = 0.0
    State.EvadeTimer         = 0.0
    State.EvadeBacktrack     = false
    State.SideSign           = 1
    State.StuckTimer         = 0.0
    State.StuckCount         = 0
    State.LastCheckPos       = nil
    State.AmbientElapsed     = 0.0
    State.LastFlashEnsure    = 0.0
    State.HouseGoalCooldown  = 0.0
    State.Gen2Triggered      = false
    State.Gen3Triggered      = false
    State.HouseStage2Solved  = false
    State.HouseStage2Wps     = nil
    State.FrontDoor          = nil
    State.BackDoor           = nil
    State.KatesDoor          = nil
    State.BackGate           = nil
    State.KatesPage          = nil
    State.ActiveFlashlight   = nil
    State.AllFlashlights     = {}
    State.TriggerBox1        = nil
    State.TriggerBox2        = nil
    State.LightingInterp     = nil
    State.LevelScript        = nil
    State.HouseScript        = nil
    State.ScreamCue          = nil
    State.Generators         = {}
end

function PrologueStory.IsActive()              return State.Active == true end
function PrologueStory.GetStage()              return State.Stage end
function PrologueStory.GetCompletedCount()     return math.max(0, math.min(5, State.ParkGateReached and 5 or (State.Stage - 1))) end
function PrologueStory.GetTotalCount()         return 5 end
function PrologueStory.IsParkGateReached()     return State.ParkGateReached == true end
function PrologueStory.IsNightTriggered()      return State.NightTriggered == true end
function PrologueStory.IsScreamPlayed()        return State.ScreamPlayed == true end
function PrologueStory.IsFlashlightPickedUp()  return State.FlashlightPickedUp == true end
function PrologueStory.IsBackDoorUnlocked()    return State.BackDoorUnlocked == true end
function PrologueStory.IsBackGateOpened()      return State.BackGateOpened == true end
function PrologueStory.IsSlenderTransferred()  return State.SlenderTransferred == true end
function PrologueStory.GetHouseNavAnchor()     return { X = HOUSE_INTERIOR_ANCHOR.X, Y = HOUSE_INTERIOR_ANCHOR.Y, Z = HOUSE_INTERIOR_ANCHOR.Z } end
function PrologueStory.GetSubPhase()           return State.SubPhase end
function PrologueStory.GetWpIdx()              return State.WpIdx end

function PrologueStory.GetStageName(stageOverride)
    local st = tonumber(stageOverride) or State.Stage
    return STAGE_NAMES[st] or STAGE_NAMES[1]
end

local function SetDoorStateSafe(door, sender, stVal)
    if not Logger.IsValidObj(door) then return false end
    local ok = false
    pcall(function()
        if door.SetState then
            door:SetState(sender, stVal, false)
            ok = true
        end
    end)
    pcall(function()
        if door.RequestStateChange then
            door:RequestStateChange(sender, stVal)
            ok = true
        end
    end)
    if stVal ~= 3 then
        pcall(function()
            if Logger.IsValidObj(door.DoorCollisionAndNavigationBlocker) then
                door.DoorCollisionAndNavigationBlocker:SetCollisionEnabled(0)
            end
        end)
    end
    return ok
end

function PrologueStory.DismissPrologueIntro(world, pc)
    if not State.Active then return end
    for _, mp in ipairs(FindAllOf("MediaPlayer") or {}) do
        if Logger.IsValidObj(mp) then
            pcall(function() mp:Pause() end)
            pcall(function() mp:Close() end)
        end
    end
    for _, uw in ipairs(FindAllOf("W_MoviePlayer_C") or {}) do
        if Logger.IsValidObj(uw) then
            pcall(function() uw:SetVisibility(1) end)
            pcall(function() uw:RemoveFromParent() end)
        end
    end
    if Logger.IsValidObj(pc) then
        pcall(function()
            local cm = pc.PlayerCameraManager
            if Logger.IsValidObj(cm) then
                if cm.StopCameraFade then cm:StopCameraFade() end
                if cm.SetManualCameraFade then
                    cm:SetManualCameraFade(0.0, { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }, false)
                end
            end
        end)
    end
end

local function RefreshActiveFlashlight(survivorPos)
    local active = nil
    local fallback = nil
    local bestDist = 1e9
    local flList = FindAllOf("BP_Pickup_Flashlight_C") or {}
    State.AllFlashlights = flList
    for _, fl in ipairs(flList) do
        if Logger.IsValidObj(fl) then
            local hidden = false
            local avail = true
            pcall(function() hidden = (fl.bHidden == true) end)
            pcall(function() if fl.bAvailableForPickup ~= nil then avail = (fl.bAvailableForPickup ~= false) end end)
            if (not hidden) and avail then
                local loc = Bridge.GetActorLoc(fl)
                if loc then
                    local d = survivorPos and Bridge.Dist(loc, survivorPos) or Bridge.Dist(loc, HOUSE_INTERIOR_ANCHOR)
                    if d < bestDist then
                        bestDist = d
                        active = fl
                    end
                else
                    active = fl
                end
            elseif not fallback then
                fallback = fl
            end
        end
    end
    State.ActiveFlashlight = active or fallback
    return State.ActiveFlashlight
end

local function CachePrologueActors(world, survivor)
    for _, d in ipairs(FindAllOf("BP_DoorBase_C") or {}) do
        if Logger.IsValidObj(d) then
            local dn = Logger.SafeName(d)
            if dn == "BP_Door_Main" then
                State.FrontDoor = d
                pcall(function() d.bOpenableByAI = true end)
                local st = 0
                pcall(function() st = d:GetState() end)
                if st == 3 then
                    SetDoorStateSafe(d, survivor, 0)
                end
            elseif dn == "BP_Door_Main2" then
                State.BackDoor = d
                -- Keep BP_Door_Main2 locked until Kate's bedroom trigger in Stage 3
                pcall(function() d:SetState(survivor, 3, true) end)
            elseif dn == "BP_Door_Room14_Locked" then
                State.KatesDoor = d
                pcall(function() d:SetState(survivor, 3, true) end)
            end
        end
    end

    for _, g in ipairs(FindAllOf("BP_BackGate_Level1_C") or {}) do
        if Logger.IsValidObj(g) then
            State.BackGate = g
            break
        end
    end

    for _, pg in ipairs(FindAllOf("BP_PickUp_Page_Level1_C") or {}) do
        if Logger.IsValidObj(pg) then
            local pn = Logger.SafeName(pg)
            if string.find(pn, "BP_PickUp_Page_Level01", 1, true) or not State.KatesPage then
                State.KatesPage = pg
            end
        end
    end

    for _, tb in ipairs(FindAllOf("TriggerBox") or {}) do
        if Logger.IsValidObj(tb) then
            local tn = Logger.SafeName(tb)
            if tn == "TriggerBox_1" then
                State.TriggerBox1 = tb
                pcall(function() tb:SetActorEnableCollision(false) end)
            elseif tn == "TriggerBox_2" then
                State.TriggerBox2 = tb
                pcall(function() tb:SetActorEnableCollision(false) end)
            end
        end
    end

    for _, li in ipairs(FindAllOf("LightingInterpolator") or {}) do
        if Logger.IsValidObj(li) then
            State.LightingInterp = li
            break
        end
    end
    for _, ls in ipairs(FindAllOf("Level01_Prologue_C") or {}) do
        if Logger.IsValidObj(ls) then
            State.LevelScript = ls
            break
        end
    end
    for _, hs in ipairs(FindAllOf("Level01_HouseAndYard_C") or {}) do
        if Logger.IsValidObj(hs) then
            State.HouseScript = hs
            break
        end
    end

    for _, sc in ipairs(FindAllOf("SoundCue") or {}) do
        if Logger.IsValidObj(sc) then
            local sn = Logger.SafeName(sc)
            if string.find(sn, "gateScream", 1, true) then
                State.ScreamCue = sc
                break
            end
        end
    end

    for _, act in ipairs(FindAllOf("Actor") or {}) do
        if Logger.IsValidObj(act) then
            local fn = Logger.SafeName(act)
            if string.find(fn, "Generator", 1, true) then
                local loc = Bridge.GetActorLoc(act)
                if loc then
                    table.insert(State.Generators, { actor = act, pos = loc, name = fn })
                end
            end
        end
    end

    RefreshActiveFlashlight(HOUSE_INTERIOR_ANCHOR)
end

function PrologueStory.Init(world, survivor, ai, mapCfg, HumanVisuals)
    PrologueStory.Reset()
    if not mapCfg or mapCfg.key ~= "PROLOGUE" then
        return false
    end
    State.Active = true

    -- Place Survivor right at vanilla Car beside the fallen tree with flashlight OFF
    if Logger.IsValidObj(survivor) then
        pcall(function()
            local cmc = survivor.CharacterMovement
            if Logger.IsValidObj(cmc) then
                cmc.MaxAcceleration = 2400.0
            end
        end)
        pcall(function()
            survivor:K2_SetActorLocationAndRotation(
                { X = CAR_SPAWN.X, Y = CAR_SPAWN.Y, Z = CAR_SPAWN.Z },
                { Pitch = 0.0, Yaw = CAR_SPAWN.Yaw, Roll = 0.0 },
                false, {}, true
            )
        end)
        if HumanVisuals and HumanVisuals.SetYawImmediate then
            HumanVisuals.SetYawImmediate(CAR_SPAWN.Yaw)
        end
        if HumanVisuals and HumanVisuals.SetFlashlightEnabled then
            HumanVisuals.SetFlashlightEnabled(false)
        end
    end

    CachePrologueActors(world, survivor)
    Logger.Info(string.format(
        "PrologueStory initialized: Stage=1 CarSpawn=(%.0f,%.0f,%.0f) ActiveFlashlight=%s Doors=[F=%s B=%s K=%s Gate=%s Trigger1=%s]",
        CAR_SPAWN.X, CAR_SPAWN.Y, CAR_SPAWN.Z,
        tostring(Logger.SafeName(State.ActiveFlashlight)),
        tostring(Logger.SafeName(State.FrontDoor)),
        tostring(Logger.SafeName(State.BackDoor)),
        tostring(Logger.SafeName(State.KatesDoor)),
        tostring(Logger.SafeName(State.BackGate)),
        tostring(Logger.SafeName(State.TriggerBox1))))
    return true
end

function PrologueStory.GetInitialSlenderSpawn(world, survLoc, survivor)
    local hLoc = survLoc or { X = CAR_SPAWN.X, Y = CAR_SPAWN.Y, Z = CAR_SPAWN.Z }
    for _, c in ipairs(ROAD_AMBUSH_SPOTS) do
        local gH, gz, norm = Bridge.GroundTrace(world, c.X, c.Y, c.Z + 400.0, c.Z - 600.0, { survivor })
        if gH and (not norm or norm.Z >= 0.55) then
            local slCand = { X = c.X, Y = c.Y, Z = gz + (Config.SLENDER.CAPSULE_HALF_HEIGHT or 92.0) }
            if Bridge.HasLineOfSight(world,
                { X = slCand.X, Y = slCand.Y, Z = slCand.Z + 55.0 },
                { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z + 65.0 },
                { survivor }) then
                return slCand
            end
            return slCand
        end
    end
    return { X = ROAD_AMBUSH_SPOTS[1].X, Y = ROAD_AMBUSH_SPOTS[1].Y, Z = ROAD_AMBUSH_SPOTS[1].Z }
end

function PrologueStory.ShouldBlockDoorAI(door)
    if not State.Active or not Logger.IsValidObj(door) then return false end
    local dn = Logger.SafeName(door)
    if dn == "BP_Door_Main2" and not State.BackDoorUnlocked then
        return true
    end
    if dn == "BP_Door_Room14_Locked" and State.Stage < STAGE.KATES_ROOM_2F then
        return true
    end
    local st = 0
    pcall(function() st = door:GetState() end)
    if st == 3 and dn ~= "BP_Door_Room14_Locked" then
        return true
    end
    return false
end

function PrologueStory.TickAmbient(world, pc, dt, HumanVisuals)
    if not State.Active then return end
    State.AmbientElapsed = State.AmbientElapsed + (dt or 0.016)
    if State.AmbientElapsed <= 4.0 then
        PrologueStory.DismissPrologueIntro(world, pc)
    end
    -- Keep flashlight cleanly off in Stage 1 & 2 until picked up, and keep back door locked until Nightfall
    if (not State.FlashlightPickedUp) and (State.AmbientElapsed - State.LastFlashEnsure >= 0.5) then
        State.LastFlashEnsure = State.AmbientElapsed
        if HumanVisuals and HumanVisuals.IsFlashlightEnabled and HumanVisuals.IsFlashlightEnabled() then
            HumanVisuals.SetFlashlightEnabled(false)
        end
        if (not State.BackDoorUnlocked) and Logger.IsValidObj(State.BackDoor) then
            local st = 0
            pcall(function() st = State.BackDoor:GetState() end)
            if st ~= 3 then
                pcall(function() State.BackDoor:SetState(nil, 3, true) end)
            end
        end
    end
end

function PrologueStory.GetHudObjectiveTarget()
    if State.Stage == STAGE.ROAD_TO_HOUSE then
        return HOUSE_PORCH_GOAL
    elseif State.Stage == STAGE.FIND_FLASHLIGHT then
        return (Logger.IsValidObj(State.ActiveFlashlight) and Bridge.GetActorLoc(State.ActiveFlashlight)) or HOUSE_INTERIOR_ANCHOR
    elseif State.Stage == STAGE.KATES_ROOM_2F then
        return (Logger.IsValidObj(State.KatesPage) and Bridge.GetActorLoc(State.KatesPage)) or KATES_ROOM_POS
    elseif State.Stage == STAGE.EXIT_BACK_DOOR then
        return (Logger.IsValidObj(State.BackGate) and Bridge.GetActorLoc(State.BackGate)) or TRAILHEAD_POS
    elseif State.Stage == STAGE.NIGHT_FOREST_TO_PARK then
        return (Logger.IsValidObj(State.TriggerBox1) and Bridge.GetActorLoc(State.TriggerBox1)) or TRIGGERBOX1_FALLBACK
    end
    return HOUSE_PORCH_GOAL
end

local function ApplyNightfallLighting(world, CameraCtrl)
    if Logger.IsValidObj(State.HouseScript) then
        pcall(function()
            if State.HouseScript.TurnOffLamp then State.HouseScript:TurnOffLamp() end
        end)
    end
    if Logger.IsValidObj(State.LightingInterp) then
        pcall(function()
            State.LightingInterp.CurrentInterpolation = 1.0
            if State.LightingInterp.Interpolate then
                State.LightingInterp:Interpolate(1.0)
            end
        end)
    end
    if Logger.IsValidObj(State.LevelScript) then
        pcall(function()
            if State.LevelScript.DirLightInterp then State.LevelScript:DirLightInterp(1.0) end
            if State.LevelScript.SkyLightInterp then State.LevelScript:SkyLightInterp(1.0) end
        end)
    end
    -- Reinforce Sunset->Night light actors in case any interpolated component lagged
    for _, dl in ipairs(FindAllOf("DirectionalLight") or {}) do
        if Logger.IsValidObj(dl) then
            local dn = Logger.SafeName(dl)
            if string.find(dn, "Sunset", 1, true) then
                pcall(function() dl:SetActorHiddenInGame(true) end)
                pcall(function() if dl.LightComponent then dl.LightComponent:SetIntensity(0.0) end end)
            elseif string.find(dn, "Night", 1, true) then
                pcall(function() dl:SetActorHiddenInGame(false) end)
            end
        end
    end
    for _, sl in ipairs(FindAllOf("SkyLight") or {}) do
        if Logger.IsValidObj(sl) then
            local sn = Logger.SafeName(sl)
            if string.find(sn, "Sunset", 1, true) then
                pcall(function() if sl.LightComponent then sl.LightComponent:SetIntensity(0.0) end end)
            end
        end
    end
    if CameraCtrl and CameraCtrl.SetNightVision then
        CameraCtrl.SetNightVision(true)
    end
end

local function TriggerNightfallAndTransfer(world, survivor, slender, SlenderCtrl, CameraCtrl, Overlay)
    if State.NightTriggered then return end
    State.NightTriggered = true
    ApplyNightfallLighting(world, CameraCtrl)

    -- Forest Scream Cue (2D + 3D near gate)
    local gateLoc = (Logger.IsValidObj(State.BackGate) and Bridge.GetActorLoc(State.BackGate)) or BACK_GATE_POS
    if Logger.IsValidObj(State.ScreamCue) and Bridge.PlaySoundObj2D then
        Bridge.PlaySoundObj2D(world, State.ScreamCue, 1.0, 1.0)
        if Bridge.PlaySoundObjAtLocation then
            Bridge.PlaySoundObjAtLocation(world, State.ScreamCue, gateLoc, 1.0, 1.0)
        end
        State.ScreamPlayed = true
    else
        local played = Bridge.PlaySound2D and Bridge.PlaySound2D(world, "/Game/Audio/Scream/gateScream_Cue.gateScream_Cue", 1.0, 1.0)
        State.ScreamPlayed = (played ~= false)
    end

    -- Unlock & open Back Door (BP_Door_Main2) + open Back Gate (BP_BackGate_Level1_10)
    State.BackDoorUnlocked = true
    if Logger.IsValidObj(State.BackDoor) then
        pcall(function() State.BackDoor.bOpenableByAI = true end)
        SetDoorStateSafe(State.BackDoor, survivor, 1)
    end
    if Logger.IsValidObj(State.BackGate) then
        pcall(function()
            if State.BackGate.OpenUp then State.BackGate:OpenUp() end
        end)
        pcall(function()
            if Logger.IsValidObj(State.BackGate.Box1) then State.BackGate.Box1:SetCollisionEnabled(0) end
            if Logger.IsValidObj(State.BackGate.Box2) then State.BackGate.Box2:SetCollisionEnabled(0) end
        end)
        State.BackGateOpened = true
    end

    -- Anti-Trap Slenderman Transfer to Backyard facing BP_Door_Main2
    if Logger.IsValidObj(slender) and SlenderCtrl and SlenderCtrl.SetPositionSafe then
        local targetDest = BACKYARD_TRANSFER_SPOTS[1]
        for _, cand in ipairs(BACKYARD_TRANSFER_SPOTS) do
            local gh, gz = Bridge.GroundTrace(world, cand.X, cand.Y, cand.Z + 300.0, cand.Z - 400.0, { survivor, slender })
            if gh and gz then
                targetDest = { X = cand.X, Y = cand.Y, Z = gz + (Config.SLENDER.CAPSULE_HALF_HEIGHT or 92.0) }
                break
            end
        end
        local faceYaw = Bridge.YawFromVec(BACK_DOOR_POS.X - targetDest.X, BACK_DOOR_POS.Y - targetDest.Y)
        SlenderCtrl.SetPositionSafe(world, targetDest, faceYaw)
        if CameraCtrl then
            if CameraCtrl.NotifyTeleport then CameraCtrl.NotifyTeleport() end
            if CameraCtrl.SetViewAngles then CameraCtrl.SetViewAngles(-4.0, faceYaw) end
        end
        State.SlenderTransferred = true
    end

    if Overlay and Overlay.ShowToast then
        Overlay.ShowToast("DARKNESS FALLS — A SCREAM ECHOES FROM THE BACKYARD!", 4.5)
    end
    Logger.Info("PrologueStory NIGHTFALL triggered: Lighting=1.0 Scream=" .. tostring(State.ScreamPlayed)
        .. " BackDoorUnlocked=true BackGateOpen=" .. tostring(State.BackGateOpened)
        .. " SlenderTransferred=" .. tostring(State.SlenderTransferred))
end

local function BuildTraceIgnore(survivor, slender)
    local ig = {}
    if Logger.IsValidObj(survivor) then table.insert(ig, survivor) end
    if Logger.IsValidObj(slender) then table.insert(ig, slender) end
    if Logger.IsValidObj(State.FrontDoor) then table.insert(ig, State.FrontDoor) end
    if State.BackDoorUnlocked and Logger.IsValidObj(State.BackDoor) then table.insert(ig, State.BackDoor) end
    if State.Stage >= STAGE.KATES_ROOM_2F and Logger.IsValidObj(State.KatesDoor) then table.insert(ig, State.KatesDoor) end
    if State.BackGateOpened and Logger.IsValidObj(State.BackGate) then table.insert(ig, State.BackGate) end
    return ig
end

local function MoveAlongWaypoints(world, dt, survivor, slender, waypoints, desiredSpeed, threatMem, fear, HumanVisuals)
    local hLoc = Bridge.GetActorLoc(survivor)
    if not hLoc or not waypoints or #waypoints == 0 then return true end
    local traceIgnore = BuildTraceIgnore(survivor, slender)

    -- Clamp & advance waypoint index
    State.WpIdx = math.max(1, math.min(#waypoints, State.WpIdx))
    local wp = waypoints[State.WpIdx]
    while State.WpIdx < #waypoints do
        local curWp = waypoints[State.WpIdx]
        local d2d = Bridge.Dist2D(hLoc, curWp)
        local dz  = math.abs(hLoc.Z - (curWp.Z or hLoc.Z))
        local thresh = (curWp.stairs or curWp.floor2 or curWp.guardhouse or curWp.floor1) and 68.0 or (curWp.narrow and 115.0 or 185.0)
        local zThresh = (curWp.stairs or curWp.floor2) and 95.0 or 260.0
        if d2d <= thresh and dz <= zThresh then
            State.WpIdx = State.WpIdx + 1
            wp = waypoints[State.WpIdx]
        else
            break
        end
    end

    local activeWp = waypoints[State.WpIdx]
    local isIndoorTight = (activeWp.stairs == true) or (activeWp.floor2 == true) or (activeWp.bridge == true) or (activeWp.narrow == true) or (activeWp.guardhouse == true)

    -- Corridor-safe outdoor evasion when threatened by Slenderman
    local slLoc = Logger.IsValidObj(slender) and Bridge.GetActorLoc(slender) or nil
    local sideOffset = 0.0
    local targetIdx = State.WpIdx
    if (not isIndoorTight) and slLoc and threatMem then
        local slDist = Bridge.Dist(hLoc, slLoc)
        local scared = (fear >= 42.0) or (threatMem.HasLOS == true) or (slDist < 1750.0)
        if scared then
            local vx, vy = activeWp.X - hLoc.X, activeWp.Y - hLoc.Y
            local sx, sy = slLoc.X - hLoc.X, slLoc.Y - hLoc.Y
            local vLen = math.sqrt(vx * vx + vy * vy)
            local sLen = math.sqrt(sx * sx + sy * sy)
            local aheadDot = (vLen > 1.0 and sLen > 1.0) and ((vx * sx + vy * sy) / (vLen * sLen)) or 0.0
            if aheadDot > 0.35 and slDist < 1900.0 and State.WpIdx > 3 then
                State.EvadeBacktrack = true
                State.EvadeTimer = 2.0
                State.SideSign = -State.SideSign
            end
            sideOffset = State.SideSign * 115.0
        end
    end
    if State.EvadeTimer > 0.0 then
        State.EvadeTimer = math.max(0.0, State.EvadeTimer - dt)
        if State.EvadeTimer <= 0.0 then
            State.EvadeBacktrack = false
        end
    end
    if State.EvadeBacktrack and (not isIndoorTight) and State.WpIdx > 3 then
        targetIdx = math.max(2, State.WpIdx - 2)
    end
    local targetWp = waypoints[targetIdx]

    -- Direction & lateral shoulder dodge
    local dx = targetWp.X - hLoc.X
    local dy = targetWp.Y - hLoc.Y
    local dist2D = math.sqrt(dx * dx + dy * dy)
    if State.WpIdx == #waypoints and dist2D <= ((activeWp.stairs or activeWp.floor2) and 68.0 or 175.0) then
        return true
    end
    if dist2D < 1.0 then return false end

    local baseYaw = Bridge.YawFromVec(dx, dy)
    local aimX, aimY = targetWp.X, targetWp.Y
    if math.abs(sideOffset) > 1.0 and dist2D > 220.0 then
        local px, py = -dy / dist2D, dx / dist2D
        aimX = aimX + px * sideOffset
        aimY = aimY + py * sideOffset
        baseYaw = Bridge.YawFromVec(aimX - hLoc.X, aimY - hLoc.Y)
    end

    -- Whisker obstacle avoidance
    local whiskerAngles = (activeWp.stairs or activeWp.floor2)
        and { 0.0, -18.0, 18.0, -35.0, 35.0 }
        or  { 0.0, -24.0, 24.0, -48.0, 48.0, -75.0, 75.0, -100.0, 100.0 }
    local lookDist = (activeWp.stairs or activeWp.floor2) and 75.0 or 115.0
    local chosenYaw = baseYaw
    for _, angOff in ipairs(whiskerAngles) do
        local wy = Bridge.NormalizeAngle(baseYaw + angOff)
        local fx, fy = Bridge.ForwardFromRot(0.0, wy)
        local hitLow = Bridge.LineTrace(world,
            { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z - 25.0 },
            { X = hLoc.X + fx * lookDist, Y = hLoc.Y + fy * lookDist, Z = hLoc.Z - 25.0 },
            traceIgnore, 0, false)
        local hitMid = Bridge.LineTrace(world,
            { X = hLoc.X, Y = hLoc.Y, Z = hLoc.Z + 45.0 },
            { X = hLoc.X + fx * lookDist, Y = hLoc.Y + fy * lookDist, Z = hLoc.Z + 45.0 },
            traceIgnore, 0, false)
        if (not hitLow) and (not hitMid) then
            chosenYaw = wy
            break
        end
    end

    local spd = desiredSpeed
    if activeWp.stairs then spd = math.min(spd, 275.0) end
    local fx, fy = Bridge.ForwardFromRot(0.0, chosenYaw)

    if HumanVisuals and HumanVisuals.SetMoveSpeed then
        HumanVisuals.SetMoveSpeed(spd)
    end
    if HumanVisuals and HumanVisuals.AimToward then
        HumanVisuals.AimToward(chosenYaw, -4.0, dt, 10.0)
    end
    pcall(function()
        survivor:AddMovementInput({ X = fx, Y = fy, Z = 0.0 }, 1.0, false)
    end)

    -- Anti-stuck watchdog (only intervenes if physics walking stalls)
    State.StuckTimer = State.StuckTimer + dt
    if not State.LastCheckPos then
        State.LastCheckPos = hLoc
    elseif State.StuckTimer >= 0.85 then
        local prog = Bridge.Dist2D(State.LastCheckPos, hLoc)
        State.StuckTimer = 0.0
        State.LastCheckPos = hLoc
        if prog < 25.0 then
            State.StuckCount = State.StuckCount + 1
            State.SideSign = -State.SideSign
            State.EvadeBacktrack = false
            local pushDist = 70.0
            local px = hLoc.X + (dx / dist2D) * pushDist
            local py = hLoc.Y + (dy / dist2D) * pushDist
            local pz = targetWp.Z or hLoc.Z
            local gh2, gz2 = Bridge.GroundTrace(world, px, py, hLoc.Z + 140.0, hLoc.Z - 260.0, traceIgnore)
            if gh2 and gz2 and (not activeWp.stairs or math.abs((gz2 + 92.0) - hLoc.Z) <= 95.0) then
                pz = gz2 + 92.0
            end
            pcall(function()
                survivor:K2_SetActorLocationAndRotation({ X = px, Y = py, Z = pz }, { Pitch = 0.0, Yaw = baseYaw, Roll = 0.0 }, false, {}, true)
            end)
            if State.StuckCount % 3 == 0 and State.WpIdx < #waypoints then
                State.WpIdx = State.WpIdx + 1
            end
        end
    end

    return false
end

local function NavigateHouseGoal(world, dt, survivor, ai, slender, targetPos, desiredSpeed, fear, HumanNav, HumanVisuals, HumanPerception)
    State.HouseGoalCooldown = math.max(0.0, State.HouseGoalCooldown - dt)
    local hLoc = Bridge.GetActorLoc(survivor)
    if not hLoc or not targetPos then return true end
    if Bridge.Dist2D(hLoc, targetPos) <= 165.0 and math.abs(hLoc.Z - targetPos.Z) <= 135.0 then
        return true
    end
    local dangerZones = HumanPerception and HumanPerception.GetDangerZones and HumanPerception.GetDangerZones() or nil
    local navState = HumanNav.GetNavState and HumanNav.GetNavState() or "Idle"
    if State.HouseGoalCooldown <= 0.0 or navState == "Idle" or navState == "Reached" or navState == "Stuck" then
        State.HouseGoalCooldown = 1.4
        local dest = targetPos
        if fear >= 68.0 and HumanNav.PickEscapeGoal and Logger.IsValidObj(slender) then
            local sLoc = Bridge.GetActorLoc(slender)
            local esc = sLoc and HumanNav.PickEscapeGoal(world, hLoc, sLoc, dangerZones) or nil
            if esc and (State.BackDoorUnlocked or esc.Y < 61700.0) then
                dest = esc
            end
        end
        HumanNav.SetGoal(world, hLoc, dest, dangerZones, fear >= 40.0, ai)
    end
    if HumanVisuals and HumanVisuals.SetMoveSpeed then
        HumanVisuals.SetMoveSpeed(desiredSpeed)
    end
    local _, steer, stuckNeedsNewGoal = HumanNav.UpdateMovement(world, dt, survivor, ai, slender, dangerZones)
    if steer and steer.Yaw and HumanVisuals and HumanVisuals.AimToward then
        HumanVisuals.AimToward(steer.Yaw, -4.0, dt, (fear >= 40.0) and 11.0 or 8.0)
    end
    if stuckNeedsNewGoal then
        State.HouseGoalCooldown = 0.0
    end
    return false
end

local function OpenNearby1FDoors(hLoc, survivor)
    if not hLoc then return end
    for _, d in ipairs(FindAllOf("BP_DoorBase_C") or {}) do
        if Logger.IsValidObj(d) and (not PrologueStory.ShouldBlockDoorAI(d)) then
            local dl = Bridge.GetActorLoc(d)
            if dl and dl.Z <= 9350.0 and Bridge.Dist2D(hLoc, dl) <= 275.0 then
                local st = 0
                pcall(function() st = d:GetState() end)
                if st ~= 1 and st ~= 3 then
                    SetDoorStateSafe(d, survivor, 1)
                end
            end
        end
    end
end

local function IsClear1FSegment(world, pA, pB, ignore, halfW)
    local midZ = math.min(pA.Z, pB.Z) - 92.0
    local offsets = { 0.0 }
    if halfW and halfW > 0.1 then
        offsets = { 0.0, halfW, -halfW }
    end
    local dx = pB.X - pA.X
    local dy = pB.Y - pA.Y
    local d = math.sqrt(dx * dx + dy * dy)
    if d < 1.0 then return true end
    local px, py = -dy / d, dx / d
    for _, zOff in ipairs({ 55.0, 115.0 }) do
        local z = midZ + zOff
        for _, off in ipairs(offsets) do
            local s = { X = pA.X + px * off, Y = pA.Y + py * off, Z = z }
            local e = { X = pB.X + px * off, Y = pB.Y + py * off, Z = z }
            if Bridge.LineTrace(world, s, e, ignore, 0, false) then
                return false
            end
        end
    end
    return true
end

local function SolveStage2HousePath(world, startPos, targetPos, survivor, slender)
    local step = 85.0
    local minX, maxX = 41350.0, 46150.0
    local minY, maxY = 58350.0, 62050.0

    local ig = { survivor }
    if Logger.IsValidObj(slender) then table.insert(ig, slender) end
    for _, f in ipairs(State.AllFlashlights or {}) do
        if Logger.IsValidObj(f) then table.insert(ig, f) end
    end
    local doorNodes = {}
    for _, d in ipairs(FindAllOf("BP_DoorBase_C") or {}) do
        if Logger.IsValidObj(d) and (not PrologueStory.ShouldBlockDoorAI(d)) then
            local dl = Bridge.GetActorLoc(d)
            if dl and dl.Z >= 8900.0 and dl.Z <= 9350.0 then
                table.insert(ig, d)
                table.insert(doorNodes, { pos = dl, name = Logger.SafeName(d) })
            end
        end
    end

    local function Snap(x, y)
        local gx = math.floor(x / step + 0.5) * step
        local gy = math.floor(y / step + 0.5) * step
        return gx, gy, string.format("%d_%d", math.floor(gx + 0.5), math.floor(gy + 0.5))
    end

    local nodes = {}
    local cellToId = {}
    local sx, sy, sKey = Snap(startPos.X, startPos.Y)
    local sgH, sgz = Bridge.GroundTrace(world, sx, sy, 9220.0, 8880.0, ig)
    local sPos = { X = sx, Y = sy, Z = (sgH and sgz or (startPos.Z - 92.0)) + 92.0 }
    nodes[1] = { id = 1, pos = sPos, parent = nil }
    cellToId[sKey] = 1
    local queue = { 1 }

    local dirs = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }
    local qHead = 1
    while qHead <= #queue and #nodes < 1600 do
        local uId = queue[qHead]
        qHead = qHead + 1
        local u = nodes[uId]
        for _, dir in ipairs(dirs) do
            local nx = u.pos.X + dir[1] * step
            local ny = u.pos.Y + dir[2] * step
            if nx >= minX and nx <= maxX and ny >= minY and ny <= maxY then
                local _, _, key = Snap(nx, ny)
                if not cellToId[key] then
                    local gh, gz, norm = Bridge.GroundTrace(world, nx, ny, 9220.0, 8880.0, ig)
                    if gh and gz and gz >= 8980.0 and gz <= 9160.0 and (not norm or norm.Z >= 0.65) then
                        local cand = { X = nx, Y = ny, Z = gz + 92.0 }
                        if IsClear1FSegment(world, u.pos, cand, ig, 10.0) then
                            local nid = #nodes + 1
                            nodes[nid] = { id = nid, pos = cand, parent = uId }
                            cellToId[key] = nid
                            table.insert(queue, nid)
                        end
                    end
                end
            end
        end

        -- Also jump cleanly across nearby unlocked 1F DoorBase tunnels when within 170cm
        for _, dn in ipairs(doorNodes) do
            if Bridge.Dist2D(u.pos, dn.pos) <= 185.0 then
                for _, off in ipairs({ { 115, 0 }, { -115, 0 }, { 0, 115 }, { 0, -115 } }) do
                    local tx, ty, tKey = Snap(dn.pos.X + off[1], dn.pos.Y + off[2])
                    if (not cellToId[tKey]) and tx >= minX and tx <= maxX and ty >= minY and ty <= maxY then
                        local gh, gz, norm = Bridge.GroundTrace(world, tx, ty, 9220.0, 8880.0, ig)
                        if gh and gz and gz >= 8980.0 and gz <= 9160.0 and (not norm or norm.Z >= 0.65) then
                            local cand = { X = tx, Y = ty, Z = gz + 92.0 }
                            if IsClear1FSegment(world, u.pos, cand, ig, 6.0) then
                                local nid = #nodes + 1
                                nodes[nid] = { id = nid, pos = cand, parent = uId }
                                cellToId[tKey] = nid
                                table.insert(queue, nid)
                            end
                        end
                    end
                end
            end
        end
    end

    local bestId, bestScore = 1, 1e12
    for i = 1, #nodes do
        local nPos = nodes[i].pos
        local d = Bridge.Dist2D(nPos, targetPos)
        local score = d
        if d <= 360.0 then
            local wallHit = Bridge.LineTrace(world,
                { X = nPos.X, Y = nPos.Y, Z = nPos.Z + 25.0 },
                { X = targetPos.X, Y = targetPos.Y, Z = targetPos.Z + 10.0 },
                ig, 0, false)
            if not wallHit then
                score = d - 1000.0
            end
        end
        if score < bestScore then
            bestScore = score
            bestId = i
        end
    end

    local rev = {}
    local cur = bestId
    while cur do
        local p = nodes[cur].pos
        table.insert(rev, { X = p.X, Y = p.Y, Z = p.Z, narrow = true, floor1 = true })
        cur = nodes[cur].parent
    end
    local path = {}
    for i = #rev, 1, -1 do
        table.insert(path, rev[i])
    end
    -- Append final direct point near pickup in case target is on a side table edge
    if #path > 0 then
        local last = path[#path]
        if Bridge.Dist2D(last, targetPos) > 120.0 then
            table.insert(path, { X = targetPos.X, Y = targetPos.Y, Z = last.Z, narrow = true, floor1 = true })
        end
    end
    Logger.Info(string.format("PrologueStory SolveStage2HousePath: bfsNodes=%d pathLen=%d endDist=%.1fcm target=(%.0f,%.0f)",
        #nodes, #path, Bridge.Dist2D(nodes[bestId].pos, targetPos), targetPos.X, targetPos.Y))
    return path
end

local function EnterStage(stage, subPhase, goalLabel)
    State.Stage     = stage
    State.SubPhase  = subPhase
    State.GoalLabel = goalLabel
    State.WpIdx     = 1
    State.StuckTimer = 0.0
    State.LastCheckPos = nil
    State.HouseGoalCooldown = 0.0
    State.HouseStage2Solved = false
    State.HouseStage2Wps = nil
    Logger.Info(string.format("PrologueStory -> Stage %d (%s): %s", stage, tostring(subPhase), tostring(goalLabel)))
end

function PrologueStory.UpdateAI(world, dt, survivor, ai, slender, aiState, deps)
    if not State.Active or not Logger.IsValidObj(survivor) then return end
    local HumanNav        = deps.HumanNav
    local HumanVisuals    = deps.HumanVisuals
    local HumanPerception = deps.HumanPerception
    local HumanFear       = deps.HumanFear
    local CameraCtrl      = deps.CameraCtrl
    local SlenderCtrl     = deps.SlenderCtrl
    local Overlay         = deps.Overlay

    local hLoc = Bridge.GetActorLoc(survivor)
    if not hLoc then return end
    local fear = HumanFear and HumanFear.GetFear() or 0.0
    local mem  = HumanPerception and HumanPerception.GetMemory() or {}
    local desiredSpeed = (aiState and aiState.DesiredSpeed) or 315.0
    if desiredSpeed < 315.0 then desiredSpeed = 315.0 end

    -- Synchronize FSM display state cleanly without running EightPages page logic
    if aiState then
        if fear >= 55.0 then
            aiState.State = "Panicking"
            aiState.TransitionReason = "Slender fear in Prologue"
        elseif mem.HasLOS or (mem.SlenderDist and mem.SlenderDist < 1700.0) then
            aiState.State = "Escaping"
            aiState.TransitionReason = "Spotted Slenderman"
        else
            aiState.State = "Explore"
            aiState.TransitionReason = State.GoalLabel
        end
        aiState.GoalLabel = State.GoalLabel
    end

    -- ======================= STAGE 1: ROAD TO HOUSE =======================
    if State.Stage == STAGE.ROAD_TO_HOUSE then
        -- Open front door proactively as she nears porch
        if Logger.IsValidObj(State.FrontDoor) and Bridge.Dist2D(hLoc, FRONT_DOOR_POS) <= 450.0 then
            SetDoorStateSafe(State.FrontDoor, survivor, 1)
        end
        local reachedPorch = MoveAlongWaypoints(world, dt, survivor, slender, ROAD_WAYPOINTS, desiredSpeed, mem, fear, HumanVisuals)
        if reachedPorch or (Bridge.Dist2D(hLoc, HOUSE_PORCH_GOAL) <= 230.0 and hLoc.Z <= 9350.0) then
            SetDoorStateSafe(State.FrontDoor, survivor, 1)
            EnterStage(STAGE.FIND_FLASHLIGHT, "1F_FLASHLIGHT", "Enter House & Grab Flashlight")
            if Overlay and Overlay.ShowToast then
                Overlay.ShowToast("Lauren reached Kate's House — looking for her Flashlight inside!", 3.5)
            end
        end

    -- ======================= STAGE 2: FIND FLASHLIGHT (1F) =======================
    elseif State.Stage == STAGE.FIND_FLASHLIGHT then
        local fl = State.ActiveFlashlight
        if not Logger.IsValidObj(fl) then
            fl = RefreshActiveFlashlight(hLoc)
        end
        local flLoc = Logger.IsValidObj(fl) and Bridge.GetActorLoc(fl) or HOUSE_INTERIOR_ANCHOR
        OpenNearby1FDoors(hLoc, survivor)

        -- Make sure she clears the front porch threshold cleanly before 1F pathing
        if hLoc.Y < 58620.0 and Bridge.Dist2D(hLoc, FRONT_DOOR_POS) <= 650.0 then
            SetDoorStateSafe(State.FrontDoor, survivor, 1)
            MoveAlongWaypoints(world, dt, survivor, slender, { { X = 44270.0, Y = 58820.0, Z = 9108.0, narrow = true } }, desiredSpeed, mem, fear, HumanVisuals)
        else
            if not State.HouseStage2Solved then
                State.HouseStage2Solved = true
                State.WpIdx = 1
                State.HouseStage2Wps = SolveStage2HousePath(world, hLoc, flLoc, survivor, slender)
            end
            if State.HouseStage2Wps and #State.HouseStage2Wps > 0 then
                local doneS2 = MoveAlongWaypoints(world, dt, survivor, slender, State.HouseStage2Wps, desiredSpeed, mem, fear, HumanVisuals)
                if doneS2 and Bridge.Dist2D(hLoc, flLoc) > 280.0 then
                    NavigateHouseGoal(world, dt, survivor, ai, slender, flLoc, desiredSpeed, fear, HumanNav, HumanVisuals, HumanPerception)
                end
            else
                NavigateHouseGoal(world, dt, survivor, ai, slender, flLoc, desiredSpeed, fear, HumanNav, HumanVisuals, HumanPerception)
            end
        end

        -- Pick up active flashlight when in reach (any side of furniture table)
        local curFlLoc = Logger.IsValidObj(fl) and Bridge.GetActorLoc(fl) or flLoc
        local dProp = Bridge.Dist2D(hLoc, curFlLoc)
        if dProp <= 265.0 and math.abs(hLoc.Z - curFlLoc.Z) <= 195.0 then
            if Logger.IsValidObj(fl) then
                pcall(function() fl:SetActorHiddenInGame(true) end)
                pcall(function() fl:SetActorEnableCollision(false) end)
                pcall(function() fl.bAvailableForPickup = false end)
            end
            State.FlashlightPickedUp = true
            if HumanVisuals and HumanVisuals.SetFlashlightEnabled then
                HumanVisuals.SetFlashlightEnabled(true)
            end
            if Bridge.PlaySoundAtLocation then
                Bridge.PlaySoundAtLocation(world, "/Engine/EditorSounds/Notifications/CompileSuccess_Cue.CompileSuccess_Cue", hLoc, 0.35, 1.1)
            end
            if HumanNav and HumanNav.Stop then HumanNav.Stop(ai) end
            EnterStage(STAGE.KATES_ROOM_2F, "TO_STAIRS", "Climb to Kate's Bedroom (2F)")
            if Overlay and Overlay.ShowToast then
                Overlay.ShowToast("Lauren picked up the Flashlight! Heading upstairs to Kate's Room...", 3.5)
            end
        end

    -- ======================= STAGE 3: KATE'S ROOM (2F) -> NIGHTFALL =======================
    elseif State.Stage == STAGE.KATES_ROOM_2F then
        if State.SubPhase == "TO_STAIRS" then
            local stairApp = STAIR_FOOT_POS
            if HumanNav and HumanNav.GetNearestWalkableNode then
                local node = HumanNav.GetNearestWalkableNode(STAIR_FOOT_POS, 380.0, 160.0)
                if node and node.pos then stairApp = node.pos end
            end
            if Bridge.Dist2D(hLoc, STAIR_FOOT_POS) <= 185.0 or Bridge.Dist2D(hLoc, stairApp) <= 135.0 or (hLoc.Z >= 9190.0) then
                if HumanNav and HumanNav.Stop then HumanNav.Stop(ai) end
                State.SubPhase = "CLIMB_2F"
                State.WpIdx = 1
                State.GoalLabel = "Climb Stairs to Kate's Room"
            else
                NavigateHouseGoal(world, dt, survivor, ai, slender, stairApp, desiredSpeed, 0.0, HumanNav, HumanVisuals, HumanPerception)
            end
        elseif State.SubPhase == "CLIMB_2F" then
            -- Proactively unlock & open Kate's locked door when she reaches the 2F hall outside it
            if Logger.IsValidObj(State.KatesDoor) and Bridge.Dist2D(hLoc, { X = 41265.0, Y = 60605.0, Z = 9633.0 }) <= 260.0 then
                SetDoorStateSafe(State.KatesDoor, survivor, 1)
            end
            local arrivedKate = MoveAlongWaypoints(world, dt, survivor, slender, STAIR_TO_KATE_WAYPOINTS, math.max(210.0, desiredSpeed), mem, 0.0, HumanVisuals)
            local noteLoc = (Logger.IsValidObj(State.KatesPage) and Bridge.GetActorLoc(State.KatesPage)) or KATES_NOTE_FALLBACK
            if arrivedKate or (Bridge.Dist2D(hLoc, KATES_ROOM_POS) <= 215.0 and hLoc.Z >= 9550.0) then
                SetDoorStateSafe(State.KatesDoor, survivor, 1)
                State.SubPhase = "INSPECT_KATE"
                State.InspectTimer = 0.0
                State.GoalLabel = "Inspecting Kate's Room & Note"
                State.KatesRoomInspected = true
                if HumanVisuals and HumanVisuals.AimToward then
                    HumanVisuals.AimToward(Bridge.YawFromVec(noteLoc.X - hLoc.X, noteLoc.Y - hLoc.Y), -6.0, 0.5, 20.0)
                end
            end
        elseif State.SubPhase == "INSPECT_KATE" then
            State.InspectTimer = State.InspectTimer + dt
            local noteLoc = (Logger.IsValidObj(State.KatesPage) and Bridge.GetActorLoc(State.KatesPage)) or KATES_NOTE_FALLBACK
            if HumanVisuals and HumanVisuals.AimToward then
                HumanVisuals.AimToward(Bridge.YawFromVec(noteLoc.X - hLoc.X, noteLoc.Y - hLoc.Y), -6.0, dt, 8.0)
            end
            if State.InspectTimer >= 1.1 then
                if Logger.IsValidObj(State.KatesPage) then
                    pcall(function() State.KatesPage:SetActorHiddenInGame(true) end)
                    pcall(function() State.KatesPage:SetActorEnableCollision(false) end)
                end
                State.KatesNoteCollected = true
                TriggerNightfallAndTransfer(world, survivor, slender, SlenderCtrl, CameraCtrl, Overlay)
                EnterStage(STAGE.EXIT_BACK_DOOR, "DESCEND_STAIRS", "Descend Stairs to Back Door")
            end
        end

    -- ======================= STAGE 4: EXIT BACK DOOR -> BACK GATE =======================
    elseif State.Stage == STAGE.EXIT_BACK_DOOR then
        if State.SubPhase == "DESCEND_STAIRS" then
            if Logger.IsValidObj(State.KatesDoor) and Bridge.Dist2D(hLoc, { X = 41265.0, Y = 60605.0, Z = 9633.0 }) <= 260.0 then
                SetDoorStateSafe(State.KatesDoor, survivor, 1)
            end
            local at1F = MoveAlongWaypoints(world, dt, survivor, slender, KATE_DOWN_TO_1F_WAYPOINTS, math.max(305.0, desiredSpeed), mem, 0.0, HumanVisuals)
            if at1F or (hLoc.Z <= 9180.0 and Bridge.Dist2D(hLoc, STAIR_FOOT_POS) <= 170.0) then
                if HumanNav and HumanNav.Stop then HumanNav.Stop(ai) end
                State.SubPhase = "EXIT_BACK_HALL"
                State.GoalLabel = "Exit through Back Door (1F)"
            end
        elseif State.SubPhase == "EXIT_BACK_HALL" then
            SetDoorStateSafe(State.BackDoor, survivor, 1)
            local backApproach = { X = 44193.0, Y = 61550.0, Z = 9108.0 }
            if HumanNav and HumanNav.GetNearestWalkableNode then
                local node = HumanNav.GetNearestWalkableNode(backApproach, 380.0, 160.0)
                if node and node.pos then backApproach = node.pos end
            end
            if (hLoc.Y >= 61150.0 and hLoc.X <= 44780.0) or Bridge.Dist2D(hLoc, BACK_DOOR_POS) <= 550.0 then
                MoveAlongWaypoints(world, dt, survivor, slender, {
                    { X = 44193.0, Y = 61680.0, Z = 9108.0, narrow = true },
                    { X = 44193.0, Y = 62400.0, Z = 9100.0, narrow = true },
                }, math.max(305.0, desiredSpeed), mem, fear, HumanVisuals)
            else
                NavigateHouseGoal(world, dt, survivor, ai, slender, backApproach, math.max(295.0, desiredSpeed), 0.0, HumanNav, HumanVisuals, HumanPerception)
            end
            if hLoc.Y >= 62080.0 and hLoc.Z <= 9260.0 then
                if HumanNav and HumanNav.Stop then HumanNav.Stop(ai) end
                State.SubPhase = "CROSS_BACKYARD"
                State.WpIdx = 1
                State.GoalLabel = "Escape through Backyard Gate"
            end
        elseif State.SubPhase == "CROSS_BACKYARD" then
            local pastGate = MoveAlongWaypoints(world, dt, survivor, slender, BACKYARD_TO_GATE_WAYPOINTS, math.max(350.0, desiredSpeed), mem, fear, HumanVisuals)
            if (pastGate and hLoc.Y >= 66820.0) or (hLoc.Y >= 66820.0 and Bridge.Dist2D(hLoc, BACK_GATE_POS) <= 450.0) then
                EnterStage(STAGE.NIGHT_FOREST_TO_PARK, "FOREST_TRAIL", "Reach Oakside Park Gate (Night Woods)")
                if Overlay and Overlay.ShowToast then
                    Overlay.ShowToast("Lauren escaped into the Night Forest — Hunt her down before Oakside Park!", 4.0)
                end
            end
        end

    -- ======================= STAGE 5: NIGHT WOODS -> OAKSIDE PARK =======================
    elseif State.Stage == STAGE.NIGHT_FOREST_TO_PARK then
        -- Optional immersion: trigger roadside floodlight generators when passing Gen2 / Gen3
        if (not State.Gen2Triggered) and Bridge.Dist2D(hLoc, { X = 57600.0, Y = 73200.0, Z = 7024.0 }) <= 480.0 then
            State.Gen2Triggered = true
            State.GoalLabel = "Follow Woods past Generator & Creek Bridge"
        elseif (not State.Gen3Triggered) and Bridge.Dist2D(hLoc, { X = 81000.0, Y = 66600.0, Z = 6247.0 }) <= 480.0 then
            State.Gen3Triggered = true
            State.GoalLabel = "Head North past Burnt House to Oakside Park"
        end

        MoveAlongWaypoints(world, dt, survivor, slender, FOREST_TO_PARK_WAYPOINTS, desiredSpeed, mem, fear, HumanVisuals)

        local trigPos = (Logger.IsValidObj(State.TriggerBox1) and Bridge.GetActorLoc(State.TriggerBox1)) or TRIGGERBOX1_FALLBACK
        if Bridge.Dist2D(hLoc, trigPos) <= 285.0 and math.abs(hLoc.Z - trigPos.Z) <= 350.0 then
            State.ParkGateReached = true
            State.GoalLabel = "Oakside Park Gate Reached!"
            Logger.Info("PrologueStory -> HUMAN REACHED TriggerBox_1 (Oakside Park)!")
        end
    end
end

return PrologueStory
