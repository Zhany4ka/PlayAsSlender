-- PlayAsSlender Native-Asset UMG Overlay (Camcorder HUD, Chapter Cards, Ability Gauges, Telemetry & End Screen)
local Logger  = require("logger")
local Bridge  = require("ue_bridge")
local Config  = require("config")
local UITheme = require("ui_theme")

local Overlay = {}

local State = {
    Initialized     = false,
    DebugVisible    = Config.DEBUG.SHOW_PANEL_ON_START,
    RootUserWidget  = nil,
    RootCanvas      = nil,
    Widgets         = {},
    LastTexts       = {},
    LastVis         = {},
    LastOpacity     = {},
    ToastText       = "",
    ToastExpiresAt  = 0.0,
    ToastStartAt    = 0.0,
    LastMode        = "",
    LastMapKey      = "",
    LastEndMapKey   = "",
    LastEndWinner   = "",
    CachedVanilla   = {},
    NextVanillaScan = 0.0,
    NativeMainMenu  = nil,
    NextMenuCheck   = 0.0,
    LastHPBar       = { visible = false, x = 0.0, y = 0.0, healthPct = 100.0, method = "none" },
    HPMethodLogged  = false,
}

local function SetSlotAnchored(slot, x, y, ax, ay, alX, alY, zOrder)
    if not Logger.IsValidObj(slot) then return end
    pcall(function()
        slot:SetAnchors({
            Minimum = { X = ax or 0.0, Y = ay or 0.0 },
            Maximum = { X = ax or 0.0, Y = ay or 0.0 },
        })
        slot:SetAlignment({ X = alX or 0.0, Y = alY or 0.0 })
        slot:SetPosition({ X = x, Y = y })
        slot:SetAutoSize(true)
        if zOrder then slot:SetZOrder(zOrder) end
    end)
end

local function SetSlotFullscreen(slot, zOrder)
    if not Logger.IsValidObj(slot) then return end
    pcall(function()
        slot:SetAnchors({
            Minimum = { X = 0.0, Y = 0.0 },
            Maximum = { X = 1.0, Y = 1.0 },
        })
        slot:SetOffsets({ Left = 0.0, Top = 0.0, Right = 0.0, Bottom = 0.0 })
        slot:SetAutoSize(false)
        if zOrder then slot:SetZOrder(zOrder) end
    end)
end

local function SetWidgetVisible(key, widgetObj, visible, isInteractive)
    if not Logger.IsValidObj(widgetObj) then return end
    local stateKey = tostring(key) .. (isInteractive and "_I" or "")
    if State.LastVis[stateKey] == visible then return end
    State.LastVis[stateKey] = visible
    -- ESlateVisibility: 0=Visible (interactive), 1=Collapsed, 3=HitTestInvisible
    local vis = visible and (isInteractive and 0 or 3) or 1
    pcall(function() widgetObj:SetVisibility(vis) end)
end

function Overlay.SetInteractive(interactive)
    local vis = interactive and 4 or 3 -- 4=SelfHitTestInvisible (children clickable), 3=HitTestInvisible
    if Logger.IsValidObj(State.RootUserWidget) then
        pcall(function() State.RootUserWidget:SetVisibility(vis) end)
    end
    if Logger.IsValidObj(State.RootCanvas) then
        pcall(function() State.RootCanvas:SetVisibility(vis) end)
    end
end

function Overlay.GetRootWidget()
    return State.RootUserWidget
end

function Overlay.GetEndButtons()
    local eb = State.Widgets and State.Widgets.EndBanner
    if not eb then return nil end
    return {
        nextBtn    = eb.BtnNext,
        restartBtn = eb.BtnRestart,
        menuBtn    = eb.BtnMenu,
        unlockNote = eb.UnlockNote,
    }
end

local function SetCachedText(key, tbObj, newText)
    if not Logger.IsValidObj(tbObj) then return end
    local str = tostring(newText or "")
    if State.LastTexts[key] == str then return end
    State.LastTexts[key] = str
    pcall(function() tbObj:SetText(FText(str)) end)
end

local function SetCachedOpacity(key, wObj, alpha)
    if not Logger.IsValidObj(wObj) then return end
    local q = math.floor((alpha or 1.0) * 50.0 + 0.5) / 50.0
    if State.LastOpacity[key] == q then return end
    State.LastOpacity[key] = q
    pcall(function() wObj:SetRenderOpacity(q) end)
end

local function SetCachedColor(key, tbObj, col)
    if not Logger.IsValidObj(tbObj) or not col then return end
    local ck = string.format("%.2f_%.2f_%.2f", col.R, col.G, col.B)
    if State.LastTexts["_col_" .. key] == ck then return end
    State.LastTexts["_col_" .. key] = ck
    pcall(function() tbObj:SetColorAndOpacity(UITheme.MakeSlateColor(col)) end)
end

local function AddBoxChild(box, child, hAlign, vAlign, padL, padT, padR, padB)
    if not Logger.IsValidObj(box) or not Logger.IsValidObj(child) then return nil end
    local ok, slot = pcall(function() return box:AddChild(child) end)
    if ok and Logger.IsValidObj(slot) then
        pcall(function()
            if hAlign ~= nil and slot.SetHorizontalAlignment then slot:SetHorizontalAlignment(hAlign) end
            if vAlign ~= nil and slot.SetVerticalAlignment then slot:SetVerticalAlignment(vAlign) end
            if (padL or padT or padR or padB) and slot.SetPadding then
                slot:SetPadding({ Left = padL or 0, Top = padT or 0, Right = padR or 0, Bottom = padB or 0 })
            end
        end)
        return slot
    end
    return nil
end

local function FormatClockHMS(secFloat)
    local s = math.max(0, math.floor(secFloat or 0))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    local sc = s % 60
    return string.format("%02d:%02d:%02d", h, m, sc)
end

local function SanitizeAscii(s)
    local out = tostring(s or "")
    out = out:gsub("\226\128\148", "-"):gsub("\226\128\147", "-")
    out = out:gsub("\226\128\152", "'"):gsub("\226\128\153", "'")
    out = out:gsub("\226\128\156", '"'):gsub("\226\128\157", '"')
    out = out:gsub("[\128-\255]", "")
    return out
end

local function CreateHudPanel(wt, name, tint, padL, padT, padR, padB)
    local mat = UITheme.GetMat("BACKDROP_FADE")
    local bg = mat or UITheme.GetTex("FADE_RECT")
    return UITheme.CreateBackdropContainer(wt, name, bg, tint, mat ~= nil, padL, padT, padR, padB)
end

function Overlay.HideVanillaHUD(hide)
    local vis = hide and 1 or 3
    local now = os.clock()
    if #State.CachedVanilla == 0 or now >= State.NextVanillaScan then
        State.NextVanillaScan = now + 2.0
        State.CachedVanilla = {}
        local allW = FindAllOf("UserWidget") or {}
        for _, w in ipairs(allW) do
            if Logger.IsValidObj(w) then
                local name = Logger.SafeName(w)
                local isOurs = string.find(name, "PlayAsSlender", 1, true)
                    or string.find(name, "PAS_", 1, true)
                if not isOurs then
                    if string.find(name, "W_SlenderHUD", 1, true)
                        or string.find(name, "W_InteractionHighlight", 1, true)
                        or string.find(name, "W_SlenderScreenNotice", 1, true)
                        or string.find(name, "W_PlayerActorHudInfo", 1, true)
                        or string.find(name, "W_MoviePlayer", 1, true)
                        or string.find(name, "W_SlenderScreenDialogue", 1, true)
                        or string.find(name, "Static", 1, true)
                        or string.find(name, "Glitch", 1, true)
                        or string.find(name, "Sanity", 1, true)
                        or string.find(name, "ScreenEffect", 1, true)
                        or string.find(name, "Chromatic", 1, true)
                        or string.find(name, "Damage", 1, true)
                        or string.find(name, "Blood", 1, true) then
                        table.insert(State.CachedVanilla, w)
                    end
                end
            end
        end
    end
    for _, w in ipairs(State.CachedVanilla) do
        if Logger.IsValidObj(w) then
            pcall(function() w:SetVisibility(vis) end)
        end
    end
end

-- =========================================================
-- Widget Group Builders (100% Native Slender: The Arrival Assets)
-- =========================================================
local function BuildAmbientLayer(wt, cv)
    local camTex = UITheme.GetTex("CAMERA_FRAME")
    local vigAsset = UITheme.GetMat("VIGNETTE") or UITheme.GetTex("RADIAL_GRADIENT")
    local vigIsMat = (UITheme.GetMat("VIGNETTE") ~= nil)
    local t1 = UITheme.GetTex("TENDRIL_1")
    local t2 = UITheme.GetTex("TENDRIL_2")

    local camImg = UITheme.CreateImage(wt, "PAS_CamFrame", camTex, { R = 1.0, G = 1.0, B = 1.0, A = 0.24 }, false)
    if Logger.IsValidObj(camImg) then
        local s = cv:AddChildToCanvas(camImg)
        SetSlotFullscreen(s, 4)
    end

    local vigImg = UITheme.CreateImage(wt, "PAS_Vignette", vigAsset, { R = 0.08, G = 0.01, B = 0.02, A = 0.85 }, vigIsMat)
    if Logger.IsValidObj(vigImg) then
        pcall(function() vigImg:SetRenderOpacity(0.08) end)
        local s = cv:AddChildToCanvas(vigImg)
        SetSlotFullscreen(s, 6)
    end

    local tendrilL = UITheme.CreateSizedImage(wt, "PAS_TendrilL", t1, 460.0, 115.0, { R = 0.90, G = 0.85, B = 0.82, A = 0.55 }, false)
    if Logger.IsValidObj(tendrilL) then
        pcall(function()
            tendrilL:SetRenderTransformAngle(-22.0)
            tendrilL:SetRenderOpacity(0.0)
        end)
        local s = cv:AddChildToCanvas(tendrilL)
        SetSlotAnchored(s, -60.0, 0.0, 0.0, 0.5, 0.0, 0.5, 8)
    end

    local tendrilR = UITheme.CreateSizedImage(wt, "PAS_TendrilR", t2, 460.0, 115.0, { R = 0.90, G = 0.85, B = 0.82, A = 0.55 }, false)
    if Logger.IsValidObj(tendrilR) then
        pcall(function()
            tendrilR:SetRenderTransform({
                Translation = { X = 0.0, Y = 0.0 },
                Scale       = { X = -1.0, Y = 1.0 },
                Shear       = { X = 0.0, Y = 0.0 },
                Angle       = 22.0,
            })
            tendrilR:SetRenderOpacity(0.0)
        end)
        local s = cv:AddChildToCanvas(tendrilR)
        SetSlotAnchored(s, 60.0, 0.0, 1.0, 0.5, 1.0, 0.5, 8)
    end

    local cross = UITheme.CreateAccentLine(wt, "PAS_HammerCrosshair", 6.0, 6.0, { R = 0.94, G = 0.88, B = 0.82, A = 0.88 })
    if Logger.IsValidObj(cross) then
        local s = cv:AddChildToCanvas(cross)
        SetSlotAnchored(s, 0.0, 0.0, 0.5, 0.5, 0.5, 0.5, 32)
        pcall(function() cross:SetVisibility(1) end)
    end

    return {
        CamFrame  = camImg,
        Vignette  = vigImg,
        TendrilL  = tendrilL,
        TendrilR  = tendrilR,
        Crosshair = cross,
    }
end

local function BuildMenuChapterCard(wt, name, thumbTex, keyName, titleStr, subtitleStr)
    local button = UITheme.GetMat("SLENDER_BTN")
    local bg = button or UITheme.GetTex("BUTTON_ALT") or UITheme.GetTex("BUTTON")
    local card = UITheme.CreateBackdropContainer(wt, name, bg, UITheme.COLORS.ASH, button ~= nil, 13, 8, 13, 8)
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    if not card or not hbCls or not vbCls then return nil end

    local hb = StaticConstructObject(hbCls, wt, Bridge.FName(name .. "_HB"))
    local vb = StaticConstructObject(vbCls, wt, Bridge.FName(name .. "_VB"))

    local thumbSB = UITheme.CreateSizedImage(wt, name .. "_THUMB", thumbTex, 88.0, 78.0)
    local keyBadge = UITheme.CreateKeycapBadge(wt, name .. "_KEY", keyName, 36.0)
    local titleTb = UITheme.CreateText(wt, name .. "_TTL", titleStr, "HORROR", 23.0, UITheme.COLORS.BONE, 20, 1)
    local subTb = UITheme.CreateText(wt, name .. "_SUB", subtitleStr, "BODY_BOLD", 13.0, UITheme.COLORS.ASH, 15, 1)

    AddBoxChild(vb, titleTb, 1, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, name .. "_SP2", 1, 5), 1, 1)
    AddBoxChild(vb, subTb, 1, 1)

    AddBoxChild(hb, thumbSB, 1, 2)
    AddBoxChild(hb, keyBadge, 1, 2, 7, 0, 8, 0)
    AddBoxChild(hb, vb, 0, 2)

    card:SetContent(hb)
    return card.Root
end

local function BuildMenuPanel(wt, cv)
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    if not vbCls then return nil end

    local rootVB = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_Menu_VB"))
    local headTxt = UITheme.CreateText(wt, "PAS_Menu_Title", "PLAY AS SLENDER", "HORROR", 30.0, UITheme.COLORS.BONE, 45, 1)
    local hdrAcc = UITheme.CreateAccentLine(wt, "PAS_Menu_HdrAcc", 0.0, 4.0, UITheme.COLORS.CRIMSON_SOFT)
    AddBoxChild(rootVB, headTxt, 2, 1)
    AddBoxChild(rootVB, hdrAcc, 0, 1)
    AddBoxChild(rootVB, UITheme.CreateSpacer(wt, "PAS_Menu_SP1", 1, 12), 1, 1)

    local card1 = BuildMenuChapterCard(
        wt, "PAS_Menu_C1",
        UITheme.GetTex("ICON_PROLOGUE"),
        Config.KEYS.QUICK_START_HOUSE,
        "PROLOGUE",
        "KATE'S HOUSE & YARD"
    )
    local card2 = BuildMenuChapterCard(
        wt, "PAS_Menu_C2",
        UITheme.GetTex("ICON_EIGHT_PAGES"),
        Config.KEYS.QUICK_START_FOREST,
        "THE EIGHT PAGES",
        "OAKSIDE PARK FOREST"
    )

    AddBoxChild(rootVB, card1, 0, 1)
    AddBoxChild(rootVB, UITheme.CreateSpacer(wt, "PAS_Menu_SP2", 1, 10), 1, 1)
    AddBoxChild(rootVB, card2, 0, 1)
    local slot = cv:AddChildToCanvas(rootVB)
    SetSlotAnchored(slot, -34.0, 0.0, 1.0, 0.48, 1.0, 0.5, 50)
    return { Root = rootVB }
end

local function BuildTopStatus(wt, cv)
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    if not hbCls or not vbCls then return nil end

    local container = CreateHudPanel(wt, "PAS_TopStatus", UITheme.COLORS.PANEL_DARK, 12, 9, 16, 9)
    if not container then return nil end

    local mainHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Top_HB"))
    local rightVB = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_Top_VB"))
    local row1HB  = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Top_R1"))
    local row2HB  = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Top_R2"))

    local mapTex = UITheme.GetTex("ICON_EIGHT_PAGES") or UITheme.GetTex("ICON_PROLOGUE")
    local mapSB, mapImg = UITheme.CreateSizedImage(wt, "PAS_Top_Thumb", mapTex, 58.0, 51.0)
    local mapTb = UITheme.CreateText(wt, "PAS_Top_Map", "THE EIGHT PAGES", "HORROR", 21.0, UITheme.COLORS.BONE, 30, 1)
    AddBoxChild(row1HB, mapTb, 1, 2)

    local pageSB, _ = UITheme.CreateSizedImage(wt, "PAS_Top_PageIcn", UITheme.GetTex("ICON_PAGE"), 20.0, 22.0, { R = 0.96, G = 0.94, B = 0.88, A = 0.96 }, false)
    local objTb     = UITheme.CreateText(wt, "PAS_Top_Obj", "0 / 8", "CAMCORDER", 15.0, UITheme.COLORS.BONE, 20, 1)
    local fearLbl   = UITheme.CreateText(wt, "PAS_Top_FearLbl", "FEAR", "CAMCORDER", 11.0, UITheme.COLORS.ASH, 60, 1)
    local fearGauge = UITheme.CreateSlenderGauge(wt, "PAS_Top_FearBar", 125.0, 10.0, UITheme.COLORS.BONE)
    local fearPctTb = UITheme.CreateText(wt, "PAS_Top_FearPct", "0%", "CAMCORDER", 14.0, UITheme.COLORS.BONE, 10, 1)
    local senseTb   = UITheme.CreateText(wt, "PAS_Top_Sense", "STAGE I: STALKING  |  0.0m  |  HIDDEN (EXPLORING)", "CAMCORDER", 11.5, UITheme.COLORS.ASH, 25, 1)

    AddBoxChild(row2HB, pageSB, 1, 2)
    AddBoxChild(row2HB, UITheme.CreateSpacer(wt, "PAS_Top_SP2", 6, 1), 1, 2)
    AddBoxChild(row2HB, objTb, 1, 2)
    AddBoxChild(row2HB, UITheme.CreateSpacer(wt, "PAS_Top_SP3", 16, 1), 1, 2)
    AddBoxChild(row2HB, fearLbl, 1, 2)
    AddBoxChild(row2HB, UITheme.CreateSpacer(wt, "PAS_Top_SP4", 8, 1), 1, 2)
    if fearGauge then AddBoxChild(row2HB, fearGauge.Root, 1, 2, 0, 0, 7, 0) end
    AddBoxChild(row2HB, fearPctTb, 1, 2)

    local acc, _ = UITheme.CreateAccentLine(wt, "PAS_Top_Acc", 0.0, 2.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.65 })
    AddBoxChild(rightVB, row1HB, 1, 1)
    AddBoxChild(rightVB, UITheme.CreateSpacer(wt, "PAS_Top_SP6", 1, 4), 1, 1)
    AddBoxChild(rightVB, row2HB, 1, 1)
    AddBoxChild(rightVB, UITheme.CreateSpacer(wt, "PAS_Top_SP7", 1, 4), 1, 1)
    AddBoxChild(rightVB, senseTb, 1, 1)
    AddBoxChild(rightVB, UITheme.CreateSpacer(wt, "PAS_Top_SP8b", 1, 5), 1, 1)
    AddBoxChild(rightVB, acc, 0, 1)

    AddBoxChild(mainHB, mapSB, 1, 2)
    AddBoxChild(mainHB, UITheme.CreateSpacer(wt, "PAS_Top_SP8", 12, 1), 1, 2)
    AddBoxChild(mainHB, rightVB, 0, 2)

    container:SetContent(mainHB)
    local slot = cv:AddChildToCanvas(container.Root)
    SetSlotAnchored(slot, 22.0, 18.0, 0.0, 0.0, 0.0, 0.0, 50)
    return {
        Root      = container.Root,
        MapImg    = mapImg,
        MapText   = mapTb,
        ObjText   = objTb,
        FearGauge = fearGauge,
        FearPct   = fearPctTb,
        SenseText = senseTb,
    }
end

local function BuildControlsStrip(wt, cv)
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    if not hbCls or not vbCls then return nil end

    local rootVB = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_Ctrl_RootVB"))
    local recPill = CreateHudPanel(wt, "PAS_Ctrl_RecPill", UITheme.COLORS.PANEL_DARK, 10, 4, 12, 4)
    local recHB  = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Ctrl_RecHB"))

    local recDotSB, recDotImg = UITheme.CreateSizedImage(wt, "PAS_Ctrl_RecDot", UITheme.GetTex("REC_DOT"), 16.0, 16.0)
    local recTxtSB = UITheme.CreateSizedImage(wt, "PAS_Ctrl_RecTxt", UITheme.GetTex("REC_BADGE"), 42.0, 21.0)
    local timerTb             = UITheme.CreateText(wt, "PAS_Ctrl_Timer", "00:00:00", "CAMCORDER", 16.0, UITheme.COLORS.BONE, 30, 1)

    AddBoxChild(recHB, recDotSB, 1, 2)
    AddBoxChild(recHB, UITheme.CreateSpacer(wt, "PAS_Ctrl_RSP1", 5, 1), 1, 2)
    AddBoxChild(recHB, recTxtSB, 1, 2)
    AddBoxChild(recHB, UITheme.CreateSpacer(wt, "PAS_Ctrl_RSP2", 8, 1), 1, 2)
    AddBoxChild(recHB, timerTb, 1, 2)
    recPill:SetContent(recHB)

    local bar = CreateHudPanel(wt, "PAS_Controls", UITheme.COLORS.PANEL_DARK, 12, 6, 12, 6)
    local stripHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Ctrl_StripHB"))

    local function AddKeyBindGroup(idx, keysList, labelStr)
        if idx > 1 then
            AddBoxChild(stripHB, UITheme.CreateText(wt, "PAS_Ctrl_SEP" .. idx, " | ", "BODY", 11.0, UITheme.COLORS.DIM, 0, 0), 1, 2)
        end
        for kIdx, kn in ipairs(keysList) do
            AddBoxChild(stripHB, UITheme.CreateKeycapBadge(wt, "PAS_Ctrl_K" .. idx .. "_" .. kIdx, kn, 21.0), 1, 2)
            if kIdx < #keysList then
                AddBoxChild(stripHB, UITheme.CreateSpacer(wt, "PAS_Ctrl_KS" .. idx .. "_" .. kIdx, 2, 1), 1, 2)
            end
        end
        AddBoxChild(stripHB, UITheme.CreateSpacer(wt, "PAS_Ctrl_LS" .. idx, 5, 1), 1, 2)
        AddBoxChild(stripHB, UITheme.CreateText(wt, "PAS_Ctrl_LB" .. idx, labelStr, "BODY_BOLD", 11.0, UITheme.COLORS.ASH, 30, 1), 1, 2)
    end

    AddKeyBindGroup(1, { Config.KEYS.FORWARD, Config.KEYS.LEFT, Config.KEYS.BACKWARD, Config.KEYS.RIGHT }, "MOVE")
    AddKeyBindGroup(2, { Config.KEYS.SPRINT }, "GLIDE")
    AddKeyBindGroup(3, { Config.KEYS.TOGGLE_DEBUG }, "INFO")
    AddKeyBindGroup(4, { Config.KEYS.TOGGLE_FREECAM }, "CAM")
    AddKeyBindGroup(5, { Config.KEYS.RESTART_ROUND }, "RESTART")

    bar:SetContent(stripHB)
    AddBoxChild(rootVB, recPill.Root, 3, 1)
    AddBoxChild(rootVB, UITheme.CreateSpacer(wt, "PAS_Ctrl_VSP", 1, 5), 1, 1)
    AddBoxChild(rootVB, bar.Root, 3, 1)

    local slot = cv:AddChildToCanvas(rootVB)
    SetSlotAnchored(slot, -22.0, 18.0, 1.0, 0.0, 1.0, 0.0, 50)
    return {
        Root      = rootVB,
        RecDot    = recDotImg,
        TimerText = timerTb,
    }
end

local function BuildAbilityCard(wt, name, keyName, iconTex, iconW, iconH, titleStr)
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    local button = UITheme.GetMat("SLENDER_BTN_HOV")
    local bg = button or UITheme.GetTex("BUTTON_ALT") or UITheme.GetTex("BUTTON")
    local card = UITheme.CreateBackdropContainer(wt, name, bg, UITheme.COLORS.ASH, button ~= nil, 11, 7, 11, 7)
    if not card or not hbCls or not vbCls then return nil end

    local vb = StaticConstructObject(vbCls, wt, Bridge.FName(name .. "_VB"))
    local topHB = StaticConstructObject(hbCls, wt, Bridge.FName(name .. "_TOP"))

    local keyBadge = UITheme.CreateKeycapBadge(wt, name .. "_KEY", keyName, 25.0)
    local icoSB, _ = UITheme.CreateSizedImage(wt, name .. "_ICO", iconTex, iconW, iconH, { R = 0.94, G = 0.92, B = 0.86, A = 0.92 }, false)
    local titleTb  = UITheme.CreateText(wt, name .. "_TTL", titleStr, "HORROR", 14.0, UITheme.COLORS.BONE, 30, 1)
    local statTb   = UITheme.CreateText(wt, name .. "_STAT", "READY", "CAMCORDER", 11.0, UITheme.COLORS.BONE, 30, 1)
    local gauge    = UITheme.CreateSlenderGauge(wt, name .. "_BAR", 172.0, 6.0, UITheme.COLORS.BONE)

    AddBoxChild(topHB, keyBadge, 1, 2)
    AddBoxChild(topHB, UITheme.CreateSpacer(wt, name .. "_SP1", 5, 1), 1, 2)
    AddBoxChild(topHB, icoSB, 1, 2)
    AddBoxChild(topHB, UITheme.CreateSpacer(wt, name .. "_SP2", 7, 1), 1, 2)
    AddBoxChild(topHB, titleTb, 1, 2)
    AddBoxChild(topHB, UITheme.CreateSpacer(wt, name .. "_SP3", 10, 1), 1, 2)
    AddBoxChild(topHB, statTb, 3, 2)

    AddBoxChild(vb, topHB, 0, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, name .. "_SP4", 1, 4), 1, 1)
    if gauge then AddBoxChild(vb, gauge.Root, 0, 1) end

    card:SetContent(vb)
    return {
        Root     = card.Root,
        BgImg    = card.BgImg,
        Status   = statTb,
        Gauge    = gauge,
    }
end

local function BuildAbilitiesBar(wt, cv)
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    if not hbCls then return nil end

    local rootHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Abil_HB"))

    local cTp = BuildAbilityCard(wt, "PAS_Abil_TP", Config.KEYS.TELEPORT,      UITheme.GetTex("ICON_SPINNER"),   20.0, 20.0, "TELEPORT")
    local cDr = BuildAbilityCard(wt, "PAS_Abil_DR", Config.KEYS.PSYCHIC_DREAD, UITheme.GetTex("TENDRIL_2"),      28.0, 14.0, "DREAD")
    local cTr = BuildAbilityCard(wt, "PAS_Abil_TR", Config.KEYS.TERRIFY,       UITheme.GetTex("SKETCH_TERRIFY"), 16.0, 22.0, "TERRIFY")
    local cHm = BuildAbilityCard(wt, "PAS_Abil_HM", Config.KEYS.TOGGLE_HAMMER or "R", UITheme.GetTex("TENDRIL_1") or UITheme.GetTex("ICON_SPINNER"), 24.0, 14.0, "HAMMER")

    local fcContainer = CreateHudPanel(wt, "PAS_Abil_FC", UITheme.COLORS.PANEL_DARK, 10, 7, 10, 7)
    local fcTxt = UITheme.CreateText(wt, "PAS_Abil_FCT", "FREE CAM", "CAMCORDER", 12.0, UITheme.COLORS.AMBER, 40, 1)
    if fcContainer and fcTxt then
        fcContainer:SetContent(fcTxt)
    end

    if cTp then AddBoxChild(rootHB, cTp.Root, 1, 2) end
    AddBoxChild(rootHB, UITheme.CreateSpacer(wt, "PAS_Abil_SP1", 12, 1), 1, 2)
    if cDr then AddBoxChild(rootHB, cDr.Root, 1, 2) end
    AddBoxChild(rootHB, UITheme.CreateSpacer(wt, "PAS_Abil_SP2", 12, 1), 1, 2)
    if cTr then AddBoxChild(rootHB, cTr.Root, 1, 2) end
    if cHm then
        AddBoxChild(rootHB, UITheme.CreateSpacer(wt, "PAS_Abil_SP4", 12, 1), 1, 2)
        AddBoxChild(rootHB, cHm.Root, 1, 2)
    end
    if fcContainer then
        AddBoxChild(rootHB, UITheme.CreateSpacer(wt, "PAS_Abil_SP3", 10, 1), 1, 2)
        AddBoxChild(rootHB, fcContainer.Root, 1, 2)
    end

    local slot = cv:AddChildToCanvas(rootHB)
    SetSlotAnchored(slot, 0.0, -20.0, 0.5, 1.0, 0.5, 1.0, 50)
    return {
        Root    = rootHB,
        Tp      = cTp,
        Dr      = cDr,
        Tr      = cTr,
        Hm      = cHm,
        FreeCam = fcContainer and fcContainer.Root or nil,
    }
end

local function BuildToast(wt, cv)
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    local container = CreateHudPanel(wt, "PAS_Toast", UITheme.COLORS.PANEL_DARK, 26, 8, 26, 8)
    if not container or not vbCls then return nil end

    local vb = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_Toast_VB"))
    local txt = UITheme.CreateText(wt, "PAS_Toast_TXT", "", "BODY_BOLD", 16.0, UITheme.COLORS.BONE, 30, 1)
    local acc, _ = UITheme.CreateAccentLine(wt, "PAS_Toast_Acc", 260.0, 2.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.82 })
    AddBoxChild(vb, txt, 2, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, "PAS_Toast_SP", 1, 4), 1, 1)
    AddBoxChild(vb, acc, 0, 1)
    container:SetContent(vb)

    local slot = cv:AddChildToCanvas(container.Root)
    SetSlotAnchored(slot, 0.0, -106.0, 0.5, 1.0, 0.5, 1.0, 60)
    return { Root = container.Root, Text = txt }
end

local function BuildDebugPanel(wt, cv)
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    if not vbCls or not hbCls then return nil end

    local container = CreateHudPanel(wt, "PAS_Debug", UITheme.COLORS.PANEL_DARK, 16, 11, 18, 12)
    if not container then return nil end

    local vb = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_Dbg_VB"))
    local hdrHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Dbg_HDR"))
    local hdrTxt = UITheme.CreateText(wt, "PAS_Dbg_Title", "SURVIVOR TELEMETRY", "HORROR", 17.0, UITheme.COLORS.BONE, 40, 1)
    local hdrKey = UITheme.CreateKeycapBadge(wt, "PAS_Dbg_Key", Config.KEYS.TOGGLE_DEBUG, 20.0)
    local acc, _ = UITheme.CreateAccentLine(wt, "PAS_Dbg_Acc", 340.0, 2.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.72 })

    AddBoxChild(hdrHB, hdrTxt, 1, 2)
    AddBoxChild(hdrHB, UITheme.CreateSpacer(wt, "PAS_Dbg_HSP", 16, 1), 1, 2)
    AddBoxChild(hdrHB, hdrKey, 3, 2)

    local metersHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_Dbg_MHB"))
    local fLbl = UITheme.CreateText(wt, "PAS_Dbg_FL", "FEAR", "CAMCORDER", 11.0, UITheme.COLORS.ASH, 40, 1)
    local fBar = UITheme.CreateSlenderGauge(wt, "PAS_Dbg_FB", 105.0, 8.0, UITheme.COLORS.CRIMSON)
    local sLbl = UITheme.CreateText(wt, "PAS_Dbg_SL", "STAMINA", "CAMCORDER", 11.0, UITheme.COLORS.ASH, 40, 1)
    local sBar = UITheme.CreateSlenderGauge(wt, "PAS_Dbg_SB", 105.0, 8.0, UITheme.COLORS.BONE)

    AddBoxChild(metersHB, fLbl, 1, 2)
    AddBoxChild(metersHB, UITheme.CreateSpacer(wt, "PAS_Dbg_MSP1", 6, 1), 1, 2)
    if fBar then AddBoxChild(metersHB, fBar.Root, 1, 2) end
    AddBoxChild(metersHB, UITheme.CreateSpacer(wt, "PAS_Dbg_MSP2", 14, 1), 1, 2)
    AddBoxChild(metersHB, sLbl, 1, 2)
    AddBoxChild(metersHB, UITheme.CreateSpacer(wt, "PAS_Dbg_MSP3", 6, 1), 1, 2)
    if sBar then AddBoxChild(metersHB, sBar.Root, 1, 2) end

    local bodyTb = UITheme.CreateText(wt, "PAS_Dbg_Body", "...", "BODY", 12.5, { R = 0.82, G = 0.88, B = 0.82, A = 0.96 }, 10, 1)

    AddBoxChild(vb, hdrHB, 0, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, "PAS_Dbg_SP1", 1, 4), 1, 1)
    AddBoxChild(vb, acc, 0, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, "PAS_Dbg_SP2", 1, 7), 1, 1)
    AddBoxChild(vb, metersHB, 1, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, "PAS_Dbg_SP3", 1, 6), 1, 1)
    AddBoxChild(vb, bodyTb, 1, 1)

    container:SetContent(vb)
    local slot = cv:AddChildToCanvas(container.Root)
    SetSlotAnchored(slot, 22.0, 120.0, 0.0, 0.0, 0.0, 0.0, 55)
    return {
        Root         = container.Root,
        FearGauge    = fBar,
        StaminaGauge = sBar,
        BodyText     = bodyTb,
    }
end

local function CreateNativeEndButton(world, pc, idStr, labelText)
    local btnCls = UITheme.GetClass("/Game/Blueprints/UI/Buttons/W_Button.W_Button_C")
    local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
    local btn = nil
    if Logger.IsValidObj(btnCls) and Logger.IsValidObj(wbl) and Logger.IsValidObj(pc) then
        local okC, w = pcall(function() return wbl:Create(world, btnCls, pc) end)
        if okC and Logger.IsValidObj(w) then
            btn = w
        end
    end
    if not Logger.IsValidObj(btn) then
        return nil
    end

    local ft = FText(tostring(labelText))
    pcall(function() btn.ID = tostring(idStr) end)
    pcall(function() btn.Style = 32 end)
    pcall(function() btn.Scale = 0.62 end)
    pcall(function() btn.FontSizeOverride = 20 end)
    pcall(function() btn.ShowIcon = false end)
    pcall(function() btn.HideText = false end)
    pcall(function() btn.UseHoverFont = true end)
    pcall(function() btn.bIsFocusable = true end)
    pcall(function() btn["Label Text"] = ft end)
    pcall(function() btn:PreConstruct(false) end)
    pcall(function() btn:Construct() end)
    pcall(function() btn:SetStyle(32) end)
    pcall(function() btn:Init() end)
    pcall(function() btn:SetText(ft) end)

    pcall(function()
        local lbl = btn.txt_Label
        if Logger.IsValidObj(lbl) then
            lbl.AllCaps = true
            lbl.AutoWrap = false
            lbl.CharacterLimit = 32
            pcall(function() lbl["Set Text"](lbl, ft) end)
            if Logger.IsValidObj(lbl.TextBlock_21) then
                UITheme.ApplyFont(lbl.TextBlock_21, "HORROR", 19.0, 28, UITheme.COLORS.BONE, 1)
                lbl.TextBlock_21:SetText(ft)
            end
        end
    end)

    pcall(function() btn:SetVisibility(0) end)
    pcall(function() btn:SetIsEnabled(true) end)
    pcall(function()
        if Logger.IsValidObj(btn.btn_Button) then
            btn.btn_Button:SetVisibility(0)
            btn.btn_Button:SetIsEnabled(true)
        end
    end)
    return btn
end

local function BuildEndBanner(wt, cv, world, pc)
    local ovCls = UITheme.GetClass("/Script/UMG.Overlay")
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    if not ovCls or not vbCls or not hbCls then return nil end

    local fullOv = StaticConstructObject(ovCls, wt, Bridge.FName("PAS_End_FullOV"))
    local bgMat  = UITheme.GetMat("GAME_COMPLETE_BG")
    local bgTex  = UITheme.GetTex("RADIAL_GRADIENT") or UITheme.GetTex("FADE_RECT")
    local bgImg  = UITheme.CreateImage(wt, "PAS_End_BG", bgMat or bgTex, { R = 0.36, G = 0.33, B = 0.33, A = 0.91 }, bgMat ~= nil)
    if bgImg then
        pcall(function() bgImg:SetVisibility(3) end)
        local s0 = fullOv:AddChildToOverlay(bgImg)
        s0:SetHorizontalAlignment(0)
        s0:SetVerticalAlignment(0)
    end

    -- Corner tendril accents
    local t1 = UITheme.CreateSizedImage(wt, "PAS_End_T1", UITheme.GetTex("TENDRIL_1"), 620.0, 155.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.32 }, false)
    if t1 then
        pcall(function() t1:SetRenderTransformAngle(-14.0); t1:SetVisibility(3) end)
        local sT1 = fullOv:AddChildToOverlay(t1)
        if sT1 then sT1:SetHorizontalAlignment(1); sT1:SetVerticalAlignment(3) end
    end
    local t2 = UITheme.CreateSizedImage(wt, "PAS_End_T2", UITheme.GetTex("TENDRIL_2"), 620.0, 155.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.32 }, false)
    if t2 then
        pcall(function() t2:SetRenderTransformAngle(14.0); t2:SetVisibility(3) end)
        local sT2 = fullOv:AddChildToOverlay(t2)
        if sT2 then sT2:SetHorizontalAlignment(3); sT2:SetVerticalAlignment(1) end
    end

    local card = CreateHudPanel(wt, "PAS_End_Card", UITheme.COLORS.PANEL_DARK, 36, 22, 36, 22)
    if not card then return nil end
    pcall(function() card.Root:SetVisibility(4) end)

    local sketch = UITheme.GetTex("SKETCH_SLENDER") or UITheme.GetTex("SKETCH_ALT")
    local wmSB, wmImg = UITheme.CreateSizedImage(wt, "PAS_End_WM", sketch, 150.0, 225.0)
    if wmSB then pcall(function() wmSB:SetVisibility(3) end) end

    local cardHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_CHB"))
    local mainVB = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_End_VB"))
    pcall(function() cardHB:SetVisibility(4); mainVB:SetVisibility(4) end)

    -- Chapter Header Strip
    local chapHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_ChapHB"))
    local defChapTex = UITheme.GetTex("ICON_EIGHT_PAGES") or UITheme.GetTex("ICON_PROLOGUE")
    local chapSB, chapImg = UITheme.CreateSizedImage(wt, "PAS_End_ChapIcn", defChapTex, 56.0, 48.0)
    local chapHdrTb = UITheme.CreateText(wt, "PAS_End_ChapHdr", "CHAPTER: THE EIGHT PAGES   |   STAGE I: STALKING", "CAMCORDER", 13.0, UITheme.COLORS.ASH, 25, 1)
    AddBoxChild(chapHB, chapSB, 1, 2)
    AddBoxChild(chapHB, UITheme.CreateSpacer(wt, "PAS_End_ChapSP", 12, 1), 1, 2)
    AddBoxChild(chapHB, chapHdrTb, 1, 2)
    pcall(function() chapHB:SetVisibility(3) end)

    local titleTb  = UITheme.CreateText(wt, "PAS_End_Title", "SLENDERMAN VICTORY", "HORROR", 28.0, UITheme.COLORS.CRIMSON, 55, 2)
    local reasonTb = UITheme.CreateText(wt, "PAS_End_Reason", "The Human could not withstand the terror.", "BODY", 14.5, UITheme.COLORS.ASH, 15, 1)

    -- Hunter Rank & Score Banner
    local rankPanel = CreateHudPanel(wt, "PAS_End_Rank", { R = 0.14, G = 0.04, B = 0.04, A = 0.88 }, 16, 6, 16, 6)
    local rankTb    = UITheme.CreateText(wt, "PAS_End_RankTxt", "HUNTER RANK : A [SHADOW STALKER]  -  0 PTS", "HORROR", 21.0, UITheme.COLORS.AMBER, 30, 2)
    if rankPanel and rankTb then
        rankPanel:SetContent(rankTb)
        pcall(function() rankPanel.Root:SetVisibility(3) end)
    end

    local acc, _ = UITheme.CreateAccentLine(wt, "PAS_End_Acc", 510.0, 2.0, { R = 0.84, G = 0.16, B = 0.16, A = 0.85 })

    -- Dual Native Gauges: Sanity Shattered + Objectives Denied
    local barsHB  = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_BarsHB"))
    local fearVB  = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_End_FearVB"))
    local fearHdr = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_FearHdr"))
    local fearLbl = UITheme.CreateText(wt, "PAS_End_FearLbl", "SANITY SHATTERED", "CAMCORDER", 11.5, UITheme.COLORS.ASH, 20, 1)
    local fearHSp = UITheme.CreateSpacer(wt, "PAS_End_FearHdrSP", 14, 1)
    local fearValTb = UITheme.CreateText(wt, "PAS_End_FearVal", "0%", "CAMCORDER", 12.0, UITheme.COLORS.CRIMSON_SOFT, 15, 1)
    local fearBar = UITheme.CreateSlenderGauge(wt, "PAS_End_FearBar", 240.0, 11.0, UITheme.COLORS.CRIMSON)
    AddBoxChild(fearHdr, fearLbl, 1, 2)
    local fSpSlot = AddBoxChild(fearHdr, fearHSp, 0, 2)
    if fSpSlot and fSpSlot.SetSize then pcall(function() fSpSlot:SetSize({ Value = 1.0, SizeRule = 1 }) end) end
    AddBoxChild(fearHdr, fearValTb, 3, 2)
    AddBoxChild(fearVB, fearHdr, 0, 1)
    AddBoxChild(fearVB, UITheme.CreateSpacer(wt, "PAS_End_FearBarSP", 1, 4), 1, 1)
    if fearBar then AddBoxChild(fearVB, fearBar.Root, 0, 1) end

    local denyVB  = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_End_DenyVB"))
    local denyHdr = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_DenyHdr"))
    local denyLbl = UITheme.CreateText(wt, "PAS_End_DenyLbl", "OBJECTIVES DENIED", "CAMCORDER", 11.5, UITheme.COLORS.ASH, 20, 1)
    local denyHSp = UITheme.CreateSpacer(wt, "PAS_End_DenyHdrSP", 14, 1)
    local denyValTb = UITheme.CreateText(wt, "PAS_End_DenyVal", "0 / 8 DENIED", "CAMCORDER", 12.0, UITheme.COLORS.AMBER, 15, 1)
    local denyBar = UITheme.CreateSlenderGauge(wt, "PAS_End_DenyBar", 240.0, 11.0, UITheme.COLORS.AMBER)
    AddBoxChild(denyHdr, denyLbl, 1, 2)
    local dSpSlot = AddBoxChild(denyHdr, denyHSp, 0, 2)
    if dSpSlot and dSpSlot.SetSize then pcall(function() dSpSlot:SetSize({ Value = 1.0, SizeRule = 1 }) end) end
    AddBoxChild(denyHdr, denyValTb, 3, 2)
    AddBoxChild(denyVB, denyHdr, 0, 1)
    AddBoxChild(denyVB, UITheme.CreateSpacer(wt, "PAS_End_DenyBarSP", 1, 4), 1, 1)
    if denyBar then AddBoxChild(denyVB, denyBar.Root, 0, 1) end

    AddBoxChild(barsHB, fearVB, 1, 1)
    AddBoxChild(barsHB, UITheme.CreateSpacer(wt, "PAS_End_BarsSP", 30, 1), 1, 1)
    AddBoxChild(barsHB, denyVB, 1, 1)
    pcall(function() barsHB:SetVisibility(3) end)

    -- 2-Column Camcorder Dossier
    local statsHB  = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_StatsHB"))
    local statsTb  = UITheme.CreateText(wt, "PAS_End_Stats", "...", "CAMCORDER", 12.5, UITheme.COLORS.BONE, 20, 1)
    local statsRTb = UITheme.CreateText(wt, "PAS_End_StatsR", "", "CAMCORDER", 12.5, UITheme.COLORS.BONE, 20, 1)
    AddBoxChild(statsHB, statsTb, 1, 1)
    AddBoxChild(statsHB, UITheme.CreateSpacer(wt, "PAS_End_StatsSP", 28, 1), 1, 1)
    AddBoxChild(statsHB, statsRTb, 1, 1)
    pcall(function() statsHB:SetVisibility(3) end)

    local unlockTb = UITheme.CreateText(wt, "PAS_End_Unlock", "", "BODY_BOLD", 13.0, UITheme.COLORS.AMBER, 20, 1)
    local hintTb   = UITheme.CreateText(wt, "PAS_End_Hint", "[ENTER] NEXT LEVEL  |  [F8] RESTART  |  [M / BACKSPACE] MAIN MENU", "CAMCORDER", 11.0, UITheme.COLORS.DIM, 20, 1)
    pcall(function()
        titleTb:SetVisibility(3); reasonTb:SetVisibility(3)
        statsTb:SetVisibility(3); statsRTb:SetVisibility(3)
        unlockTb:SetVisibility(3); hintTb:SetVisibility(3)
        if Logger.IsValidObj(acc) then acc:SetVisibility(3) end
    end)

    local footHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_End_FHB"))
    pcall(function() footHB:SetVisibility(4) end)

    local btnNext    = CreateNativeEndButton(world, pc, "PAS_END_NEXT", "NEXT LEVEL")
    local nextSp     = UITheme.CreateSpacer(wt, "PAS_End_NSP", 22, 1)
    local btnRestart = CreateNativeEndButton(world, pc, "PAS_END_RESTART", "RESTART [F8]")
    local menuSp     = UITheme.CreateSpacer(wt, "PAS_End_MSP", 22, 1)
    local btnMenu    = CreateNativeEndButton(world, pc, "PAS_END_MENU", "MAIN MENU")

    if btnNext then
        pcall(function() btnNext:SetVisibility(1) end)
        if nextSp then pcall(function() nextSp:SetVisibility(1) end) end
        AddBoxChild(footHB, btnNext, 1, 2)
        if nextSp then AddBoxChild(footHB, nextSp, 1, 2) end
    end
    if btnRestart then
        AddBoxChild(footHB, btnRestart, 1, 2)
        if btnMenu and menuSp then AddBoxChild(footHB, menuSp, 1, 2) end
    else
        local f8Key = UITheme.CreateKeycapBadge(wt, "PAS_End_F8", Config.KEYS.RESTART_ROUND, 26.0)
        local footTb = UITheme.CreateText(wt, "PAS_End_Foot", "RESTART [F8]  |  MENU [M]", "HORROR", 19.0, UITheme.COLORS.BONE, 30, 1)
        AddBoxChild(footHB, f8Key, 1, 2)
        AddBoxChild(footHB, UITheme.CreateSpacer(wt, "PAS_End_FSP", 10, 1), 1, 2)
        AddBoxChild(footHB, footTb, 1, 2)
    end
    if btnMenu then
        AddBoxChild(footHB, btnMenu, 1, 2)
    end

    AddBoxChild(mainVB, chapHB, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP1", 1, 6), 1, 1)
    AddBoxChild(mainVB, titleTb, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP1b", 1, 4), 1, 1)
    AddBoxChild(mainVB, reasonTb, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP2", 1, 9), 1, 1)
    if rankPanel then
        AddBoxChild(mainVB, rankPanel.Root, 1, 1)
    elseif rankTb then
        AddBoxChild(mainVB, rankTb, 1, 1)
    end
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP2b", 1, 9), 1, 1)
    AddBoxChild(mainVB, acc, 0, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP3", 1, 10), 1, 1)
    AddBoxChild(mainVB, barsHB, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP3b", 1, 12), 1, 1)
    AddBoxChild(mainVB, statsHB, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP3c", 1, 9), 1, 1)
    AddBoxChild(mainVB, unlockTb, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP3d", 1, 9), 1, 1)
    AddBoxChild(mainVB, hintTb, 1, 1)
    AddBoxChild(mainVB, UITheme.CreateSpacer(wt, "PAS_End_SP4", 1, 8), 1, 1)
    AddBoxChild(mainVB, footHB, 1, 1)

    AddBoxChild(cardHB, mainVB, 1, 2)
    if wmSB then
        AddBoxChild(cardHB, UITheme.CreateSpacer(wt, "PAS_End_WMS", 24, 1), 1, 2)
        AddBoxChild(cardHB, wmSB, 3, 2)
    end
    card:SetContent(cardHB)

    local sCard = fullOv:AddChildToOverlay(card.Root)
    if sCard then
        sCard:SetHorizontalAlignment(2) -- Center
        sCard:SetVerticalAlignment(2)   -- Center
    end

    local slot = cv:AddChildToCanvas(fullOv)
    SetSlotFullscreen(slot, 80)

    return {
        Root       = fullOv,
        ChapterImg = chapImg,
        ChapterHdr = chapHdrTb,
        Title      = titleTb,
        Reason     = reasonTb,
        RankBgImg  = rankPanel and rankPanel.BgImg or nil,
        RankText   = rankTb,
        FearBar    = fearBar,
        FearVal    = fearValTb,
        DenyBar    = denyBar,
        DenyVal    = denyValTb,
        Stats      = statsTb,
        StatsR     = statsRTb,
        UnlockNote = unlockTb,
        HintText   = hintTb,
        WmImg      = wmImg,
        BtnNext    = btnNext,
        NextSpacer = nextSp,
        BtnRestart = btnRestart,
        BtnMenu    = btnMenu,
    }
end

-- =========================================================
-- Lifecycle & Updates
-- =========================================================
function Overlay.Reset()
    if Logger.IsValidObj(State.RootUserWidget) then
        pcall(function() State.RootUserWidget:RemoveFromParent() end)
    end
    UITheme.Reset()
    State.Initialized     = false
    State.RootUserWidget  = nil
    State.RootCanvas      = nil
    State.Widgets         = {}
    State.LastTexts       = {}
    State.LastVis         = {}
    State.LastOpacity     = {}
    State.LastMode        = ""
    State.LastMapKey      = ""
    State.LastEndMapKey   = ""
    State.LastEndWinner   = ""
    State.CachedVanilla   = {}
    State.NextVanillaScan = 0.0
    State.NativeMainMenu  = nil
    State.NextMenuCheck   = 0.0
    State.LastHPBar       = { visible = false, x = 0.0, y = 0.0, healthPct = 100.0, method = "none" }
    State.HPMethodLogged  = false
end

local HEALTH_GREEN = { R = 0.36, G = 0.86, B = 0.48, A = 0.96 }

local function BuildSurvivorHealthBar(wt, cv)
    local vbCls = UITheme.GetClass("/Script/UMG.VerticalBox")
    local hbCls = UITheme.GetClass("/Script/UMG.HorizontalBox")
    if not vbCls or not hbCls then return nil end

    local container = CreateHudPanel(wt, "PAS_SurvHP", { R = 0.04, G = 0.04, B = 0.05, A = 0.86 }, 8, 4, 8, 5)
    if not container then return nil end

    local vb    = StaticConstructObject(vbCls, wt, Bridge.FName("PAS_SurvHP_VB"))
    local hdrHB = StaticConstructObject(hbCls, wt, Bridge.FName("PAS_SurvHP_HB"))
    local lblTb = UITheme.CreateText(wt, "PAS_SurvHP_Lbl", "SURVIVOR", "BODY_BOLD", 10.5, UITheme.COLORS.BONE, 25, 1)
    local pctTb = UITheme.CreateText(wt, "PAS_SurvHP_Pct", "100%", "CAMCORDER", 11.0, HEALTH_GREEN, 15, 1)
    local gauge = UITheme.CreateSlenderGauge(wt, "PAS_SurvHP_Gauge", 118.0, 9.0, HEALTH_GREEN)
    if gauge then
        gauge:SetPercent(1.0)
    end

    AddBoxChild(hdrHB, lblTb, 1, 2)
    AddBoxChild(hdrHB, UITheme.CreateSpacer(wt, "PAS_SurvHP_SP1", 8, 1), 1, 2)
    AddBoxChild(hdrHB, pctTb, 3, 2)

    AddBoxChild(vb, hdrHB, 0, 1)
    AddBoxChild(vb, UITheme.CreateSpacer(wt, "PAS_SurvHP_SP2", 1, 3), 1, 1)
    if gauge then AddBoxChild(vb, gauge.Root, 0, 1) end

    container:SetContent(vb)
    pcall(function() container.Root:SetVisibility(1) end)
    local slot = cv:AddChildToCanvas(container.Root)
    SetSlotAnchored(slot, 0.0, 0.0, 0.0, 0.0, 0.5, 1.0, 18)

    return {
        Root    = container.Root,
        Slot    = slot,
        Label   = lblTb,
        PctText = pctTb,
        Gauge   = gauge,
    }
end

function Overlay.GetHealthBarState()
    return State.LastHPBar
end

function Overlay.UpdateSurvivorHealthBar(world, pc, survivor, slender, headPos, fear, ended, camPos, camRot, fovDeg)
    local hp = State.Widgets and State.Widgets.SurvivorHP
    if not State.Initialized or not hp then return end

    local function HideBar(reason)
        SetWidgetVisible("SurvHP", hp.Root, false)
        State.LastHPBar = {
            visible   = false,
            x         = 0.0,
            y         = 0.0,
            healthPct = Bridge.Clamp(100.0 - (tonumber(fear) or 0.0), 0.0, 100.0),
            method    = reason or "hidden",
        }
    end

    if ended or (not Logger.IsValidObj(survivor)) or (not headPos) or (not camPos) or (not Logger.IsValidObj(pc)) then
        HideBar("inactive")
        return
    end

    local dist = Bridge.Dist(camPos, headPos)
    if dist > 5500.0 then
        HideBar("too_far")
        return
    end

    if dist > 550.0 then
        local ignore = {}
        if Logger.IsValidObj(slender)  then table.insert(ignore, slender)  end
        if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end
        local chestPos = { X = headPos.X, Y = headPos.Y, Z = headPos.Z - 48.0 }
        local visHead  = Bridge.HasLineOfSight(world, camPos, headPos, ignore, survivor)
        local visChest = visHead or Bridge.HasLineOfSight(world, camPos, chestPos, ignore, survivor)
        if not visChest then
            HideBar("occluded")
            return
        end
    end

    local onScr, sx, sy, method = Bridge.ProjectWorldToWidget(world, pc, headPos, camPos, camRot, fovDeg or 90.0)
    if not onScr then
        HideBar(method)
        return
    end

    if not State.HPMethodLogged then
        State.HPMethodLogged = true
        Logger.Info(string.format("Survivor overhead HP bar active (method=%s, screen=(%.1f, %.1f), dist=%.0fcm)",
            tostring(method), sx, sy, dist))
    end

    SetWidgetVisible("SurvHP", hp.Root, true)
    if Logger.IsValidObj(hp.Slot) then
        pcall(function() hp.Slot:SetPosition({ X = sx, Y = sy }) end)
    end
    local scale = Bridge.Clamp(1.12 - (dist / 4500.0) * 0.42, 0.72, 1.12)
    pcall(function() hp.Root:SetRenderScale({ X = scale, Y = scale }) end)

    local healthPct = Bridge.Clamp(100.0 - (tonumber(fear) or 0.0), 0.0, 100.0)
    local col = HEALTH_GREEN
    if healthPct < 30.0 then
        col = UITheme.COLORS.CRIMSON
    elseif healthPct < 60.0 then
        col = UITheme.COLORS.AMBER
    end

    if hp.Gauge then
        hp.Gauge:SetPercent(healthPct / 100.0)
        hp.Gauge:SetColor(col)
    end
    SetCachedText("SurvHPPct", hp.PctText, string.format("%.0f%%", healthPct))
    SetCachedColor("SurvHPCol", hp.PctText, col)

    State.LastHPBar = {
        visible   = true,
        x         = sx,
        y         = sy,
        healthPct = healthPct,
        method    = method,
    }
end

function Overlay.Init(pc, mode)
    Overlay.Reset()
    if not Logger.IsValidObj(pc) then return false end

    UITheme.Init()

    local uwCls = Bridge.GetClass("/Script/UMG.UserWidget")
    local wtCls = Bridge.GetClass("/Script/UMG.WidgetTree")
    local cpCls = Bridge.GetClass("/Script/UMG.CanvasPanel")
    if not uwCls or not wtCls or not cpCls then
        Logger.Error("Overlay.Init: Missing core UMG classes")
        return false
    end

    local widget = StaticConstructObject(uwCls, pc, Bridge.FName("PlayAsSlenderOverlay"))
    if Logger.IsValidObj(widget) then
        local wt = StaticConstructObject(wtCls, widget, Bridge.FName("PlayAsSlenderWT"))
        local cp = StaticConstructObject(cpCls, wt, Bridge.FName("PlayAsSlenderCanvas"))
        if Logger.IsValidObj(wt) and Logger.IsValidObj(cp) then
            pcall(function()
                widget.WidgetTree = wt
                wt.RootWidget = cp
                widget:SetVisibility(3) -- HitTestInvisible at root so mouse/clicks never block!
            end)
            local okAdd = pcall(function() widget:AddToViewport(999) end)
            local inVp = false
            pcall(function() inVp = widget:IsInViewport() end)
            if okAdd and inVp then
                State.RootUserWidget = widget
                State.RootCanvas = cp
            end
        end
    end

    if not Logger.IsValidObj(State.RootCanvas) then
        Logger.Error("Overlay.Init: Failed to create UUserWidget overlay")
        return false
    end

    local wt = State.RootUserWidget.WidgetTree
    local cv = State.RootCanvas

    if mode == "MENU" then
        -- Main Menu uses native W_SubMenu_Main button injected by menu_integration.lua (no floating homemade overlay)
    else
        State.Widgets.Ambient    = BuildAmbientLayer(wt, cv)
        State.Widgets.SurvivorHP = BuildSurvivorHealthBar(wt, cv)
        State.Widgets.TopStatus  = BuildTopStatus(wt, cv)
        State.Widgets.Controls   = BuildControlsStrip(wt, cv)
        State.Widgets.Abilities  = BuildAbilitiesBar(wt, cv)
        State.Widgets.Toast      = BuildToast(wt, cv)
        State.Widgets.DebugPanel = BuildDebugPanel(wt, cv)
        State.Widgets.EndBanner  = BuildEndBanner(wt, cv, Bridge.GetWorld(), pc)
    end

    State.Initialized = true
    Overlay.SetModeVisibility(mode or "GAME")
    if mode == "GAME" then
        Overlay.HideVanillaHUD(true)
    end
    Logger.Info("Overlay initialized with native Slender assets (mode=" .. tostring(mode) .. ")")
    return true
end

function Overlay.SetModeVisibility(mode)
    if not State.Initialized then return end
    State.LastMode = mode
    local isMenu = (mode == "MENU")
    local isGame = (mode == "GAME")

    if State.Widgets.Ambient then
        SetWidgetVisible("AmbCam", State.Widgets.Ambient.CamFrame, isGame)
        SetWidgetVisible("AmbVig", State.Widgets.Ambient.Vignette, isGame)
        SetWidgetVisible("AmbTL",  State.Widgets.Ambient.TendrilL, false)
        SetWidgetVisible("AmbTR",  State.Widgets.Ambient.TendrilR, false)
        SetWidgetVisible("HammerCrosshair", State.Widgets.Ambient.Crosshair, false)
    end
    if State.Widgets.MenuPanel  then SetWidgetVisible("MenuPanel",  State.Widgets.MenuPanel.Root,  isMenu) end
    if State.Widgets.SurvivorHP then SetWidgetVisible("SurvHP",     State.Widgets.SurvivorHP.Root, false) end
    if State.Widgets.TopStatus  then SetWidgetVisible("TopStatus",  State.Widgets.TopStatus.Root,  isGame) end
    if State.Widgets.Controls   then SetWidgetVisible("Controls",   State.Widgets.Controls.Root,   isGame) end
    if State.Widgets.Abilities  then SetWidgetVisible("Abilities",  State.Widgets.Abilities.Root,  isGame) end
    if State.Widgets.DebugPanel then SetWidgetVisible("DebugPanel", State.Widgets.DebugPanel.Root, isGame and State.DebugVisible) end
    if State.Widgets.Toast      then SetWidgetVisible("Toast",      State.Widgets.Toast.Root,      false) end
    if State.Widgets.EndBanner  then SetWidgetVisible("EndBanner",  State.Widgets.EndBanner.Root,  false) end
end

function Overlay.SetDebugVisible(vis)
    State.DebugVisible = (vis == true)
    if State.Widgets.DebugPanel then
        SetWidgetVisible("DebugPanel", State.Widgets.DebugPanel.Root, State.LastMode == "GAME" and State.DebugVisible)
    end
end

function Overlay.ToggleDebugPanel()
    Overlay.SetDebugVisible(not State.DebugVisible)
    Logger.Info("DebugPanel visible = " .. tostring(State.DebugVisible))
end

function Overlay.IsDebugVisible()
    return State.DebugVisible
end

function Overlay.ShowToast(msg, durationSec)
    State.ToastText = tostring(msg or "")
    State.ToastStartAt = os.clock()
    State.ToastExpiresAt = State.ToastStartAt + (durationSec or 2.5)
end

function Overlay.UpdateMenu()
    if not State.Initialized or not State.Widgets.MenuPanel then return end
    local now = os.clock()
    if now < State.NextMenuCheck then return end
    State.NextMenuCheck = now + 0.15

    local nativeMenu = State.NativeMainMenu
    if not Logger.IsValidObj(nativeMenu) then
        nativeMenu = FindFirstOf("W_SubMenu_Main_C")
        State.NativeMainMenu = nativeMenu
    end

    local visible = true
    if Logger.IsValidObj(nativeMenu) then
        visible = nativeMenu:IsInViewport() and nativeMenu:IsVisible()
    end
    SetWidgetVisible("MenuPanel", State.Widgets.MenuPanel.Root, visible)
end

local function UpdateAbilitySlot(key, card, cdRem, cdMax, isActive)
    if not card then return end
    local ready = (not isActive) and ((cdRem or 0.0) <= 0.05)
    local frac = 1.0
    if isActive then
        frac = 1.0
    elseif not ready and cdMax and cdMax > 0.01 then
        frac = 1.0 - Bridge.Clamp((cdRem or 0.0) / cdMax, 0.0, 1.0)
    end

    local statusStr = isActive and "ACTIVE" or (ready and "READY" or string.format("%.1fs", cdRem or 0.0))
    local col = isActive and UITheme.COLORS.CRIMSON or (ready and UITheme.COLORS.BONE or UITheme.COLORS.DIM)
    SetCachedText(key .. "_ST", card.Status, statusStr)
    SetCachedColor(key .. "_STC", card.Status, col)
    if card.Gauge then
        card.Gauge:SetPercent(frac)
        card.Gauge:SetColor(isActive and UITheme.COLORS.CRIMSON or (ready and UITheme.COLORS.BONE or UITheme.COLORS.ASH))
    end

    if Logger.IsValidObj(card.BgImg) then
        local tint = isActive and UITheme.COLORS.CRIMSON or UITheme.COLORS.DIM
        local tintKey = "_cbg_" .. key
        if State.LastTexts[tintKey] ~= tint then
            State.LastTexts[tintKey] = tint
            pcall(function() card.BgImg:SetColorAndOpacity(tint) end)
        end
    end
end

function Overlay.UpdateGame(info)
    if not State.Initialized or not info then return end
    local now = os.clock()
    local ended = (info.winner ~= nil and info.winner ~= "")

    -- Top-left Status (swap native chapter icon cleanly by mapKey)
    local top = State.Widgets.TopStatus
    if top then
        SetWidgetVisible("TopStatus", top.Root, not ended)
        local mk = tostring(info.mapKey or "EIGHT_PAGES")
        if mk ~= State.LastMapKey then
            State.LastMapKey = mk
            local mapTex = nil
            if info.mapIconPath and UITheme.GetDynamicTexture then
                mapTex = UITheme.GetDynamicTexture(info.mapIconPath)
            end
            if not Logger.IsValidObj(mapTex) then
                local iconKey = (mk == "PROLOGUE" or mk == "PROLOGUE_YARD") and "ICON_PROLOGUE" or "ICON_EIGHT_PAGES"
                mapTex = UITheme.GetTex(iconKey)
            end
            UITheme.ApplyImageTexture(top.MapImg, mapTex, UITheme.COLORS.WHITE)
        end
        local cleanMapLabel = (mk == "PROLOGUE") and "PROLOGUE - KATE'S HOUSE"
            or ((mk == "EIGHT_PAGES") and "THE EIGHT PAGES"
            or SanitizeAscii(string.upper(tostring(info.mapTitle or mk))))
        SetCachedText("TopMap", top.MapText, cleanMapLabel)
        SetCachedText("TopObj", top.ObjText, string.format("%d / %d", info.pagesCollected or 0, info.pagesTotal or 8))

        local fear = Bridge.Clamp(info.fear or 0.0, 0.0, 100.0)
        SetCachedText("TopFearPct", top.FearPct, string.format("%.0f%%", fear))

        local fCol = UITheme.COLORS.BONE
        if fear >= 68.0 then
            fCol = UITheme.COLORS.CRIMSON
        elseif fear >= 35.0 then
            fCol = UITheme.COLORS.AMBER
        end
        if top.FearGauge then
            top.FearGauge:SetPercent(fear / 100.0)
            top.FearGauge:SetColor(fCol)
        end
        SetCachedColor("TopFearCol", top.FearPct, fCol)

        if top.SenseText then
            local distM = (info.distanceCm ~= nil) and ((tonumber(info.distanceCm) or 0.0) / 100.0)
                or (tonumber(info.closestDistM) or 0.0)
            local aiUpper = SanitizeAscii(string.upper(tostring(info.aiState or "EXPLORING")))
            local stageLabel = SanitizeAscii(string.upper(tostring(info.huntStageName or "STAGE I: STALKING")))
            local senseStr, senseCol
            if info.hasLOS then
                senseStr = string.format("WATCHING YOU!  |  %.1fm  |  %s", distM, aiUpper)
                senseCol = UITheme.COLORS.CRIMSON_SOFT
            else
                senseStr = string.format("%s  |  %.1fm  |  HIDDEN (%s)", stageLabel, distM, aiUpper)
                senseCol = (aiUpper == "PANICKING" or aiUpper == "ESCAPING") and UITheme.COLORS.AMBER or UITheme.COLORS.ASH
            end
            SetCachedText("TopSense", top.SenseText, senseStr)
            SetCachedColor("TopSenseCol", top.SenseText, senseCol)
        end
    end

    -- Top-right Camcorder REC clock
    local ctrl = State.Widgets.Controls
    if ctrl then
        SetWidgetVisible("Controls", ctrl.Root, not ended)
        SetCachedText("CtrlTime", ctrl.TimerText, FormatClockHMS(info.elapsed or 0.0))
        local pulse = (math.floor(now * 2.0) % 2 == 0) and 0.95 or 0.35
        SetCachedOpacity("CtrlRecDot", ctrl.RecDot, pulse)
    end

    -- Abilities bar
    local ab = State.Widgets.Abilities
    if ab then
        SetWidgetVisible("Abilities", ab.Root, not ended)
        UpdateAbilitySlot("TP", ab.Tp, info.cdTeleport, Config.ABILITIES.TELEPORT_COOLDOWN, false)
        UpdateAbilitySlot("DR", ab.Dr, info.cdDread,    Config.ABILITIES.DREAD_COOLDOWN,    info.dreadActive == true)
        UpdateAbilitySlot("TR", ab.Tr, info.cdTerrify,  Config.ABILITIES.TERRIFY_COOLDOWN,  false)
        if ab.Hm then
            local hmEq = (info.hammerEquipped == true)
            if not hmEq then
                SetCachedText("HM_ST", ab.Hm.Status, "STOWED")
                SetCachedColor("HM_STC", ab.Hm.Status, UITheme.COLORS.ASH)
                if ab.Hm.Gauge then
                    ab.Hm.Gauge:SetPercent(0.0)
                    ab.Hm.Gauge:SetColor(UITheme.COLORS.ASH)
                end
                if Logger.IsValidObj(ab.Hm.BgImg) and State.LastTexts["_cbg_HM"] ~= UITheme.COLORS.DIM then
                    State.LastTexts["_cbg_HM"] = UITheme.COLORS.DIM
                    pcall(function() ab.Hm.BgImg:SetColorAndOpacity(UITheme.COLORS.DIM) end)
                end
            else
                local cd = tonumber(info.cdHammer) or 0.0
                local cdMax = tonumber(info.hammerCooldownMax) or (Config.HAMMER.SWING_COOLDOWN or 0.48)
                local ready = (cd <= 0.05)
                local frac = ready and 1.0 or (1.0 - Bridge.Clamp(cd / math.max(0.01, cdMax), 0.0, 1.0))
                SetCachedText("HM_ST", ab.Hm.Status, ready and "ARMED" or string.format("%.1fs", cd))
                SetCachedColor("HM_STC", ab.Hm.Status, ready and UITheme.COLORS.AMBER or UITheme.COLORS.CRIMSON_SOFT)
                if ab.Hm.Gauge then
                    ab.Hm.Gauge:SetPercent(frac)
                    ab.Hm.Gauge:SetColor(ready and UITheme.COLORS.AMBER or UITheme.COLORS.CRIMSON)
                end
                if Logger.IsValidObj(ab.Hm.BgImg) and State.LastTexts["_cbg_HM"] ~= UITheme.COLORS.CRIMSON then
                    State.LastTexts["_cbg_HM"] = UITheme.COLORS.CRIMSON
                    pcall(function() ab.Hm.BgImg:SetColorAndOpacity(UITheme.COLORS.CRIMSON) end)
                end
            end
        end
        if ab.FreeCam then
            SetWidgetVisible("AbilFC", ab.FreeCam, info.freeCam == true)
        end
    end

    if State.Widgets.Ambient and State.Widgets.Ambient.Crosshair then
        SetWidgetVisible("HammerCrosshair", State.Widgets.Ambient.Crosshair, (not ended) and (info.hammerEquipped == true))
    end

    -- Ambient camcorder frame kept clean & glitch-free even at high Fear / close pursuit
    local amb = State.Widgets.Ambient
    if amb then
        SetWidgetVisible("AmbCam", amb.CamFrame, not ended)
        SetWidgetVisible("AmbVig", amb.Vignette, not ended)
        SetCachedOpacity("AmbVig", amb.Vignette, 0.06)
        SetWidgetVisible("AmbTL", amb.TendrilL, false)
        SetWidgetVisible("AmbTR", amb.TendrilR, false)
    end

    -- Notice Toast with smooth fade in/out
    local toast = State.Widgets.Toast
    if toast then
        local showToast = not ended and (now < State.ToastExpiresAt) and (State.ToastText ~= "")
        SetWidgetVisible("Toast", toast.Root, showToast)
        if showToast then
            SetCachedText("Toast", toast.Text, State.ToastText)
            local isWarn = string.find(State.ToastText, "cooldown", 1, true)
                or string.find(State.ToastText, "Blocked", 1, true)
                or string.find(State.ToastText, "failed", 1, true)
                or string.find(State.ToastText, "Terrified", 1, true)
            SetCachedColor("ToastC", toast.Text, isWarn and UITheme.COLORS.CRIMSON_SOFT or UITheme.COLORS.BONE)

            local elapsedT = now - (State.ToastStartAt or now)
            local remT = State.ToastExpiresAt - now
            local op = 1.0
            if elapsedT < 0.16 then
                op = Bridge.Clamp(elapsedT / 0.16, 0.1, 1.0)
            elseif remT < 0.40 then
                op = Bridge.Clamp(remT / 0.40, 0.0, 1.0)
            end
            SetCachedOpacity("ToastO", toast.Root, op)
        end
    end

    -- Survivor Telemetry Dossier (Tab / F1)
    local dbg = State.Widgets.DebugPanel
    if dbg then
        local showDbg = State.DebugVisible and (not ended)
        SetWidgetVisible("DebugPanel", dbg.Root, showDbg)
        if showDbg then
            local fear = Bridge.Clamp(info.fear or 0.0, 0.0, 100.0)
            local stam = Bridge.Clamp(info.stamina or 100.0, 0.0, 100.0)
            if dbg.FearGauge then dbg.FearGauge:SetPercent(fear / 100.0) end
            if dbg.StaminaGauge then dbg.StaminaGauge:SetPercent(stam / 100.0) end

            local dst = info.dest or { X = 0, Y = 0, Z = 0 }
            SetCachedText("DebugBody", dbg.BodyText, string.format(
                "AI State   : %s   |   Human LOS : %s\n" ..
                "Fear / Stam: %.1f / 100   |   %.0f%%\n" ..
                "Goal       : %s\n" ..
                "Objectives : %d / %d   (Known: %d)\n" ..
                "Distance   : %.1f m\n" ..
                "Dest (XYZ) : (%.0f, %.0f, %.0f)\n" ..
                "Nav State  : %s\n" ..
                "Transition : %s\n" ..
                "Perf       : %.0f FPS   (mod %.2f ms)",
                tostring(info.aiState or "Init"), info.hasLOS and "VISIBLE" or "HIDDEN",
                fear, stam,
                tostring(info.goal or "-"),
                info.pagesCollected or 0, info.pagesTotal or 8, info.knownPages or 0,
                (info.distanceCm or 0.0) / 100.0,
                dst.X or 0, dst.Y or 0, dst.Z or 0,
                tostring(info.navState or "-"),
                tostring(info.lastReason or "-"),
                info.fps or 0.0, info.tickMs or 0.0
            ))
        end
    end

    -- Authentic End Screen
    local eb = State.Widgets.EndBanner
    if eb then
        SetWidgetVisible("EndBanner", eb.Root, ended, true)
        if not ended then
            State.LastEndWinner = ""
        else
            local d = info.endDetails
            local isSlenderWin = (info.winner == "SLENDER_WIN")
            if State.LastEndWinner ~= info.winner then
                State.LastEndWinner = info.winner
                SetCachedColor("EndTitleCol", eb.Title, isSlenderWin and UITheme.COLORS.CRIMSON or UITheme.COLORS.BONE)
                if Logger.IsValidObj(eb.WmImg) then
                    local sketchKey = isSlenderWin and "SKETCH_SLENDER" or "SKETCH_ALT"
                    UITheme.ApplyImageTexture(eb.WmImg, UITheme.GetTex(sketchKey))
                end
            end

            local endMk = tostring(info.mapKey or "EIGHT_PAGES") .. "|" .. tostring(info.mapIconPath or "")
            if endMk ~= State.LastEndMapKey then
                State.LastEndMapKey = endMk
                if Logger.IsValidObj(eb.ChapterImg) then
                    local mapTex = nil
                    if info.mapIconPath and UITheme.GetDynamicTexture then
                        mapTex = UITheme.GetDynamicTexture(info.mapIconPath)
                    end
                    if not Logger.IsValidObj(mapTex) then
                        local mk = tostring(info.mapKey or "EIGHT_PAGES")
                        local iconKey = (mk == "PROLOGUE" or mk == "PROLOGUE_YARD") and "ICON_PROLOGUE" or "ICON_EIGHT_PAGES"
                        mapTex = UITheme.GetTex(iconKey)
                    end
                    UITheme.ApplyImageTexture(eb.ChapterImg, mapTex, UITheme.COLORS.WHITE)
                end
            end

            local chapTitle = SanitizeAscii(string.upper(tostring(info.mapTitle or info.mapKey or "THE EIGHT PAGES")))
            local stageName = SanitizeAscii(string.upper(tostring((d and d.stageName) or info.huntStageName or "STAGE I: STALKING")))
            if eb.ChapterHdr then
                SetCachedText("EndChapHdr", eb.ChapterHdr, string.format("CHAPTER: %s   |   %s", chapTitle, stageName))
            end

            local titleStr  = SanitizeAscii((d and d.title) or (isSlenderWin and "SLENDERMAN VICTORY" or "HUMAN SURVIVED"))
            local reasonStr = SanitizeAscii((d and d.reason) or "")
            SetCachedText("EndTitle", eb.Title, titleStr)
            SetCachedText("EndReason", eb.Reason, reasonStr)

            local rankLetter = SanitizeAscii(tostring((d and d.rankLetter) or (isSlenderWin and "A" or "D")))
            local rankTitle  = SanitizeAscii(string.upper(tostring((d and d.rankTitle) or (isSlenderWin and "SHADOW STALKER" or "PREY ESCAPED"))))
            local scoreVal   = math.floor(tonumber(d and d.score) or 0)
            if eb.RankText then
                SetCachedText("EndRankTxt", eb.RankText, string.format(
                    "HUNTER RANK : %s [%s]  -  %d PTS",
                    rankLetter, rankTitle, scoreVal
                ))
                SetCachedColor("EndRankCol", eb.RankText, isSlenderWin and UITheme.COLORS.AMBER or UITheme.COLORS.ASH)
            end
            if Logger.IsValidObj(eb.RankBgImg) then
                local rBgKey = isSlenderWin and "W" or "L"
                if State.LastTexts["_rankbg"] ~= rBgKey then
                    State.LastTexts["_rankbg"] = rBgKey
                    pcall(function()
                        eb.RankBgImg:SetColorAndOpacity(isSlenderWin
                            and { R = 0.14, G = 0.04, B = 0.04, A = 0.88 }
                            or  { R = 0.07, G = 0.07, B = 0.08, A = 0.88 })
                    end)
                end
            end

            local peakFear   = Bridge.Clamp((d and d.peakFear) or info.fear or 0.0, 0.0, 100.0)
            local totalObj   = math.max(1, tonumber(d and d.total) or tonumber(info.pagesTotal) or 8)
            local pagesFound = math.max(0, tonumber(d and d.pages) or tonumber(info.pagesCollected) or 0)
            local prevented  = (d and d.prevented ~= nil) and tonumber(d.prevented) or math.max(0, totalObj - pagesFound)
            prevented = math.max(0, math.min(totalObj, prevented))

            if eb.FearBar then
                eb.FearBar:SetPercent(peakFear / 100.0)
                eb.FearBar:SetColor(UITheme.COLORS.CRIMSON)
            end
            if eb.FearVal then
                SetCachedText("EndFearVal", eb.FearVal, string.format("%.0f%%", peakFear))
            end
            if eb.DenyBar then
                eb.DenyBar:SetPercent(prevented / totalObj)
                eb.DenyBar:SetColor(isSlenderWin and UITheme.COLORS.AMBER or UITheme.COLORS.BONE)
            end
            if eb.DenyVal then
                SetCachedText("EndDenyVal", eb.DenyVal, string.format("%d / %d DENIED", prevented, totalObj))
                SetCachedColor("EndDenyValCol", eb.DenyVal, isSlenderWin and UITheme.COLORS.AMBER or UITheme.COLORS.BONE)
            end

            if d then
                local closestVal = tonumber(d.closestDistM or info.closestDistM)
                local closestStr = (closestVal and closestVal < 900.0) and string.format("%.1f m", closestVal) or "--.- m"
                local leftCol = string.format(
                    "MATCH DURATION   : %.1f s\n" ..
                    "OBJECTIVES FOUND : %d / %d\n" ..
                    "PEAK HUMAN FEAR  : %.0f / 100\n" ..
                    "TELEPORTS USED   : %d",
                    d.elapsed or 0.0, pagesFound, totalObj, peakFear, tonumber(d.tpUsed) or 0
                )
                local rightCol = string.format(
                    "CLOSEST STALK : %s\n" ..
                    "HUNT STAGE    : %s\n" ..
                    "AMBUSH SHOCKS : %d\n" ..
                    "TERRIFY       : %d  |  INTERCEPTS : %d",
                    closestStr, stageName, tonumber(d.ambushes) or 0, tonumber(d.scares) or 0, tonumber(d.intercepts) or 0
                )
                SetCachedText("EndStats", eb.Stats, leftCol)
                if eb.StatsR then
                    SetCachedText("EndStatsR", eb.StatsR, rightCol)
                end
            else
                SetCachedText("EndStats", eb.Stats, SanitizeAscii(tostring(info.endSummary or info.winner)))
                if eb.StatsR then
                    SetCachedText("EndStatsR", eb.StatsR, "")
                end
            end

            local showNext = isSlenderWin and (info.canPlayNext == true)
            if eb.BtnNext then
                SetWidgetVisible("EndBtnNext", eb.BtnNext, showNext, true)
            end
            if eb.NextSpacer then
                SetWidgetVisible("EndNextSp", eb.NextSpacer, showNext, false)
            end
            if eb.HintText then
                local hintStr = showNext
                    and "[ENTER] NEXT LEVEL  |  [F8] RESTART  |  [M / BACKSPACE] MAIN MENU"
                    or  "[F8] RESTART  |  [M / BACKSPACE] MAIN MENU"
                SetCachedText("EndHintTxt", eb.HintText, hintStr)
            end
            if eb.UnlockNote then
                local noteStr = ""
                local noteCol = UITheme.COLORS.ASH
                if isSlenderWin then
                    if info.nextMapTitle then
                        noteStr = (info.newlyUnlocked and "NEXT CHAPTER UNLOCKED : " or "NEXT CHAPTER READY : ")
                            .. SanitizeAscii(string.upper(tostring(info.nextMapTitle)))
                        noteCol = UITheme.COLORS.AMBER
                    else
                        noteStr = "CAMPAIGN COMPLETE - ALL CHAPTERS CLEARED"
                        noteCol = UITheme.COLORS.AMBER
                    end
                else
                    noteStr = "DEFEAT - NEXT CHAPTER REMAINS LOCKED"
                    noteCol = UITheme.COLORS.CRIMSON_SOFT
                end
                SetCachedText("EndUnlockNote", eb.UnlockNote, noteStr)
                SetCachedColor("EndUnlockCol", eb.UnlockNote, noteCol)
            end
        end
    end
end

return Overlay
