-- PlayAsSlender Authentic Game Asset Theme & UMG Builders
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local UITheme = {}

UITheme.COLORS = {
    BONE         = { R = 0.92, G = 0.90, B = 0.85, A = 1.0 },
    ASH          = { R = 0.72, G = 0.70, B = 0.66, A = 0.95 },
    DIM          = { R = 0.48, G = 0.47, B = 0.45, A = 0.90 },
    CRIMSON      = { R = 0.84, G = 0.16, B = 0.16, A = 1.0 },
    CRIMSON_SOFT = { R = 0.92, G = 0.42, B = 0.38, A = 1.0 },
    AMBER        = { R = 0.90, G = 0.72, B = 0.34, A = 1.0 },
    PANEL_DARK   = { R = 0.04, G = 0.04, B = 0.05, A = 0.84 },
    WHITE        = { R = 1.00, G = 1.00, B = 1.00, A = 1.0 },
    TRANSPARENT  = { R = 0.00, G = 0.00, B = 0.00, A = 0.0 },
}

local KEYCAP_ALIASES = {
    LeftShift       = "shift_left",
    RightShift      = "shift_right",
    LeftControl     = "ctrl_left",
    RightControl    = "ctrl_right",
    LeftAlt         = "alt_left",
    RightAlt        = "alt_right",
    SpaceBar        = "space",
    Escape          = "esc",
    LeftMouseButton = "lmb",
    Tab             = "tab",
    Enter           = "enter",
    Delete          = "del",
    Insert          = "insert",
    End             = "end",
    Home            = "home",
    PageUp          = "pageup",
    PageDown        = "pagedown",
    BackSpace       = "backspace",
    CapsLock        = "capslock",
    ForwardSlash    = "forwardSlash",
    LeftBracket     = "leftbracket",
    RightBracket    = "rightbracket",
    Equals          = "plus",
    Tilde           = "tilda",
    Apostrophe      = "apostrophe",
    Comma           = "comma",
    Period          = "period",
    Semicolon       = "semicolon",
    Up              = "up",
    Down            = "down",
    Left            = "left",
    Right           = "right",
    RightMouseButton = "rmb",
    MiddleMouseButton = "cmb",
    MouseScrollUp   = "mw_up",
    MouseScrollDown = "mw_down",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
    Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
}

local Cache = {
    Initialized = false,
    Fonts       = {},
    Tex         = {},
    Mat         = {},
    Keycaps     = {},
    Classes     = {},
}

function UITheme.Reset()
    Cache.Initialized = false
    Cache.Fonts       = {}
    Cache.Tex         = {}
    Cache.Mat         = {}
    Cache.Keycaps     = {}
    Cache.Classes     = {}
end

local function LoadCached(bucket, key, path)
    local cur = bucket[key]
    if cur == false then return nil end
    if Logger.IsValidObj(cur) then return cur end
    if not path or path == "" then return nil end
    local obj = Bridge.LoadOrFindAsset(path)
    if Logger.IsValidObj(obj) then
        bucket[key] = obj
        return obj
    end
    bucket[key] = false
    return nil
end

function UITheme.GetClass(clsPath)
    local c = Cache.Classes[clsPath]
    if Logger.IsValidObj(c) then return c end
    c = Bridge.GetClass(clsPath)
    if Logger.IsValidObj(c) then
        Cache.Classes[clsPath] = c
        return c
    end
    return nil
end

function UITheme.Init()
    UITheme.Reset()
    local A = Config.UI_ASSETS

    -- Fonts
    LoadCached(Cache.Fonts, "HORROR",    A.FONT_HORROR)
    LoadCached(Cache.Fonts, "CAMCORDER", A.FONT_CAMCORDER)
    LoadCached(Cache.Fonts, "BODY",      A.FONT_BODY)

    -- Fallback harvest from live native UI if any font was deferred
    if not Logger.IsValidObj(Cache.Fonts.HORROR) then
        for _, tb in ipairs(FindAllOf("TextBlock") or {}) do
            if Logger.IsValidObj(tb) then
                local ok = pcall(function()
                    local fo = tb.Font and tb.Font.FontObject
                    if Logger.IsValidObj(fo) then
                        local fn = Logger.SafeFullName(fo)
                        if string.find(fn, "dbehavior_Font", 1, true) then
                            Cache.Fonts.HORROR = fo
                        elseif string.find(fn, "pixelated_Font", 1, true) and not Logger.IsValidObj(Cache.Fonts.CAMCORDER) then
                            Cache.Fonts.CAMCORDER = fo
                        end
                    end
                end)
                if ok and Logger.IsValidObj(Cache.Fonts.HORROR) and Logger.IsValidObj(Cache.Fonts.CAMCORDER) then
                    break
                end
            end
        end
    end

    -- Textures
    LoadCached(Cache.Tex, "BUTTON",          A.TEX_BUTTON)
    LoadCached(Cache.Tex, "BUTTON_ALT",      A.TEX_BUTTON_ALT)
    LoadCached(Cache.Tex, "SLIDER_BG",       A.TEX_SLIDER_BG)
    LoadCached(Cache.Tex, "SLIDER_FILL",     A.TEX_SLIDER_FILL)
    LoadCached(Cache.Tex, "TENDRIL_1",       A.TEX_TENDRIL_1)
    LoadCached(Cache.Tex, "TENDRIL_2",       A.TEX_TENDRIL_2)
    LoadCached(Cache.Tex, "SKETCH_SLENDER",  A.TEX_SKETCH_SLENDER)
    LoadCached(Cache.Tex, "SKETCH_ALT",      A.TEX_SKETCH_ALT)
    LoadCached(Cache.Tex, "SKETCH_TERRIFY",  A.TEX_SKETCH_TERRIFY)
    LoadCached(Cache.Tex, "ICON_PROLOGUE",   A.TEX_ICON_PROLOGUE)
    LoadCached(Cache.Tex, "ICON_EIGHT_PAGES",A.TEX_ICON_EIGHT_PAGES)
    LoadCached(Cache.Tex, "ICON_PAGE",       A.TEX_ICON_PAGE)
    LoadCached(Cache.Tex, "ICON_SPINNER",    A.TEX_ICON_SPINNER)
    LoadCached(Cache.Tex, "CAMERA_FRAME",    A.TEX_CAMERA_FRAME)
    LoadCached(Cache.Tex, "REC_BADGE",       A.TEX_REC_BADGE)
    LoadCached(Cache.Tex, "REC_DOT",         A.TEX_REC_DOT)
    LoadCached(Cache.Tex, "FADE_RECT",       A.TEX_FADE_RECT)
    LoadCached(Cache.Tex, "RADIAL_GRADIENT", A.TEX_RADIAL_GRADIENT)

    -- Materials (UserInterface Domain = 5)
    LoadCached(Cache.Mat, "GAME_COMPLETE_BG", A.MAT_GAME_COMPLETE_BG)
    LoadCached(Cache.Mat, "SLENDER_BTN",      A.MAT_SLENDER_BTN)
    LoadCached(Cache.Mat, "SLENDER_BTN_HOV",  A.MAT_SLENDER_BTN_HOVER)
    LoadCached(Cache.Mat, "VIGNETTE",         A.MAT_VIGNETTE)
    LoadCached(Cache.Mat, "BACKDROP_FADE",    A.MAT_BACKDROP_FADE)
    LoadCached(Cache.Mat, "SUBTITLE_LINE",    A.MAT_SUBTITLE_LINE)

    Cache.Initialized = true
end

function UITheme.GetTex(key) return (Cache.Tex[key] and Cache.Tex[key] ~= false) and Cache.Tex[key] or nil end
function UITheme.GetMat(key) return (Cache.Mat[key] and Cache.Mat[key] ~= false) and Cache.Mat[key] or nil end

function UITheme.GetDynamicTexture(assetPath)
    if not assetPath or assetPath == "" then return nil end
    return LoadCached(Cache.Tex, "dyn_" .. tostring(assetPath), assetPath)
end

function UITheme.GetKeycapTexture(keyName)
    if not keyName or keyName == "" then return nil end
    if Cache.Keycaps[keyName] ~= nil then
        return Cache.Keycaps[keyName] or nil
    end
    local token = KEYCAP_ALIASES[keyName] or string.lower(tostring(keyName))
    local path = string.format("%s%s.black_%s", Config.UI_ASSETS.KEYCAP_PREFIX, token, token)
    local tex = Bridge.LoadOrFindAsset(path)
    if Logger.IsValidObj(tex) then
        Cache.Keycaps[keyName] = tex
        return tex
    end
    Cache.Keycaps[keyName] = false
    return nil
end

function UITheme.MakeSlateColor(c)
    return {
        SpecifiedColor = { R = c.R or 1.0, G = c.G or 1.0, B = c.B or 1.0, A = c.A ~= nil and c.A or 1.0 },
        ColorUseRule   = 0,
    }
end

function UITheme.ApplyFont(tb, role, size, letterSpacing, colorTbl, outlineSize)
    if not Logger.IsValidObj(tb) then return end
    local A = Config.UI_ASSETS
    local fObj, tf = Cache.Fonts.BODY, A.FONT_BODY_TF
    if role == "HORROR" then
        fObj = Logger.IsValidObj(Cache.Fonts.HORROR) and Cache.Fonts.HORROR or Cache.Fonts.BODY
        tf   = Logger.IsValidObj(Cache.Fonts.HORROR) and A.FONT_HORROR_TYPEFACE or A.FONT_BODY_TF
    elseif role == "CAMCORDER" then
        fObj = Logger.IsValidObj(Cache.Fonts.CAMCORDER) and Cache.Fonts.CAMCORDER or Cache.Fonts.BODY
        tf   = Logger.IsValidObj(Cache.Fonts.CAMCORDER) and A.FONT_CAMCORDER_TF or A.FONT_BODY_TF
    elseif role == "BODY_BOLD" then
        fObj = Cache.Fonts.BODY
        tf   = A.FONT_BODY_BOLD_TF
    end

    if Logger.IsValidObj(fObj) then
        pcall(function()
            tb:SetFont({
                FontObject       = fObj,
                TypefaceFontName = Bridge.FName(tf),
                Size             = size or 16.0,
                LetterSpacing    = letterSpacing or 0,
                OutlineSettings  = {
                    OutlineSize  = outlineSize or 1,
                    OutlineColor = { R = 0.0, G = 0.0, B = 0.0, A = 0.90 },
                },
            })
        end)
    end
    local col = colorTbl or UITheme.COLORS.BONE
    pcall(function()
        tb:SetColorAndOpacity(UITheme.MakeSlateColor(col))
        tb:SetShadowOffset({ X = 1.5, Y = 1.5 })
        tb:SetShadowColorAndOpacity({ R = 0.0, G = 0.0, B = 0.0, A = 0.92 })
    end)
end

function UITheme.CreateText(wt, name, text, role, size, colorTbl, letterSpacing, outlineSize)
    local tbCls = UITheme.GetClass("/Script/UMG.TextBlock")
    if not tbCls or not Logger.IsValidObj(wt) then return nil end
    local tb = StaticConstructObject(tbCls, wt, Bridge.FName(name))
    if not Logger.IsValidObj(tb) then return nil end
    UITheme.ApplyFont(tb, role, size, letterSpacing, colorTbl, outlineSize)
    pcall(function() tb:SetAutoWrapText(false) end)
    if text ~= nil then
        pcall(function() tb:SetText(FText(tostring(text))) end)
    end
    return tb
end

function UITheme.ApplyImageTexture(img, tex, tint)
    if not Logger.IsValidObj(img) then return false end
    return pcall(function()
        if Logger.IsValidObj(tex) then
            img:SetBrushFromTexture(tex, false)
            img:SetColorAndOpacity(tint or UITheme.COLORS.WHITE)
        else
            img:SetColorAndOpacity(UITheme.COLORS.TRANSPARENT)
        end
    end)
end

function UITheme.CreateImage(wt, name, asset, tint, isMaterial)
    local imCls = UITheme.GetClass("/Script/UMG.Image")
    if not imCls or not Logger.IsValidObj(wt) or not Logger.IsValidObj(asset) then return nil end
    local img = StaticConstructObject(imCls, wt, Bridge.FName(name))
    if not Logger.IsValidObj(img) then return nil end
    local ok = pcall(function()
        if isMaterial then
            img:SetBrushFromMaterial(asset)
        else
            img:SetBrushFromTexture(asset, false)
        end
        img:SetColorAndOpacity(tint or UITheme.COLORS.WHITE)
    end)
    if ok then return img end
    return nil
end

function UITheme.CreateSizedImage(wt, name, asset, widthPx, heightPx, tint, isMaterial)
    local sbCls = UITheme.GetClass("/Script/UMG.SizeBox")
    if not sbCls or not Logger.IsValidObj(wt) then return nil, nil end
    local img = UITheme.CreateImage(wt, name .. "_IMG", asset, tint, isMaterial)
    if not Logger.IsValidObj(img) then return nil, nil end
    local sb = StaticConstructObject(sbCls, wt, Bridge.FName(name .. "_SB"))
    if not Logger.IsValidObj(sb) then return nil, nil end
    pcall(function()
        sb:SetWidthOverride(widthPx)
        sb:SetHeightOverride(heightPx)
        sb:SetContent(img)
    end)
    return sb, img
end

function UITheme.CreateSpacer(wt, name, widthPx, heightPx)
    local spCls = UITheme.GetClass("/Script/UMG.Spacer")
    if not spCls or not Logger.IsValidObj(wt) then return nil end
    local sp = StaticConstructObject(spCls, wt, Bridge.FName(name))
    if not Logger.IsValidObj(sp) then return nil end
    pcall(function() sp:SetSize({ X = widthPx or 8.0, Y = heightPx or 4.0 }) end)
    return sp
end

function UITheme.CreateKeycapBadge(wt, name, keyName, sizePx)
    local sz = sizePx or 24.0
    local tex = UITheme.GetKeycapTexture(keyName)
    if Logger.IsValidObj(tex) then
        local sb = UITheme.CreateSizedImage(wt, name, tex, sz, sz)
        if sb then return sb end
    end
    -- Keys without an icon still show their configured name.
    local sbCls = UITheme.GetClass("/Script/UMG.SizeBox")
    if not sbCls then return nil end
    local tb = UITheme.CreateText(wt, name .. "_TXT", "[" .. tostring(keyName or "?") .. "]", "BODY_BOLD", math.max(12.0, sz * 0.51), UITheme.COLORS.BONE, 0, 1)
    if not tb then return nil end
    local sb = StaticConstructObject(sbCls, wt, Bridge.FName(name .. "_SB"))
    if not Logger.IsValidObj(sb) then return tb end
    sb:SetMinDesiredHeight(sz)
    sb:SetMinDesiredWidth(sz)
    local slot = sb:SetContent(tb)
    if Logger.IsValidObj(slot) then
        slot:SetHorizontalAlignment(2)
        slot:SetVerticalAlignment(2)
    end
    return sb
end

function UITheme.CreateAccentLine(wt, name, widthPx, heightPx, tint)
    local sbCls = UITheme.GetClass("/Script/UMG.SizeBox")
    if not sbCls or not Logger.IsValidObj(wt) then return nil end
    local sb = StaticConstructObject(sbCls, wt, Bridge.FName(name .. "_SB"))
    local mat = UITheme.GetMat("SUBTITLE_LINE")
    local tex = UITheme.GetTex("SLIDER_FILL") or UITheme.GetTex("FADE_RECT")
    local img = UITheme.CreateImage(wt, name .. "_LINE", mat or tex, tint or { R = 0.85, G = 0.22, B = 0.20, A = 0.85 }, mat ~= nil)
    if Logger.IsValidObj(sb) and Logger.IsValidObj(img) then
        pcall(function()
            if widthPx and widthPx > 0 then sb:SetWidthOverride(widthPx) end
            sb:SetHeightOverride(heightPx or 2.0)
            sb:SetContent(img)
        end)
        return sb, img
    end
    return nil, nil
end

-- Creates an Overlay backdrop container with native texture/material fill + optional accent divider + padded content holder
function UITheme.CreateBackdropContainer(wt, name, bgAsset, tint, isMaterial, padL, padT, padR, padB)
    local ovCls = UITheme.GetClass("/Script/UMG.Overlay")
    local bdCls = UITheme.GetClass("/Script/UMG.Border")
    if not ovCls or not bdCls or not Logger.IsValidObj(wt) then return nil end

    local ov = StaticConstructObject(ovCls, wt, Bridge.FName(name .. "_OV"))
    local bgImg = UITheme.CreateImage(wt, name .. "_BG", bgAsset, tint or UITheme.COLORS.PANEL_DARK, isMaterial == true)
    local contentHolder = StaticConstructObject(bdCls, wt, Bridge.FName(name .. "_HOLD"))
    if not Logger.IsValidObj(ov) or not Logger.IsValidObj(contentHolder) then
        return nil
    end

    if bgImg then
        local sBg = ov:AddChildToOverlay(bgImg)
        if Logger.IsValidObj(sBg) then
            sBg:SetHorizontalAlignment(0)
            sBg:SetVerticalAlignment(0)
        end
    end

    pcall(function()
        contentHolder:SetBrushColor(UITheme.COLORS.TRANSPARENT)
        contentHolder:SetPadding({ Left = padL or 14.0, Top = padT or 10.0, Right = padR or 14.0, Bottom = padB or 10.0 })
        local sC = ov:AddChildToOverlay(contentHolder)
        if sC then
            sC:SetHorizontalAlignment(0)
            sC:SetVerticalAlignment(0)
        end
    end)

    return {
        Root   = ov,
        BgImg  = bgImg,
        Holder = contentHolder,
        SetContent = function(self, child)
            if Logger.IsValidObj(self.Holder) and Logger.IsValidObj(child) then
                pcall(function() self.Holder:SetContent(child) end)
            end
        end,
    }
end

function UITheme.CreateSlenderGauge(wt, name, widthPx, heightPx, fillTint)
    local sbCls = UITheme.GetClass("/Script/UMG.SizeBox")
    local pbCls = UITheme.GetClass("/Script/UMG.ProgressBar")
    local track = UITheme.GetTex("SLIDER_BG")
    local fill = UITheme.GetTex("SLIDER_FILL")
    if not sbCls or not pbCls or not track or not fill or not Logger.IsValidObj(wt) then return nil end

    local box = StaticConstructObject(sbCls, wt, Bridge.FName(name .. "_SB"))
    local bar = StaticConstructObject(pbCls, wt, Bridge.FName(name .. "_Bar"))
    if not Logger.IsValidObj(box) or not Logger.IsValidObj(bar) then
        return nil
    end

    local size = { X = widthPx, Y = heightPx }
    local ok = Logger.SafeCall("Creating game-textured meter " .. name, function()
        bar.WidgetStyle = {
            BackgroundImage = {
                ResourceObject = track, DrawAs = 3, ImageSize = size,
                TintColor = UITheme.MakeSlateColor({ R = 0.16, G = 0.16, B = 0.16, A = 1.0 }),
            },
            FillImage = {
                ResourceObject = fill, DrawAs = 3, ImageSize = size,
                TintColor = UITheme.MakeSlateColor(UITheme.COLORS.WHITE),
            },
        }
        bar.BarFillStyle = 0 -- Mask the game texture at the current percentage.
        bar.BarFillType = 0 -- LeftToRight
        bar.BorderPadding = { X = 0.0, Y = 0.0 }
        bar:SetFillColorAndOpacity(fillTint or UITheme.COLORS.BONE)
        bar:SetPercent(0.0)
        box:SetWidthOverride(widthPx)
        box:SetHeightOverride(heightPx)
        box:SetContent(bar)
    end)
    if not ok then return nil end

    local lastPct = 0.0
    local lastColor = fillTint or UITheme.COLORS.BONE
    return {
        Root = box,
        SetPercent = function(self, frac)
            local percent = math.floor(Bridge.Clamp(frac, 0.0, 1.0) * 100.0 + 0.5) / 100.0
            if percent == lastPct then return end
            bar:SetPercent(percent)
            lastPct = percent
        end,
        SetColor = function(self, col)
            if col == lastColor then return end
            bar:SetFillColorAndOpacity(col)
            lastColor = col
        end,
    }
end

return UITheme
