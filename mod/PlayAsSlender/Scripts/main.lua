-- PlayAsSlender Main Entry Point (Universal Map Support, Native Menu Integration, Custom Loading Screens)
local UEHelpers        = require("UEHelpers")
local Config           = require("config")
local Logger           = require("logger")
local Bridge           = require("ue_bridge")
local LoadingScreenMgr = require("loading_screen_manager")
local ProgressionMgr   = require("progression_manager")
local MenuIntegration  = require("menu_integration")
local Overlay          = require("debug_overlay")
local CameraCtrl       = require("camera_controller")
local SlenderCtrl      = require("slender_controller")
local Abilities        = require("slender_abilities")
local HammerMgr        = require("slender_hammer")
local HumanVisuals     = require("human_visuals")
local ObjectiveManager = require("objective_manager")
local HumanNav         = require("human_navigation")
local HumanPerception  = require("human_perception")
local HumanFear        = require("human_fear_system")
local HumanAI          = require("human_ai_controller")
local GameModeMgr      = require("game_mode_manager")
local PrologueStory    = require("prologue_story")

Logger.Init()
ProgressionMgr.Init()
local kbPath, kbCount = Config.LoadUserKeybinds()
Logger.Info(string.format("PlayAsSlender loaded (keybinds=%s, %d keys applied).", tostring(kbPath), tonumber(kbCount) or 0))

local State = {
    WorldName       = "",
    WorldAddr       = 0,
    Mode            = "BOOT", -- "MENU" | "GAME" | "VANILLA" | "OTHER"
    ModArmed        = false,
    ActiveMapCfg    = nil,
    HasNavMesh      = true,
    EnterTimer      = 0.0,
    InitializedMap  = false,
    WasPaused        = false,
    LastUiUpdate     = 0.0,
    MatchEndHandled  = false,
    EndNextChapter   = nil,
    EndNewlyUnlock   = false,
    TravelInProgress = false,
    PendingTravel    = nil,
    PerfTickMs       = 0.0,
}

MenuIntegration.Init(function(armed, _)
    State.ModArmed = (armed == true)
end)

local function ClearLevelRefs()
    Overlay.Reset()
    MenuIntegration.ResetForNewWorld()
    CameraCtrl.Reset()
    SlenderCtrl.Reset()
    Abilities.Reset()
    HammerMgr.Reset()
    HumanVisuals.Reset()
    ObjectiveManager.Reset()
    HumanNav.Reset()
    HumanPerception.Reset()
    HumanFear.Reset()
    HumanAI.Reset(State.ActiveMapCfg)
    GameModeMgr.Reset()
    PrologueStory.Reset()
    Bridge.ClearWorldCaches()
    State.InitializedMap  = false
    State.WasPaused       = false
    State.MatchEndHandled = false
    State.EndNextChapter  = nil
    State.EndNewlyUnlock  = false
end

local function ScheduleTravel(kind, mapCfg, modArmed, levelPath)
    if State.TravelInProgress or State.PendingTravel then return end
    State.PendingTravel = {
        kind      = kind,
        mapCfg    = mapCfg,
        modArmed  = modArmed == true,
        levelPath = levelPath,
    }
end

local function TriggerRestart(world)
    local mapCfg = State.ActiveMapCfg or Config.MAPS.EIGHT_PAGES
    Logger.Info("Restart [F8] -> Scheduling reload of " .. mapCfg.path .. " as Slenderman")
    ScheduleTravel("RESTART", mapCfg, true, mapCfg.path)
end

local function TriggerReturnToMenu(world)
    Logger.Info("EndScreen -> Scheduling return to Main Menu")
    ScheduleTravel("MENU", nil, false, "/Game/Maps/Slender/SlenderMainMenu")
end

local function TriggerNextLevel(world)
    local nextCfg = State.EndNextChapter
    if (not nextCfg) or (not ProgressionMgr.IsChapterUnlocked(nextCfg.token)) then
        Logger.Warn("TriggerNextLevel blocked: next level is locked or unavailable.")
        return
    end
    Logger.Info("EndScreen -> Scheduling advance to Next Unlocked Chapter: " .. tostring(nextCfg.token))
    ScheduleTravel("NEXT", nextCfg, true, nextCfg.path)
end

local function ExecutePendingTravel(world, pc, req)
    State.PendingTravel = nil
    State.TravelInProgress = true
    State.ModArmed = req.modArmed

    local ai = HumanVisuals.GetAI()
    if Logger.IsValidObj(ai) then
        pcall(function() ai:UnPossess() end)
    end
    if Logger.IsValidObj(pc) then
        pcall(function()
            pc.bAutoManageActiveCameraTarget = true
            pc:SetViewTargetWithBlend(pc, 0.0, 0, 0.0, false)
        end)
    end

    if req.kind == "MENU" then
        LoadingScreenMgr.RestoreVanilla(world)
    else
        LoadingScreenMgr.ApplyModLoadingScreens(world, req.mapCfg)
    end
    ClearLevelRefs()
    Bridge.LoadLevel(world, req.levelPath)
end

MenuIntegration.RegisterButtonHandler("PAS_END_RESTART", TriggerRestart)
MenuIntegration.RegisterButtonHandler("PAS_END_NEXT",    TriggerNextLevel)
MenuIntegration.RegisterButtonHandler("PAS_END_MENU",    TriggerReturnToMenu)

local function NeutralizeIntroCutscenes(world, pc, survivor, forceStopFade)
    for _, sq in ipairs(FindAllOf("LevelSequenceActor") or {}) do
        if Logger.IsValidObj(sq) then
            local wasPlaying = false
            pcall(function()
                local sp = sq.SequencePlayer
                if Logger.IsValidObj(sp) then
                    wasPlaying = (sp:IsPlaying() == true)
                    sp:Stop()
                    sp:Pause()
                end
            end)
            pcall(function() sq:SetActorTickEnabled(false) end)
            if wasPlaying then
                Logger.Info("Stopped active LevelSequenceActor: " .. Logger.SafeName(sq))
            end
        end
    end

    if Logger.IsValidObj(survivor) then
        pcall(function() survivor:StopAnimMontage(nil) end)
        for _, comp in ipairs({ survivor.Mesh, survivor.ShadowCaster }) do
            if Logger.IsValidObj(comp) then
                pcall(function()
                    local ai = comp:GetAnimInstance()
                    if Logger.IsValidObj(ai) then ai:Montage_Stop(0.0, nil) end
                end)
            end
        end
        pcall(function()
            local cmc = survivor.CharacterMovement
            if Logger.IsValidObj(cmc) and tonumber(cmc.MovementMode) ~= 1 then
                cmc:SetMovementMode(1, 0)
            end
        end)
    end

    if Logger.IsValidObj(pc) then
        pcall(function()
            if pc:IsMoveInputIgnored() then
                pc:ResetIgnoreMoveInput()
                pc:SetIgnoreMoveInput(false)
            end
        end)
        pcall(function()
            if pc:IsLookInputIgnored() then
                pc:ResetIgnoreLookInput()
                pc:SetIgnoreLookInput(false)
            end
        end)
        if forceStopFade then
            pcall(function()
                if Logger.IsValidObj(pc.PlayerCameraManager) then
                    pc.PlayerCameraManager:StopCameraFade()
                end
            end)
        end
    end
end

local function InitPlayableLevel(world, pc, mapCfg)
    State.InitializedMap = true
    State.ActiveMapCfg   = mapCfg
    local hasNavMesh     = (#(FindAllOf("RecastNavMesh") or {}) > 0)
    State.HasNavMesh     = hasNavMesh
    Logger.Info(string.format("Initializing PlayAsSlender on %s (NavMesh=%s)...", mapCfg.token, tostring(hasNavMesh)))

    NeutralizeIntroCutscenes(world, pc, nil, true)

    local gm = Bridge.GetGameMode()
    local okH, survivor, ai, ps = HumanVisuals.Init(world, pc, mapCfg.key)
    if not okH then
        -- Retry next ticks cleanly if Pawn wasn't spawned yet right after OpenLevel
        State.InitializedMap = false
        State.EnterTimer = 0.8
        return
    end

    PrologueStory.Init(world, survivor, ai, mapCfg, HumanVisuals)
    local navAnchor = (mapCfg.key == "PROLOGUE") and PrologueStory.GetHouseNavAnchor() or nil
    ObjectiveManager.Init(world, survivor, ps, gm, mapCfg.key, hasNavMesh)
    HumanNav.BuildGraph(world, ObjectiveManager.GetExplorationZones(), Bridge.GetActorLoc(survivor), hasNavMesh, survivor, navAnchor)
    ObjectiveManager.SnapZonesToWalkableGraph(HumanNav, world)
    HumanPerception.Reset()
    HumanFear.Reset()
    HumanAI.Reset(mapCfg)
    GameModeMgr.Reset()

    local okS, slPos, slYaw = SlenderCtrl.Init(world, survivor, mapCfg, hasNavMesh)
    if okS then
        CameraCtrl.Init(world, pc, slPos, slYaw)
        HammerMgr.Init(world, SlenderCtrl.GetActor())
        if mapCfg.key == "PROLOGUE" and CameraCtrl.SetNightVision then
            CameraCtrl.SetNightVision(false)
        end
    end
    if HumanVisuals.UpdateLights then
        HumanVisuals.UpdateLights(world, SlenderCtrl.GetActor(), CameraCtrl.GetCamActor and CameraCtrl.GetCamActor() or nil)
    end

    NeutralizeIntroCutscenes(world, pc, survivor, true)
    if mapCfg.key == "PROLOGUE" then
        PrologueStory.DismissPrologueIntro(world, pc)
    end
    Overlay.Init(pc, "GAME")
    MenuIntegration.EnsureButtonHook()
    Overlay.HideVanillaHUD(true)
    Overlay.ShowToast(mapCfg.title, 4.0)
end

local function OnTick()
    local t0 = os.clock()
    local world = Bridge.GetWorld()
    if not Logger.IsValidObj(world) then return end

    local wname = Logger.SafeFullName(world)
    local waddr = Bridge.GetObjAddr(world)
    if waddr ~= State.WorldAddr or wname ~= State.WorldName then
        Logger.Info(string.format("World changed: %s (0x%X) -> %s (0x%X)",
            tostring(State.WorldName), tonumber(State.WorldAddr) or 0, wname, tonumber(waddr) or 0))
        ClearLevelRefs()
        State.WorldName        = wname
        State.WorldAddr        = waddr
        State.EnterTimer       = 0.0
        State.TravelInProgress = false
        State.PendingTravel    = nil

        local mapCfg = Config.ResolveAnyPlayableMap(wname)
        if Config.IsMenuMap(wname) then
            State.Mode = "MENU"
            State.ActiveMapCfg = nil
            State.ModArmed = false
            MenuIntegration.ResetForNewWorld()
            LoadingScreenMgr.RestoreVanilla(world)
        elseif mapCfg and State.ModArmed then
            State.Mode = "GAME"
            State.ActiveMapCfg = mapCfg
            State.ModArmed = true
        elseif mapCfg then
            State.Mode = "VANILLA"
            State.ActiveMapCfg = nil
            Logger.Info("PlayAsSlender: Launched without PlayAsSlender mode -> keeping vanilla gameplay intact.")
        else
            State.Mode = "OTHER"
            State.ActiveMapCfg = nil
        end
    end

    if State.TravelInProgress then
        return
    end

    local dt = Bridge.GetDeltaSeconds(world)
    State.EnterTimer = State.EnterTimer + dt
    local pc = Bridge.GetPC()
    if not Logger.IsValidObj(pc) then return end

    if State.PendingTravel then
        ExecutePendingTravel(world, pc, State.PendingTravel)
        return
    end

    -- MAIN MENU
    if State.Mode == "MENU" then
        if not State.InitializedMap and State.EnterTimer > 0.8 then
            State.InitializedMap = true
            Overlay.Init(pc, "MENU")
        end
        MenuIntegration.Tick(world, pc, dt, State.ModArmed)

        if Bridge.WasKeyJustPressed(pc, Config.KEYS.QUICK_START_HOUSE) then
            Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_UI_CLICK, 0.55, 1.0, { "click_Cue", "click" })
            State.ModArmed = true
            State.TravelInProgress = true
            LoadingScreenMgr.ApplyModLoadingScreens(world, Config.MAPS.PROLOGUE)
            Logger.Info("QuickStart House [F9] -> Loading Level01_Prologue")
            Bridge.LoadLevel(world, Config.MAPS.PROLOGUE.path)
        elseif Bridge.WasKeyJustPressed(pc, Config.KEYS.QUICK_START_FOREST) then
            Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_UI_CLICK, 0.55, 1.0, { "click_Cue", "click" })
            State.ModArmed = true
            State.TravelInProgress = true
            LoadingScreenMgr.ApplyModLoadingScreens(world, Config.MAPS.EIGHT_PAGES)
            Logger.Info("QuickStart Forest [F7] -> Loading Level02_TheEightPages")
            Bridge.LoadLevel(world, Config.MAPS.EIGHT_PAGES.path)
        end
        return
    end

    -- PLAYABLE MAPS
    if State.Mode == "GAME" and State.ActiveMapCfg then
        local initDelay = (State.ActiveMapCfg.key == "PROLOGUE") and 2.2 or 1.5
        if not State.InitializedMap then
            if State.EnterTimer >= initDelay then
                InitPlayableLevel(world, pc, State.ActiveMapCfg)
            end
            return
        end

        -- Takeover Watchdog: if level reloaded in-place or UE handed Pawn back to PC, immediately re-takeover as Slenderman!
        if (not Logger.IsValidObj(SlenderCtrl.GetActor()))
            or (not Logger.IsValidObj(HumanVisuals.GetActor()))
            or Logger.IsValidObj(pc.Pawn) then
            Logger.Warn("Takeover watchdog triggered! Re-initializing PlayAsSlender...")
            ClearLevelRefs()
            State.EnterTimer = 0.5
            return
        end

        -- Pause guard
        if Bridge.IsGamePaused(world) then
            State.WasPaused = true
            return
        elseif State.WasPaused then
            State.WasPaused = false
            if not GameModeMgr.IsMatchEnded() then
                pcall(function() pc.bShowMouseCursor = false end)
                pcall(function()
                    local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
                    if Logger.IsValidObj(wbl) and wbl.SetInputMode_GameOnly then
                        wbl:SetInputMode_GameOnly(pc, false)
                    end
                end)
            end
        end

        Overlay.HideVanillaHUD(true)

        if Bridge.WasKeyJustPressed(pc, Config.KEYS.TOGGLE_DEBUG) or Bridge.WasKeyJustPressed(pc, Config.KEYS.TOGGLE_DEBUG2) then
            Overlay.ToggleDebugPanel()
            Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_UI_CLICK, 0.45, 1.0, { "click_Cue", "click" })
        end
        if Bridge.WasKeyJustPressed(pc, Config.KEYS.TOGGLE_FREECAM) then
            local fc = CameraCtrl.ToggleFreeCam(SlenderCtrl.GetActor())
            Overlay.ShowToast(fc and ("Free camera on [" .. Config.KEYS.TOGGLE_FREECAM .. " to exit]") or "Free camera off", 2.0)
        end
        if Config.KEYS.TOGGLE_VISION and Bridge.WasKeyJustPressed(pc, Config.KEYS.TOGGLE_VISION) then
            local nv = CameraCtrl.ToggleNightVision()
            Bridge.PlaySound2D(world, Config.UI_ASSETS.SOUND_UI_CLICK, 0.40, 1.0, { "click_Cue", "click" })
            Overlay.ShowToast(nv and "Night Vision ON" or "Night Vision OFF", 1.8)
        end
        if Bridge.WasKeyJustPressed(pc, Config.KEYS.RESTART_ROUND) then
            TriggerRestart(world)
            return
        end

        local survivor = HumanVisuals.GetActor()
        local ai       = HumanVisuals.GetAI()
        local slender  = SlenderCtrl.GetActor()
        local humanFwd = select(1, HumanVisuals.GetForward())

        if (GameModeMgr.GetElapsed() or 0.0) < (Config.HUMAN.START_OBJECTIVE_GRACE_SEC or 5.0) then
            NeutralizeIntroCutscenes(world, pc, survivor, false)
        end

        local matchEnded = GameModeMgr.IsMatchEnded()
        local matchRes, _, endSummary = GameModeMgr.GetResult()

        if matchEnded and not State.MatchEndHandled then
            State.MatchEndHandled = true
            local newlyUnl, nextCfg = ProgressionMgr.OnMatchEnded(State.ActiveMapCfg, matchRes)
            State.EndNewlyUnlock = newlyUnl
            State.EndNextChapter = (matchRes == "SLENDER_WIN") and nextCfg or nil
            Overlay.SetInteractive(true)
            pcall(function()
                pc.bShowMouseCursor = true
                pc.bEnableClickEvents = true
                pc.bEnableMouseOverEvents = true
            end)
            pcall(function()
                local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
                if Logger.IsValidObj(wbl) and wbl.SetInputMode_GameAndUIEx then
                    wbl:SetInputMode_GameAndUIEx(pc, Overlay.GetRootWidget(), 0, false)
                end
            end)
        elseif (not matchEnded) and State.MatchEndHandled then
            State.MatchEndHandled = false
            State.EndNextChapter  = nil
            State.EndNewlyUnlock  = false
            Overlay.SetInteractive(false)
            pcall(function() pc.bShowMouseCursor = false end)
            pcall(function()
                local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
                if Logger.IsValidObj(wbl) and wbl.SetInputMode_GameOnly then
                    wbl:SetInputMode_GameOnly(pc, false)
                end
            end)
        end

        CameraCtrl.Update(world, pc, dt, slender, survivor, matchEnded)
        SlenderCtrl.Update(world, pc, dt, CameraCtrl.GetYaw(), survivor, CameraCtrl.IsFreeCam() or matchEnded)
        if not matchEnded then
            if PrologueStory.IsActive() then
                PrologueStory.TickAmbient(world, pc, dt, HumanVisuals)
            end
            local canDiscoverObj = (GameModeMgr.GetElapsed() >= (Config.HUMAN.START_OBJECTIVE_GRACE_SEC or 5.0))
            Abilities.Update(world, pc, dt, slender, survivor, humanFwd, HumanFear, HumanAI)
            HammerMgr.Update(world, pc, dt, slender, survivor, CameraCtrl, HumanFear, CameraCtrl.IsFreeCam())
            HumanAI.Update(world, dt, survivor, ai, slender, Abilities, false, canDiscoverObj)
            GameModeMgr.Update(world, dt, slender, survivor)
        else
            HumanAI.Update(world, dt, survivor, ai, slender, Abilities, true)
            if Bridge.WasKeyJustPressed(pc, "M") or Bridge.WasKeyJustPressed(pc, "BackSpace") then
                TriggerReturnToMenu(world)
                return
            elseif (matchRes == "SLENDER_WIN") and State.EndNextChapter and Bridge.WasKeyJustPressed(pc, "Enter") then
                TriggerNextLevel(world)
                return
            end
        end

        if HumanVisuals.SuppressGlitchEffects then
            HumanVisuals.SuppressGlitchEffects(world, pc, false)
        end
        if HumanVisuals.UpdateLights then
            HumanVisuals.UpdateLights(world, slender, CameraCtrl.GetCamActor and CameraCtrl.GetCamActor() or nil)
        end

        if Overlay.UpdateSurvivorHealthBar then
            local camPos, camRot, fovDeg = CameraCtrl.GetViewTransform()
            local headPos = HumanVisuals.GetHeadWorldLoc and HumanVisuals.GetHeadWorldLoc() or nil
            Overlay.UpdateSurvivorHealthBar(world, pc, survivor, slender, headPos, HumanFear.GetFear(), matchEnded, camPos, camRot, fovDeg)
        end

        -- Throttled HUD refresh (10 Hz)
        local now = os.clock()
        State.PerfTickMs = State.PerfTickMs * 0.9 + ((now - t0) * 1000.0) * 0.1
        if now - State.LastUiUpdate >= (1.0 / Config.RATES.UI_HZ) then
            State.LastUiUpdate = now
            local sLoc = SlenderCtrl.GetLocation() or { X = 0, Y = 0, Z = 0 }
            local hLoc = HumanVisuals.GetLocation() or { X = 0, Y = 0, Z = 0 }
            local mem  = HumanPerception.GetMemory()
            local uiAb = Abilities.GetUiState()
            local uiHm = HammerMgr.GetUiState()
            local curRes, _, curEndSum = GameModeMgr.GetResult()
            local pagesCol = ObjectiveManager.GetCollectedCount()
            local pagesTot = ObjectiveManager.GetTotalCount()
            local hudMetrics = GameModeMgr.GetHudMetrics and GameModeMgr.GetHudMetrics() or nil
            local _, fallbackStageName = nil, nil
            if (not hudMetrics or not hudMetrics.stageName) and GameModeMgr.GetHuntStage then
                _, fallbackStageName = GameModeMgr.GetHuntStage(pagesCol, pagesTot)
            end
            local huntStageName = (hudMetrics and hudMetrics.stageName) or fallbackStageName or "STAGE I: STALKING"
            local closestDistM  = hudMetrics and hudMetrics.closestDistM or nil
            if State.ActiveMapCfg and State.ActiveMapCfg.key == "PROLOGUE" and PrologueStory.IsActive() then
                huntStageName = PrologueStory.GetStageName()
                local tgt = PrologueStory.GetHudObjectiveTarget()
                if tgt then
                    closestDistM = Bridge.Dist(hLoc, tgt) / 100.0
                end
            end

            Overlay.UpdateGame({
                mapKey         = State.ActiveMapCfg.key,
                mapTitle       = State.ActiveMapCfg.title,
                mapIconPath    = State.ActiveMapCfg.iconPath,
                elapsed        = GameModeMgr.GetElapsed(),
                pagesCollected = pagesCol,
                pagesTotal     = pagesTot,
                huntStageName  = huntStageName,
                closestDistM   = closestDistM,
                fear           = HumanFear.GetFear(),
                stamina        = HumanAI.GetStamina(),
                aiState        = HumanAI.GetState(),
                goal           = HumanAI.GetGoalLabel(),
                knownPages     = ObjectiveManager.GetKnownCount(),
                distanceCm     = mem.SlenderDist or Bridge.Dist(sLoc, hLoc),
                hasLOS         = mem.HasLOS,
                dest           = HumanNav.GetCurrentDest() or hLoc,
                navState       = HumanNav.GetNavState(),
                lastReason     = HumanAI.GetTransitionReason(),
                cdTeleport     = uiAb.cdTp,
                cdDread        = uiAb.cdDr,
                cdTerrify      = uiAb.cdTr,
                dreadActive    = uiAb.dreadActive,
                terrifyFlash   = uiAb.terrifyFlash,
                hammerEquipped = uiHm.equipped,
                cdHammer       = uiHm.cd,
                hammerCooldownMax = uiHm.cdMax,
                freeCam        = CameraCtrl.IsFreeCam(),
                winner         = (curRes ~= "ACTIVE") and curRes or nil,
                endSummary     = curEndSum,
                endDetails     = GameModeMgr.GetEndDetails(),
                canPlayNext    = (curRes == "SLENDER_WIN") and (State.EndNextChapter ~= nil),
                nextMapTitle   = State.EndNextChapter and State.EndNextChapter.title or nil,
                newlyUnlocked  = State.EndNewlyUnlock,
                fps            = dt > 0 and (1.0 / dt) or 60.0,
                tickMs         = State.PerfTickMs,
            })
        end
    end
end

local function ScheduleNextTick()
    ExecuteInGameThreadAfterFrames(1, function()
        Logger.SafeCall("OnTick", OnTick)
        ScheduleNextTick()
    end)
end

ExecuteInGameThread(function()
    Logger.Info("GameThread tick loop started via ExecuteInGameThreadAfterFrames(1)")
    ScheduleNextTick()
end)
