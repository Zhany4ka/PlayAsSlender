-- PlayAsSlender Camera Controller (Smooth 3P Orbit, Spring-Arm Anti-Clip, Teleport Blend, FreeCam)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local CameraCtrl = {}

local State = {
    CamActor          = nil,
    VisionLight       = nil,
    NightVisionOn     = true,
    Yaw               = 0.0,
    Pitch             = -12.0,
    CurrentCamPos     = nil,
    TeleportBlendLeft = 0.0,
    FreeCam           = false,
    FreeCamPos        = nil,
    FreeCamYaw        = 0.0,
    FreeCamPitch      = -10.0,
    LastViewPos       = nil,
    LastViewRot       = { Pitch = -12.0, Yaw = 0.0, Roll = 0.0 },
    LastViewForward   = { X = 1.0, Y = 0.0, Z = 0.0 },
    FovDeg            = 90.0,
}

function CameraCtrl.Reset()
    if Logger.IsValidObj(State.VisionLight) then
        pcall(function() State.VisionLight:SetIntensity(0.0) end)
        pcall(function() State.VisionLight:SetVisibility(false, true) end)
    end
    State.CamActor          = nil
    State.VisionLight       = nil
    State.NightVisionOn     = (Config.CAMERA.NIGHT_VISION_ENABLED ~= false)
    State.CurrentCamPos     = nil
    State.TeleportBlendLeft = 0.0
    State.FreeCam           = false
    State.FreeCamPos        = nil
    State.LastViewPos       = nil
    State.LastViewRot       = { Pitch = -12.0, Yaw = 0.0, Roll = 0.0 }
    State.FovDeg            = 90.0
end

local function ApplyVisionPostProcess(camComp, enabled)
    if not Logger.IsValidObj(camComp) then return end
    pcall(function()
        camComp.PostProcessBlendWeight = enabled and 1.0 or 0.0
        local pps = camComp.PostProcessSettings
        if pps then
            local g = Config.CAMERA.NIGHT_VISION_GAMMA or 1.10
            pcall(function() pps.bOverride_AutoExposureBias = true end)
            pcall(function() pps.AutoExposureBias = Config.CAMERA.NIGHT_VISION_EXPOSURE_BIAS or 1.1 end)
            pcall(function() pps.bOverride_AutoExposureMinBrightness = true end)
            pcall(function() pps.AutoExposureMinBrightness = Config.CAMERA.NIGHT_VISION_MIN_BRIGHTNESS or -2.5 end)
            pcall(function() pps.bOverride_VignetteIntensity = true end)
            pcall(function() pps.VignetteIntensity = Config.CAMERA.NIGHT_VISION_VIGNETTE or 0.05 end)
            pcall(function() pps.bOverride_SceneFringeIntensity = true end)
            pcall(function() pps.SceneFringeIntensity = 0.0 end)
            pcall(function() pps.bOverride_ChromaticAberrationStartOffset = true end)
            pcall(function() pps.ChromaticAberrationStartOffset = 0.0 end)
            pcall(function() pps.bOverride_FilmGrainIntensity = true end)
            pcall(function() pps.FilmGrainIntensity = 0.0 end)
            pcall(function() pps.bOverride_ColorGamma = true end)
            pcall(function() pps.ColorGamma = { X = g, Y = g + 0.02, Z = g + 0.05, W = 1.0 } end)
        end
    end)
end

local function CreateVisionLight(cam, initialPos)
    local ptCls = Bridge.GetClass("/Script/Engine.PointLightComponent")
    if not Logger.IsValidObj(ptCls) or not Logger.IsValidObj(cam) then
        return nil
    end
    local idXform = {
        Rotation    = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
        Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D     = { X = 1.0, Y = 1.0, Z = 1.0 },
    }
    local vl = nil
    pcall(function()
        vl = cam:AddComponentByClass(ptCls, true, idXform, false)
    end)
    if not Logger.IsValidObj(vl) then
        Logger.Warn("CameraCtrl: Failed to add PAS_SlenderVisionLight PointLightComponent")
        return nil
    end

    local on = State.NightVisionOn == true
    local inten = on and (Config.CAMERA.NIGHT_VISION_INTENSITY or 4.2) or 0.0
    local radius = Config.CAMERA.NIGHT_VISION_RADIUS or 5500.0
    local falloffExp = Config.CAMERA.NIGHT_VISION_FALLOFF_EXP or 0.65
    local srcRad = Config.CAMERA.NIGHT_VISION_SOURCE_RADIUS or 160.0
    local specScale = Config.CAMERA.NIGHT_VISION_SPECULAR_SCALE or 0.04
    local col = Config.CAMERA.NIGHT_VISION_COLOR or { R = 0.78, G = 0.88, B = 1.0, A = 1.0 }

    pcall(function() vl:SetMobility(2) end)
    pcall(function() vl:SetCastShadows(false) end)
    pcall(function() vl.CastShadows = false end)
    pcall(function() vl.bCastDynamicShadow = false end)
    pcall(function() vl.bCastStaticShadow = false end)
    pcall(function() vl.IntensityUnits = 0 end) -- Unitless so linear falloff intensity works consistently
    pcall(function() vl.bUseInverseSquaredFalloff = false end)
    pcall(function() vl:SetLightFalloffExponent(falloffExp) end)
    pcall(function() vl:SetAttenuationRadius(radius) end)
    pcall(function() vl:SetSourceRadius(srcRad) end)
    pcall(function() vl:SetSpecularScale(specScale) end)
    pcall(function() vl:SetLightColor(col, true) end)
    pcall(function() vl:SetIntensity(inten) end)
    pcall(function() vl.bAffectsWorld = on end)
    pcall(function() vl:SetHiddenInGame(not on, true) end)
    pcall(function() vl:SetVisibility(on, true) end)
    pcall(function() vl:SetActive(on, true) end)
    if initialPos then
        pcall(function()
            vl:K2_SetWorldLocation({ X = initialPos.X, Y = initialPos.Y, Z = initialPos.Z + 175.0 }, false, {}, true)
        end)
    end
    pcall(function()
        if vl.MarkRenderStateDirty then vl:MarkRenderStateDirty() end
    end)

    local rbInten, rbRad, rbCast, rbInv = -1.0, -1.0, true, true
    pcall(function() rbInten = tonumber(vl.Intensity) or -1.0 end)
    pcall(function() rbRad   = tonumber(vl.AttenuationRadius) or -1.0 end)
    pcall(function() rbCast  = (vl.CastShadows == true) end)
    pcall(function() rbInv   = (vl.bUseInverseSquaredFalloff == true) end)
    Logger.Info(string.format(
        "PAS_SlenderVisionLight initialized (on=%s, Inten=%.2f, Radius=%.0f, CastShadows=%s, InvSq=%s)",
        tostring(on), rbInten, rbRad, tostring(rbCast), tostring(rbInv)))

    return vl
end

local function ApplyVisionStateToScene()
    local on = State.NightVisionOn == true
    if Logger.IsValidObj(State.CamActor) and Logger.IsValidObj(State.CamActor.CameraComponent) then
        ApplyVisionPostProcess(State.CamActor.CameraComponent, on)
    end
    if Logger.IsValidObj(State.VisionLight) then
        local inten = on and (Config.CAMERA.NIGHT_VISION_INTENSITY or 4.2) or 0.0
        pcall(function() State.VisionLight.bAffectsWorld = on end)
        pcall(function() State.VisionLight:SetIntensity(inten) end)
        pcall(function() State.VisionLight:SetHiddenInGame(not on, true) end)
        pcall(function() State.VisionLight:SetVisibility(on, true) end)
        pcall(function() State.VisionLight:SetActive(on, true) end)
        pcall(function()
            if State.VisionLight.MarkRenderStateDirty then State.VisionLight:MarkRenderStateDirty() end
        end)
    end
end

function CameraCtrl.Init(world, pc, initialFocusPos, initialYaw)
    CameraCtrl.Reset()
    if not Logger.IsValidObj(world) or not Logger.IsValidObj(pc) then return false end

    State.Yaw   = initialYaw or 0.0
    State.Pitch = -12.0

    local fx, fy, fz = Bridge.ForwardFromRot(State.Pitch, State.Yaw)
    local pivot = {
        X = initialFocusPos.X,
        Y = initialFocusPos.Y,
        Z = initialFocusPos.Z + 85.0,
    }
    local camPos = {
        X = pivot.X - fx * Config.CAMERA.DISTANCE,
        Y = pivot.Y - fy * Config.CAMERA.DISTANCE,
        Z = pivot.Z - fz * Config.CAMERA.DISTANCE + 30.0,
    }

    local cam = Bridge.SpawnActorDeferred(world, "/Script/Engine.CameraActor", camPos, State.Yaw)
    if not Logger.IsValidObj(cam) then
        Logger.Error("CameraCtrl.Init: Failed to spawn CameraActor")
        return false
    end

    State.NightVisionOn = (Config.CAMERA.NIGHT_VISION_ENABLED ~= false)
    pcall(function()
        if Logger.IsValidObj(cam.CameraComponent) then
            cam.CameraComponent.FieldOfView = 90.0
            cam.CameraComponent.bConstrainAspectRatio = false
            ApplyVisionPostProcess(cam.CameraComponent, State.NightVisionOn)
        end
    end)

    State.CamActor        = cam
    State.VisionLight     = CreateVisionLight(cam, initialFocusPos)
    State.CurrentCamPos   = camPos
    State.LastViewPos     = camPos
    State.LastViewRot     = { Pitch = State.Pitch, Yaw = State.Yaw, Roll = 0.0 }
    State.LastViewForward = { X = fx, Y = fy, Z = fz }
    State.FovDeg          = 90.0

    pcall(function() pc.bAutoManageActiveCameraTarget = false end)
    pcall(function() pc:SetViewTargetWithBlend(cam, 0.0, 0, 0.0, false) end)
    pcall(function() pc.bShowMouseCursor = false end)

    -- Ensure GameOnly input mode so mouse delta captures cleanly without cursor hitting edges
    pcall(function()
        local wbl = Bridge.GetClass("/Script/UMG.Default__WidgetBlueprintLibrary")
        if Logger.IsValidObj(wbl) and wbl.SetInputMode_GameOnly then
            wbl:SetInputMode_GameOnly(pc, false)
        end
    end)

    Logger.Info("CameraController initialized @ Yaw=" .. string.format("%.1f", State.Yaw))
    return true
end

function CameraCtrl.GetYaw()
    return State.FreeCam and State.FreeCamYaw or State.Yaw
end

function CameraCtrl.GetPitch()
    return State.FreeCam and State.FreeCamPitch or State.Pitch
end

function CameraCtrl.GetCamActor()
    return State.CamActor
end

function CameraCtrl.GetViewRay()
    local pos = State.LastViewPos or State.CurrentCamPos or { X = 0, Y = 0, Z = 0 }
    local fwd = State.LastViewForward or { X = 1, Y = 0, Z = 0 }
    return pos, fwd
end

function CameraCtrl.GetViewTransform()
    local pos = State.LastViewPos or State.CurrentCamPos or { X = 0, Y = 0, Z = 0 }
    local rot = State.LastViewRot or { Pitch = State.Pitch, Yaw = State.Yaw, Roll = 0.0 }
    return pos, rot, (State.FovDeg or 90.0)
end

function CameraCtrl.ToggleNightVision()
    State.NightVisionOn = not State.NightVisionOn
    ApplyVisionStateToScene()
    Logger.Info("Slenderman Night Vision = " .. tostring(State.NightVisionOn))
    return State.NightVisionOn
end

function CameraCtrl.SetNightVision(enabled)
    State.NightVisionOn = (enabled == true)
    ApplyVisionStateToScene()
    Logger.Info("Slenderman Night Vision = " .. tostring(State.NightVisionOn))
    return State.NightVisionOn
end

function CameraCtrl.GetVisionInfo()
    local vl = State.VisionLight
    local valid = Logger.IsValidObj(vl)
    local inten, rad, cast, invSq, vis = 0.0, 0.0, false, false, false
    if valid then
        pcall(function() inten = tonumber(vl.Intensity) or 0.0 end)
        pcall(function() rad   = tonumber(vl.AttenuationRadius) or 0.0 end)
        pcall(function() cast  = (vl.CastShadows == true) end)
        pcall(function() invSq = (vl.bUseInverseSquaredFalloff == true) end)
        pcall(function() vis   = (vl:IsVisible() == true) and (vl.bHiddenInGame ~= true) end)
    end
    return {
        enabled      = State.NightVisionOn == true,
        hasLight     = valid and vis and (inten > 0.01),
        intensity    = inten,
        radius       = rad,
        castShadows  = cast,
        invSqFalloff = invSq,
    }
end

function CameraCtrl.IsFreeCam()
    return State.FreeCam
end

function CameraCtrl.ToggleFreeCam(slender)
    State.FreeCam = not State.FreeCam
    if State.FreeCam then
        State.FreeCamPos   = State.CurrentCamPos and { X = State.CurrentCamPos.X, Y = State.CurrentCamPos.Y, Z = State.CurrentCamPos.Z } or Bridge.GetActorLoc(slender)
        State.FreeCamYaw   = State.Yaw
        State.FreeCamPitch = State.Pitch
        Logger.Info("Debug FreeCam ENABLED")
    else
        Logger.Info("Debug FreeCam DISABLED")
    end
    return State.FreeCam
end

function CameraCtrl.NotifyTeleport()
    State.TeleportBlendLeft = 0.35
end

function CameraCtrl.SetViewAngles(pitch, yaw)
    State.Pitch = Bridge.Clamp(pitch, Config.CAMERA.PITCH_MIN, Config.CAMERA.PITCH_MAX)
    State.Yaw   = Bridge.NormalizeAngle(yaw)
end

function CameraCtrl.Update(world, pc, dt, slender, survivor, freezeLook)
    if not Logger.IsValidObj(State.CamActor) or not Logger.IsValidObj(pc) then return end

    -- Keep ViewTarget locked onto our CameraActor
    local vt = nil
    pcall(function() vt = pc:GetViewTarget() end)
    if not Logger.IsValidObj(vt) or vt:GetAddress() ~= State.CamActor:GetAddress() then
        pcall(function() pc:SetViewTargetWithBlend(State.CamActor, 0.0, 0, 0.0, false) end)
    end

    -- Read mouse look delta (zeroed on post-match End Screen so mouse stays steady for buttons)
    local dx, dy = 0.0, 0.0
    if not freezeLook then
        dx, dy = Bridge.GetMouseDelta(pc)
        -- Also allow keyboard arrow keys as optional look fallback
        if Bridge.IsKeyDown(pc, "Left")  then dx = dx - 2.0 * dt * 60.0 end
        if Bridge.IsKeyDown(pc, "Right") then dx = dx + 2.0 * dt * 60.0 end
        if Bridge.IsKeyDown(pc, "Up")    then dy = dy + 1.5 * dt * 60.0 end
        if Bridge.IsKeyDown(pc, "Down")  then dy = dy - 1.5 * dt * 60.0 end
    end

    if State.FreeCam then
        State.FreeCamYaw   = Bridge.NormalizeAngle(State.FreeCamYaw + dx * Config.CAMERA.MOUSE_SENS_YAW * 10.0)
        State.FreeCamPitch = Bridge.Clamp(State.FreeCamPitch + dy * Config.CAMERA.MOUSE_SENS_PITCH * 10.0, -85.0, 85.0)

        local fx, fy, fz = Bridge.ForwardFromRot(State.FreeCamPitch, State.FreeCamYaw)
        local rx, ry, _  = Bridge.RightFromYaw(State.FreeCamYaw)

        local fwdIn   = (Bridge.IsKeyDown(pc, Config.KEYS.FORWARD) and 1 or 0) - (Bridge.IsKeyDown(pc, Config.KEYS.BACKWARD) and 1 or 0)
        local rightIn = (Bridge.IsKeyDown(pc, Config.KEYS.RIGHT)   and 1 or 0) - (Bridge.IsKeyDown(pc, Config.KEYS.LEFT)     and 1 or 0)
        local upIn    = (Bridge.IsKeyDown(pc, Config.KEYS.FREECAM_UP) and 1 or 0) - (Bridge.IsKeyDown(pc, Config.KEYS.FREECAM_DOWN) and 1 or 0)

        local spd = Config.CAMERA.FREECAM_SPEED * (Bridge.IsKeyDown(pc, Config.KEYS.SPRINT) and Config.CAMERA.FREECAM_FAST_MULT or 1.0)
        local p = State.FreeCamPos or { X = 0, Y = 0, Z = 0 }
        p.X = p.X + (fx * fwdIn + rx * rightIn) * spd * dt
        p.Y = p.Y + (fy * fwdIn + ry * rightIn) * spd * dt
        p.Z = p.Z + (fz * fwdIn + upIn) * spd * dt
        State.FreeCamPos = p

        local rot = { Pitch = State.FreeCamPitch, Yaw = State.FreeCamYaw, Roll = 0.0 }
        pcall(function() State.CamActor:K2_SetActorLocationAndRotation(p, rot, false, {}, true) end)
        if Logger.IsValidObj(State.VisionLight) and State.NightVisionOn then
            pcall(function()
                State.VisionLight:K2_SetWorldLocation(p, false, {}, true)
            end)
        end
        State.LastViewPos     = p
        State.LastViewRot     = rot
        State.LastViewForward = { X = fx, Y = fy, Z = fz }
        return
    end

    if not Logger.IsValidObj(slender) then return end
    local slLoc = Bridge.GetActorLoc(slender)
    if not slLoc then return end

    -- Update orbit angles (UE MouseX/MouseY analog delta is typically small per frame; scale smoothly)
    State.Yaw   = Bridge.NormalizeAngle(State.Yaw + dx * Config.CAMERA.MOUSE_SENS_YAW * 10.0)
    State.Pitch = Bridge.Clamp(State.Pitch + dy * Config.CAMERA.MOUSE_SENS_PITCH * 10.0, Config.CAMERA.PITCH_MIN, Config.CAMERA.PITCH_MAX)

    local fx, fy, fz = Bridge.ForwardFromRot(State.Pitch, State.Yaw)
    local rx, ry, _  = Bridge.RightFromYaw(State.Yaw)

    -- Pivot around Slenderman's upper chest/shoulder (tall figure, capsule halfHeight ~115)
    local pivot = {
        X = slLoc.X + rx * Config.CAMERA.SHOULDER_OFFSET,
        Y = slLoc.Y + ry * Config.CAMERA.SHOULDER_OFFSET,
        Z = slLoc.Z + 80.0,
    }
    local rawTarget = {
        X = pivot.X - fx * Config.CAMERA.DISTANCE,
        Y = pivot.Y - fy * Config.CAMERA.DISTANCE,
        Z = pivot.Z - fz * Config.CAMERA.DISTANCE + 45.0,
    }

    -- Spring-arm anti-clipping trace (ignore Slenderman & Survivor so camera never snaps on character capsules)
    local ignore = {}
    if Logger.IsValidObj(slender)  then table.insert(ignore, slender)  end
    if Logger.IsValidObj(survivor) then table.insert(ignore, survivor) end

    local hit, info = Bridge.LineTrace(world, pivot, rawTarget, ignore, 0, false)
    local desiredPos = rawTarget
    if hit and info and info.ImpactPoint then
        local totalDist = Bridge.Dist(pivot, rawTarget)
        local hitDist   = Bridge.Dist(pivot, info.ImpactPoint)
        local safeDist  = math.max(Config.CAMERA.MIN_DISTANCE, hitDist - Config.CAMERA.WALL_PADDING)
        if totalDist > 1.0 and safeDist < totalDist then
            local ratio = safeDist / totalDist
            desiredPos = {
                X = Bridge.Lerp(pivot.X, rawTarget.X, ratio),
                Y = Bridge.Lerp(pivot.Y, rawTarget.Y, ratio),
                Z = Bridge.Lerp(pivot.Z, rawTarget.Z, ratio),
            }
        end
    end

    -- Smooth exponential interpolation (extra smooth right after teleport)
    if not State.CurrentCamPos then
        State.CurrentCamPos = desiredPos
    else
        local speed = Config.CAMERA.SMOOTH_POS_SPEED
        if State.TeleportBlendLeft > 0.0 then
            State.TeleportBlendLeft = math.max(0.0, State.TeleportBlendLeft - dt)
            speed = Config.CAMERA.TELEPORT_BLEND_SPEED
        end
        local alpha = 1.0 - math.exp(-speed * dt)
        State.CurrentCamPos = {
            X = Bridge.Lerp(State.CurrentCamPos.X, desiredPos.X, alpha),
            Y = Bridge.Lerp(State.CurrentCamPos.Y, desiredPos.Y, alpha),
            Z = Bridge.Lerp(State.CurrentCamPos.Z, desiredPos.Z, alpha),
        }
    end

    -- Look slightly forward past Slenderman's shoulder along camera aim ray
    local aimTarget = {
        X = pivot.X + fx * 1200.0,
        Y = pivot.Y + fy * 1200.0,
        Z = pivot.Z + fz * 1200.0,
    }
    local camRot = Bridge.RotatorFromVec(
        aimTarget.X - State.CurrentCamPos.X,
        aimTarget.Y - State.CurrentCamPos.Y,
        aimTarget.Z - State.CurrentCamPos.Z
    )

    pcall(function()
        State.CamActor:K2_SetActorLocationAndRotation(State.CurrentCamPos, camRot, false, {}, true)
    end)

    if Logger.IsValidObj(State.VisionLight) and State.NightVisionOn then
        pcall(function()
            State.VisionLight:K2_SetWorldLocation({ X = slLoc.X, Y = slLoc.Y, Z = slLoc.Z + 175.0 }, false, {}, true)
        end)
    end

    State.LastViewPos     = State.CurrentCamPos
    State.LastViewRot     = camRot
    State.LastViewForward = { X = fx, Y = fy, Z = fz }
end

return CameraCtrl
