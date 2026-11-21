-- PlayAsSlender Native Main Menu Button & Chapter Select Integration
local Config           = require("config")
local Logger           = require("logger")
local Bridge           = require("ue_bridge")
local LoadingScreenMgr = require("loading_screen_manager")
local ProgressionMgr   = require("progression_manager")

local MenuIntegration = {}

local BUTTON_LABEL_RU = "ИГРАТЬ ЗА СЛЕНДЕРА"
local LOCKED_ICON_PATH = "/Game/Art/Slender/LevelIcons/locked/levelicon_prologue.levelicon_prologue"

local LEVELINFO_TO_TOKEN = {
    LI_Level01 = "Level01_Prologue",
    LI_Level02 = "Level02_TheEightPages",
    LI_Level03 = "Level03_IntoTheAbyss",
    LI_Level04 = "Level04_Flashback",
    LI_Level05 = "Level05_TheArrival",
    LI_Level06 = "Level06_Escape",
    LI_Level07 = "Level07_Memories",
    LI_Level08 = "Level08_Homestead",
    LI_Level09 = "Level09_Genesis",
    LI_Level10 = "Level10",
    LI_Level99 = "Level99_Haunted",
}

local State = {
    OnArmChanged         = nil,
    LatestWorld          = nil,
    InjectedMenu         = nil,
    InjectedMenuFullName = nil,
    ModButton            = nil,
    ModButtonFullName    = nil,
    ButtonHooked         = false,
    ChapterHooked        = false,
    OpeningModCSUntil    = 0.0,
    WasInChapterSelect   = false,
    WasCSVisible         = false,
    UnlockedCS           = nil,
    UnlockedCSFullName   = nil,
    TouchedEntries       = {},
    ChapterButtonMap     = {},
    OrderLoggedOnce      = false,
    CustomButtonHandlers = {},
    PendingLaunchPath    = nil,
    PendingLaunchTimer   = 0.0,
    LastModClickClock    = 0.0,
}

local function ReadFString(val)
    if val == nil then return "" end
    if type(val) == "userdata" and val.ToString then
        local ok, s = pcall(function() return val:ToString() end)
        if ok and s ~= nil then return tostring(s) end
    end
    return tostring(val)
end

local function NotifyArmChanged(armed, chapterCfg)
    if State.OnArmChanged then
        State.OnArmChanged(armed == true, chapterCfg)
    end
end

function MenuIntegration.Init(onArmChangedFn)
    State.OnArmChanged = onArmChangedFn
end

function MenuIntegration.RegisterButtonHandler(idStr, fn)
    if idStr and idStr ~= "" and type(fn) == "function" then
        State.CustomButtonHandlers[tostring(idStr)] = fn
    end
end

function MenuIntegration.ResetForNewWorld()
    State.LatestWorld          = nil
    State.InjectedMenu         = nil
    State.InjectedMenuFullName = nil
    State.ModButton            = nil
    State.ModButtonFullName    = nil
    State.WasInChapterSelect   = false
    State.WasCSVisible         = false
    State.UnlockedCS           = nil
    State.UnlockedCSFullName   = nil
    State.TouchedEntries       = {}
    State.ChapterButtonMap     = {}
    State.PendingLaunchPath    = nil
    State.PendingLaunchTimer   = 0.0
end

local function CopySlotProps(srcSlot)
    local info = {
        pad  = { Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 },
        ha   = 0,
        va   = 0,
        size = { Value = 1.0, SizeRule = 0 },
    }
    if not Logger.IsValidObj(srcSlot) then return info end
    pcall(function()
        local p = srcSlot.Padding
        if p then
            info.pad = { Left = p.Left or 0.0, Top = p.Top or 0.0, Right = p.Right or 0.0, Bottom = p.Bottom or 0.0 }
        end
    end)
    pcall(function() info.ha = tonumber(srcSlot.HorizontalAlignment) or 0 end)
    pcall(function() info.va = tonumber(srcSlot.VerticalAlignment) or 0 end)
    pcall(function()
        local s = srcSlot.Size
        if s then
            info.size = { Value = s.Value or 1.0, SizeRule = tonumber(s.SizeRule) or 0 }
        end
    end)
    return info
end

local function ApplySlotProps(dstSlot, info)
    if not Logger.IsValidObj(dstSlot) or not info then return end
    pcall(function() dstSlot:SetPadding(info.pad) end)
    pcall(function() dstSlot:SetHorizontalAlignment(info.ha) end)
    pcall(function() dstSlot:SetVerticalAlignment(info.va) end)
    pcall(function() dstSlot:SetSize(info.size) end)
end

local function CopyNativeButtonStyle(srcBtn, dstBtn)
    if not Logger.IsValidObj(srcBtn) or not Logger.IsValidObj(dstBtn) then return end
    local copyProps = {
        "Style",
        "Scale",
        "StyleGuide",
        "UseCustomStyle",
        "CustomButtonStyle",
        "UseHoverFont",
        "Font",
        "FontHovered",
        "HoveredBrush",
        "HoverColour",
        "HoverScale",
        "ColLabelNormal",
        "ColLabelHovered",
        "ColLabelPressed",
        "ColLabelBGHovered",
        "ColLabelFG",
        "ColLabelBG",
        "ColLabelWarning",
        "ColFlareGlowNormal",
        "ColFlareNormal",
        "DefaultFont",
        "DefaultFontColor",
        "DefaultHoverFontColor",
        "DefaultActiveFontColor",
        "TextAlignment",
        "ButtonSize",
        "ButtonMargins",
        "ButtonPadding",
        "ButtonShear",
        "ButtonImageCrop",
        "SizeWidthRule",
        "SizeHeightRule",
        "ButtonImage",
        "HighlightImage",
        "ActiveImage",
        "bIsFocusable",
        "PressedSoundOveride",
        "HoveredSoundOverride",
        "bDisableAudio",
    }
    for _, prop in ipairs(copyProps) do
        pcall(function()
            local v = srcBtn[prop]
            if v ~= nil then
                dstBtn[prop] = v
            end
        end)
    end
    pcall(function() dstBtn.ShowIcon = false end)
    pcall(function() dstBtn.HideText = false end)
    pcall(function() dstBtn.Warning = false end)
    pcall(function() dstBtn.IsActive = false end)
    pcall(function() dstBtn["Label Text"] = FText(BUTTON_LABEL_RU) end)
end

local function ApplyButtonLabelAndStyle(srcBtn, dstBtn, labelText)
    if not Logger.IsValidObj(dstBtn) then return end
    local refStyle = 32
    pcall(function() refStyle = srcBtn.Style end)
    local ft = FText(labelText)
    pcall(function() dstBtn["Label Text"] = ft end)
    pcall(function() dstBtn:PreConstruct(false) end)
    pcall(function() dstBtn:Construct() end)
    pcall(function() dstBtn:SetStyle(refStyle) end)
    pcall(function() dstBtn:Init() end)
    pcall(function() dstBtn:SetText(ft) end)

    pcall(function()
        local srcLbl = srcBtn.txt_Label
        local dstLbl = dstBtn.txt_Label
        if Logger.IsValidObj(dstLbl) then
            if Logger.IsValidObj(srcLbl) then
                pcall(function() dstLbl.Font = srcLbl.Font end)
                pcall(function() dstLbl["Font Color"] = srcLbl["Font Color"] end)
                pcall(function() dstLbl.AllCaps = srcLbl.AllCaps end)
                pcall(function() dstLbl.Spaced = srcLbl.Spaced end)
                pcall(function() dstLbl.AutoWrap = srcLbl.AutoWrap end)
                pcall(function() dstLbl.Justification = srcLbl.Justification end)
                pcall(function() dstLbl.CharacterLimit = math.max(30, tonumber(srcLbl.CharacterLimit) or 25) end)
            end
            pcall(function() dstLbl["Set Text"](dstLbl, ft) end)
            pcall(function()
                if Logger.IsValidObj(dstLbl.TextBlock_21) then
                    dstLbl.TextBlock_21:SetText(ft)
                end
            end)
        end
    end)

    pcall(function() dstBtn:SetVisibility(0) end)
    pcall(function() dstBtn:SetIsEnabled(true) end)
    pcall(function()
        if Logger.IsValidObj(dstBtn.btn_Button) then
            dstBtn.btn_Button:SetIsEnabled(true)
        end
    end)
end

local function InjectMainMenuButton(world, pc, mainMenu)
    if not Logger.IsValidObj(mainMenu) then return false end
    local refBtn = nil
    local extBtn = nil
    pcall(function() refBtn = mainMenu.btn_chapter end)
    pcall(function() extBtn = mainMenu.btn_extended_chapters end)
    if not Logger.IsValidObj(refBtn) then return false end

    local parentPanel = nil
    pcall(function() parentPanel = refBtn:GetParent() end)
    if not Logger.IsValidObj(parentPanel) then return false end

    local cnt = 0
    pcall(function() cnt = parentPanel:GetChildrenCount() end)
    if cnt <= 0 then return false end

    local menuFull = Logger.SafeFullName(mainMenu)
    -- Avoid duplicate injection if already present in this panel
    for i = 0, cnt - 1 do
        local ch = nil
        pcall(function() ch = parentPanel:GetChildAt(i) end)
        if Logger.IsValidObj(ch) then
            local bid = ""
            pcall(function()
                local idVal = ch.ID
                if type(idVal) == "userdata" and idVal.ToString then
                    bid = tostring(idVal:ToString() or "")
                elseif idVal ~= nil then
                    bid = tostring(idVal)
                end
            end)
            if Logger.SafeFullName(ch) == State.ModButtonFullName or bid == "PAS_MOD_BTN" then
                State.InjectedMenu = mainMenu
                State.InjectedMenuFullName = menuFull
                State.ModButton = ch
                State.ModButtonFullName = Logger.SafeFullName(ch)
                return true
            end
        end
    end

    local btnCls = nil
    pcall(function() btnCls = refBtn:GetClass() end)
    if not Logger.IsValidObj(btnCls) then return false end

    local newBtn = nil
    local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
    if Logger.IsValidObj(wbl) and Logger.IsValidObj(pc) then
        local okC, w = pcall(function() return wbl:Create(world, btnCls, pc) end)
        if okC and Logger.IsValidObj(w) then
            newBtn = w
        end
    end
    if not Logger.IsValidObj(newBtn) then
        local wt = nil
        pcall(function() wt = mainMenu.WidgetTree end)
        local outer = Logger.IsValidObj(wt) and wt or mainMenu
        local okS, w = pcall(function() return StaticConstructObject(btnCls, outer, Bridge.FName("PAS_Btn_PlayAsSlender")) end)
        if okS and Logger.IsValidObj(w) then
            newBtn = w
        end
    end
    pcall(function()
        if Logger.IsValidObj(newBtn) then
            newBtn.ID = "PAS_MOD_BTN"
        end
    end)
    if not Logger.IsValidObj(newBtn) then
        Logger.Warn("MenuIntegration: Failed creating W_Button_C for Main Menu")
        return false
    end

    CopyNativeButtonStyle(refBtn, newBtn)

    local insertAfter = Logger.IsValidObj(extBtn) and extBtn or refBtn
    local insertAfterFull = Logger.SafeFullName(insertAfter)
    local refSlotInfo = CopySlotProps(refBtn.Slot)
    local children = {}
    for i = 0, cnt - 1 do
        local ch = nil
        pcall(function() ch = parentPanel:GetChildAt(i) end)
        if Logger.IsValidObj(ch) then
            table.insert(children, {
                widget   = ch,
                fullName = Logger.SafeFullName(ch),
                slotInfo = CopySlotProps(ch.Slot),
            })
        end
    end

    parentPanel:ClearChildren()
    local inserted = false
    for _, item in ipairs(children) do
        local addedSlot = nil
        pcall(function() addedSlot = parentPanel:AddChildToVerticalBox(item.widget) end)
        ApplySlotProps(addedSlot, item.slotInfo)
        if (not inserted) and insertAfterFull ~= "" and item.fullName == insertAfterFull then
            local modSlot = nil
            pcall(function() modSlot = parentPanel:AddChildToVerticalBox(newBtn) end)
            ApplySlotProps(modSlot, refSlotInfo)
            inserted = true
        end
    end
    if not inserted then
        local modSlot = nil
        pcall(function() modSlot = parentPanel:AddChildToVerticalBox(newBtn) end)
        ApplySlotProps(modSlot, refSlotInfo)
    end

    ApplyButtonLabelAndStyle(refBtn, newBtn, BUTTON_LABEL_RU)
    pcall(function() parentPanel:ForceLayoutPrepass() end)
    pcall(function() mainMenu:ForceLayoutPrepass() end)

    State.InjectedMenu         = mainMenu
    State.InjectedMenuFullName = Logger.SafeFullName(mainMenu)
    State.ModButton            = newBtn
    State.ModButtonFullName    = Logger.SafeFullName(newBtn)

    Logger.Info("MenuIntegration: Injected native W_Button_C '" .. BUTTON_LABEL_RU .. "' into W_SubMenu_Main (" .. tostring(parentPanel:GetChildrenCount()) .. " items)")
    return true
end

local function OpenModdedChapterSelect(world, mainMenu)
    local targetWorld = Logger.IsValidObj(world) and world or State.LatestWorld
    local menu = Logger.IsValidObj(mainMenu) and mainMenu or State.InjectedMenu or FindFirstOf("W_SubMenu_Main_C")
    NotifyArmChanged(true, nil)
    LoadingScreenMgr.ApplyModLoadingScreens(targetWorld, nil)

    State.LastModClickClock = os.clock()
    State.OpeningModCSUntil = State.LastModClickClock + 0.50

    if Logger.IsValidObj(State.ModButton) then
        pcall(function() State.ModButton:PlayClickCue() end)
    end

    local opened = false
    if Logger.IsValidObj(menu) then
        pcall(function()
            if Logger.IsValidObj(menu.btn_chapter) and Logger.IsValidObj(menu.btn_chapter.btn_Button) then
                menu.btn_chapter.btn_Button.OnClicked:Broadcast()
                opened = true
            end
        end)
        if not opened then
            pcall(function()
                menu:BndEvt__W_SlenderMainMenu_btn_chapter_K2Node_ComponentBoundEvent_0_Clicked__DelegateSignature()
                opened = true
            end)
        end
    end
    Logger.Info("MenuIntegration: Opened native ChapterSelect in PlayAsSlender mode (opened=" .. tostring(opened) .. ")")
    return opened
end

function MenuIntegration.TriggerModButton(world)
    return OpenModdedChapterSelect(world, State.InjectedMenu)
end

local function RestoreTouchedEntries()
    for _, entry in ipairs(State.TouchedEntries) do
        if Logger.IsValidObj(entry) then
            pcall(function() entry:InitializeEntry() end)
        end
    end
    State.TouchedEntries = {}
    State.UnlockedCS = nil
end

local function ResolveChapterFromEntry(entry)
    if not Logger.IsValidObj(entry) then return nil end
    local gotoCls = nil
    pcall(function() gotoCls = entry.GotoLevel end)
    if not Logger.IsValidObj(gotoCls) then return nil end
    local clsName = Logger.SafeName(gotoCls)
    for prefix, tok in pairs(LEVELINFO_TO_TOKEN) do
        if string.find(clsName, prefix, 1, true) then
            return Config.FindChapterByToken(tok)
        end
    end
    return nil
end

local function ApplyChapterProgression(cs, forceRefresh)
    local csFull = Logger.SafeFullName(cs)
    if not Logger.IsValidObj(cs) then return end
    if (not forceRefresh) and State.UnlockedCSFullName == csFull then return end
    local propNames = {
        "W_Sub_ChapterEntry",
        "W_Sub_ChapterEntry_1",
        "W_Sub_ChapterEntry_2",
        "W_Sub_ChapterEntry_3",
        "W_Sub_ChapterEntry_4",
        "W_Sub_ChapterEntry_5",
        "W_Sub_ChapterEntry_6",
        "W_Sub_ChapterEntry_7",
        "W_Sub_ChapterEntry_8",
    }
    State.TouchedEntries   = {}
    State.ChapterButtonMap = {}

    local discoveredOrder = {}
    local unlockedCount = 0
    local lockedCount   = 0
    local lockFallbackTex = Bridge.LoadOrFindAsset(LOCKED_ICON_PATH)

    for idx, pName in ipairs(propNames) do
        local entry = nil
        pcall(function() entry = cs[pName] end)
        if Logger.IsValidObj(entry) then
            local ch = ResolveChapterFromEntry(entry)
            if ch and ch.token then
                discoveredOrder[idx] = ch.token
            end
        end
    end
    if #discoveredOrder == 9 then
        ProgressionMgr.SyncCampaignOrder(discoveredOrder)
        if not State.OrderLoggedOnce then
            State.OrderLoggedOnce = true
            Logger.Info("MenuIntegration: ChapterSelect slot order = " .. table.concat(discoveredOrder, ", "))
        end
    end

    for idx, pName in ipairs(propNames) do
        local entry = nil
        pcall(function() entry = cs[pName] end)
        if Logger.IsValidObj(entry) then
            table.insert(State.TouchedEntries, entry)
            local ch = ResolveChapterFromEntry(entry)
            local unlocked = ProgressionMgr.IsIndexUnlocked(idx)

            if idx <= 2 and (not State.OrderLoggedOnce or forceRefresh) then
                local eEn, baEn, btnEn = "?", "?", "?"
                pcall(function() eEn = tostring(entry:GetIsEnabled()) end)
                pcall(function()
                    if Logger.IsValidObj(entry.ButtonArea) then
                        baEn = tostring(entry.ButtonArea:GetIsEnabled())
                        if Logger.IsValidObj(entry.ButtonArea.btn_Button) then
                            btnEn = tostring(entry.ButtonArea.btn_Button:GetIsEnabled())
                        end
                    end
                end)
                Logger.Info(string.format("MenuIntegration: Initial slot[%d] %s unlocked=%s (entry=%s ba=%s btn=%s)",
                    idx, tostring(ch and ch.token or pName), tostring(unlocked), eEn, baEn, btnEn))
            end

            if unlocked then
                unlockedCount = unlockedCount + 1
                local revTex = (ch and ch.iconPath) and Bridge.LoadOrFindAsset(ch.iconPath) or entry.DisplayedImage
                pcall(function()
                    entry:SetVisibility(0)
                    entry:SetIsEnabled(true)
                end)
                pcall(function()
                    local ba = entry.ButtonArea
                    if Logger.IsValidObj(ba) then
                        ba:SetVisibility(0)
                        pcall(function() ba:ToggleEnabled(true) end)
                        ba:SetIsEnabled(true)
                        if Logger.IsValidObj(ba.btn_Button) then
                            ba.btn_Button:SetVisibility(0)
                            ba.btn_Button:SetIsEnabled(true)
                        end
                    end
                end)
                pcall(function()
                    local dm = entry.DynMat
                    if Logger.IsValidObj(dm) and Logger.IsValidObj(revTex) then
                        dm:SetTextureParameterValue(Bridge.FName("Texture"), revTex)
                        if Logger.IsValidObj(entry.DisplayImage) then
                            entry.DisplayImage:SetBrushFromMaterial(dm)
                            entry.DisplayImage:SetColorAndOpacity({ R = 1.0, G = 1.0, B = 1.0, A = 1.0 })
                        end
                    elseif Logger.IsValidObj(entry.DisplayImage) and Logger.IsValidObj(revTex) then
                        entry.DisplayImage:SetBrushFromTexture(revTex, false)
                        entry.DisplayImage:SetColorAndOpacity({ R = 1.0, G = 1.0, B = 1.0, A = 1.0 })
                    end
                end)
                pcall(function()
                    if Logger.IsValidObj(entry.DisplayText) then
                        entry.DisplayText:SetColorAndOpacity({ SpecifiedColor = { R = 0.92, G = 0.90, B = 0.85, A = 1.0 }, ColorUseRule = 0 })
                    end
                end)
            else
                lockedCount = lockedCount + 1
                local lockTex = entry.LockedImage
                if not Logger.IsValidObj(lockTex) then lockTex = lockFallbackTex end
                pcall(function()
                    entry:SetVisibility(3) -- HitTestInvisible
                    entry:SetIsEnabled(true)
                end)
                pcall(function()
                    local ba = entry.ButtonArea
                    if Logger.IsValidObj(ba) then
                        pcall(function() ba:ToggleEnabled(false) end)
                        ba:SetIsEnabled(false)
                        ba:SetVisibility(3)
                        if Logger.IsValidObj(ba.btn_Button) then
                            ba.btn_Button:SetIsEnabled(false)
                        end
                    end
                end)
                pcall(function()
                    local dm = entry.DynMat
                    if Logger.IsValidObj(dm) and Logger.IsValidObj(lockTex) then
                        dm:SetTextureParameterValue(Bridge.FName("Texture"), lockTex)
                        if Logger.IsValidObj(entry.DisplayImage) then
                            entry.DisplayImage:SetBrushFromMaterial(dm)
                            entry.DisplayImage:SetColorAndOpacity({ R = 0.72, G = 0.72, B = 0.72, A = 0.92 })
                        end
                    end
                end)
                pcall(function()
                    if Logger.IsValidObj(entry.DisplayText) then
                        entry.DisplayText:SetColorAndOpacity({ SpecifiedColor = { R = 0.45, G = 0.44, B = 0.42, A = 0.75 }, ColorUseRule = 0 })
                    end
                end)
            end

            pcall(function()
                if Logger.IsValidObj(entry.ButtonArea) then
                    State.ChapterButtonMap[Logger.SafeFullName(entry.ButtonArea)] = {
                        entry    = entry,
                        chapter  = ch,
                        index    = idx,
                        unlocked = unlocked,
                    }
                end
            end)
        end
    end

    State.UnlockedCS = cs
    State.UnlockedCSFullName = csFull
    Logger.Info(string.format("MenuIntegration: Applied ChapterSelect progression (unlocked_max=%d, open=%d, locked=%d)",
        ProgressionMgr.GetUnlockedMax(), unlockedCount, lockedCount))
end

function MenuIntegration.EnsureButtonHook()
    if not State.ButtonHooked then
        local okH = pcall(function()
            RegisterHook(
                "/Game/Blueprints/UI/Buttons/W_Button.W_Button_C:BndEvt__btn_Button_K2Node_ComponentBoundEvent_3_OnButtonClickedEvent__DelegateSignature",
                function(selfCtx)
                    local btn = nil
                    pcall(function() btn = selfCtx:get() end)
                    if not Logger.IsValidObj(btn) then return end
                    local full = Logger.SafeFullName(btn)
                    local bid = ""
                    pcall(function() bid = ReadFString(btn.ID) end)
                    local w = Bridge.GetWorld()
                    if not Logger.IsValidObj(w) then w = State.LatestWorld end

                    -- 1. Registered custom End Screen / UI button handlers
                    local handler = (bid ~= "") and State.CustomButtonHandlers[bid] or nil
                    if handler then
                        Logger.Info("MenuIntegration: Custom button clicked (" .. bid .. ")")
                        pcall(function() handler(w) end)
                        return
                    end

                    -- 2. Main Menu Play-as-Slender button
                    if (State.ModButtonFullName and full == State.ModButtonFullName) or bid == "PAS_MOD_BTN" then
                        Logger.Info("MenuIntegration: User clicked '" .. BUTTON_LABEL_RU .. "'")
                        OpenModdedChapterSelect(w, State.InjectedMenu)
                        return
                    end

                    -- 3. ChapterSelect card ButtonArea clicks when modded mode is armed
                    local chRec = State.ChapterButtonMap[full]
                    if chRec and LoadingScreenMgr.IsApplied() then
                        if not chRec.unlocked or (chRec.chapter and not ProgressionMgr.IsChapterUnlocked(chRec.chapter.token)) then
                            Logger.Info(string.format("MenuIntegration: Blocked click on LOCKED chapter [%d] %s",
                                tonumber(chRec.index) or 0, tostring(chRec.chapter and chRec.chapter.token or "?")))
                            return
                        end
                        if chRec.chapter and not State.PendingLaunchPath then
                            NotifyArmChanged(true, chRec.chapter)
                            LoadingScreenMgr.ApplyModLoadingScreens(w, chRec.chapter)
                            State.PendingLaunchPath  = chRec.chapter.path
                            State.PendingLaunchTimer = 0.05
                            Logger.Info(string.format("MenuIntegration: Clicked UNLOCKED chapter [%d] -> %s",
                                tonumber(chRec.index) or 0, tostring(chRec.chapter.token)))
                        end
                        return
                    end

                    -- 4. Direct vanilla menu navigation outside our programmatic ChapterSelect open restores vanilla mode
                    if os.clock() > State.OpeningModCSUntil and Logger.IsValidObj(State.InjectedMenu) then
                        local mm = State.InjectedMenu
                        local isVanillaMenuBtn = (full == Logger.SafeFullName(mm.btn_start))
                            or (full == Logger.SafeFullName(mm.btn_chapter))
                            or (full == Logger.SafeFullName(mm.btn_extended_chapters))
                        if isVanillaMenuBtn then
                            NotifyArmChanged(false, nil)
                            LoadingScreenMgr.RestoreVanilla(w)
                            RestoreTouchedEntries()
                            Logger.Info("MenuIntegration: Vanilla menu button clicked (" .. Logger.SafeName(btn) .. ") -> vanilla mode restored")
                        end
                    end
                end
            )
        end)
        if okH then
            State.ButtonHooked = true
            Logger.Info("MenuIntegration: Hooked W_Button_C click event")
        end
    end

    if not State.ChapterHooked then
        local sampleCE = FindFirstOf("W_Sub_ChapterEntry_C")
        if Logger.IsValidObj(sampleCE) then
            local okC = pcall(function()
                RegisterHook(
                    "/Game/Blueprints/UI/Slender/MainMenu/W_Sub_ChapterEntry.W_Sub_ChapterEntry_C:BndEvt__W_Sub_ChapterEntry_ButtonArea_K2Node_ComponentBoundEvent_2_Clicked__DelegateSignature",
                    function(selfCtx)
                        if not LoadingScreenMgr.IsApplied() then return end
                        local entry = nil
                        pcall(function() entry = selfCtx:get() end)
                        local ch = ResolveChapterFromEntry(entry)
                        if not ch then return end
                        if not ProgressionMgr.IsChapterUnlocked(ch.token) then
                            Logger.Info("MenuIntegration: ChapterEntry hook blocked locked chapter " .. tostring(ch.token))
                            return
                        end
                        if not State.PendingLaunchPath then
                            local w = Bridge.GetWorld()
                            if not Logger.IsValidObj(w) then w = State.LatestWorld end
                            NotifyArmChanged(true, ch)
                            LoadingScreenMgr.ApplyModLoadingScreens(w, ch)
                            State.PendingLaunchPath  = ch.path
                            State.PendingLaunchTimer = 0.05
                            Logger.Info("MenuIntegration: Chapter card clicked in PlayAsSlender mode -> " .. tostring(ch.token))
                        end
                    end
                )
            end)
            if okC then
                State.ChapterHooked = true
                Logger.Info("MenuIntegration: Hooked W_Sub_ChapterEntry_C click event")
            end
        end
    end
end

local function EnsureHooks()
    MenuIntegration.EnsureButtonHook()
end

function MenuIntegration.TryClickChapterIndex(idx)
    local cs = FindFirstOf("W_SubMenu_ChapterSelect_C")
    if not Logger.IsValidObj(cs) then return false, "NoChapterSelect" end
    local propNames = {
        "W_Sub_ChapterEntry",
        "W_Sub_ChapterEntry_1",
        "W_Sub_ChapterEntry_2",
        "W_Sub_ChapterEntry_3",
        "W_Sub_ChapterEntry_4",
        "W_Sub_ChapterEntry_5",
        "W_Sub_ChapterEntry_6",
        "W_Sub_ChapterEntry_7",
        "W_Sub_ChapterEntry_8",
    }
    local pName = propNames[idx]
    if not pName then return false, "BadIndex" end
    local entry = nil
    pcall(function() entry = cs[pName] end)
    if not Logger.IsValidObj(entry) then return false, "MissingEntry" end
    local ba = entry.ButtonArea
    if not Logger.IsValidObj(ba) then return false, "MissingButtonArea" end
    local innerBtn = ba.btn_Button
    if not Logger.IsValidObj(innerBtn) then return false, "MissingInnerButton" end

    local enabled = false
    pcall(function() enabled = (ba:GetIsEnabled() == true) and (innerBtn:GetIsEnabled() == true) end)
    if not enabled then
        return false, "DisabledByProgression"
    end
    local ok = pcall(function() innerBtn.OnClicked:Broadcast() end)
    return ok, ok and "Clicked" or "BroadcastFailed"
end

function MenuIntegration.GetChapterCardStates()
    local out = {}
    local cs = FindFirstOf("W_SubMenu_ChapterSelect_C")
    if not Logger.IsValidObj(cs) then return out end
    local propNames = {
        "W_Sub_ChapterEntry",
        "W_Sub_ChapterEntry_1",
        "W_Sub_ChapterEntry_2",
        "W_Sub_ChapterEntry_3",
        "W_Sub_ChapterEntry_4",
        "W_Sub_ChapterEntry_5",
        "W_Sub_ChapterEntry_6",
        "W_Sub_ChapterEntry_7",
        "W_Sub_ChapterEntry_8",
    }
    for idx, pName in ipairs(propNames) do
        local entry = nil
        pcall(function() entry = cs[pName] end)
        if Logger.IsValidObj(entry) then
            local ch = ResolveChapterFromEntry(entry)
            local unlocked = ProgressionMgr.IsIndexUnlocked(idx)
            local btnEn = false
            pcall(function()
                local ba = entry.ButtonArea
                local ib = ba and ba.btn_Button
                btnEn = Logger.IsValidObj(ba) and Logger.IsValidObj(ib) and (ba:GetIsEnabled() == true) and (ib:GetIsEnabled() == true)
            end)
            table.insert(out, {
                index      = idx,
                token      = ch and ch.token or "?",
                unlocked   = unlocked,
                btnEnabled = btnEn,
            })
        end
    end
    return out
end

function MenuIntegration.OpenChapterByToken(world, token, allowLockedOverride)
    local targetWorld = Logger.IsValidObj(world) and world or State.LatestWorld
    local cs = FindFirstOf("W_SubMenu_ChapterSelect_C")
    if Logger.IsValidObj(cs) then
        local propNames = {
            "W_Sub_ChapterEntry",
            "W_Sub_ChapterEntry_1",
            "W_Sub_ChapterEntry_2",
            "W_Sub_ChapterEntry_3",
            "W_Sub_ChapterEntry_4",
            "W_Sub_ChapterEntry_5",
            "W_Sub_ChapterEntry_6",
            "W_Sub_ChapterEntry_7",
            "W_Sub_ChapterEntry_8",
        }
        for _, pName in ipairs(propNames) do
            local entry = nil
            pcall(function() entry = cs[pName] end)
            local ch = ResolveChapterFromEntry(entry)
            if ch and string.find(ch.token, token, 1, true) then
                if (not allowLockedOverride) and (not ProgressionMgr.IsChapterUnlocked(ch.token)) then
                    Logger.Info("MenuIntegration.OpenChapterByToken blocked locked chapter: " .. tostring(ch.token))
                    return false, ch
                end
                NotifyArmChanged(true, ch)
                LoadingScreenMgr.ApplyModLoadingScreens(targetWorld, ch)
                if allowLockedOverride then
                    Bridge.LoadLevel(targetWorld, ch.path)
                else
                    local clicked = pcall(function()
                        entry.ButtonArea.btn_Button.OnClicked:Broadcast()
                    end)
                    if not clicked then
                        pcall(function()
                            entry:BndEvt__W_Sub_ChapterEntry_ButtonArea_K2Node_ComponentBoundEvent_2_Clicked__DelegateSignature()
                        end)
                    end
                    State.PendingLaunchPath  = ch.path
                    State.PendingLaunchTimer = 0.05
                end
                return true, ch
            end
        end
    end
    local fallback = Config.FindChapterByToken(token)
    if fallback then
        if (not allowLockedOverride) and (not ProgressionMgr.IsChapterUnlocked(fallback.token)) then
            return false, fallback
        end
        NotifyArmChanged(true, fallback)
        LoadingScreenMgr.ApplyModLoadingScreens(targetWorld, fallback)
        Bridge.LoadLevel(targetWorld, fallback.path)
        return true, fallback
    end
    return false, nil
end

function MenuIntegration.Tick(world, pc, dt, modArmed)
    State.LatestWorld = world
    LoadingScreenMgr.EnsureTextures(world)

    -- Handle fallback travel for unlocked cards in modded ChapterSelect
    if State.PendingLaunchPath then
        State.PendingLaunchTimer = State.PendingLaunchTimer - (dt or 0.016)
        if State.PendingLaunchTimer <= 0.0 then
            local p = State.PendingLaunchPath
            State.PendingLaunchPath = nil
            Logger.Info("MenuIntegration: Launching chapter via OpenLevel -> " .. tostring(p))
            Bridge.LoadLevel(world, p)
            return
        end
    end

    local mainMenu = FindFirstOf("W_SubMenu_Main_C")
    if Logger.IsValidObj(mainMenu) and mainMenu:IsInViewport() then
        local mmFull = Logger.SafeFullName(mainMenu)
        if State.InjectedMenuFullName ~= mmFull or not Logger.IsValidObj(State.ModButton) then
            InjectMainMenuButton(world, pc, mainMenu)
        end
    end

    EnsureHooks()

    local cs = FindFirstOf("W_SubMenu_ChapterSelect_C")
    local csVisible = false
    if Logger.IsValidObj(cs) then
        pcall(function()
            csVisible = (cs:IsInViewport() == true) and (cs:IsVisible() == true)
        end)
    end

    if csVisible then
        local justOpened = not State.WasCSVisible
        State.WasCSVisible       = true
        State.WasInChapterSelect = true
        if modArmed then
            ApplyChapterProgression(cs, justOpened)
        end
    else
        State.WasCSVisible = false
        if State.WasInChapterSelect and not State.PendingLaunchPath then
            local menuVisible = false
            if Logger.IsValidObj(mainMenu) then
                pcall(function()
                    menuVisible = (mainMenu:IsInViewport() == true) and (mainMenu:IsVisible() == true)
                end)
            end
            if menuVisible and os.clock() > State.OpeningModCSUntil then
                State.WasInChapterSelect = false
                if modArmed then
                    NotifyArmChanged(false, nil)
                    LoadingScreenMgr.RestoreVanilla(world)
                    RestoreTouchedEntries()
                    Logger.Info("MenuIntegration: Returned from ChapterSelect -> disarmed & restored vanilla")
                end
            end
        end
    end
end

function MenuIntegration.GetStateSnapshot()
    local buttonText = ""
    local buttonVisible = false
    local childCount = 0
    if Logger.IsValidObj(State.ModButton) then
        pcall(function()
            buttonVisible = State.ModButton:IsVisible() == true
            if Logger.IsValidObj(State.ModButton.txt_Label) and Logger.IsValidObj(State.ModButton.txt_Label.TextBlock_21) then
                buttonText = State.ModButton.txt_Label.TextBlock_21:GetText():ToString()
            end
            local parent = State.ModButton:GetParent()
            if Logger.IsValidObj(parent) then
                childCount = parent:GetChildrenCount()
            end
        end)
    end
    local cs = FindFirstOf("W_SubMenu_ChapterSelect_C")
    local csVisible = false
    if Logger.IsValidObj(cs) then
        pcall(function() csVisible = (cs:IsInViewport() == true) and (cs:IsVisible() == true) end)
    end
    return {
        buttonInjected = Logger.IsValidObj(State.ModButton),
        buttonVisible  = buttonVisible,
        buttonText     = buttonText,
        menuItemCount  = childCount,
        csVisible      = csVisible,
        loadingApplied = LoadingScreenMgr.IsApplied(),
    }
end

return MenuIntegration
