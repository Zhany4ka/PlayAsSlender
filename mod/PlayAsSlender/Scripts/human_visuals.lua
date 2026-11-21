-- PlayAsSlender Human Survivor Visuals (Multi-Map Discovery, AIController Possession & Lighting)
local UEHelpers = require("UEHelpers")
local Config    = require("config")
local Logger    = require("logger")
local Bridge    = require("ue_bridge")

local HumanVisuals = {}

local State = {
    Survivor           = nil,
    AI                 = nil,
    PlayerState        = nil,
    ShadowMesh         = nil,
    Flashlight         = nil,
    ModFlashlight      = nil,
    OrigFlashlight     = nil,
    PointLight               = nil,
    PointLight0              = nil,
    FollowComp               = nil,
    PostProcessComp          = nil,
    FlashlightEnabled        = true,
    ModFlashlightIntensity   = 60.0,
    PointLightBaseIntensity  = nil,
    PointLight0BaseIntensity = nil,
    CurrentYaw         = 0.0,
    CurrentPitch       = -4.0,
    LastLightScan      = -1.0,
    LastCamScan        = -1.0,
    LastGlitchSweep    = -1.0,
    MpcParamResetCount = 0,
    MpcLogged          = false,
    LoggedStrayLights  = {},
    VisualInfo         = { meshName = "", matNames = {}, hasShadowMat = false, lightingChannel0 = false },
}

function HumanVisuals.Reset()
    State.Survivor           = nil
    State.AI                 = nil
    State.PlayerState        = nil
    State.ShadowMesh         = nil
    State.Flashlight         = nil
    State.ModFlashlight      = nil
    State.OrigFlashlight     = nil
    State.PointLight         = nil
    State.PointLight0        = nil
    State.FollowComp         = nil
    State.PostProcessComp    = nil
    State.CurrentYaw         = 0.0
    State.CurrentPitch       = -4.0
    State.LastLightScan      = -1.0
    State.LastCamScan        = -1.0
    State.LastGlitchSweep    = -1.0
    State.MpcParamResetCount = 0
    State.MpcLogged          = false
    State.LoggedStrayLights  = {}
    State.VisualInfo         = { meshName = "", matNames = {}, hasShadowMat = false, lightingChannel0 = false }
end

function HumanVisuals.GetActor()       return State.Survivor end
function HumanVisuals.GetAI()          return State.AI end
function HumanVisuals.GetPlayerState() return State.PlayerState end

function HumanVisuals.GetVisualInfo()
    local comp = State.ShadowMesh
    if not Logger.IsValidObj(comp) then
        return State.VisualInfo
    end
    local asset = nil
    pcall(function() asset = comp:GetSkinnedAsset() end)
    local meshName = Logger.SafeName(asset)
    local c0 = false
    pcall(function() c0 = (comp.LightingChannels.bChannel0 == true) end)
    local numSlots = 0
    pcall(function() numSlots = comp:GetNumMaterials() end)
    local matNames = {}
    local hasShadow = false
    for idx = 0, math.max(0, (tonumber(numSlots) or 0) - 1) do
        local curMat = nil
        pcall(function() curMat = comp:GetMaterial(idx) end)
        local curName = Logger.SafeName(curMat)
        if (not Logger.IsValidObj(curMat)) or string.find(curName, "ShadowCaster", 1, true) then
            hasShadow = true
        end
        table.insert(matNames, curName)
    end
    local info = {
        meshName         = meshName,
        matNames         = matNames,
        hasShadowMat     = hasShadow,
        lightingChannel0 = c0,
    }
    State.VisualInfo = info
    return info
end

function HumanVisuals.GetLocation()
    return Bridge.GetActorLoc(State.Survivor)
end

function HumanVisuals.GetEyeLoc()
    local loc = Bridge.GetActorLoc(State.Survivor)
    if not loc then return nil end
    return { X = loc.X, Y = loc.Y, Z = loc.Z + 65.0 }
end

function HumanVisuals.GetHeadWorldLoc()
    local loc = Bridge.GetActorLoc(State.Survivor)
    if not loc then return nil end
    local headMesh = Logger.IsValidObj(State.ShadowMesh) and State.ShadowMesh or (Logger.IsValidObj(State.Survivor) and State.Survivor.Mesh or nil)
    if Logger.IsValidObj(headMesh) then
        for _, boneName in ipairs({ "head", "Head" }) do
            local okS, sLoc = pcall(function() return headMesh:GetSocketLocation(Bridge.FName(boneName)) end)
            if okS and sLoc and sLoc.X then
                local headPt = { X = sLoc.X, Y = sLoc.Y, Z = sLoc.Z }
                if Bridge.Dist(headPt, loc) <= 160.0 and headPt.Z > (loc.Z + 25.0) then
                    return { X = headPt.X, Y = headPt.Y, Z = headPt.Z + 32.0 }
                end
            end
        end
    end
    return { X = loc.X, Y = loc.Y, Z = loc.Z + 112.0 }
end

function HumanVisuals.GetForward()
    local rot = Bridge.GetActorRot(State.Survivor)
    local yaw = rot and rot.Yaw or State.CurrentYaw
    local fx, fy, fz = Bridge.ForwardFromRot(0.0, yaw)
    return { X = fx, Y = fy, Z = fz }, yaw
end

local function FindSurvivorPawn(pc)
    local pawn = nil
    if Logger.IsValidObj(pc) then
        pcall(function() pawn = pc.Pawn end)
        if Logger.IsValidObj(pawn) then return pawn end
    end
    for _, clsName in ipairs({
        "BP_ProjectXCharacter_Survivor_C",
        "BP_ProjectXCharacter_Survivor_Level02_TheEightPages_C",
        "BP_ProjectXCharacter_Survivor_Level01_Prologue_C",
        "BP_ProjectXCharacter_Survivor_Level03_IntoTheAbyss_C",
        "BP_ProjectXCharacter_Survivor_Level04_Flashback_C",
        "BP_ProjectXCharacter_Survivor_Level05_TheArrival_C",
        "BP_ProjectXCharacter_Survivor_Level06_Escape_C",
        "BP_ProjectXCharacter_Survivor_Level07_Memories_C",
        "BP_ProjectXCharacter_Survivor_Level08_Homestead_C",
        "BP_ProjectXCharacter_Survivor_Level09_Genesis_C",
        "BP_ProjectXCharacter_Survivor_Level10_C",
        "BP_ProjectXCharacter_Survivor_Level99_Haunted_C",
    }) do
        local found = FindAllOf(clsName)
        if found and #found > 0 and Logger.IsValidObj(found[1]) then
            return found[1]
        end
    end
    -- Generic fallback: any ProjectXCharacter not named Slender/Chaser/Charlie
    for _, ch in ipairs(FindAllOf("ProjectXCharacter") or {}) do
        if Logger.IsValidObj(ch) then
            local cn = Logger.SafeName(ch:GetClass())
            if not string.find(cn, "Slender", 1, true)
                and not string.find(cn, "Chaser", 1, true)
                and not string.find(cn, "Charlie", 1, true)
                and not string.find(cn, "Teleporter", 1, true)
            then
                return ch
            end
        end
    end
    return nil
end

local function AttachLightToCapsule(comp, capsule, noneName, relLoc, relRot)
    if not Logger.IsValidObj(comp) or not Logger.IsValidObj(capsule) then return end
    pcall(function()
        comp:K2_AttachToComponent(capsule, noneName, 0, 0, 0, false)
        comp:K2_SetRelativeLocation(relLoc, false, {}, true)
        comp:K2_SetRelativeRotation(relRot, false, {}, true)
    end)
end

local function GetCompWorldLoc(comp)
    if not Logger.IsValidObj(comp) then return nil end
    local out = nil
    pcall(function()
        local loc = comp:K2_GetComponentLocation()
        if loc and loc.X then
            out = { X = loc.X, Y = loc.Y, Z = loc.Z }
        end
    end)
    return out
end

local function IsSpotLightActive(comp)
    if not Logger.IsValidObj(comp) then return false end
    local isVis, isHidden, affectsWorld = false, false, true
    local inten = 0.0
    pcall(function() isVis = (comp:IsVisible() == true) end)
    pcall(function() isHidden = (comp.bHiddenInGame == true) end)
    pcall(function() inten = tonumber(comp.Intensity) or 0.0 end)
    pcall(function()
        if comp.bAffectsWorld ~= nil then
            affectsWorld = (comp.bAffectsWorld ~= false)
        end
    end)
    return isVis and (not isHidden) and (inten > 0.01) and affectsWorld
end

local function SilenceSpotLight(comp)
    if not Logger.IsValidObj(comp) then return end
    pcall(function() comp.bAffectsWorld = false end)
    pcall(function() comp:SetComponentTickEnabled(false) end)
    pcall(function() comp:SetActive(false, false) end)
    pcall(function() comp:SetIntensity(0.0) end)
    pcall(function() comp:SetVisibility(false, true) end)
    pcall(function() comp:SetHiddenInGame(true, true) end)
end

local function GetKeepFlashlightAddr()
    local addr = Bridge.GetObjAddr(State.ModFlashlight)
    if addr == 0 then
        addr = Bridge.GetObjAddr(State.Flashlight)
    end
    return addr
end

local function ForEachStraySpotLight(hLoc, slLoc, camLoc, maxSlCamDist, flashlightHumanDist, onMatch)
    local keepAddr = GetKeepFlashlightAddr()
    local allSpots = (type(FindAllOf) == "function" and FindAllOf("SpotLightComponent")) or {}
    for _, slc in ipairs(allSpots) do
        if Logger.IsValidObj(slc) then
            local slcAddr = Bridge.GetObjAddr(slc)
            if (keepAddr == 0 or slcAddr ~= keepAddr) and IsSpotLightActive(slc) then
                local compLoc = GetCompWorldLoc(slc)
                if compLoc then
                    local dHuman = hLoc and Bridge.Dist(compLoc, hLoc) or 9999.0
                    local dSl    = slLoc and Bridge.Dist(compLoc, slLoc) or 9999.0
                    local dCam   = camLoc and Bridge.Dist(compLoc, camLoc) or 9999.0
                    local nearSlOrCam = (slLoc ~= nil and dSl <= maxSlCamDist) or (camLoc ~= nil and dCam <= maxSlCamDist)
                    local fullName = Logger.SafeFullName(slc)
                    local byProximity = (dHuman > 450.0 and nearSlOrCam)
                    local byName = (flashlightHumanDist ~= nil)
                        and (string.find(fullName, "Flashlight", 1, true) ~= nil)
                        and (dHuman > flashlightHumanDist)
                    if byProximity or byName then
                        onMatch(slc, slcAddr, fullName, dHuman, dSl, dCam)
                    end
                end
            end
        end
    end
end

local function CreateModFlashlight(pawn, origFl)
    local spotCls = Bridge.GetClass("/Script/Engine.SpotLightComponent")
    if not Logger.IsValidObj(spotCls) or not Logger.IsValidObj(pawn) then
        return nil, 0.0
    end
    local idXform = {
        Rotation    = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
        Translation = { X = 0.0, Y = 0.0, Z = 0.0 },
        Scale3D     = { X = 1.0, Y = 1.0, Z = 1.0 },
    }
    local modFl = nil
    pcall(function()
        modFl = pawn:AddComponentByClass(spotCls, true, idXform, false)
    end)
    if not Logger.IsValidObj(modFl) then
        return nil, 0.0
    end

    local innerCone, outerCone, attRadius, inten = 14.0, 32.0, 3200.0, 1.5
    if Logger.IsValidObj(origFl) then
        pcall(function()
            if type(origFl.InnerConeAngle) == "number" and origFl.InnerConeAngle > 0.0 then
                innerCone = origFl.InnerConeAngle
            end
        end)
        pcall(function()
            if type(origFl.OuterConeAngle) == "number" and origFl.OuterConeAngle > 0.0 then
                outerCone = origFl.OuterConeAngle
            end
        end)
        pcall(function()
            if type(origFl.AttenuationRadius) == "number" and origFl.AttenuationRadius > 100.0 then
                attRadius = origFl.AttenuationRadius
            end
        end)
        pcall(function()
            local oi = tonumber(origFl.Intensity)
            if oi and oi > 0.05 then
                inten = math.max(1.5, math.min(oi, 5.0))
            end
        end)
        pcall(function()
            if type(origFl.IntensityUnits) == "number" then
                modFl.IntensityUnits = origFl.IntensityUnits
            end
        end)
    end

    pcall(function() modFl:SetMobility(2) end)
    pcall(function() modFl:SetInnerConeAngle(innerCone) end)
    pcall(function() modFl:SetOuterConeAngle(outerCone) end)
    pcall(function() modFl:SetAttenuationRadius(attRadius) end)
    pcall(function() modFl:SetIntensity(inten) end)

    local colorApplied = false
    if Logger.IsValidObj(origFl) then
        pcall(function()
            local lc = origFl:GetLightColor()
            if lc and lc.R ~= nil then
                modFl:SetLightColor(lc, true)
                colorApplied = true
            end
        end)
    end
    if not colorApplied then
        pcall(function() modFl:SetLightColor({ R = 0.95, G = 0.95, B = 1.0, A = 1.0 }, true) end)
    end

    pcall(function() modFl.bAffectsWorld = true end)
    pcall(function() modFl:SetHiddenInGame(false, true) end)
    pcall(function() modFl:SetVisibility(true, true) end)
    pcall(function() modFl:SetActive(true, true) end)
    return modFl, inten
end

local function DisablePawnWeaponFlashlight(pawn)
    local wc = nil
    pcall(function() wc = pawn.WeaponComponent end)
    if Logger.IsValidObj(wc) then
        pcall(function() wc:SetComponentTickEnabled(false) end)
        pcall(function() wc:SetActive(false, false) end)
    end

    local cw = nil
    pcall(function() cw = pawn:GetCurrentWeapon() end)
    if not Logger.IsValidObj(cw) and Logger.IsValidObj(wc) then
        pcall(function() cw = wc:GetCurrentWeapon() end)
    end
    if not Logger.IsValidObj(cw) and Logger.IsValidObj(wc) then
        pcall(function() cw = wc.CurrentWeapon end)
    end
    if Logger.IsValidObj(cw) then
        pcall(function() cw:SetActorTickEnabled(false) end)
        pcall(function() cw:SetActorHiddenInGame(true) end)
    end
end

function HumanVisuals.Init(world, pc, mapKey)
    HumanVisuals.Reset()
    if not Logger.IsValidObj(world) then return false end

    local pawn = FindSurvivorPawn(pc)
    if not Logger.IsValidObj(pawn) then
        Logger.Error("HumanVisuals.Init: Survivor pawn not found!")
        return false
    end

    -- Preserve PlayerState before AIController:Possess clears pawn.PlayerState
    local ps = nil
    pcall(function() ps = pawn.PlayerState end)
    if not Logger.IsValidObj(ps) then
        local pStates = UEHelpers.GetAllPlayerStates()
        if pStates and #pStates > 0 then ps = pStates[1] end
    end

    -- Stop any active intro cutscene LevelSequenceActor / AnimMontage before positioning Survivor
    for _, sq in ipairs(FindAllOf("LevelSequenceActor") or {}) do
        if Logger.IsValidObj(sq) then
            pcall(function()
                if Logger.IsValidObj(sq.SequencePlayer) then
                    sq.SequencePlayer:Stop()
                end
            end)
            pcall(function() sq:SetActorTickEnabled(false) end)
        end
    end
    pcall(function() pawn:StopAnimMontage(nil) end)
    for _, comp in ipairs({ pawn.Mesh, pawn.ShadowCaster }) do
        if Logger.IsValidObj(comp) then
            pcall(function()
                local ai = comp:GetAnimInstance()
                if Logger.IsValidObj(ai) then ai:Montage_Stop(0.0, nil) end
            end)
        end
    end
    pcall(function()
        if Logger.IsValidObj(pawn.CharacterMovement) then
            pawn.CharacterMovement:SetMovementMode(1, 0)
        end
    end)

    -- On Level06_Escape, PlayerStart starts in 2F intro sketch cutscene; place Survivor cleanly in 1F Main Hallway inside the house
    -- On Level01_Prologue, PrologueStory places Survivor at the vanilla Car beside the fallen tree with flashlight OFF
    if mapKey == "ESCAPE" then
        local targetXY = { X = 44270.0, Y = 58850.0, Z = 9100.0 }
        local gHit, gz = Bridge.GroundTrace(world, targetXY.X, targetXY.Y, 9350.0, 8750.0, { pawn })
        local spawnPos = { X = targetXY.X, Y = targetXY.Y, Z = (gHit and gz or 9006.3) + 92.0 }
        pcall(function()
            pawn:K2_SetActorLocationAndRotation(spawnPos, { Pitch = 0.0, Yaw = 90.0, Roll = 0.0 }, false, {}, true)
        end)
        Logger.Info(string.format("Escape Human placed inside 1F House Hallway @ (%.0f, %.0f, %.0f)", spawnPos.X, spawnPos.Y, spawnPos.Z))
    end

local FALLBACK_SLOT_MATERIALS = {
    sk_laurenshadow = {
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/HairStyles/HairStyle_B/MaterialInstances/MI_HS_B_01.MI_HS_B_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Skin_MaterialInstances/MI_SkinBody_B_01.MI_SkinBody_B_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/TShirt_A/MaterialInstances/MI_TShirt_A_01.MI_TShirt_A_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/Combat_Boots_A/M_Combat_Boots_A_Master_01.M_Combat_Boots_A_Master_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Skin_MaterialInstances/MI_SkinHead_B_01.MI_SkinHead_B_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eyelashes/MaterialInstances/MI_Female_A_Eyelash_01.MI_Female_A_Eyelash_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eyeball/MaterialInstances/MI_Eyeball_Black_01.MI_Eyeball_Black_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eyeball/MaterialInstances/MI_EyeShadow_01.MI_EyeShadow_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eye_Caruncle/MaterialInstances/MI_Eye_Caruncle_01.MI_Eye_Caruncle_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eye_Tearline/MaterialInstances/MI_Tearline_01.MI_Tearline_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Teeth_Tongue/MaterialInstances/MI_Teeth_Tongue_A_01.MI_Teeth_Tongue_A_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/SkinBody_Head_B/Eyebrows/MaterialInstances/MI_Female_Eyebrow_01.MI_Female_Eyebrow_01",
        "/Game/ThirdPartyAssets/FemaleHero_Survival/Materials/Pants_Cargo_A/MaterialInstances/MI_Pants_Cargo_A_01.MI_Pants_Cargo_A_01",
    },
    sk_charliesdadshadow = {
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/M_eye.M_eye",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/m_faceitems_eyelash.m_faceitems_eyelash",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/m_hair_card_face.m_hair_card_face",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/M_male_haircards.M_male_haircards",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/M_male_haircap.M_male_haircap",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/M_male_head.M_male_head",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/body/M_male_basebody.M_male_basebody",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/cloth/MI_male_casual_sneakers_hi.MI_male_casual_sneakers_hi",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/cloth/MI_male_casual_shirts.MI_male_casual_shirts",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/cloth/MI_male_casual_Tshirt1.MI_male_casual_Tshirt1",
        "/Game/ThirdPartyAssets/Male_Casual_Outfits/Materials/cloth/MI_male_casual_jeans2.MI_male_casual_jeans2",
    },
    sk_changeling_boy_shadow = {
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Cloth/Instance/MI_Changeling_Boy_Blouse_Inst.MI_Changeling_Boy_Blouse_Inst",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Cloth/Instance/MI_Changeling_Boy_Socks_Inst.MI_Changeling_Boy_Socks_Inst",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Cloth/Instance/MI_Changeling_Boy_Shorts_Inst.MI_Changeling_Boy_Shorts_Inst",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Cloth/Instance/MI_Changeling_Boy_Boots_Inst.MI_Changeling_Boy_Boots_Inst",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/Instance/MI_Changeling_Boy_Hair.MI_Changeling_Boy_Hair",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/Instance/MI_Changeling_Boy_Body.MI_Changeling_Boy_Body",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/Instance/MI_Changeling_Boy_Head.MI_Changeling_Boy_Head",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/M_Changeling_Boy_Eyelashes.M_Changeling_Boy_Eyelashes",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/Instance/MI_Changeling_Boy_Eye.MI_Changeling_Boy_Eye",
        "/Game/ThirdPartyAssets/Changeling_Boy/Material/Body/Instance/MI_Changeling_Boy_Teeth.MI_Changeling_Boy_Teeth",
    },
}

local function ApplyTexturedHumanMaterials(comp)
    if not Logger.IsValidObj(comp) then return end
    local asset = nil
    pcall(function() asset = comp:GetSkinnedAsset() end)
    local meshName = Logger.SafeName(asset)
    local lowMesh  = string.lower(meshName)

    -- 1. Drop blueprint Chaser_ShadowCaster_Material overrides so full mesh materials take effect
    pcall(function() comp:EmptyOverrideMaterials() end)

    -- 2. Explicitly bind non-shadow materials from asset.Materials (already cooked on all three shadow proxy meshes)
    pcall(function()
        local assetMats = asset and asset.Materials
        local n = assetMats and #assetMats or 0
        for i = 1, n do
            local mInt = nil
            pcall(function() mInt = assetMats[i].MaterialInterface end)
            if Logger.IsValidObj(mInt) and not string.find(Logger.SafeName(mInt), "ShadowCaster", 1, true) then
                pcall(function() comp:SetMaterial(i - 1, mInt) end)
            end
        end
    end)

    -- 3. Fallback per-slot restoration by mesh key if any slot still uses ShadowCaster
    local fbList = FALLBACK_SLOT_MATERIALS[lowMesh]
        or FALLBACK_SLOT_MATERIALS.sk_laurenshadow
    local numSlots = 0
    pcall(function() numSlots = comp:GetNumMaterials() end)
    local matNames = {}
    local hasShadow = false
    for idx = 0, math.max(0, (tonumber(numSlots) or 0) - 1) do
        local curMat = nil
        pcall(function() curMat = comp:GetMaterial(idx) end)
        local curName = Logger.SafeName(curMat)
        if (not Logger.IsValidObj(curMat)) or string.find(curName, "ShadowCaster", 1, true) then
            local fbPath = fbList[idx + 1] or fbList[1]
            local fbObj  = fbPath and Bridge.LoadOrFindAsset(fbPath) or nil
            if Logger.IsValidObj(fbObj) then
                pcall(function() comp:SetMaterial(idx, fbObj) end)
                curMat  = fbObj
                curName = Logger.SafeName(fbObj)
            end
        end
        if (not Logger.IsValidObj(curMat)) or string.find(curName, "ShadowCaster", 1, true) then
            hasShadow = true
        end
        table.insert(matNames, curName)
    end

    -- ShadowCaster starts on Channel 2 only (c0=false, c1=false, c2=true), which skips all scene lighting
    pcall(function() comp:SetLightingChannels(true, false, false) end)
    pcall(function()
        comp.LightingChannels.bChannel0 = true
        comp.LightingChannels.bChannel1 = false
        comp.LightingChannels.bChannel2 = false
    end)
    pcall(function() comp.OverlayMaterial = nil end)
    pcall(function() comp.bAffectDynamicIndirectLighting = true end)
    pcall(function() comp.bAffectDistanceFieldLighting = true end)
    pcall(function() comp.bRenderInMainPass = true end)
    pcall(function() comp:SetCastShadow(true) end)
    pcall(function() comp.bCastHiddenShadow = false end)
    pcall(function() comp.bSelfShadowOnly = false end)
    pcall(function() comp.bRenderCustomDepth = false end)

    local c0 = false
    pcall(function() c0 = (comp.LightingChannels.bChannel0 == true) end)
    State.VisualInfo = {
        meshName         = meshName,
        matNames         = matNames,
        hasShadowMat     = hasShadow,
        lightingChannel0 = c0,
    }
    Logger.Info(string.format("HumanVisuals textured mesh ready: %s slots=%d hasShadowMat=%s c0=%s",
        meshName, #matNames, tostring(hasShadow), tostring(c0)))
end

    -- Expose Survivor's 3P ShadowCaster mesh without black ShadowCaster override materials (or fallback Mesh)
    local hasVisibleBody = false
    pcall(function()
        local sc = pawn.ShadowCaster
        if Logger.IsValidObj(sc) and Logger.IsValidObj(sc:GetSkinnedAsset()) then
            sc:SetOnlyOwnerSee(false)
            sc:SetOwnerNoSee(false)
            sc:SetHiddenInGame(false, true)
            sc:SetVisibility(true, true)
            ApplyTexturedHumanMaterials(sc)
            State.ShadowMesh = sc
            hasVisibleBody = true
            Logger.Info("Unhid Survivor.ShadowCaster (" .. Logger.SafeName(sc:GetSkinnedAsset()) .. ")")
        end
    end)
    if not hasVisibleBody then
        pcall(function()
            local m = pawn.Mesh
            if Logger.IsValidObj(m) then
                m:SetOnlyOwnerSee(false)
                m:SetOwnerNoSee(false)
                m:SetHiddenInGame(false, true)
                m:SetVisibility(true, true)
                ApplyTexturedHumanMaterials(m)
                State.ShadowMesh = m
                Logger.Info("Unhid Survivor.Mesh fallback (" .. Logger.SafeName(m:GetSkinnedAsset()) .. ")")
            end
        end)
    end

    -- Prevent BP_ProjectXCharacter ReceiveTick / WeaponSystem from moving FirstPersonFollowComponent + orig Flashlight to PlayerCameraManager (Slenderman 3P camera)
    pcall(function() pawn.bAllowCameraTick = false end)
    pcall(function()
        local fpf = pawn.FirstPersonFollowComponent
        if Logger.IsValidObj(fpf) then
            fpf:SetComponentTickEnabled(false)
            State.FollowComp = fpf
        end
    end)
    pcall(function()
        local fpc = pawn.FirstPersonCameraComponent
        if Logger.IsValidObj(fpc) then
            fpc:SetComponentTickEnabled(false)
        end
    end)
    DisablePawnWeaponFlashlight(pawn)

    -- Replace Blueprint-owned pawn.Flashlight with a mod-owned SpotLightComponent attached directly to CapsuleComponent
    local origFl = nil
    pcall(function()
        if Logger.IsValidObj(pawn.Flashlight) then
            origFl = pawn.Flashlight
        end
    end)
    State.OrigFlashlight = origFl

    local modFl, modInten = CreateModFlashlight(pawn, origFl)
    if Logger.IsValidObj(modFl) then
        State.ModFlashlight          = modFl
        State.Flashlight             = modFl
        State.ModFlashlightIntensity = tonumber(modInten) or 60.0
        State.FlashlightEnabled      = true
        State.PointLightBaseIntensity  = nil
        State.PointLight0BaseIntensity = nil
        SilenceSpotLight(State.OrigFlashlight)
        Logger.Info(string.format("PAS_HumanFlashlight active (intensity=%.2f, origMuted=%s)",
            modInten, tostring(Logger.IsValidObj(State.OrigFlashlight))))
    elseif Logger.IsValidObj(origFl) then
        pcall(function()
            origFl:SetHiddenInGame(false, true)
            origFl:SetVisibility(true, true)
            local inten = 0.0
            pcall(function() inten = origFl.Intensity end)
            if type(inten) == "number" and inten <= 0.05 then
                origFl:SetIntensity(1.5)
            end
            State.Flashlight     = origFl
            State.OrigFlashlight = nil
            Logger.Warn(string.format("PAS_HumanFlashlight creation failed; using fallback pawn.Flashlight (intensity=%.2f)", tonumber(inten) or -1.0))
        end)
    end

    pcall(function()
        if Logger.IsValidObj(pawn.PointLight) then
            State.PointLight = pawn.PointLight
        end
    end)
    pcall(function()
        if Logger.IsValidObj(pawn.PointLight_0) then
            State.PointLight0 = pawn.PointLight_0
        end
    end)

    local cap = nil
    pcall(function() cap = pawn.CapsuleComponent end)
    if Logger.IsValidObj(cap) then
        local noneName = Bridge.FName("None")
        local relLoc   = { X = 28.0, Y = 12.0, Z = 42.0 }
        local relRot   = { Pitch = -4.0, Yaw = 0.0, Roll = 0.0 }
        AttachLightToCapsule(State.ModFlashlight or State.Flashlight, cap, noneName, relLoc, relRot)
        AttachLightToCapsule(State.PointLight, cap, noneName, relLoc, relRot)
        AttachLightToCapsule(State.PointLight0, cap, noneName, relLoc, relRot)
        AttachLightToCapsule(State.FollowComp, cap, noneName, relLoc, relRot)
    end

    -- Spawn AIController and possess Survivor cleanly
    local ai = Bridge.SpawnActorDeferred(world, "/Script/AIModule.AIController", { X = 0.0, Y = 0.0, Z = 0.0 }, 0.0)
    if not Logger.IsValidObj(ai) then
        Logger.Error("HumanVisuals.Init: Failed to spawn AIController")
        return false
    end

    pcall(function() ai:Possess(pawn) end)
    if Logger.IsValidObj(ps) then
        pcall(function() pawn:SetOwnedPlayerState(ps) end)
    end

    pcall(function()
        local cmc = pawn.CharacterMovement
        if Logger.IsValidObj(cmc) then
            cmc.bOrientRotationToMovement = false
            cmc.MaxWalkSpeed = Config.HUMAN.WALK_SPEED
        end
    end)

    pcall(function() pawn.bAllowCameraTick = false end)
    DisablePawnWeaponFlashlight(pawn)
    if Logger.IsValidObj(State.ModFlashlight) and Logger.IsValidObj(State.OrigFlashlight) then
        SilenceSpotLight(State.OrigFlashlight)
    end
    if Logger.IsValidObj(cap) and Logger.IsValidObj(State.FollowComp) then
        AttachLightToCapsule(State.FollowComp, cap, Bridge.FName("None"),
            { X = 28.0, Y = 12.0, Z = 42.0 }, { Pitch = -4.0, Yaw = 0.0, Roll = 0.0 })
    end

    local r = Bridge.GetActorRot(pawn)
    State.CurrentYaw   = r and r.Yaw or 0.0
    State.CurrentPitch = -4.0
    State.Survivor     = pawn
    State.AI           = ai
    State.PlayerState  = ps

    HumanVisuals.SuppressGlitchEffects(world, pc, true)
    HumanVisuals.UpdateLights(world, nil, nil)
    Logger.Info("HumanVisuals ready; pc.Pawn=" .. Logger.SafeName(Logger.IsValidObj(pc) and pc.Pawn or nil))
    return true, pawn, ai, ps
end

local GLITCH_PARAM_TOKENS = {
    "static", "glitch", "distort", "chromatic", "aberration",
    "noise", "tear", "scan", "shake", "vignette",
    "drain", "blur", "blood", "damage", "fear", "slender",
    "grain", "fringe", "spooky", "flash",
}

local function IsGlitchScalarName(lowName)
    for _, tok in ipairs(GLITCH_PARAM_TOKENS) do
        if string.find(lowName, tok, 1, true) then
            return true
        end
    end
    return false
end

local function DisablePostProcessComp(pp)
    if not Logger.IsValidObj(pp) then return end
    pcall(function() pp.bEnabled = false end)
    pcall(function() pp.BlendWeight = 0.0 end)
    pcall(function() pp.bUnbound = false end)
    pcall(function() pp:SetComponentTickEnabled(false) end)
    pcall(function() pp:Deactivate() end)
end

function HumanVisuals.SuppressGlitchEffects(world, pc, forceNow)
    local pawn = State.Survivor
    if Logger.IsValidObj(pawn) then
        pcall(function()
            local maxS = tonumber(pawn.MaxSanity)
            if maxS and maxS < 100.0 then pawn.MaxSanity = 100.0 end
            pawn.Sanity = 100.0
        end)
        pcall(function()
            local pp = pawn.PostProcess
            if Logger.IsValidObj(pp) then
                State.PostProcessComp = pp
                DisablePostProcessComp(pp)
            end
        end)
    end

    if Logger.IsValidObj(pc) then
        pcall(function()
            local pcm = pc.PlayerCameraManager
            if Logger.IsValidObj(pcm) then
                if pcm.StopAllCameraShakes then
                    pcm:StopAllCameraShakes(true)
                end
                if Logger.IsValidObj(pawn) then
                    for _, propName in ipairs({ "FOVShiftCameraModifier", "LimpLoopModifier" }) do
                        local cm = pawn[propName]
                        if Logger.IsValidObj(cm) then
                            pcall(function() cm:DisableModifier(true) end)
                            pcall(function() pcm:RemoveCameraModifier(cm) end)
                        end
                    end
                end
            end
        end)
    end

    local now = os.clock()
    if (not forceNow) and State.LastGlitchSweep >= 0.0 and (now - State.LastGlitchSweep) < 0.45 then
        return
    end
    State.LastGlitchSweep = now

    if Logger.IsValidObj(State.PostProcessComp) then
        DisablePostProcessComp(State.PostProcessComp)
    end

    -- Neutralize residual VisualSanityDrain components & vanilla glitch/sanity-drain actors
    if type(FindAllOf) == "function" then
        for _, vsc in ipairs(FindAllOf("VisualSanityDrainComponent") or {}) do
            if Logger.IsValidObj(vsc) then
                pcall(function() vsc:SetComponentTickEnabled(false) end)
                pcall(function() vsc:Deactivate() end)
            end
        end
        for _, clsName in ipairs({ "BP_SpookyGlitch_C", "BP_SanityDrainVolume_C", "SanityDrainVolume" }) do
            for _, act in ipairs(FindAllOf(clsName) or {}) do
                if Logger.IsValidObj(act) then
                    pcall(function() act:SetActorTickEnabled(false) end)
                    pcall(function() act:SetActorEnableCollision(false) end)
                    pcall(function() act:SetActorHiddenInGame(true) end)
                end
            end
        end
    end

    -- Reset glitch/static/sanity scalar parameters in VisualsMaterialParameterCollection and matching MPCs
    local kml = Bridge.GetClass("/Script/Engine.Default__KismetMaterialLibrary")
    if Logger.IsValidObj(world) and Logger.IsValidObj(kml) and kml.SetScalarParameterValue then
        local mpcSeen = {}
        local mpcList = {}
        local function AddMpcIfMatch(mpc)
            if not Logger.IsValidObj(mpc) then return end
            local addr = Bridge.GetObjAddr(mpc)
            if addr ~= 0 and not mpcSeen[addr] then
                mpcSeen[addr] = true
                table.insert(mpcList, mpc)
            end
        end

        if Logger.IsValidObj(pawn) then
            pcall(function() AddMpcIfMatch(pawn.VisualsMaterialParameterCollection) end)
        end
        if type(FindAllOf) == "function" then
            for _, mpc in ipairs(FindAllOf("MaterialParameterCollection") or {}) do
                if Logger.IsValidObj(mpc) then
                    local nm = string.lower(Logger.SafeName(mpc))
                    if string.find(nm, "playerstats", 1, true)
                        or string.find(nm, "screeneffect", 1, true)
                        or string.find(nm, "glitch", 1, true)
                        or string.find(nm, "static", 1, true)
                        or string.find(nm, "sanity", 1, true)
                        or string.find(nm, "visual", 1, true)
                    then
                        AddMpcIfMatch(mpc)
                    end
                end
            end
        end

        local logDiag = (not State.MpcLogged)
        for _, mpc in ipairs(mpcList) do
            local mpcName = Logger.SafeName(mpc)
            local scalarNames = {}
            local skippedNames = {}
            pcall(function()
                local scalars = mpc.ScalarParameters
                if scalars then
                    local count = #scalars
                    for i = 1, count do
                        local sp = scalars[i]
                        if sp then
                            local pName = sp.ParameterName
                            local pStr = tostring(pName and pName:ToString() or pName or "")
                            local low = string.lower(pStr)
                            if IsGlitchScalarName(low) or (string.find(low, "sanity", 1, true) ~= nil) then
                                local targetVal = IsGlitchScalarName(low) and 0.0 or 1.0
                                pcall(function() kml:SetScalarParameterValue(world, mpc, pName, targetVal) end)
                                State.MpcParamResetCount = State.MpcParamResetCount + 1
                                if logDiag then
                                    table.insert(scalarNames, string.format("%s=%.2f", pStr, targetVal))
                                end
                            elseif logDiag then
                                table.insert(skippedNames, pStr)
                            end
                        end
                    end
                end
            end)
            if logDiag and (#scalarNames > 0 or #skippedNames > 0) then
                Logger.Info(string.format("Glitch suppression MPC %s: reset=[%s] kept=[%s]",
                    mpcName, table.concat(scalarNames, ", "), table.concat(skippedNames, ", ")))
            end
        end
        State.MpcLogged = true
    end
end

function HumanVisuals.GetGlitchSuppressionInfo(pc)
    local sanity = -1.0
    local ppEnabled = false
    local ppBlend = 0.0
    if Logger.IsValidObj(State.Survivor) then
        pcall(function() sanity = tonumber(State.Survivor.Sanity) or -1.0 end)
        pcall(function()
            local pp = State.PostProcessComp or State.Survivor.PostProcess
            if Logger.IsValidObj(pp) then
                ppEnabled = (pp.bEnabled == true)
                ppBlend   = tonumber(pp.BlendWeight) or 0.0
            end
        end)
    end
    return {
        sanity        = sanity,
        ppEnabled     = ppEnabled,
        ppBlendWeight = ppBlend,
        mpcResetCount = State.MpcParamResetCount or 0,
    }
end

function HumanVisuals.UpdateLights(world, slenderActor, camActor)
    if not Logger.IsValidObj(State.Survivor) then return end
    local hLoc = Bridge.GetActorLoc(State.Survivor)
    if not hLoc then return end

    local yaw   = State.CurrentYaw or 0.0
    local pitch = State.CurrentPitch or -4.0
    local fx, fy, _ = Bridge.ForwardFromRot(0.0, yaw)
    local flPos = {
        X = hLoc.X + fx * 28.0,
        Y = hLoc.Y + fy * 28.0,
        Z = hLoc.Z + 42.0,
    }
    local flRot = { Pitch = pitch, Yaw = yaw, Roll = 0.0 }

    -- Scan for stray active SpotLightComponents BEFORE snapping/muting so any post-tick camera drift is detected and silenced
    local slLoc  = Logger.IsValidObj(slenderActor) and Bridge.GetActorLoc(slenderActor) or nil
    local camLoc = Logger.IsValidObj(camActor) and Bridge.GetActorLoc(camActor) or nil
    if slLoc or camLoc then
        local now = os.clock()
        local needScan = (slLoc ~= nil and (now - State.LastLightScan) >= 0.4)
            or (camLoc ~= nil and (now - State.LastCamScan) >= 0.4)
        if needScan then
            if slLoc  then State.LastLightScan = now end
            if camLoc then State.LastCamScan   = now end

            ForEachStraySpotLight(hLoc, slLoc, camLoc, 650.0, 250.0, function(slc, slcAddr, fullName, dHuman, dSl, dCam)
                SilenceSpotLight(slc)
                if not State.LoggedStrayLights[slcAddr] then
                    State.LoggedStrayLights[slcAddr] = true
                    Logger.Info(string.format("Muted stray SpotLightComponent: %s (dHuman=%.0f dSl=%.0f dCam=%.0f)",
                        fullName, dHuman, dSl, dCam))
                end
            end)
        end
    end

    if Logger.IsValidObj(State.OrigFlashlight)
        and Bridge.GetObjAddr(State.OrigFlashlight) ~= Bridge.GetObjAddr(State.ModFlashlight)
    then
        SilenceSpotLight(State.OrigFlashlight)
    end

    local activeFl = Logger.IsValidObj(State.ModFlashlight) and State.ModFlashlight or State.Flashlight
    if Logger.IsValidObj(activeFl) then
        pcall(function()
            activeFl:K2_SetWorldLocationAndRotation(flPos, flRot, false, {}, true)
        end)
    end
    if Logger.IsValidObj(State.PointLight) then
        pcall(function()
            State.PointLight:K2_SetWorldLocation(flPos, false, {}, true)
        end)
    end
    if Logger.IsValidObj(State.PointLight0) then
        pcall(function()
            State.PointLight0:K2_SetWorldLocation(hLoc, false, {}, true)
        end)
    end
    if Logger.IsValidObj(State.FollowComp) then
        pcall(function()
            State.FollowComp:K2_SetWorldLocationAndRotation(flPos, flRot, false, {}, true)
        end)
    end
end

function HumanVisuals.IsFlashlightEnabled()
    return State.FlashlightEnabled == true
end

function HumanVisuals.SetFlashlightEnabled(enabled)
    local on = (enabled == true)
    State.FlashlightEnabled = on
    local fl = Logger.IsValidObj(State.ModFlashlight) and State.ModFlashlight or State.Flashlight
    if Logger.IsValidObj(fl) then
        pcall(function() fl:SetVisibility(on, false) end)
        pcall(function() fl:SetHiddenInGame(not on, false) end)
        pcall(function() fl:SetIntensity(on and (State.ModFlashlightIntensity or 60.0) or 0.0) end)
        pcall(function() if fl.SetAffectsWorld then fl:SetAffectsWorld(on) end end)
    end
    if Logger.IsValidObj(State.OrigFlashlight) then
        SilenceSpotLight(State.OrigFlashlight)
    end
    if Logger.IsValidObj(State.PointLight) then
        if State.PointLightBaseIntensity == nil then
            pcall(function() State.PointLightBaseIntensity = tonumber(State.PointLight.Intensity) or 5.0 end)
        end
        pcall(function() State.PointLight:SetVisibility(on, false) end)
        pcall(function() State.PointLight:SetIntensity(on and (State.PointLightBaseIntensity or 5.0) or 0.0) end)
        pcall(function() if State.PointLight.SetAffectsWorld then State.PointLight:SetAffectsWorld(on) end end)
    end
    if Logger.IsValidObj(State.PointLight0) then
        if State.PointLight0BaseIntensity == nil then
            pcall(function() State.PointLight0BaseIntensity = tonumber(State.PointLight0.Intensity) or 5.0 end)
        end
        pcall(function() State.PointLight0:SetVisibility(on, false) end)
        pcall(function() State.PointLight0:SetIntensity(on and (State.PointLight0BaseIntensity or 5.0) or 0.0) end)
        pcall(function() if State.PointLight0.SetAffectsWorld then State.PointLight0:SetAffectsWorld(on) end end)
    end
end

function HumanVisuals.GetFlashlightInfo(slenderActor, camActor)
    local info = {
        valid            = false,
        distToHuman      = 9999.0,
        distToSlender    = 9999.0,
        distToCam        = 9999.0,
        activeStrayCount = 0,
        details          = "none",
    }

    local hLoc   = Logger.IsValidObj(State.Survivor) and Bridge.GetActorLoc(State.Survivor) or nil
    local slLoc  = Logger.IsValidObj(slenderActor) and Bridge.GetActorLoc(slenderActor) or nil
    local camLoc = Logger.IsValidObj(camActor) and Bridge.GetActorLoc(camActor) or nil

    local activeFl = Logger.IsValidObj(State.ModFlashlight) and State.ModFlashlight or State.Flashlight
    local flLoc = GetCompWorldLoc(activeFl)
    if flLoc then
        info.valid = true
        if hLoc   then info.distToHuman   = Bridge.Dist(flLoc, hLoc)   end
        if slLoc  then info.distToSlender = Bridge.Dist(flLoc, slLoc)  end
        if camLoc then info.distToCam     = Bridge.Dist(flLoc, camLoc) end
    end

    local strayList = {}
    ForEachStraySpotLight(hLoc, slLoc, camLoc, 650.0, nil, function(slc, _, _, dHuman, dSl, dCam)
        info.activeStrayCount = info.activeStrayCount + 1
        local inten = 0.0
        pcall(function() inten = tonumber(slc.Intensity) or 0.0 end)
        table.insert(strayList, string.format("%s(inten=%.2f,dH=%.0f,dSl=%.0f,dCam=%.0f)",
            Logger.SafeName(slc), inten, dHuman, dSl, dCam))
    end)
    if #strayList > 0 then
        info.details = table.concat(strayList, "; ")
    end

    return info
end

function HumanVisuals.SetYawImmediate(yawDeg)
    if not Logger.IsValidObj(State.Survivor) then return end
    State.CurrentYaw = Bridge.NormalizeAngle(yawDeg)
    pcall(function()
        State.Survivor:K2_SetActorRotation({ Pitch = 0.0, Yaw = State.CurrentYaw, Roll = 0.0 }, false)
    end)
    if Logger.IsValidObj(State.AI) then
        pcall(function()
            State.AI:SetControlRotation({ Pitch = 0.0, Yaw = State.CurrentYaw, Roll = 0.0 })
        end)
    end
    HumanVisuals.UpdateLights()
end

function HumanVisuals.AimToward(targetYaw, targetPitch, dt, rotSpeed)
    if not Logger.IsValidObj(State.Survivor) then return end
    local alpha = math.min(1.0, (rotSpeed or 7.5) * (dt or 0.016))
    State.CurrentYaw   = Bridge.LerpAngle(State.CurrentYaw, targetYaw, alpha)
    State.CurrentPitch = targetPitch or -4.0
    pcall(function()
        State.Survivor:K2_SetActorRotation({ Pitch = 0.0, Yaw = State.CurrentYaw, Roll = 0.0 }, false)
    end)
    if Logger.IsValidObj(State.AI) then
        pcall(function()
            State.AI:SetControlRotation({ Pitch = targetPitch or 0.0, Yaw = State.CurrentYaw, Roll = 0.0 })
        end)
    end
    HumanVisuals.UpdateLights()
end

function HumanVisuals.SetMoveSpeed(speedCmPerSec)
    if not Logger.IsValidObj(State.Survivor) then return end
    pcall(function()
        local cmc = State.Survivor.CharacterMovement
        if Logger.IsValidObj(cmc) then
            cmc.MaxWalkSpeed = speedCmPerSec
        end
    end)
end

return HumanVisuals
