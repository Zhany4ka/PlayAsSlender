-- Cut upright wall panels in their own coordinate system. Each remaining strip
-- owns its collision and can be struck again independently.
local Bridge = require("ue_bridge")
local Logger = require("logger")
local Config = require("config")
local Breach = {}
local remnants, originals, checkedMeshes = {}, {}, {}
local count = 0
local cubePath = "/Engine/BasicShapes/Cube.Cube"
local maxRemnants = 220

local function destroy(actor)
    if Logger.IsValidObj(actor) then pcall(function() actor:K2_DestroyActor() end) end
end

function Breach.IsRemnant(comp)
    return remnants[Bridge.GetObjAddr(comp)] ~= nil
end

local function restore(s)
    if Logger.IsValidObj(s.comp) then
        pcall(function()
            s.comp:SetVisibility(s.visible, false)
            s.comp:SetHiddenInGame(s.hidden, false)
            s.comp:SetCollisionEnabled(s.collision)
        end)
    end
end

function Breach.Reset()
    for _, rec in pairs(remnants) do destroy(rec.actor) end
    for _, s in ipairs(originals) do restore(s) end
    remnants, originals, checkedMeshes, count = {}, {}, {}, 0
end

local function worldPoint(p, w, z, depth)
    depth = depth or 0
    return Bridge.Vec(p.center.X + p.ux*w - p.uy*depth, p.center.Y + p.uy*w + p.ux*depth, z)
end

local function wallCoord(p, point)
    return (point.X - p.center.X) * p.ux + (point.Y - p.center.Y) * p.uy
end

local function panelShape(comp, center, facing)
    local lo, hi = { X = 0, Y = 0, Z = 0 }, { X = 0, Y = 0, Z = 0 }
    comp:GetLocalBounds(lo, hi)
    local scale, rot = comp:K2_GetComponentScale(), comp:K2_GetComponentRotation()
    -- A cooked wall may be authored flat and rotated upright by the level.
    local yaw, pitch, roll = math.rad(rot.Yaw), math.rad(rot.Pitch), math.rad(rot.Roll)
    local cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    local cr, sr = math.cos(roll), math.sin(roll)
    local axes = {
        X = {x = cp*cy, y = cp*sy, z = sp},
        Y = {x = sr*sp*cy-cr*sy, y = sr*sp*sy+cr*cy, z = -sr*cp},
        Z = {x = -cr*sp*cy-sr*sy, y = sr*cy-cr*sp*sy, z = cr*cp},
    }
    local h, horizontal = nil, {}
    for axis, direction in pairs(axes) do
        direction.length = math.abs((hi[axis]-lo[axis]) * scale[axis])
        if math.abs(direction.z) >= 0.985 then h = direction.length
        else horizontal[#horizontal+1] = direction end
    end
    if not h or #horizontal ~= 2 then return end
    local across, through = horizontal[1], horizontal[2]
    if across.length < through.length then across, through = through, across end
    local w, d = across.length, through.length
    if w < (facing and 45 or 155) or w > 4800 or h < (facing and 45 or 140) or h > 750
        or d > 68 or d > w * 0.24 then return end
    local angle = math.atan(across.y, across.x)
    return {center = center, ux = math.cos(angle), uy = math.sin(angle), yaw = math.deg(angle),
        width = w, height = h, depth = math.max(2, d)}
end

local WALL_ALLOW_TOKENS = {
    "wall", "siding", "plaster", "drywall", "brick", "partition",
    "cabin", "barn", "shed", "panel", "corrugated",
}
local WALL_EXCLUDE_TOKENS = {
    "door", "window", "archway", "frame", "trim", "baseboard", "molding",
    "decal", "opening", "roof", "floor", "ceiling", "stair",
}

function Breach.Describe(comp, center, normal, name, facing)
    if not center or not normal or math.abs(normal.Z) > 0.45 then return end
    local old = remnants[Bridge.GetObjAddr(comp)]
    if old then return old.shape end
    local meshName = string.lower(Logger.SafeName(comp.StaticMesh))
    local blob = string.lower(name or "") .. " " .. meshName
    local allowed = false
    for _, tok in ipairs(WALL_ALLOW_TOKENS) do
        if blob:find(tok, 1, true) then
            allowed = true
            break
        end
    end
    if not allowed then return end
    for _, token in ipairs(WALL_EXCLUDE_TOKENS) do
        if blob:find(token, 1, true) then return end
    end
    local ok, p = pcall(panelShape, comp, center, facing)
    if ok and p and math.abs(-p.uy * normal.X + p.ux * normal.Y) > 0.90 then return p end
end

-- Refuse to fill doorways and irregular mesh silhouettes with solid rubble.
-- Trace this component alone so overlapping interior/exterior skins are valid.
local function solidFace(comp, p, trustCollisionless)
    if Breach.IsRemnant(comp) then return true end
    local mesh = Bridge.GetObjAddr(comp.StaticMesh)
    if mesh == 0 then return false end
    if mesh == Bridge.GetObjAddr(Bridge.LoadOrFindAsset(cubePath)) then return true end
    local cols, rows = math.ceil(p.width / 64), math.ceil(p.height / 64)
    local key = string.format("%s/%d/%d/%.0f", mesh, cols, rows, p.depth)
    if checkedMeshes[key] ~= nil then return checkedMeshes[key] end
    local colEn = tonumber(comp:GetCollisionEnabled()) or 0
    local restoredCol = false
    if colEn == 0 then
        pcall(function() comp:SetCollisionEnabled(1); restoredCol = true end)
    end
    local d = p.depth * 0.5 + 8
    local isSolid = true
    for i = 0, cols do
        local w = (i / cols - 0.5) * (p.width - 10)
        for j = 0, rows do
            local z = p.center.Z + (j / rows - 0.5) * (p.height - 10)
            local a, b = worldPoint(p, w, z, d), worldPoint(p, w, z, -d)
            if not comp:K2_LineTraceComponent(a, b, true, false, false, {}, {}, {}, {}) and
               not comp:K2_LineTraceComponent(b, a, true, false, false, {}, {}, {}, {}) then
                isSolid = false
                break
            end
        end
        if not isSolid then break end
    end
    if restoredCol then
        pcall(function() comp:SetCollisionEnabled(colEn) end)
    end
    if isSolid then
        checkedMeshes[key] = true
        return true
    end
    if colEn == 0 and trustCollisionless then
        -- Render-only decorative reverse skin on same blueprint; trust Describe token filter without poisoning cache.
        return true
    end
    if colEn ~= 0 then
        checkedMeshes[key] = false
    end
    return false
end

local function cutLimits(p, cut)
    local w = wallCoord(p, cut.center)
    return math.max(-p.width/2, w-cut.width/2), math.min(p.width/2, w+cut.width/2),
        math.max(p.center.Z-p.height/2, cut.center.Z-cut.height/2),
        math.min(p.center.Z+p.height/2, cut.center.Z+cut.height/2)
end

local function split(p, point, heavy, sharedCut)
    local halfW = p.width / 2
    local bottom, top = p.center.Z - p.height / 2, p.center.Z + p.height / 2
    local width = math.min(p.width, heavy and 180 or 130)
    local halfHeight = (Config.SLENDER and Config.SLENDER.CAPSULE_HALF_HEIGHT) or 115
    local height = math.min(p.height, halfHeight * 2 + (heavy and 40 or 22))
    local left = Bridge.Clamp(wallCoord(p, point) - width/2, -halfW, halfW-width)
    local low = Bridge.Clamp(point.Z - height/2, bottom, top-height)
    if point.Z - bottom <= height - 12 then low = bottom end
    local right, high = left + width, low + height
    if left + halfW < 12 then left = -halfW end
    if halfW - right < 12 then right = halfW end
    if top - high < 12 then high = top end
    if sharedCut then left, right, low, high = cutLimits(p, sharedCut) end
    local strips = {}
    local function add(l, r, b, t)
        if r > l and t > b then
            strips[#strips+1] = {center = worldPoint(p, (l+r)/2, (b+t)/2), ux = p.ux,
                uy = p.uy, yaw = p.yaw, width = r-l, height = t-b, depth = p.depth}
        end
    end
    add(-halfW, left, bottom, top)
    add(right, halfW, bottom, top)
    add(left, right, bottom, low)
    add(left, right, high, top)
    return strips, {center = worldPoint(p, (left+right)/2, (low+high)/2), ux=p.ux, uy=p.uy,
        yaw=p.yaw, width=right-left, height=high-low, depth=p.depth}
end

local function makeStrip(world, p, cube, layer)
    local actor = Bridge.SpawnActorDeferred(world, "/Script/Engine.StaticMeshActor", p.center, p.yaw)
    if not Logger.IsValidObj(actor) then return end
    local ok, rec = pcall(function()
        local comp = actor.StaticMeshComponent
        comp:SetMobility(2)
        if not comp:SetStaticMesh(cube) then return end
        comp:SetWorldScale3D(Bridge.Vec(p.width/100, p.depth/100, p.height/100))
        if Logger.IsValidObj(layer.mat) then comp:SetMaterial(0, layer.mat) end
        comp:SetCollisionProfileName(layer.profile, true)
        comp:SetCollisionEnabled(layer.collision)
        comp:SetCollisionObjectType(layer.objectType)
        for ch = 0, #layer.responses do comp:SetCollisionResponseToChannel(ch, layer.responses[ch]) end
        if tonumber(comp:GetCollisionEnabled()) ~= layer.collision then return end
        local id = Bridge.GetObjAddr(comp)
        if id == 0 then return end
        return {id=id, actor=actor, comp=comp, shape=p, mat=layer.mat, kind=layer.kind}
    end)
    if ok and rec then return rec end
    destroy(actor)
end

function Breach.Material(comp)
    local rec = remnants[Bridge.GetObjAddr(comp)]
    if rec then return rec.kind, rec.mat end
end

local function readLayer(comp, shape, mat, kind, point, heavy, sharedCut, trustCollisionless)
    local layer = {id=Bridge.GetObjAddr(comp), comp=comp, collision=tonumber(comp:GetCollisionEnabled()), mat=mat, kind=kind,
        visible=comp:IsVisible(), hidden=comp.bHiddenInGame == true, profile=comp:GetCollisionProfileName(),
        objectType=comp:GetCollisionObjectType(), responses={}}
    if not layer.visible or layer.hidden then return end
    local solid = solidFace(comp, shape, trustCollisionless)
    if not solid then return end
    -- ECC_MAX in UE 5.3 is 33, the usable game channels end at 31.
    for ch=0,31 do layer.responses[ch] = comp:GetCollisionResponseToChannel(ch) end
    layer.strips, layer.cut = split(shape, point, heavy, sharedCut)
    return layer
end

local TRIM_TOKENS = {
    "trim", "baseboard", "molding", "peel", "decal",
    "switch", "thermostat", "outlet", "painting", "poster", "picture",
}

local function isTrimOverlap(name, ext, center, p, cut)
    if math.max(ext.X, ext.Y, ext.Z) > 220 then return false end
    local match = false
    for _, tok in ipairs(TRIM_TOKENS) do
        if name:find(tok, 1, true) then match = true; break end
    end
    if not match then return false end
    local du = (center.X - cut.center.X) * p.ux + (center.Y - cut.center.Y) * p.uy
    local dn = (center.X - cut.center.X) * (-p.uy) + (center.Y - cut.center.Y) * p.ux
    local extU = math.abs(ext.X * p.ux) + math.abs(ext.Y * p.uy)
    local extN = math.abs(ext.X * (-p.uy)) + math.abs(ext.Y * p.ux)
    return math.abs(du) <= (cut.width * 0.5 + extU + 12)
        and math.abs(dn) <= (cut.depth * 0.5 + extN + 58)
        and (center.Z + ext.Z) >= (cut.center.Z - cut.height * 0.5 - 12)
        and (center.Z - ext.Z) <= (cut.center.Z + cut.height * 0.5 + 12)
end

-- Stage every strip of every facing layer before changing any source collision.
function Breach.Open(world, comp, p, point, normal, mat, kind, heavy, ignore, classify, protected)
    local cube = Bridge.LoadOrFindAsset(cubePath)
    if not Logger.IsValidObj(cube) then return end
    local ok, first = pcall(readLayer, comp, p, mat, kind, point, heavy, nil, false)
    if not ok or not first then return end
    local layers = {first}
    local trims = {}
    local compOwner = nil
    pcall(function() compOwner = comp:GetOwner() end)
    local compOwnerAddr = Bridge.GetObjAddr(compOwner)
    local seen = {[Bridge.GetObjAddr(comp)]=true}
    local candidates = Bridge.SphereOverlapComponents(world, first.cut.center,
        math.sqrt(first.cut.width^2 + first.cut.height^2)/2 + 75, ignore)
    -- Piercing trace through impact point along -normal so paired back-face wall actors are never missed.
    local pierceIgnore = {}
    for _, a in ipairs(ignore or {}) do pierceIgnore[#pierceIgnore + 1] = a end
    if Logger.IsValidObj(compOwner) then pierceIgnore[#pierceIgnore + 1] = compOwner end
    local pStart = Bridge.Vec(point.X + normal.X * 10, point.Y + normal.Y * 10, point.Z + normal.Z * 10)
    local pEnd   = Bridge.Vec(point.X - normal.X * 88, point.Y - normal.Y * 88, point.Z - normal.Z * 88)
    for _ = 1, 4 do
        local ph, pi = Bridge.LineTrace(world, pStart, pEnd, pierceIgnore, 0, false)
        if not ph or not pi or not Logger.IsValidObj(pi.Component) then break end
        candidates[#candidates + 1] = pi.Component
        if Logger.IsValidObj(pi.Actor) then
            pierceIgnore[#pierceIgnore + 1] = pi.Actor
        else
            break
        end
        if pi.ImpactPoint then
            pStart = Bridge.Vec(pi.ImpactPoint.X - normal.X * 4, pi.ImpactPoint.Y - normal.Y * 4, pi.ImpactPoint.Z - normal.Z * 4)
        end
    end
    -- A blueprint may own a decorative, collisionless reverse face.
    pcall(function()
        local parts = comp:GetOwner():K2_GetComponentsByClass(Bridge.GetClass("/Script/Engine.StaticMeshComponent"))
        if type(parts) == "table" then
            for _, entry in ipairs(parts) do
                local c = Bridge.ResolveObjectParam(entry)
                if c then candidates[#candidates+1] = c end
            end
        elseif parts then
            parts:ForEach(function(_, entry) candidates[#candidates+1] = entry:get() end)
        end
    end)
    local ism = Bridge.GetClass("/Script/Engine.InstancedStaticMeshComponent")
    for _, other in ipairs(candidates) do
        local id = Bridge.GetObjAddr(other)
        if id ~= 0 and not seen[id] then
            seen[id] = true
            local owner = other:GetOwner()
            local center, ext = Bridge.GetComponentBounds(other)
            if center and ext and Logger.IsValidObj(owner) and owner.bHidden ~= true
                and other.bHiddenInGame ~= true and other:IsVisible()
                and not (Logger.IsValidObj(ism) and other:IsA(ism))
                and not protected(other, owner, normal, ext, center) then
                local k, m, name = classify(other, owner)
                local otherKind, otherMat = Breach.Material(other)
                local q = Breach.Describe(other, center, normal, name, true)
                if q and math.abs(p.ux*q.ux + p.uy*q.uy) > 0.996 and
                   math.abs((center.X-p.center.X)*(-p.uy) + (center.Y-p.center.Y)*p.ux) <= math.max(68, (p.depth+q.depth)/2 + 52) and
                   not other:IsSimulatingPhysics(Bridge.FName("None")) then
                    local left, right, low, high = cutLimits(q, first.cut)
                    if right-left > 1 and high-low > 1 then
                        local sameOwner = (compOwnerAddr ~= 0) and (Bridge.GetObjAddr(owner) == compOwnerAddr)
                        local got, layer = pcall(readLayer, other, q, otherMat or m, otherKind or k, point, heavy, first.cut, sameOwner)
                        if got and layer then
                            layers[#layers+1] = layer
                        end
                    end
                elseif not other:IsSimulatingPhysics(Bridge.FName("None")) and isTrimOverlap(name, ext, center, p, first.cut) then
                    trims[#trims+1] = { comp = other, owner = owner, blob = name, orig = center, ext = ext }
                end
            end
        end
    end
    local total = count
    for _, layer in ipairs(layers) do
        total = total + #layer.strips - (Breach.IsRemnant(layer.comp) and 1 or 0)
    end
    if total > maxRemnants then return end
    local staged = {}
    local function cancel()
        for _, rec in ipairs(staged) do destroy(rec.actor) end
    end
    for _, layer in ipairs(layers) do
        for _, shape in ipairs(layer.strips) do
            local rec = makeStrip(world, shape, cube, layer)
            if not rec then cancel(); return end
            staged[#staged+1] = rec
        end
    end
    for i, layer in ipairs(layers) do
        local disabled, verified = pcall(function()
            layer.comp:SetCollisionEnabled(0)
            layer.comp:SetHiddenInGame(true, false)
            layer.comp:SetVisibility(false, false)
            return tonumber(layer.comp:GetCollisionEnabled()) == 0 and not layer.comp:IsVisible()
        end)
        if not disabled or not verified then
            for j=1,i do restore(layers[j]) end
            cancel()
            return
        end
    end
    for _, layer in ipairs(layers) do
        local id = Bridge.GetObjAddr(layer.comp)
        local old = remnants[id]
        if old then destroy(old.actor); remnants[id] = nil
        else originals[#originals+1] = {comp=layer.comp, visible=layer.visible, hidden=layer.hidden, collision=layer.collision} end
    end
    for _, rec in ipairs(staged) do remnants[rec.id] = rec end
    count = total
    return first.cut, layers, trims
end

return Breach
