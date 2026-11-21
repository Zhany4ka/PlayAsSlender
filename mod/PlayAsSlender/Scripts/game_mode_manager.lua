-- PlayAsSlender Bidirectional Match Rules & Win/Loss Conditions
local Config           = require("config")
local Logger           = require("logger")
local Bridge           = require("ue_bridge")
local ObjectiveManager = require("objective_manager")
local HumanPerception  = require("human_perception")
local HumanFear        = require("human_fear_system")
local Abilities        = require("slender_abilities")

local GameModeMgr = {}

local State = {
    Result            = "ACTIVE", -- "ACTIVE" | "HUMAN_WIN" | "SLENDER_WIN"
    Reason            = "",
    Elapsed           = 0.0,
    CaptureHold       = 0.0,
    EndSummary        = "",
    EndDetails        = nil,
    StageReached      = 1,
    ClosestApproachCm = nil,
}

function GameModeMgr.Reset()
    State.Result            = "ACTIVE"
    State.Reason            = ""
    State.Elapsed           = 0.0
    State.CaptureHold       = 0.0
    State.EndSummary        = ""
    State.EndDetails        = nil
    State.StageReached      = 1
    State.ClosestApproachCm = nil
end

function GameModeMgr.IsMatchEnded()
    return State.Result ~= "ACTIVE"
end

function GameModeMgr.GetElapsed()
    return State.Elapsed
end

function GameModeMgr.GetEndDetails()
    return State.EndDetails
end

function GameModeMgr.GetResult()
    return State.Result, State.Reason, State.EndSummary
end

function GameModeMgr.GetHuntStage(collected, total)
    local PrologueStory = require("prologue_story")
    if PrologueStory.IsActive() then
        local st = PrologueStory.GetStage()
        return st, PrologueStory.GetStageName(st)
    end
    local c = tonumber(collected)
    local t = tonumber(total)
    if c == nil then c = tonumber(ObjectiveManager.GetCollectedCount()) or 0 end
    if t == nil then t = tonumber(ObjectiveManager.GetTotalCount()) or 8 end
    if (t >= 2 and c >= (t - 1)) or c >= 7 then
        return 4, "STAGE IV: FINAL HOUR"
    elseif c <= 1 then
        return 1, "STAGE I: STALKING"
    elseif c <= 4 then
        return 2, "STAGE II: HAUNTING"
    elseif c <= 6 then
        return 3, "STAGE III: DESPERATION"
    end
    return 4, "STAGE IV: FINAL HOUR"
end

function GameModeMgr.GetHudMetrics()
    local collected = tonumber(ObjectiveManager.GetCollectedCount()) or 0
    local total     = tonumber(ObjectiveManager.GetTotalCount()) or 8
    local stageNum, stageName = GameModeMgr.GetHuntStage(collected, total)
    local closestDistM = State.ClosestApproachCm and (State.ClosestApproachCm / 100.0) or 0.0
    return {
        stageNum     = stageNum,
        stageName    = stageName,
        closestDistM = closestDistM,
    }
end

local function FinalizeMatch(world, result, title, reason)
    if State.Result ~= "ACTIVE" then return end
    State.Result = result
    State.Reason = reason
    local pages  = tonumber(ObjectiveManager.GetCollectedCount()) or 0
    local total  = math.max(1, tonumber(ObjectiveManager.GetTotalCount()) or 8)
    local tpUsed, scares, intercepts = Abilities.GetStats()
    tpUsed     = tonumber(tpUsed) or 0
    scares     = tonumber(scares) or 0
    intercepts = tonumber(intercepts) or 0
    local ambushes = (HumanFear.GetAmbushCount and tonumber(HumanFear.GetAmbushCount())) or 0
    local peakF    = tonumber(HumanFear.GetPeakFear()) or 0.0
    local elapsed  = tonumber(State.Elapsed) or 0.0

    local prevented    = math.max(0, total - pages)
    local _, stageName = GameModeMgr.GetHuntStage(pages, total)
    local closestDistM = State.ClosestApproachCm and (State.ClosestApproachCm / 100.0) or 0.0

    local baseScore = (result == "SLENDER_WIN") and 1000 or 250
    local timeBonus = (result == "SLENDER_WIN") and math.max(0, math.floor((240.0 - elapsed) * 2.5)) or 0
    local score = baseScore
        + prevented * 150
        + timeBonus
        + math.floor(peakF * 4.0)
        + scares * 90
        + ambushes * 120
        + intercepts * 110

    local rankLetter, rankTitle
    if result == "SLENDER_WIN" then
        if pages == 0 or score >= 2100 then
            rankLetter, rankTitle = "S", "THE ARRIVAL"
        elseif score >= 1650 then
            rankLetter, rankTitle = "A", "FACELESS TERROR"
        else
            rankLetter, rankTitle = "B", "APEX STALKER"
        end
    else
        if peakF >= 65.0 then
            rankLetter, rankTitle = "C", "WOODLAND SPECTER"
        else
            rankLetter, rankTitle = "D", "PREY ESCAPED"
        end
    end

    State.EndDetails = {
        result       = result,
        title        = title,
        reason       = reason,
        elapsed      = elapsed,
        pages        = pages,
        total        = total,
        peakFear     = peakF,
        tpUsed       = tpUsed,
        scares       = scares,
        score        = score,
        rankLetter   = rankLetter,
        rankTitle    = rankTitle,
        stageName    = stageName,
        closestDistM = closestDistM,
        ambushes     = ambushes,
        intercepts   = intercepts,
        prevented    = prevented,
    }
    State.EndSummary = string.format(
        "%s\n%s\n\n" ..
        "Hunter Rank    : %s [%s] (%d pts)\n" ..
        "Hunt Stage     : %s   |   Closest Stalk: %.1f m\n" ..
        "Duration       : %.1f s\n" ..
        "Objectives     : %d / %d (%d Denied)\n" ..
        "Peak Human Fear: %.0f / 100   |   Ambushes: %d\n" ..
        "Teleports Used : %d   |   Terrify Landed: %d   |   Intercepts: %d\n\n" ..
        "[F8] Restart Match as Slenderman",
        title, reason, rankLetter, rankTitle, score, stageName, closestDistM,
        elapsed, pages, total, prevented, peakF, ambushes, tpUsed, scares, intercepts
    )
    Logger.Info("MATCH ENDED [" .. result .. "] Rank=" .. rankLetter .. " Score=" .. tostring(score) .. ": " .. reason)
    if result == "SLENDER_WIN" then
        Bridge.PlaySound2D(world, Config.ASSETS.SOUND_DRAMATIC, 0.90, 1.0, { "Teleporter_Dramatic", "Teleporter" })
    end
end

function GameModeMgr.Update(world, dt, slender, survivor)
    if State.Result ~= "ACTIVE" then return State.Result end
    State.Elapsed = State.Elapsed + dt

    local slLoc = Logger.IsValidObj(slender) and Bridge.GetActorLoc(slender) or nil
    local huLoc = Logger.IsValidObj(survivor) and Bridge.GetActorLoc(survivor) or nil
    if slLoc and huLoc then
        local dist3D = Bridge.Dist(slLoc, huLoc)
        if (not State.ClosestApproachCm) or dist3D < State.ClosestApproachCm then
            State.ClosestApproachCm = dist3D
        end
    end

    local collected = ObjectiveManager.GetCollectedCount()
    local total     = ObjectiveManager.GetTotalCount()
    local stageNum, stageName = GameModeMgr.GetHuntStage(collected, total)

    -- 1. Human Victory: Chapter 1 Prologue Park Gate OR All 8 pages collected
    local PrologueStory = require("prologue_story")
    if PrologueStory.IsActive() then
        if PrologueStory.IsParkGateReached() then
            FinalizeMatch(
                world,
                "HUMAN_WIN",
                "SURVIVOR ESCAPED TO OAKSIDE PARK",
                "Lauren abandoned her car, grabbed Kate's flashlight & bedroom note, fled into the night woods, and reached Oakside Park."
            )
            return State.Result
        end
    elseif collected >= total then
        FinalizeMatch(
            world,
            "HUMAN_WIN",
            "HUMAN SURVIVED — ALL OBJECTIVES COMPLETED",
            "The Human gathered the objectives and escaped."
        )
        return State.Result
    end

    -- 2. Slenderman Victory (Psychological Breakdown)
    if HumanFear.IsBrokenDown() then
        FinalizeMatch(
            world,
            "SLENDER_WIN",
            "SLENDERMAN VICTORY — PSYCHOLOGICAL BREAKDOWN",
            "Overwhelming terror shattered the Human's sanity."
        )
        return State.Result
    end

    -- 3. Slenderman Victory (Sustained Capture under fear & line of sight)
    if Logger.IsValidObj(slender) and Logger.IsValidObj(survivor) then
        local mem  = HumanPerception.GetMemory()
        local fear = HumanFear.GetFear()
        local dist = mem.SlenderDist or Bridge.Dist(Bridge.GetActorLoc(slender), Bridge.GetActorLoc(survivor))
        local captureReady = ((dist <= Config.SLENDER.CAPTURE_RADIUS and fear >= 75.0)
            or (dist <= 175.0 and fear >= 55.0)) and (mem.HasLOS or mem.SixthSenseTriggered or dist <= 175.0)

        if captureReady then
            State.CaptureHold = State.CaptureHold + dt
            if State.CaptureHold >= 0.60 then
                FinalizeMatch(
                    world,
                    "SLENDER_WIN",
                    "SLENDERMAN VICTORY — HUMAN CAPTURED",
                    "Slenderman closed in on the panicked survivor."
                )
            end
        else
            State.CaptureHold = math.max(0.0, State.CaptureHold - dt * 1.5)
        end
    end

    if State.Result == "ACTIVE" and stageNum > State.StageReached then
        State.StageReached = stageNum
        local okOv, Overlay = pcall(require, "debug_overlay")
        if okOv and Overlay and Overlay.ShowToast then
            Overlay.ShowToast(string.format("%s - THE HUNT ESCALATES", stageName), 3.2)
        end
        Logger.Info(string.format("Hunt escalated to %s (%d/%d objectives)", stageName, collected, total))
    end

    return State.Result
end

function GameModeMgr.ForceEndForTest(world, result, title, reason)
    State.Result = "ACTIVE"
    FinalizeMatch(
        world,
        result or "SLENDER_WIN",
        title or ((result == "HUMAN_WIN") and "HUMAN SURVIVED — ALL OBJECTIVES COMPLETED" or "SLENDERMAN VICTORY — PSYCHOLOGICAL BREAKDOWN"),
        reason or ((result == "HUMAN_WIN") and "The Human gathered the objectives and escaped." or "Overwhelming terror shattered the Human's sanity.")
    )
    return State.Result
end

return GameModeMgr
