-- PlayAsSlender UE 5.3 Reflection Bridge & Pure-Lua Vector Math
local UEHelpers = require("UEHelpers")
local Logger    = require("logger")

local Bridge = {}

-- Cached static objects / FNames (safe across levels, refreshed if invalid)
local KeyFNameCache = {}
local ClassCache    = {}
local AssetCache    = {}

local ZERO_COLOR = { R = 0.0, G = 0.0, B = 0.0, A = 0.0 }
local EMPTY_ACTORS = {}

function Bridge.ClearWorldCaches()
    ClassCache = {}
    AssetCache = {}
end

function Bridge.LoadOrFindAsset(path)
    local obj = AssetCache[path]
    if Logger.IsValidObj(obj) then return obj end
    obj = StaticFindObject(path)
    if not Logger.IsValidObj(obj) and type(LoadAsset) == "function" then
        pcall(function() obj = LoadAsset(path) end)
    end
    if Logger.IsValidObj(obj) then
        AssetCache[path] = obj
        return obj
    end
    return nil
end

function Bridge.GetClass(path)
    local c = ClassCache[path]
    if Logger.IsValidObj(c) then return c end
    c = StaticFindObject(path)
    if not Logger.IsValidObj(c) and type(LoadAsset) == "function" then
        pcall(function() c = LoadAsset(path) end)
    end
    if Logger.IsValidObj(c) then
        ClassCache[path] = c
        return c
    end
    return nil
end

function Bridge.GetAsset(path)
    return Bridge.LoadOrFindAsset(path)
end

function Bridge.GetObjAddr(obj)
    if not Logger.IsValidObj(obj) then return 0 end
    local ok, addr = pcall(function() return obj:GetAddress() end)
    return (ok and addr) and addr or 0
end

function Bridge.FName(str)
    local fn = KeyFNameCache[str]
    if fn ~= nil then return fn end
    fn = UEHelpers.FindOrAddFName(str)
    KeyFNameCache[str] = fn
    return fn
end

function Bridge.GetWorld()
    return UEHelpers.GetWorld()
end

function Bridge.GetPC()
    return UEHelpers.GetPlayerController()
end

function Bridge.GetHUD()
    local pc = Bridge.GetPC()
    if Logger.IsValidObj(pc) then
        return pc.MyHUD
    end
    return nil
end

function Bridge.GetGameMode()
    return UEHelpers.GetGameModeBase()
end

function Bridge.GetGameState()
    return UEHelpers.GetGameStateBase()
end

function Bridge.GetGameplayStatics()
    return UEHelpers.GetGameplayStatics()
end

function Bridge.GetKismetSystem()
    return UEHelpers.GetKismetSystemLibrary()
end

function Bridge.GetNavSysClass()
    return Bridge.GetClass("/Script/NavigationSystem.Default__NavigationSystemV1")
end

function Bridge.GetDeltaSeconds(world)
    local gs = Bridge.GetGameplayStatics()
    if Logger.IsValidObj(gs) and Logger.IsValidObj(world) then
        local ok, dt = pcall(function() return gs:GetWorldDeltaSeconds(world) end)
        if ok and type(dt) == "number" and dt > 0 and dt < 0.25 then
            return dt
        end
    end
    return 0.016
end

function Bridge.IsGamePaused(world)
    local gs = Bridge.GetGameplayStatics()
    if Logger.IsValidObj(gs) and Logger.IsValidObj(world) then
        local ok, paused = pcall(function() return gs:IsGamePaused(world) end)
        if ok then return paused == true end
    end
    return false
end

function Bridge.LoadLevel(world, mapPath)
    local gs = Bridge.GetGameplayStatics()
    if Logger.IsValidObj(gs) and Logger.IsValidObj(world) then
        local ok, err = pcall(function()
            gs:OpenLevel(world, Bridge.FName(mapPath), true, "")
        end)
        if not ok then
            Logger.Error("OpenLevel failed: " .. tostring(err))
        end
        return ok
    end
    return false
end

-- =========================================================
-- Input Wrappers
-- =========================================================
local KeyStructScratch = { KeyName = nil }
local MouseXKey = { KeyName = nil }
local MouseYKey = { KeyName = nil }

function Bridge.IsKeyDown(pc, keyName)
    if not Logger.IsValidObj(pc) then return false end
    KeyStructScratch.KeyName = Bridge.FName(keyName)
    local ok, res = pcall(function() return pc:IsInputKeyDown(KeyStructScratch) end)
    return ok and res == true
end

function Bridge.WasKeyJustPressed(pc, keyName)
    if not Logger.IsValidObj(pc) then return false end
    KeyStructScratch.KeyName = Bridge.FName(keyName)
    local ok, res = pcall(function() return pc:WasInputKeyJustPressed(KeyStructScratch) end)
    return ok and res == true
end

function Bridge.GetMouseDelta(pc)
    if not Logger.IsValidObj(pc) then return 0.0, 0.0 end
    if MouseXKey.KeyName == nil then
        MouseXKey.KeyName = Bridge.FName("MouseX")
        MouseYKey.KeyName = Bridge.FName("MouseY")
    end
    local okX, ax = pcall(function() return pc:GetInputAnalogKeyState(MouseXKey) end)
    local okY, ay = pcall(function() return pc:GetInputAnalogKeyState(MouseYKey) end)
    local dx = (okX and type(ax) == "number") and ax or 0.0
    local dy = (okY and type(ay) == "number") and ay or 0.0
    if dx ~= 0.0 or dy ~= 0.0 then
        return dx, dy
    end
    local outX, outY = {0.0}, {0.0}
    local okD = pcall(function() pc:GetInputMouseDelta(outX, outY) end)
    if okD then
        dx = tonumber(outX[1] or outX.DeltaX or 0.0) or 0.0
        dy = tonumber(outY[1] or outY.DeltaY or 0.0) or 0.0
    end
    return dx, dy
end

-- =========================================================
-- Pure-Lua Math & Vector Helpers (zero GC churn)
-- =========================================================
local DEG_TO_RAD = math.pi / 180.0
local RAD_TO_DEG = 180.0 / math.pi

function Bridge.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Bridge.Lerp(a, b, t)
    return a + (b - a) * t
end

function Bridge.NormalizeAngle(deg)
    deg = deg % 360.0
    if deg > 180.0 then deg = deg - 360.0 end
    return deg
end

function Bridge.LerpAngle(a, b, t)
    local diff = Bridge.NormalizeAngle(b - a)
    return a + diff * t
end

function Bridge.Dist(a, b)
    local dx = b.X - a.X
    local dy = b.Y - a.Y
    local dz = b.Z - a.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Bridge.Dist2D(a, b)
    local dx = b.X - a.X
    local dy = b.Y - a.Y
    return math.sqrt(dx * dx + dy * dy)
end

function Bridge.DistSq2D(a, b)
    local dx = b.X - a.X
    local dy = b.Y - a.Y
    return dx * dx + dy * dy
end

function Bridge.ForwardFromRot(pitchDeg, yawDeg)
    local pr = pitchDeg * DEG_TO_RAD
    local yr = yawDeg * DEG_TO_RAD
    local cp = math.cos(pr)
    return math.cos(yr) * cp, math.sin(yr) * cp, math.sin(pr)
end

function Bridge.RightFromYaw(yawDeg)
    local yr = yawDeg * DEG_TO_RAD
    return -math.sin(yr), math.cos(yr), 0.0
end

function Bridge.YawFromVec(dx, dy)
    return math.atan(dy, dx) * RAD_TO_DEG
end

function Bridge.RotatorFromVec(dx, dy, dz)
    local horiz = math.sqrt(dx * dx + dy * dy)
    local pitch = math.atan(dz, horiz > 0.001 and horiz or 0.001) * RAD_TO_DEG
    local yaw   = math.atan(dy, dx) * RAD_TO_DEG
    return { Pitch = pitch, Yaw = yaw, Roll = 0.0 }
end

function Bridge.RotToQuat(pitchDeg, yawDeg, rollDeg)
    local cy = math.cos((yawDeg or 0) * 0.5 * DEG_TO_RAD)
    local sy = math.sin((yawDeg or 0) * 0.5 * DEG_TO_RAD)
    local cp = math.cos((pitchDeg or 0) * 0.5 * DEG_TO_RAD)
    local sp = math.sin((pitchDeg or 0) * 0.5 * DEG_TO_RAD)
    local cr = math.cos((rollDeg or 0) * 0.5 * DEG_TO_RAD)
    local sr = math.sin((rollDeg or 0) * 0.5 * DEG_TO_RAD)
    return {
        W = cr * cp * cy + sr * sp * sy,
        X = cr * sp * sy - sr * cp * cy,
        Y = -cr * sp * cy - sr * cp * sy,
        Z = cr * cp * sy - sr * sp * cy,
    }
end

function Bridge.GetActorLoc(actor)
    if not Logger.IsValidObj(actor) then return nil end
    local ok, loc = pcall(function() return actor:K2_GetActorLocation() end)
    if ok and loc then
        return { X = loc.X, Y = loc.Y, Z = loc.Z }
    end
    return nil
end

function Bridge.GetActorRot(actor)
    if not Logger.IsValidObj(actor) then return nil end
    local ok, rot = pcall(function() return actor:K2_GetActorRotation() end)
    if ok and rot then
        return { Pitch = rot.Pitch, Yaw = rot.Yaw, Roll = rot.Roll }
    end
    return nil
end

-- =========================================================
-- Traces & Physics Queries
-- =========================================================
-- TraceChannel: 0 = Visibility, 1 = Camera (UE ETraceTypeQuery)
function Bridge.LineTrace(worldContext, startPos, endPos, ignoreActors, traceChannel, bTraceComplex)
    local ksl = Bridge.GetKismetSystem()
    if not Logger.IsValidObj(ksl) or not Logger.IsValidObj(worldContext) then
        return false, nil
    end
    local hit = {}
    local ok, didHit = pcall(function()
        return ksl:LineTraceSingle(
            worldContext,
            startPos,
            endPos,
            traceChannel or 0,
            bTraceComplex == true,
            ignoreActors or EMPTY_ACTORS,
            0, -- EDrawDebugTrace::None
            hit,
            true,
            ZERO_COLOR,
            ZERO_COLOR,
            0.0
        )
    end)
    if not ok or not didHit then
        return false, nil
    end
    local hitActor = nil
    pcall(function() hitActor = UEHelpers.GetActorFromHitResult(hit) end)
    local info = {
        Actor        = hitActor,
        Distance     = hit.Distance or Bridge.Dist(startPos, endPos),
        Location     = hit.Location and { X = hit.Location.X, Y = hit.Location.Y, Z = hit.Location.Z } or nil,
        ImpactPoint  = hit.ImpactPoint and { X = hit.ImpactPoint.X, Y = hit.ImpactPoint.Y, Z = hit.ImpactPoint.Z } or nil,
        ImpactNormal = hit.ImpactNormal and { X = hit.ImpactNormal.X, Y = hit.ImpactNormal.Y, Z = hit.ImpactNormal.Z } or nil,
    }
    return true, info
end

function Bridge.HasLineOfSight(worldContext, fromPos, toPos, ignoreActors, targetActor)
    local hit, info = Bridge.LineTrace(worldContext, fromPos, toPos, ignoreActors, 0, false)
    if not hit then
        return true, nil
    end
    if targetActor and Logger.IsValidObj(info.Actor) then
        local same = false
        pcall(function() same = (info.Actor:GetAddress() == targetActor:GetAddress()) end)
        if same then return true, info end
    end
    return false, info
end

function Bridge.IsRayBlockedDual(worldContext, startPos, endPos, ignoreActors)
    local hitV, infoV = Bridge.LineTrace(worldContext, startPos, endPos, ignoreActors, 0, false)
    if hitV then
        return true, infoV
    end
    local hitC, infoC = Bridge.LineTrace(worldContext, startPos, endPos, ignoreActors, 1, false)
    if hitC then
        return true, infoC
    end
    return false, nil
end

function Bridge.GroundTrace(worldContext, x, y, startZ, endZ, ignoreActors)
    local s = { X = x, Y = y, Z = startZ }
    local e = { X = x, Y = y, Z = endZ }
    local hit, info = Bridge.LineTrace(worldContext, s, e, ignoreActors, 0, false)
    if hit and info.ImpactPoint then
        return true, info.ImpactPoint.Z, info.ImpactNormal, info.Actor
    end
    return false, nil, nil, nil
end

-- =========================================================
-- Navigation System Wrappers
-- =========================================================
local NavExtentDefault = { X = 450.0, Y = 450.0, Z = 600.0 }

function Bridge.ProjectPointToNav(world, pos, extent)
    local navCls = Bridge.GetNavSysClass()
    if not Logger.IsValidObj(navCls) or not Logger.IsValidObj(world) then return false, nil end
    local outLoc = {}
    local ok, res = pcall(function()
        return navCls:K2_ProjectPointToNavigation(world, pos, outLoc, nil, nil, extent or NavExtentDefault)
    end)
    if ok and res and outLoc.X then
        return true, { X = outLoc.X, Y = outLoc.Y, Z = outLoc.Z }
    end
    return false, nil
end

function Bridge.GetRandomReachablePoint(world, origin, radius)
    local navCls = Bridge.GetNavSysClass()
    if not Logger.IsValidObj(navCls) or not Logger.IsValidObj(world) then return false, nil end
    local outLoc = {}
    local ok, res = pcall(function()
        return navCls:K2_GetRandomReachablePointInRadius(world, origin, outLoc, radius, nil, nil)
    end)
    if ok and res and outLoc.X then
        return true, { X = outLoc.X, Y = outLoc.Y, Z = outLoc.Z }
    end
    return false, nil
end

function Bridge.FindNavPathPoints(world, startPos, endPos, contextActor)
    local navCls = Bridge.GetNavSysClass()
    if not Logger.IsValidObj(navCls) or not Logger.IsValidObj(world) then return nil end
    local ok, navPath = pcall(function()
        return navCls:FindPathToLocationSynchronously(world, startPos, endPos, contextActor, nil)
    end)
    if not ok or not Logger.IsValidObj(navPath) then return nil end
    local pts = nil
    pcall(function() pts = navPath.PathPoints end)
    if not pts then return nil end
    local out = {}
    local okRead = pcall(function()
        if pts.ForEach then
            pts:ForEach(function(_, elem)
                local p = elem:get()
                if p and p.X then
                    out[#out + 1] = { X = p.X, Y = p.Y, Z = p.Z }
                end
            end)
        else
            for i = 1, #pts do
                local p = pts[i]
                if p and p.X then
                    out[#out + 1] = { X = p.X, Y = p.Y, Z = p.Z }
                end
            end
        end
    end)
    if not okRead or #out < 2 then return nil end
    return out
end

-- =========================================================
-- Spawning & Audio
-- =========================================================
function Bridge.SpawnActorDeferred(world, classPath, loc, yawDeg)
    local cls = type(classPath) == "string" and Bridge.GetClass(classPath) or classPath
    if not Logger.IsValidObj(cls) or not Logger.IsValidObj(world) then
        Logger.Warn("SpawnActor: invalid class or world for " .. tostring(classPath))
        return nil
    end
    local pos = loc or { X = 0.0, Y = 0.0, Z = 0.0 }
    local rot = { Pitch = 0.0, Yaw = yawDeg or 0.0, Roll = 0.0 }
    local ok, actor = pcall(function()
        return world:SpawnActor(cls, pos, rot)
    end)
    if ok and Logger.IsValidObj(actor) then
        pcall(function()
            actor:K2_SetActorLocationAndRotation(pos, rot, false, {}, true)
        end)
        return actor
    end
    Logger.Warn("SpawnActor failed for " .. tostring(classPath) .. " err=" .. tostring(actor))
    return nil
end

function Bridge.PlaySoundObj2D(world, soundObj, vol, pitch)
    local gs = Bridge.GetGameplayStatics()
    if Logger.IsValidObj(gs) and Logger.IsValidObj(world) and Logger.IsValidObj(soundObj) then
        local ok = pcall(function()
            gs:PlaySound2D(world, soundObj, vol or 0.8, pitch or 1.0, 0.0, nil, nil, true)
        end)
        return ok
    end
    return false
end

function Bridge.PlaySoundObjAtLocation(world, soundObj, loc, vol, pitch)
    local gs = Bridge.GetGameplayStatics()
    if Logger.IsValidObj(gs) and Logger.IsValidObj(world) and Logger.IsValidObj(soundObj) and loc then
        local ok = pcall(function()
            gs:PlaySoundAtLocation(world, soundObj, loc, { Pitch = 0, Yaw = 0, Roll = 0 }, vol or 1.0, pitch or 1.0, 0.0, nil, nil, nil, nil)
        end)
        return ok
    end
    return false
end

function Bridge.FindSoundByKeywords(cacheKey, keywords)
    if AssetCache[cacheKey] ~= nil then
        if AssetCache[cacheKey] == false then return nil end
        if Logger.IsValidObj(AssetCache[cacheKey]) then return AssetCache[cacheKey] end
    end
    local classes = { "SoundCue", "SoundWave", "SoundBase" }
    for _, clsName in ipairs(classes) do
        local list = FindAllOf(clsName) or {}
        for _, snd in ipairs(list) do
            if Logger.IsValidObj(snd) then
                local fname = Logger.SafeFullName(snd)
                for _, kw in ipairs(keywords) do
                    if string.find(fname, kw, 1, true) then
                        AssetCache[cacheKey] = snd
                        return snd
                    end
                end
            end
        end
    end
    AssetCache[cacheKey] = false
    return nil
end

function Bridge.PlaySound2D(world, soundPath, vol, pitch, fallbackKeywords)
    local snd = Bridge.GetAsset(soundPath)
    if not Logger.IsValidObj(snd) and fallbackKeywords then
        snd = Bridge.FindSoundByKeywords("fb_" .. tostring(soundPath), fallbackKeywords)
    end
    return Bridge.PlaySoundObj2D(world, snd, vol, pitch)
end

function Bridge.PlaySoundAtLocation(world, soundPath, loc, vol, pitch, fallbackKeywords)
    local snd = Bridge.GetAsset(soundPath)
    if not Logger.IsValidObj(snd) and fallbackKeywords then
        snd = Bridge.FindSoundByKeywords("fb_" .. tostring(soundPath), fallbackKeywords)
    end
    return Bridge.PlaySoundObjAtLocation(world, snd, loc, vol, pitch)
end

-- =========================================================
-- Viewport Metrics & World-to-Widget Screen Projection
-- =========================================================
local function SafeFinite(v)
    return type(v) == "number" and v == v and v > -1e7 and v < 1e7
end

function Bridge.GetViewportMetrics(world, pc)
    local vpW, vpH, dpiScale = 1920.0, 1080.0, 1.0
    local wll = Bridge.GetClass("/Script/UMG.Default__WidgetLayoutLibrary")
    if Logger.IsValidObj(wll) and Logger.IsValidObj(world) then
        pcall(function()
            local sz = wll:GetViewportSize(world)
            if sz and SafeFinite(sz.X) and SafeFinite(sz.Y) and sz.X > 100.0 and sz.Y > 100.0 then
                vpW = sz.X
                vpH = sz.Y
            end
        end)
        pcall(function()
            local sc = tonumber(wll:GetViewportScale(world))
            if sc and SafeFinite(sc) and sc > 0.1 and sc < 8.0 then
                dpiScale = sc
            end
        end)
    end
    if (vpW == 1920.0 and vpH == 1080.0) and Logger.IsValidObj(pc) then
        local outX, outY = {0}, {0}
        local okSz = pcall(function() pc:GetViewportSize(outX, outY) end)
        if okSz then
            local sx = tonumber(outX[1] or outX.SizeX)
            local sy = tonumber(outY[1] or outY.SizeY)
            if sx and sy and sx > 100 and sy > 100 then
                vpW = sx
                vpH = sy
            end
        end
    end
    return vpW, vpH, dpiScale
end

function Bridge.ProjectWorldToWidget(world, pc, worldPos, camPos, camRot, fovDeg)
    if not worldPos or not Logger.IsValidObj(pc) then
        return false, 0.0, 0.0, "invalid"
    end

    local vpW, vpH, dpiScale = Bridge.GetViewportMetrics(world, pc)
    local logW = vpW / dpiScale
    local logH = vpH / dpiScale

    -- Tier 1: WidgetLayoutLibrary::ProjectWorldLocationToWidgetPosition (DPI-scaled UMG coords)
    local wll = Bridge.GetClass("/Script/UMG.Default__WidgetLayoutLibrary")
    if Logger.IsValidObj(wll) and wll.ProjectWorldLocationToWidgetPosition then
        local outPos = { X = 0.0, Y = 0.0 }
        local okW, resW = pcall(function()
            return wll:ProjectWorldLocationToWidgetPosition(pc, worldPos, outPos, false)
        end)
        if okW and resW == true and outPos and SafeFinite(outPos.X) and SafeFinite(outPos.Y)
            and (math.abs(outPos.X) > 0.5 or math.abs(outPos.Y) > 0.5)
        then
            local onScr = (outPos.X >= -140.0 and outPos.X <= logW + 140.0 and outPos.Y >= -100.0 and outPos.Y <= logH + 100.0)
            return onScr, outPos.X, outPos.Y, "wll_widget"
        end
    end

    -- Tier 2: PlayerController::ProjectWorldLocationToScreen divided by ViewportScale
    if pc.ProjectWorldLocationToScreen then
        local outScr = { X = 0.0, Y = 0.0 }
        local okS, resS = pcall(function()
            return pc:ProjectWorldLocationToScreen(worldPos, outScr, false)
        end)
        if okS and resS == true and outScr and SafeFinite(outScr.X) and SafeFinite(outScr.Y)
            and (math.abs(outScr.X) > 0.5 or math.abs(outScr.Y) > 0.5)
        then
            local sx = outScr.X / dpiScale
            local sy = outScr.Y / dpiScale
            local onScr = (sx >= -140.0 and sx <= logW + 140.0 and sy >= -100.0 and sy <= logH + 100.0)
            return onScr, sx, sy, "pc_screen"
        end
    end

    -- Tier 3: Pure-Lua exact perspective projection (MaintainXFOV) from camera world transform
    if not camPos or not camRot then
        return false, 0.0, 0.0, "no_cam"
    end
    local fx, fy, fz = Bridge.ForwardFromRot(camRot.Pitch or 0.0, camRot.Yaw or 0.0)
    local rx, ry, rz = Bridge.RightFromYaw(camRot.Yaw or 0.0)
    local ux = fy * rz - fz * ry
    local uy = fz * rx - fx * rz
    local uz = fx * ry - fy * rx

    local dx = worldPos.X - camPos.X
    local dy = worldPos.Y - camPos.Y
    local dz = worldPos.Z - camPos.Z

    local zCam = dx * fx + dy * fy + dz * fz
    if zCam <= 15.0 then
        return false, 0.0, 0.0, "behind"
    end
    local xCam = dx * rx + dy * ry + dz * rz
    local yCam = dx * ux + dy * uy + dz * uz

    local halfTanX = math.tan(math.rad((fovDeg or 90.0) * 0.5))
    local aspect = (vpH > 1.0) and (vpW / vpH) or (16.0 / 9.0)
    local halfTanY = halfTanX / aspect
    if halfTanX <= 0.001 or halfTanY <= 0.001 then
        return false, 0.0, 0.0, "bad_fov"
    end

    local ndcX = (xCam / zCam) / halfTanX
    local ndcY = (yCam / zCam) / halfTanY
    local sx = (ndcX * 0.5 + 0.5) * logW
    local sy = (0.5 - ndcY * 0.5) * logH
    local onScr = (sx >= -140.0 and sx <= logW + 140.0 and sy >= -100.0 and sy <= logH + 100.0)
    return onScr, sx, sy, "lua_proj"
end

return Bridge
