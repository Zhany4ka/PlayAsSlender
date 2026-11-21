-- PlayAsSlender Smart Hybrid Navigation (Physics-Verified House BFS + Doorway Tunnels + Dual-Height Whiskers + Non-Looping Corner Breakout)
local Config = require("config")
local Logger = require("logger")
local Bridge = require("ue_bridge")

local HumanNav = {}

local State = {
    Initialized       = false,
    HasNavMesh        = true,
    Nodes             = {}, -- { id, pos, name, isLandmark, isDoorCenter, adj = { { to, dist } } }
    Doors             = {}, -- cached BP_DoorBase_C actors for automatic AI opening
    Windows           = {}, -- cached 1F BP_InteractableWindow_C actors to prevent window-hugging edges
    GraphIgnore       = {}, -- survivor + openable BP_DoorBase_C actors
    NodeBlacklist     = {}, -- [nodeId] = expiresAt
    EdgePenalties     = {}, -- ["a_b"] = expiresAt
    RouteWaypoints    = {},
    RouteNodeIds      = {},
    RouteDoorFlags    = {},
    RouteIdx          = 1,
    FinalGoal         = nil,
    UseDangerDetour   = false,
    NavMeshPts        = nil,
    LastReplanTime    = 0.0,
    LastDoorCheckTime = 0.0,
    OpenedDoorCount   = 0,
    DoorTunnelCount   = 0,
    CurrentSubTarget  = nil,
    NavStatusStr      = "Idle",
    IntendsToMove     = false,

    -- Non-looping Stuck detection & Corner-Breakout Recovery
    StuckSamplePos          = nil,
    StuckTimer              = 0.0,
    RecoveryStage           = 0,
    RecoveryTimer           = 0.0,
    RecoveryDir             = nil,
    ForceReplanAfterRecovery = false,
    EndpointStallTimer      = 0.0,
    ConsecutiveStucks       = 0,
    StuckCount              = 0,
}

function HumanNav.Reset()
    State.Initialized             = false
    State.HasNavMesh              = true
    State.Nodes                   = {}
    State.Doors                   = {}
    State.Windows                 = {}
    State.GraphIgnore             = {}
    State.NodeBlacklist           = {}
    State.EdgePenalties           = {}
    State.RouteWaypoints          = {}
    State.RouteNodeIds            = {}
    State.RouteDoorFlags          = {}
    State.RouteIdx                = 1
    State.FinalGoal               = nil
    State.UseDangerDetour         = false
    State.NavMeshPts              = nil
    State.LastReplanTime          = 0.0
    State.LastDoorCheckTime       = 0.0
    State.OpenedDoorCount         = 0
    State.DoorTunnelCount         = 0
    State.CurrentSubTarget        = nil
    State.NavStatusStr            = "Idle"
    State.IntendsToMove           = false
    State.StuckSamplePos          = nil
    State.StuckTimer              = 0.0
    State.RecoveryStage           = 0
    State.RecoveryTimer           = 0.0
    State.RecoveryDir             = nil
    State.ForceReplanAfterRecovery = false
    State.EndpointStallTimer      = 0.0
    State.ConsecutiveStucks       = 0
    State.StuckCount              = 0
end

local function EdgeKey(a, b)
    return (a < b) and (tostring(a) .. "_" .. tostring(b)) or (tostring(b) .. "_" .. tostring(a))
end

local function PolylineLength(pts)
    local total = 0.0
    for i = 2, #pts do
        total = total + Bridge.Dist(pts[i - 1], pts[i])
    end
    return total
end

local function DistPointToSeg2D(px, py, ax, ay, bx, by)
    local dx = bx - ax
    local dy = by - ay
    local lenSq = dx * dx + dy * dy
    if lenSq < 1e-4 then
        local ex = px - ax
        local ey = py - ay
        return math.sqrt(ex * ex + ey * ey)
    end
    local t = Bridge.Clamp(((px - ax) * dx + (py - ay) * dy) / lenSq, 0.0, 1.0)
    local cx = ax + t * dx
    local cy = ay + t * dy
    local rx = px - cx
    local ry = py - cy
    return math.sqrt(rx * rx + ry * ry)
end

local function SegmentCrossesWindow(pA, pB, radius)
    if not State.Windows or #State.Windows == 0 then return false end
    local r = radius or 68.0
    for _, w in ipairs(State.Windows) do
        local d = DistPointToSeg2D(w.pos.X, w.pos.Y, pA.X, pA.Y, pB.X, pB.Y)
        if d < r then
            return true
        end
    end
    return false
end

local function AddUndirectedEdge(nodes, i, j, dist)
    if not nodes[i] or not nodes[j] or i == j then return end
    local hasIJ = false
    for _, e in ipairs(nodes[i].adj) do
        if e.to == j then
            hasIJ = true
            break
        end
    end
    if not hasIJ then
        table.insert(nodes[i].adj, { to = j, dist = dist })
    end
    local hasJI = false
    for _, e in ipairs(nodes[j].adj) do
        if e.to == i then
            hasJI = true
            break
        end
    end
    if not hasJI then
        table.insert(nodes[j].adj, { to = i, dist = dist })
    end
end

function HumanNav.IsSegmentWalkable(world, pA, pB, ignoreActors, halfWidth, opts)
    if not world or not pA or not pB then return false end
    opts = opts or {}
    local ignore = ignoreActors or State.GraphIgnore
    local floorA = pA.Z - 92.0
    local floorB = pB.Z - 92.0
    local d2D = Bridge.Dist2D(pA, pB)
    local dZ = math.abs(floorA - floorB)

    if dZ > 110.0 then return false end
    if d2D > 1.0 and dZ > 48.0 and (dZ / d2D) > 0.65 then return false end

    if (not opts.skipWindow) and SegmentCrossesWindow(pA, pB, 68.0) then
        return false
    end

    -- Early-exit knee ray (dual Visibility + Camera channel catches sills, walls, railings, blocking volumes)
    if Bridge.IsRayBlockedDual(world,
        { X = pA.X, Y = pA.Y, Z = floorA + 42.0 },
        { X = pB.X, Y = pB.Y, Z = floorB + 42.0 },
        ignore) then
        return false
    end

    -- Waist & chest center rays
    if Bridge.LineTrace(world,
        { X = pA.X, Y = pA.Y, Z = floorA + 90.0 },
        { X = pB.X, Y = pB.Y, Z = floorB + 90.0 },
        ignore, 0, false) then
        return false
    end
    if Bridge.LineTrace(world,
        { X = pA.X, Y = pA.Y, Z = floorA + 142.0 },
        { X = pB.X, Y = pB.Y, Z = floorB + 142.0 },
        ignore, 0, false) then
        return false
    end

    -- Capsule shoulder rays at +-halfWidth
    local hw = halfWidth or 26.0
    if hw > 1.0 and d2D > 5.0 then
        local perpX = -(pB.Y - pA.Y) / d2D
        local perpY = (pB.X - pA.X) / d2D
        for _, sgn in ipairs({ -1.0, 1.0 }) do
            local ox = perpX * hw * sgn
            local oy = perpY * hw * sgn
            if Bridge.LineTrace(world,
                { X = pA.X + ox, Y = pA.Y + oy, Z = floorA + 48.0 },
                { X = pB.X + ox, Y = pB.Y + oy, Z = floorB + 48.0 },
                ignore, 0, false) then
                return false
            end
            if Bridge.LineTrace(world,
                { X = pA.X + ox, Y = pA.Y + oy, Z = floorA + 90.0 },
                { X = pB.X + ox, Y = pB.Y + oy, Z = floorB + 90.0 },
                ignore, 0, false) then
                return false
            end
        end
    end

    -- Midpoint ground continuity check
    if (not opts.skipMidGround) and d2D > 130.0 then
        local tList = (d2D > 280.0) and { 0.33, 0.67 } or { 0.50 }
        for _, t in ipairs(tList) do
            local mx = pA.X + (pB.X - pA.X) * t
            local my = pA.Y + (pB.Y - pA.Y) * t
            local interpFloor = floorA + (floorB - floorA) * t
            local startZ = interpFloor + 115.0
            local endZ   = interpFloor - 135.0
            local gHit, gz, norm = Bridge.GroundTrace(world, mx, my, startZ, endZ, ignore)
            if (not gHit) or (not gz) or ((startZ - gz) < 15.0) or (not norm) or (norm.Z < 0.65) or (math.abs(gz - interpFloor) > 75.0) then
                return false
            end
        end
    end

    return true
end

local function IsDoorOpenableAI(door)
    if not Logger.IsValidObj(door) then return false end
    local dn = Logger.SafeName(door)
    if string.find(dn, "Locked", 1, true) then return false end
    local openAI = true
    pcall(function() openAI = (door.bOpenableByAI ~= false) end)
    if string.find(dn, "BP_Door_Main", 1, true) then openAI = true end
    return openAI
end

local function DiscoverDoorTunnels(world, nodes, graphIgnore, anchorPos, isHouse1F)
    local tunnels = {}
    local startZTopOff = 125.0
    local endZBotOff   = -140.0

    for _, dEntry in ipairs(State.Doors) do
        local dl = dEntry.pos
        local openable = IsDoorOpenableAI(dEntry.actor)
        local inScanBounds = false
        if isHouse1F then
            inScanBounds = (dl.Z >= 8850.0 and dl.Z <= 9350.0
                and dl.X >= 40500.0 and dl.X <= 46800.0
                and dl.Y >= 57800.0 and dl.Y <= 62400.0)
        elseif anchorPos then
            inScanBounds = (Bridge.Dist2D(dl, anchorPos) <= 9500.0 and math.abs(dl.Z - anchorPos.Z) <= 450.0)
        end
        if openable and inScanBounds then
            local rot = Bridge.GetActorRot(dEntry.actor) or { Yaw = 0.0 }
            local fx, fy = Bridge.ForwardFromRot(0.0, rot.Yaw)
            local rx, ry = Bridge.RightFromYaw(rot.Yaw)

            local orientations = {
                { shift = { fx, fy }, pass = { rx, ry } },
                { shift = { rx, ry }, pass = { fx, fy } },
            }

            local bestCand = nil
            local bestScore = -1e9

            for _, ori in ipairs(orientations) do
                local sx, sy = ori.shift[1], ori.shift[2]
                local px, py = ori.pass[1], ori.pass[2]
                for _, off in ipairs({ 0.0, 45.0, -45.0 }) do
                    local cx = dl.X + sx * off
                    local cy = dl.Y + sy * off
                    local ax, ay = cx + px * 115.0, cy + py * 115.0
                    local bx, by = cx - px * 115.0, cy - py * 115.0

                    local sZ = dl.Z + startZTopOff
                    local eZ = dl.Z + endZBotOff
                    local gHitA, gzA, nA = Bridge.GroundTrace(world, ax, ay, sZ, eZ, graphIgnore)
                    local gHitC, gzC, nC = Bridge.GroundTrace(world, cx, cy, sZ, eZ, graphIgnore)
                    local gHitB, gzB, nB = Bridge.GroundTrace(world, bx, by, sZ, eZ, graphIgnore)

                    if gHitA and gzA and (sZ - gzA) >= 15.0 and nA and nA.Z >= 0.65
                        and gHitC and gzC and (sZ - gzC) >= 15.0 and nC and nC.Z >= 0.65
                        and gHitB and gzB and (sZ - gzB) >= 15.0 and nB and nB.Z >= 0.65 then
                        local posA = { X = ax, Y = ay, Z = gzA + 92.0 }
                        local posC = { X = cx, Y = cy, Z = gzC + 92.0 }
                        local posB = { X = bx, Y = by, Z = gzB + 92.0 }
                        local optsDoor = { skipWindow = true, skipMidGround = false }

                        if HumanNav.IsSegmentWalkable(world, posA, posC, graphIgnore, 18.0, optsDoor)
                            and HumanNav.IsSegmentWalkable(world, posC, posB, graphIgnore, 18.0, optsDoor)
                            and HumanNav.IsSegmentWalkable(world, posA, posB, graphIgnore, 18.0, optsDoor) then
                            local pass24 = HumanNav.IsSegmentWalkable(world, posA, posC, graphIgnore, 24.0, optsDoor)
                                and HumanNav.IsSegmentWalkable(world, posC, posB, graphIgnore, 24.0, optsDoor)
                                and HumanNav.IsSegmentWalkable(world, posA, posB, graphIgnore, 24.0, optsDoor)
                            local pass30 = pass24
                                and HumanNav.IsSegmentWalkable(world, posA, posC, graphIgnore, 30.0, optsDoor)
                                and HumanNav.IsSegmentWalkable(world, posC, posB, graphIgnore, 30.0, optsDoor)
                            local score = (pass30 and 2000.0 or (pass24 and 1000.0 or 100.0)) + ((off == 0.0) and 5.0 or 0.0)
                            if score > bestScore then
                                bestScore = score
                                bestCand = { posA = posA, posC = posC, posB = posB, name = Logger.SafeName(dEntry.actor) }
                            end
                        end
                    end
                end
            end

            if bestCand then
                local idA = #nodes + 1
                table.insert(nodes, {
                    id = idA, pos = bestCand.posA, name = bestCand.name .. "_SideA",
                    isLandmark = false, isDoorCenter = false, adj = {},
                })
                local idC = #nodes + 1
                table.insert(nodes, {
                    id = idC, pos = bestCand.posC, name = bestCand.name .. "_Center",
                    isLandmark = false, isDoorCenter = true, adj = {},
                })
                local idB = #nodes + 1
                table.insert(nodes, {
                    id = idB, pos = bestCand.posB, name = bestCand.name .. "_SideB",
                    isLandmark = false, isDoorCenter = false, adj = {},
                })
                AddUndirectedEdge(nodes, idA, idC, Bridge.Dist(bestCand.posA, bestCand.posC))
                AddUndirectedEdge(nodes, idC, idB, Bridge.Dist(bestCand.posC, bestCand.posB))

                State.DoorTunnelCount = State.DoorTunnelCount + 1
                table.insert(tunnels, { idA = idA, idC = idC, idB = idB })
                Logger.Info(string.format("DoorTunnel[%d] %s: (%.0f,%.0f)->(%.0f,%.0f)->(%.0f,%.0f)",
                    State.DoorTunnelCount, bestCand.name,
                    bestCand.posA.X, bestCand.posA.Y,
                    bestCand.posC.X, bestCand.posC.Y,
                    bestCand.posB.X, bestCand.posB.Y))
            end
        end
    end

    return tunnels
end

local function InHouseBox(x, y)
    local inInterior = (x >= 40900.0 and x <= 46300.0 and y >= 58750.0 and y <= 62000.0)
    local inPorch    = (x >= 43700.0 and x <= 44800.0 and y >= 57900.0 and y <= 58850.0)
    return inInterior or inPorch
end

local function InYardBox(x, y)
    return x >= 39000.0 and x <= 48400.0 and y >= 53800.0 and y <= 66000.0
end

local function SnapToCell(x, y)
    if InHouseBox(x, y) then
        local gx = math.floor(x / 140.0 + 0.5) * 140.0
        local gy = math.floor(y / 140.0 + 0.5) * 140.0
        return gx, gy, string.format("H_%d_%d", math.floor(gx + 0.5), math.floor(gy + 0.5)), 140.0, true
    end
    local gx = math.floor(x / 280.0 + 0.5) * 280.0
    local gy = math.floor(y / 280.0 + 0.5) * 280.0
    return gx, gy, string.format("Y_%d_%d", math.floor(gx + 0.5), math.floor(gy + 0.5)), 280.0, false
end

local function BuildNonNavMeshHouseGraph(world, startPos, survivor)
    local nodes = {}
    local graphIgnore = State.GraphIgnore

    -- Anchor Start node (id 1) at Survivor's current grounded position
    local anchorPos = startPos or Bridge.GetActorLoc(survivor)
    if not anchorPos then return nodes end
    table.insert(nodes, {
        id = 1,
        pos = { X = anchorPos.X, Y = anchorPos.Y, Z = anchorPos.Z },
        name = "Start",
        isLandmark = false,
        isDoorCenter = false,
        adj = {},
    })

    -- Discover doorway tunnels first so interior rooms & house entrances are seeded cleanly
    local tunnels = DiscoverDoorTunnels(world, nodes, graphIgnore, anchorPos, true)

    -- Two-resolution aligned BFS flood-fill (House+Porch 140cm, Yard+Perimeter 280cm)
    local cellToId = {}
    local houseNodes = {}
    local yardNodes = {}
    local gridNodeIds = {}
    local houseQueue = {}
    local yardQueue = {}

    if InHouseBox(nodes[1].pos.X, nodes[1].pos.Y) then
        table.insert(houseQueue, 1)
    else
        table.insert(yardQueue, 1)
    end
    for _, t in ipairs(tunnels) do
        for _, tid in ipairs({ t.idA, t.idB }) do
            if InHouseBox(nodes[tid].pos.X, nodes[tid].pos.Y) then
                table.insert(houseQueue, tid)
            else
                table.insert(yardQueue, tid)
            end
        end
    end

    local hHead, yHead = 1, 1
    local gridCount = 0
    local houseGridCount = 0
    local yardGridCount = 0
    local MAX_GRID_NODES = 650
    local MAX_HOUSE_GRID = 420
    local MAX_YARD_GRID  = 230
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

    local function PopNext()
        local hasH = hHead <= #houseQueue
        local hasY = yHead <= #yardQueue
        if hasH and ((not hasY) or houseGridCount < MAX_HOUSE_GRID) then
            local id = houseQueue[hHead]
            hHead = hHead + 1
            return id
        elseif hasY then
            local id = yardQueue[yHead]
            yHead = yHead + 1
            return id
        elseif hasH then
            local id = houseQueue[hHead]
            hHead = hHead + 1
            return id
        end
        return nil
    end

    while true do
        local uId = PopNext()
        if not uId then break end
        local u = nodes[uId]
        local uInHouse = InHouseBox(u.pos.X, u.pos.Y)
        local step = uInHouse and 140.0 or 280.0
        local curFloor = u.pos.Z - 92.0

        for _, d in ipairs(dirs) do
            local rawX = u.pos.X + d[1] * step
            local rawY = u.pos.Y + d[2] * step
            local gx, gy, key, _, nInHouse = SnapToCell(rawX, rawY)

            if InYardBox(gx, gy) and ((gx ~= u.pos.X) or (gy ~= u.pos.Y)) then
                local cardinalHalfW = (uInHouse or nInHouse) and 26.0 or 30.0
                local existingId = cellToId[key]
                if existingId and existingId ~= uId then
                    if HumanNav.IsSegmentWalkable(world, u.pos, nodes[existingId].pos, graphIgnore, cardinalHalfW) then
                        AddUndirectedEdge(nodes, uId, existingId, Bridge.Dist(u.pos, nodes[existingId].pos))
                    end
                elseif not existingId and gridCount < MAX_GRID_NODES then
                    if nInHouse or (yardGridCount < MAX_YARD_GRID) or (hHead > #houseQueue) then
                        local startZ = curFloor + 110.0
                        local endZ   = curFloor - 140.0
                        local gHit, gz, norm = Bridge.GroundTrace(world, gx, gy, startZ, endZ, graphIgnore)
                        if gHit and gz and (startZ - gz) >= 15.0 and norm and norm.Z >= 0.65 and math.abs(gz - curFloor) <= 70.0 then
                            local candPos = { X = gx, Y = gy, Z = gz + 92.0 }
                            if HumanNav.IsSegmentWalkable(world, u.pos, candPos, graphIgnore, cardinalHalfW) then
                                local newId = #nodes + 1
                                table.insert(nodes, {
                                    id = newId, pos = candPos, name = key,
                                    isLandmark = false, isDoorCenter = false, adj = {},
                                })
                                cellToId[key] = newId
                                AddUndirectedEdge(nodes, uId, newId, Bridge.Dist(u.pos, candPos))
                                table.insert(gridNodeIds, newId)
                                gridCount = gridCount + 1
                                if nInHouse then
                                    houseGridCount = houseGridCount + 1
                                    table.insert(houseNodes, newId)
                                    table.insert(houseQueue, newId)
                                else
                                    yardGridCount = yardGridCount + 1
                                    table.insert(yardNodes, newId)
                                    table.insert(yardQueue, newId)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Connect Start & DoorTunnel SideA/SideB nodes to up to 6 nearest walkable grid nodes within 540 cm
    local seedIds = { 1 }
    for _, t in ipairs(tunnels) do
        table.insert(seedIds, t.idA)
        table.insert(seedIds, t.idB)
    end
    for _, sId in ipairs(seedIds) do
        local sPos = nodes[sId].pos
        local nearCands = {}
        for _, gId in ipairs(gridNodeIds) do
            if gId ~= sId then
                local dist2 = Bridge.Dist2D(sPos, nodes[gId].pos)
                if dist2 <= 540.0 then
                    table.insert(nearCands, { id = gId, d = Bridge.Dist(sPos, nodes[gId].pos) })
                end
            end
        end
        table.sort(nearCands, function(a, b) return a.d < b.d end)
        local linked = 0
        for _, c in ipairs(nearCands) do
            if linked >= 6 then break end
            if Bridge.Dist2D(sPos, nodes[c.id].pos) <= 420.0
                and HumanNav.IsSegmentWalkable(world, sPos, nodes[c.id].pos, graphIgnore, 22.0) then
                AddUndirectedEdge(nodes, sId, c.id, c.d)
                linked = linked + 1
            end
        end
        if linked == 0 then
            for _, c in ipairs(nearCands) do
                if linked >= 3 then break end
                if HumanNav.IsSegmentWalkable(world, sPos, nodes[c.id].pos, graphIgnore, 10.0) then
                    AddUndirectedEdge(nodes, sId, c.id, c.d)
                    linked = linked + 1
                end
            end
        end
    end

    -- Diagonal edges inside HouseBox (dist <= 230 cm) with full capsule clearance to avoid furniture corner clipping
    for idxA = 1, #houseNodes do
        local idA = houseNodes[idxA]
        local pA = nodes[idA].pos
        for idxB = idxA + 1, #houseNodes do
            local idB = houseNodes[idxB]
            local d = Bridge.Dist(pA, nodes[idB].pos)
            if d > 155.0 and d <= 230.0 then
                if HumanNav.IsSegmentWalkable(world, pA, nodes[idB].pos, graphIgnore, 36.0) then
                    AddUndirectedEdge(nodes, idA, idB, d)
                end
            end
        end
    end

    -- Connected-component filter from StartNode (id 1): bridge narrow interior doorways (halfW=10) if any house wing separated
    local function RunReachableFlood()
        local vis = { [1] = true }
        local q = { 1 }
        local h = 1
        while h <= #q do
            local cur = q[h]
            h = h + 1
            for _, edge in ipairs(nodes[cur].adj) do
                if not vis[edge.to] then
                    vis[edge.to] = true
                    table.insert(q, edge.to)
                end
            end
        end
        return vis
    end

    local visited = RunReachableFlood()
    for _ = 1, 2 do
        local bridgedAny = false
        for idA = 1, #nodes do
            if visited[idA] and math.abs(nodes[idA].pos.Z - 9108.0) <= 220.0 then
                for idB = 1, #nodes do
                    if (not visited[idB]) and math.abs(nodes[idB].pos.Z - nodes[idA].pos.Z) <= 130.0 then
                        local d = Bridge.Dist(nodes[idA].pos, nodes[idB].pos)
                        if d <= 360.0 and HumanNav.IsSegmentWalkable(world, nodes[idA].pos, nodes[idB].pos, graphIgnore, 10.0) then
                            AddUndirectedEdge(nodes, idA, idB, d)
                            bridgedAny = true
                            break
                        end
                    end
                end
            end
        end
        if not bridgedAny then break end
        visited = RunReachableFlood()
    end

    local oldToNew = {}
    local cleanNodes = {}
    for oldId = 1, #nodes do
        if visited[oldId] then
            local newId = #cleanNodes + 1
            oldToNew[oldId] = newId
            table.insert(cleanNodes, {
                id = newId,
                pos = nodes[oldId].pos,
                name = nodes[oldId].name,
                isLandmark = nodes[oldId].isLandmark,
                isDoorCenter = nodes[oldId].isDoorCenter,
                adj = {},
            })
        end
    end
    for oldId, newId in pairs(oldToNew) do
        for _, edge in ipairs(nodes[oldId].adj) do
            local newNb = oldToNew[edge.to]
            if newNb then
                AddUndirectedEdge(cleanNodes, newId, newNb, edge.dist)
            end
        end
    end

    Logger.Info(string.format("HumanNav BFS totals: raw=%d house=%d yard=%d reachable=%d dropped=%d",
        #nodes, houseGridCount, yardGridCount, #cleanNodes, #nodes - #cleanNodes))
    return cleanNodes
end

local function BuildNonNavMeshGenericGraph(world, startPos, survivor, zones)
    local nodes = {}
    local graphIgnore = State.GraphIgnore
    local anchorPos = startPos or Bridge.GetActorLoc(survivor)
    if not anchorPos then return nodes end

    table.insert(nodes, {
        id = 1,
        pos = { X = anchorPos.X, Y = anchorPos.Y, Z = anchorPos.Z },
        name = "Start",
        isLandmark = false,
        isDoorCenter = false,
        adj = {},
    })

    local tunnels = DiscoverDoorTunnels(world, nodes, graphIgnore, anchorPos, false)
    local step = 250.0
    local cellToId = {}
    local queue = { 1 }
    for _, t in ipairs(tunnels) do
        table.insert(queue, t.idA)
        table.insert(queue, t.idB)
    end

    local function SnapGeneric(x, y)
        local gx = math.floor(x / step + 0.5) * step
        local gy = math.floor(y / step + 0.5) * step
        return gx, gy, string.format("G_%d_%d", math.floor(gx + 0.5), math.floor(gy + 0.5))
    end

    local qHead = 1
    local MAX_NODES = 420
    local MAX_RADIUS = 9500.0
    local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

    while qHead <= #queue and #nodes < MAX_NODES do
        local uId = queue[qHead]
        qHead = qHead + 1
        local u = nodes[uId]
        local curFloor = u.pos.Z - 92.0

        for _, d in ipairs(dirs) do
            local rawX = u.pos.X + d[1] * step
            local rawY = u.pos.Y + d[2] * step
            local gx, gy, key = SnapGeneric(rawX, rawY)
            if math.abs(gx - anchorPos.X) <= MAX_RADIUS and math.abs(gy - anchorPos.Y) <= MAX_RADIUS then
                local existingId = cellToId[key]
                if existingId and existingId ~= uId then
                    if HumanNav.IsSegmentWalkable(world, u.pos, nodes[existingId].pos, graphIgnore, 24.0) then
                        AddUndirectedEdge(nodes, uId, existingId, Bridge.Dist(u.pos, nodes[existingId].pos))
                    end
                elseif not existingId and #nodes < MAX_NODES then
                    local startZ = curFloor + 125.0
                    local endZ   = curFloor - 180.0
                    local gHit, gz, norm = Bridge.GroundTrace(world, gx, gy, startZ, endZ, graphIgnore)
                    if gHit and gz and (startZ - gz) >= 15.0 and norm and norm.Z >= 0.62 and math.abs(gz - curFloor) <= 95.0 then
                        local candPos = { X = gx, Y = gy, Z = gz + 92.0 }
                        if HumanNav.IsSegmentWalkable(world, u.pos, candPos, graphIgnore, 24.0) then
                            local newId = #nodes + 1
                            table.insert(nodes, {
                                id = newId, pos = candPos, name = key,
                                isLandmark = false, isDoorCenter = false, adj = {},
                            })
                            cellToId[key] = newId
                            AddUndirectedEdge(nodes, uId, newId, Bridge.Dist(u.pos, candPos))
                            table.insert(queue, newId)
                        end
                    end
                end
            end
        end
    end

    -- Attach zone landmarks if reachable from nearby nodes
    for _, z in ipairs(zones or {}) do
        for pIdx, pt in ipairs(z.pts or {}) do
            if pt.pos and #nodes < 520 then
                local bestId, bestD = nil, 460.0
                for _, n in ipairs(nodes) do
                    local d = Bridge.Dist(n.pos, pt.pos)
                    if d < bestD then
                        bestD = d
                        bestId = n.id
                    end
                end
                if bestId and HumanNav.IsSegmentWalkable(world, nodes[bestId].pos, pt.pos, graphIgnore, 22.0) then
                    local zId = #nodes + 1
                    table.insert(nodes, {
                        id = zId,
                        pos = { X = pt.pos.X, Y = pt.pos.Y, Z = pt.pos.Z },
                        name = tostring(z.name or "Z") .. "_" .. tostring(pIdx),
                        isLandmark = (z.isLandmark == true),
                        isDoorCenter = false,
                        adj = {},
                    })
                    AddUndirectedEdge(nodes, bestId, zId, bestD)
                end
            end
        end
    end

    Logger.Info(string.format("HumanNav Generic BFS built: nodes=%d doorTunnels=%d", #nodes, State.DoorTunnelCount))
    return nodes
end

function HumanNav.BuildGraph(world, zones, startPos, hasNavMesh, survivor, anchorOverride)
    HumanNav.Reset()
    if not zones then return false end
    State.HasNavMesh = (hasNavMesh == true)

    -- Cache all doors & build GraphIgnore (survivor + AI-openable non-locked doors)
    local doors = FindAllOf("BP_DoorBase_C") or {}
    local graphIgnore = {}
    if Logger.IsValidObj(survivor) then table.insert(graphIgnore, survivor) end
    for _, d in ipairs(doors) do
        if Logger.IsValidObj(d) then
            local loc = Bridge.GetActorLoc(d)
            if loc then
                table.insert(State.Doors, { actor = d, pos = loc, opened = false })
                if IsDoorOpenableAI(d) then
                    table.insert(graphIgnore, d)
                end
            end
        end
    end
    State.GraphIgnore = graphIgnore

    -- Cache 1F windows (Level01_Prologue anti-window-hugging safeguard)
    for _, w in ipairs(FindAllOf("BP_InteractableWindow_C") or {}) do
        if Logger.IsValidObj(w) then
            local wl = Bridge.GetActorLoc(w)
            if wl and wl.Z <= 9550.0 then
                table.insert(State.Windows, { pos = wl, name = Logger.SafeName(w) })
            end
        end
    end

    local nodes = {}
    if not State.HasNavMesh then
        local sp = anchorOverride or startPos or Bridge.GetActorLoc(survivor)
        if sp and InYardBox(sp.X, sp.Y) and sp.Z >= 8800.0 and sp.Z <= 9420.0 then
            nodes = BuildNonNavMeshHouseGraph(world, anchorOverride or startPos, survivor)
            if #nodes < 15 then
                Logger.Warn("HumanNav HouseGraph too small (" .. tostring(#nodes) .. "); falling back to Generic BFS")
                State.DoorTunnelCount = 0
                nodes = BuildNonNavMeshGenericGraph(world, sp, survivor, zones)
            end
        else
            nodes = BuildNonNavMeshGenericGraph(world, sp, survivor, zones)
        end
    else
        local function TryAddNode(pos, name, isLandmark, minSep)
            if not pos then return end
            local sep = minSep or 260.0
            for _, ex in ipairs(nodes) do
                if Bridge.Dist(ex.pos, pos) < sep then
                    return
                end
            end
            table.insert(nodes, {
                id           = #nodes + 1,
                pos          = { X = pos.X, Y = pos.Y, Z = pos.Z },
                name         = name or ("Node_" .. tostring(#nodes + 1)),
                isLandmark   = (isLandmark == true),
                isDoorCenter = false,
                adj          = {},
            })
        end

        if startPos then
            local okS, projS = Bridge.ProjectPointToNav(world, startPos, { X = 350.0, Y = 350.0, Z = 600.0 })
            TryAddNode(okS and projS or startPos, "Start", false, 180.0)
        end

        for _, z in ipairs(zones) do
            TryAddNode(z.center, z.name, z.isLandmark, 220.0)
            for pIdx, pt in ipairs(z.pts or {}) do
                TryAddNode(pt.pos, z.name .. "_P" .. tostring(pIdx), false, 180.0)
            end
        end

        for i = 1, #nodes do
            local candidates = {}
            for j = 1, #nodes do
                if i ~= j then
                    local d2d = Bridge.Dist2D(nodes[i].pos, nodes[j].pos)
                    if d2d <= 2500.0 then
                        table.insert(candidates, { j = j, d = Bridge.Dist(nodes[i].pos, nodes[j].pos) })
                    end
                end
            end
            table.sort(candidates, function(a, b) return a.d < b.d end)

            for _, item in ipairs(candidates) do
                if #nodes[i].adj >= 6 then break end
                local pA = nodes[i].pos
                local pB = nodes[item.j].pos
                local pts = Bridge.FindNavPathPoints(world, pA, pB, survivor)
                if pts and #pts >= 2 and PolylineLength(pts) <= math.max(900.0, item.d * 2.75) then
                    AddUndirectedEdge(nodes, i, item.j, item.d)
                end
            end
        end
    end

    State.Nodes = nodes
    State.Initialized = true
    Logger.Info(string.format(
        "HumanNav graph built (HasNavMesh=%s): %d reachable nodes, %d door tunnels, %d doors cached, %d 1F windows guarded",
        tostring(State.HasNavMesh), #nodes, State.DoorTunnelCount, #State.Doors, #State.Windows))
    return true
end

function HumanNav.GetNearestWalkableNode(pos, maxDist, maxDZ)
    if not pos or #State.Nodes == 0 then return nil, 1e9 end
    local md = maxDist or 700.0
    local mz = maxDZ or 180.0
    local bestNode, bestD = nil, 1e9
    for _, n in ipairs(State.Nodes) do
        if not n.isDoorCenter then
            local d = Bridge.Dist2D(pos, n.pos)
            local dz = math.abs(pos.Z - n.pos.Z)
            if d <= md and dz <= mz and d < bestD then
                bestD = d
                bestNode = n
            end
        end
    end
    return bestNode, bestD
end

function HumanNav.BlacklistNearestNode(pos, durationSec)
    if not pos or #State.Nodes == 0 then return false end
    local bestId, bestD = nil, 1e9
    for _, n in ipairs(State.Nodes) do
        local d = Bridge.Dist(pos, n.pos)
        if d < bestD then
            bestD = d
            bestId = n.id
        end
    end
    if bestId then
        State.NodeBlacklist[bestId] = os.clock() + (durationSec or 35.0)
        return true
    end
    return false
end

function HumanNav.GetNodeCount()       return #State.Nodes end
function HumanNav.GetDoorTunnelCount() return State.DoorTunnelCount end

function HumanNav.GetWalkableNodes()
    local out = {}
    for _, n in ipairs(State.Nodes) do
        if not n.isDoorCenter then
            table.insert(out, n)
        end
    end
    return out
end

function HumanNav.CountWindowCrossingEdges()
    if #State.Windows == 0 or #State.Nodes == 0 then return 0 end
    local seen = {}
    local crossings = 0
    for i, u in ipairs(State.Nodes) do
        if not u.isDoorCenter then
            for _, edge in ipairs(u.adj) do
                local v = State.Nodes[edge.to]
                if v and (not v.isDoorCenter) then
                    local key = EdgeKey(i, edge.to)
                    if not seen[key] then
                        seen[key] = true
                        if SegmentCrossesWindow(u.pos, v.pos, 62.0) then
                            crossings = crossings + 1
                        end
                    end
                end
            end
        end
    end
    return crossings
end

function HumanNav.GetSameRoomApproachNode(world, pos, maxDist2D, targetActor)
    if not world or not pos or #State.Nodes == 0 then return nil, 1e9 end
    local md = maxDist2D or 280.0
    local cands = {}
    for _, n in ipairs(State.Nodes) do
        if not n.isDoorCenter then
            local d2D = Bridge.Dist2D(pos, n.pos)
            local dZ  = math.abs(pos.Z - n.pos.Z)
            if d2D <= md and dZ <= 230.0 then
                table.insert(cands, { node = n, d = d2D })
            end
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)

    local ig = {}
    for _, act in ipairs(State.GraphIgnore or {}) do
        table.insert(ig, act)
    end
    if Logger.IsValidObj(targetActor) then
        table.insert(ig, targetActor)
    end

    for _, c in ipairs(cands) do
        local n = c.node
        if not SegmentCrossesWindow(n.pos, pos, 64.0) then
            local eyeStart = { X = n.pos.X, Y = n.pos.Y, Z = n.pos.Z + 65.0 }
            local eyeEnd   = { X = pos.X, Y = pos.Y, Z = math.max(pos.Z + 12.0, n.pos.Z + 65.0) }
            local segLen   = Bridge.Dist(eyeStart, eyeEnd)
            local blocked, info = Bridge.IsRayBlockedDual(world, eyeStart, eyeEnd, ig)
            if (not blocked) or (info and info.Distance and info.Distance >= (segLen - 65.0)) then
                return n, c.d
            end
        end
    end
    return nil, 1e9
end

local function FindNearestReachableNode(world, pos, ignore, allowRelaxed)
    if #State.Nodes == 0 or not pos then return nil, 1e9 end

    if State.HasNavMesh then
        local bestId, bestD = nil, 1e9
        for _, n in ipairs(State.Nodes) do
            local d = Bridge.Dist(pos, n.pos)
            if d < bestD then
                bestD = d
                bestId = n.id
            end
        end
        return bestId, bestD
    end

    local ig = ignore or State.GraphIgnore
    local cands = {}
    local maxR = allowRelaxed and 1200.0 or 900.0
    local maxZ = allowRelaxed and 230.0 or 185.0
    for _, n in ipairs(State.Nodes) do
        local d2 = Bridge.Dist2D(pos, n.pos)
        local dz = math.abs(pos.Z - n.pos.Z)
        if d2 <= maxR and dz <= maxZ then
            table.insert(cands, { id = n.id, pos = n.pos, d = Bridge.Dist(pos, n.pos) })
        end
    end
    table.sort(cands, function(a, b) return a.d < b.d end)

    -- Pass 1: full segment walkability check (never crosses walls or 1F windows)
    for _, c in ipairs(cands) do
        if c.d <= 900.0 and math.abs(pos.Z - c.pos.Z) <= 185.0 then
            if HumanNav.IsSegmentWalkable(world, pos, c.pos, ig, 18.0, { skipMidGround = true }) then
                return c.id, c.d
            end
        end
    end

    -- Pass 2: for elevated / table collectibles, prefer a same-room floor approach node first
    if allowRelaxed then
        local sameRoomNode, sameDist = HumanNav.GetSameRoomApproachNode(world, pos, 380.0, nil)
        if sameRoomNode then
            return sameRoomNode.id, sameDist
        end
    end

    -- Fallback Pass 2b: knee-height ray anchored to node's floor height + no window crossing
    for _, c in ipairs(cands) do
        if c.d <= 600.0 and (not SegmentCrossesWindow(pos, c.pos, 68.0)) then
            local nodeKneeZ = (c.pos.Z - 92.0) + 42.0
            local blocked = Bridge.IsRayBlockedDual(
                world,
                { X = pos.X, Y = pos.Y, Z = nodeKneeZ },
                { X = c.pos.X, Y = c.pos.Y, Z = nodeKneeZ },
                ig
            )
            if not blocked then
                return c.id, c.d
            end
        end
    end

    return nil, 1e9
end

local function DangerCostAt(pos, dangerZones)
    if not dangerZones then return 0.0 end
    local pen = 0.0
    local now = os.clock()
    for _, dz in ipairs(dangerZones) do
        if (dz.expiresAt or 1e9) > now then
            local r = dz.radius or 2200.0
            local d = Bridge.Dist2D(pos, dz.pos)
            if d < r then
                pen = pen + 5500.0 * (dz.intensity or 1.0) * (1.0 - d / r)
            end
        end
    end
    return pen
end

local function ShouldUseMacroDetour(startPos, goalPos, dangerZones)
    if not State.HasNavMesh then return true end
    if not dangerZones or #dangerZones == 0 then return false end
    local mid = { X = (startPos.X + goalPos.X) * 0.5, Y = (startPos.Y + goalPos.Y) * 0.5, Z = startPos.Z }
    return (DangerCostAt(mid, dangerZones) > 600.0) or (DangerCostAt(goalPos, dangerZones) > 1200.0)
end

local function RunAStarNodes(startId, goalId, dangerZones, useEdgePenalties)
    local openSet = { [startId] = true }
    local cameFrom = {}
    local gScore = { [startId] = 0.0 }
    local fScore = { [startId] = Bridge.Dist(State.Nodes[startId].pos, State.Nodes[goalId].pos) }
    local closed = {}
    local now = os.clock()

    for _ = 1, (#State.Nodes * 2 + 10) do
        local cur, bestF = nil, 1e12
        for nid, _ in pairs(openSet) do
            local fs = fScore[nid] or 1e12
            if fs < bestF then
                bestF = fs
                cur = nid
            end
        end
        if not cur then break end
        if cur == goalId then
            local rev = {}
            local step = goalId
            while step do
                table.insert(rev, State.Nodes[step])
                step = cameFrom[step]
            end
            local rawRoute = {}
            for i = #rev, 1, -1 do
                table.insert(rawRoute, rev[i])
            end
            return rawRoute
        end

        openSet[cur] = nil
        closed[cur]  = true

        for _, edge in ipairs(State.Nodes[cur].adj) do
            local nb = edge.to
            if not closed[nb] then
                local ePen = 0.0
                if useEdgePenalties then
                    local exp = State.EdgePenalties[EdgeKey(cur, nb)]
                    if exp and exp > now then ePen = 9000.0 end
                end
                local nbNode = State.Nodes[nb]
                local mid = {
                    X = (State.Nodes[cur].pos.X + nbNode.pos.X) * 0.5,
                    Y = (State.Nodes[cur].pos.Y + nbNode.pos.Y) * 0.5,
                    Z = (State.Nodes[cur].pos.Z + nbNode.pos.Z) * 0.5,
                }
                local dCost = DangerCostAt(nbNode.pos, dangerZones) + DangerCostAt(mid, dangerZones) * 0.6
                local tentG = (gScore[cur] or 1e12) + edge.dist + ePen + dCost
                if tentG < (gScore[nb] or 1e12) then
                    cameFrom[nb] = cur
                    gScore[nb]   = tentG
                    fScore[nb]   = tentG + Bridge.Dist(nbNode.pos, State.Nodes[goalId].pos)
                    openSet[nb]  = true
                end
            end
        end
    end

    return nil
end

local function SmoothRoute(world, rawNodes, ignore)
    if not rawNodes or #rawNodes <= 2 then return rawNodes end
    local smoothed = { rawNodes[1] }
    local i = 1
    while i < #rawNodes do
        local bestNext = i + 1
        local maxLook = math.min(#rawNodes, i + 3)
        for j = maxLook, i + 2, -1 do
            local hasDoorBetween = false
            for m = i + 1, j - 1 do
                if rawNodes[m].isDoorCenter then
                    hasDoorBetween = true
                    break
                end
            end
            if not hasDoorBetween then
                if HumanNav.IsSegmentWalkable(world, rawNodes[i].pos, rawNodes[j].pos, ignore, 36.0) then
                    bestNext = j
                    break
                end
            end
        end
        table.insert(smoothed, rawNodes[bestNext])
        i = bestNext
    end
    return smoothed
end

function HumanNav.ComputeAStarRoute(world, startPos, goalPos, dangerZones, ignoreActors)
    local ignore = ignoreActors or State.GraphIgnore
    if State.HasNavMesh then
        if #State.Nodes < 2 then return { goalPos }, { 0 }, { false }, true end
        local sId = FindNearestReachableNode(world, startPos, ignore, false)
        local gId = FindNearestReachableNode(world, goalPos, ignore, true)
        if not sId or not gId or sId == gId then
            return { goalPos }, { 0 }, { false }, true
        end
        local raw = RunAStarNodes(sId, gId, dangerZones, true) or RunAStarNodes(sId, gId, dangerZones, false)
        if not raw then
            return { goalPos }, { 0 }, { false }, true
        end
        local pts, ids, doors = {}, {}, {}
        for _, n in ipairs(raw) do
            table.insert(pts, n.pos)
            table.insert(ids, n.id)
            table.insert(doors, n.isDoorCenter == true)
        end
        if Bridge.Dist(pts[#pts], goalPos) > 120.0 then
            table.insert(pts, { X = goalPos.X, Y = goalPos.Y, Z = goalPos.Z })
            table.insert(ids, 0)
            table.insert(doors, false)
        end
        return pts, ids, doors, true
    end

    -- Non-NavMesh (Level01_Prologue): STRICT reachability, NEVER return straight through a wall!
    if #State.Nodes == 0 then return nil, nil, nil, false end
    local startId = FindNearestReachableNode(world, startPos, ignore, false)
    local goalId  = FindNearestReachableNode(world, goalPos, ignore, true)
    if not startId or not goalId then
        return nil, nil, nil, false
    end

    local raw = nil
    if startId == goalId then
        raw = { State.Nodes[startId] }
    else
        raw = RunAStarNodes(startId, goalId, dangerZones, true)
        if not raw then
            raw = RunAStarNodes(startId, goalId, dangerZones, false)
        end
    end
    if not raw then
        return nil, nil, nil, false
    end

    local smoothed = SmoothRoute(world, raw, ignore)
    local pts, ids, doors = {}, {}, {}
    for _, n in ipairs(smoothed) do
        table.insert(pts, { X = n.pos.X, Y = n.pos.Y, Z = n.pos.Z })
        table.insert(ids, n.id)
        table.insert(doors, n.isDoorCenter == true)
    end

    local lastPos = pts[#pts]
    if lastPos and Bridge.Dist(lastPos, goalPos) > 80.0 then
        if HumanNav.IsSegmentWalkable(world, lastPos, goalPos, ignore, 18.0, { skipMidGround = true }) then
            table.insert(pts, { X = goalPos.X, Y = goalPos.Y, Z = goalPos.Z })
            table.insert(ids, 0)
            table.insert(doors, false)
        end
    end

    return pts, ids, doors, true
end

function HumanNav.SetGoal(world, humanPos, goalPos, dangerZones, forceReplan, ai, ignoreActors)
    if not goalPos or not humanPos then return false end
    local isNewGoal = (not State.FinalGoal) or (Bridge.Dist(State.FinalGoal, goalPos) > 130.0)
    local needReplan = forceReplan or isNewGoal
    if not needReplan then
        return true
    end

    local useDetour = ShouldUseMacroDetour(humanPos, goalPos, dangerZones)
    if useDetour then
        local pts, ids, doors, ok = HumanNav.ComputeAStarRoute(world, humanPos, goalPos, dangerZones, ignoreActors)
        if (not ok) or (not pts) or (#pts == 0) then
            State.FinalGoal      = nil
            State.RouteWaypoints = {}
            State.RouteNodeIds   = {}
            State.RouteDoorFlags = {}
            State.RouteIdx       = 1
            State.NavStatusStr   = "UnreachableGoal"
            Logger.Warn(string.format("HumanNav unreachable goal @ (%.0f, %.0f, %.0f) -> switching target",
                goalPos.X, goalPos.Y, goalPos.Z))
            return false
        end
        State.RouteWaypoints = pts
        State.RouteNodeIds   = ids or {}
        State.RouteDoorFlags = doors or {}
    else
        State.RouteWaypoints = { { X = goalPos.X, Y = goalPos.Y, Z = goalPos.Z } }
        State.RouteNodeIds   = { 0 }
        State.RouteDoorFlags = { false }
    end

    State.FinalGoal                = { X = goalPos.X, Y = goalPos.Y, Z = goalPos.Z }
    State.UseDangerDetour          = useDetour
    State.RouteIdx                 = 1
    State.NavMeshPts               = nil
    State.LastReplanTime           = 0.0
    State.StuckSamplePos           = nil
    State.StuckTimer               = 0.0
    State.EndpointStallTimer       = 0.0
    if isNewGoal then
        State.ConsecutiveStucks    = 0
    end
    State.ForceReplanAfterRecovery = false
    if Logger.IsValidObj(ai) then
        pcall(function() ai:StopMovement() end)
    end
    return true
end

function HumanNav.Stop(ai)
    State.IntendsToMove            = false
    State.NavStatusStr             = "Idle"
    State.StuckSamplePos           = nil
    State.StuckTimer               = 0.0
    State.EndpointStallTimer       = 0.0
    State.ConsecutiveStucks        = 0
    State.ForceReplanAfterRecovery = false
    if Logger.IsValidObj(ai) then
        pcall(function() ai:StopMovement() end)
    end
end

function HumanNav.TryOpenNearbyDoors(survivor, humanPos)
    local now = os.clock()
    if (now - State.LastDoorCheckTime) < 0.15 or #State.Doors == 0 then return end
    State.LastDoorCheckTime = now
    local PrologueStory = require("prologue_story")

    for _, dEntry in ipairs(State.Doors) do
        local door = dEntry.actor
        if Logger.IsValidObj(door) then
            local d2D = Bridge.Dist2D(humanPos, dEntry.pos)
            local dZ  = math.abs(humanPos.Z - dEntry.pos.Z)
            if d2D <= 270.0 and dZ <= 190.0 and IsDoorOpenableAI(door)
                and (not (PrologueStory.ShouldBlockDoorAI and PrologueStory.ShouldBlockDoorAI(door))) then
                local st = 0
                pcall(function() st = door:GetState() end)
                if st ~= 1 then
                    dEntry.opened = true
                    State.OpenedDoorCount = State.OpenedDoorCount + 1
                    pcall(function() door:RequestStateChange(survivor, 1) end)
                    pcall(function() door:SetState(survivor, 1, false) end)
                    pcall(function()
                        if Logger.IsValidObj(door.DoorCollisionAndNavigationBlocker) then
                            door.DoorCollisionAndNavigationBlocker:SetCollisionEnabled(0)
                        end
                    end)
                    Logger.Info(string.format("HumanAI opened Door: %s (totalOpened=%d)",
                        Logger.SafeName(door), State.OpenedDoorCount))
                elseif not dEntry.opened then
                    dEntry.opened = true
                    pcall(function()
                        if Logger.IsValidObj(door.DoorCollisionAndNavigationBlocker) then
                            door.DoorCollisionAndNavigationBlocker:SetCollisionEnabled(0)
                        end
                    end)
                end
            end
        end
    end
end

function HumanNav.SampleWhiskers(world, humanPos, desiredYaw, ignore)
    local floorZ = humanPos.Z - 92.0
    local kneeZ  = humanPos.Z - 48.0
    local chestZ = humanPos.Z + 20.0
    local ig     = ignore or State.GraphIgnore

    local function EvalAngle(off)
        local fx, fy = Bridge.ForwardFromRot(0.0, desiredYaw + off)
        local clear = 165.0
        local blockedNormalOK = false

        local k0 = { X = humanPos.X, Y = humanPos.Y, Z = kneeZ }
        local k1 = { X = humanPos.X + fx * 165.0, Y = humanPos.Y + fy * 165.0, Z = kneeZ }
        local hitK, infoK = Bridge.IsRayBlockedDual(world, k0, k1, ig)
        if hitK and infoK and math.abs((infoK.ImpactNormal and infoK.ImpactNormal.Z or 0.0)) < 0.65 then
            clear = math.min(clear, infoK.Distance or 55.0)
            blockedNormalOK = true
        end

        local c0 = { X = humanPos.X, Y = humanPos.Y, Z = chestZ }
        local c1 = { X = humanPos.X + fx * 165.0, Y = humanPos.Y + fy * 165.0, Z = chestZ }
        local hitC, infoC = Bridge.LineTrace(world, c0, c1, ig, 0, false)
        if hitC and infoC and math.abs((infoC.ImpactNormal and infoC.ImpactNormal.Z or 0.0)) < 0.65 then
            clear = math.min(clear, infoC.Distance or 55.0)
            blockedNormalOK = true
        end

        -- Avoid steering right back into a 1F window sill
        if SegmentCrossesWindow(humanPos, { X = humanPos.X + fx * 140.0, Y = humanPos.Y + fy * 140.0, Z = floorZ + 92.0 }, 60.0) then
            clear = math.min(clear, 45.0)
            blockedNormalOK = true
        end

        return { clear = clear, fx = fx, fy = fy, blocked = blockedNormalOK }
    end

    local angles = { -95.0, -60.0, -30.0, 0.0, 30.0, 60.0, 95.0 }
    local clearScores = {}
    local centerBlocked = false
    local bestIdx, bestClear = 4, -1.0

    for idx, off in ipairs(angles) do
        local s = EvalAngle(off)
        clearScores[idx] = s
        if off == 0.0 and s.blocked and s.clear < 120.0 then
            centerBlocked = true
        end
        if s.clear > bestClear then
            bestClear = s.clear
            bestIdx = idx
        end
    end

    -- U-shaped corner breakout: if boxed in ahead, also probe deep side & rear angles
    if centerBlocked and bestClear < 75.0 then
        for _, off in ipairs({ -135.0, 135.0, 180.0 }) do
            local s = EvalAngle(off)
            table.insert(clearScores, s)
            if s.clear > bestClear then
                bestClear = s.clear
                bestIdx = #clearScores
            end
        end
    end

    return centerBlocked, clearScores[bestIdx], clearScores
end

local function FindOpenEscapeDir(world, humanPos, blockedYaw, ignore)
    local floorZ = humanPos.Z - 92.0
    local kneeZ  = floorZ + 44.0
    local chestZ = floorZ + 112.0
    local ig     = ignore or State.GraphIgnore
    local angles = { 0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 120.0, -120.0, 150.0, -150.0, 180.0 }

    local best = { fx = 0.0, fy = 1.0, clear = 0.0 }
    local bestScore = -1e9

    for _, ang in ipairs(angles) do
        local fx, fy = Bridge.ForwardFromRot(0.0, (blockedYaw or 0.0) + ang)
        local clear = 240.0
        local hitK, infoK = Bridge.IsRayBlockedDual(world,
            { X = humanPos.X, Y = humanPos.Y, Z = kneeZ },
            { X = humanPos.X + fx * 240.0, Y = humanPos.Y + fy * 240.0, Z = kneeZ }, ig)
        if hitK and infoK and math.abs((infoK.ImpactNormal and infoK.ImpactNormal.Z or 0.0)) < 0.65 then
            clear = math.min(clear, infoK.Distance or 40.0)
        end
        local hitC, infoC = Bridge.LineTrace(world,
            { X = humanPos.X, Y = humanPos.Y, Z = chestZ },
            { X = humanPos.X + fx * 240.0, Y = humanPos.Y + fy * 240.0, Z = chestZ }, ig, 0, false)
        if hitC and infoC and math.abs((infoC.ImpactNormal and infoC.ImpactNormal.Z or 0.0)) < 0.65 then
            clear = math.min(clear, infoC.Distance or 40.0)
        end

        local gx = humanPos.X + fx * 140.0
        local gy = humanPos.Y + fy * 140.0
        local gHit, gz, norm = Bridge.GroundTrace(world, gx, gy, floorZ + 110.0, floorZ - 140.0, ig)
        local groundOk = gHit and gz and norm and norm.Z >= 0.65 and math.abs(gz - floorZ) <= 85.0
        local score = clear + (groundOk and 120.0 or -300.0) + ((math.abs(ang) >= 90.0) and 90.0 or 0.0)
        if score > bestScore then
            bestScore = score
            best = { fx = fx, fy = fy, clear = clear }
        end
    end

    return best
end

function HumanNav.ForceStuckRecoveryTest(world, survivor, humanPos, slender)
    local ignore = { survivor }
    if Logger.IsValidObj(slender) then table.insert(ignore, slender) end
    local yaw = (Bridge.GetActorRot(survivor) or { Yaw = 0.0 }).Yaw
    local bestEscape = FindOpenEscapeDir(world, humanPos, yaw, ignore)
    State.RecoveryStage = 1
    State.RecoveryTimer = 0.85
    State.RecoveryDir   = bestEscape and { X = bestEscape.fx, Y = bestEscape.fy } or { X = 1.0, Y = 0.0 }
    State.StuckCount    = State.StuckCount + 1
    State.NavStatusStr  = "StuckRecovery_Stage1"
end

-- Returns: isRecovering (bool), steerInfo (table|nil), stuckNeedsNewGoal (bool)
function HumanNav.UpdateMovement(world, dt, survivor, ai, slender, dangerZones)
    if not Logger.IsValidObj(survivor) or not Logger.IsValidObj(ai) or not State.FinalGoal then
        State.NavStatusStr = "Idle"
        return false, nil, false
    end

    local humanPos = Bridge.GetActorLoc(survivor)
    if not humanPos then return false, nil, false end
    State.IntendsToMove = true

    HumanNav.TryOpenNearbyDoors(survivor, humanPos)

    local ignore = { survivor }
    if Logger.IsValidObj(slender) then table.insert(ignore, slender) end

    -- 1. Execute active Corner-Breakout Sidestep if running (with AIController stopped!)
    if State.RecoveryStage > 0 then
        State.RecoveryTimer = State.RecoveryTimer - dt
        if State.RecoveryDir then
            pcall(function()
                survivor:AddMovementInput({ X = State.RecoveryDir.X, Y = State.RecoveryDir.Y, Z = 0.0 }, 1.0, false)
            end)
        end
        if State.RecoveryTimer <= 0.0 then
            State.RecoveryStage = 0
            State.LastReplanTime = 0.0
            State.NavMeshPts = nil
            if State.ForceReplanAfterRecovery and State.FinalGoal then
                State.ForceReplanAfterRecovery = false
                local savedGoal = State.FinalGoal
                local okReplan = HumanNav.SetGoal(world, humanPos, savedGoal, dangerZones, true, ai)
                if not okReplan then
                    return false, nil, true
                end
            end
        end
        return true, { Yaw = State.RecoveryDir and Bridge.YawFromVec(State.RecoveryDir.X, State.RecoveryDir.Y) or nil }, false
    end

    -- 2. Non-looping Stuck detector (checks every 1.5s while moving)
    if not State.StuckSamplePos then
        State.StuckSamplePos = humanPos
        State.StuckTimer = 0.0
    else
        State.StuckTimer = State.StuckTimer + dt
        if State.StuckTimer >= Config.HUMAN.STUCK_CHECK_INTERVAL then
            local disp = Bridge.Dist2D(State.StuckSamplePos, humanPos)
            State.StuckSamplePos = humanPos
            State.StuckTimer = 0.0
            if disp >= Config.HUMAN.STUCK_MIN_MOVE then
                State.ConsecutiveStucks = 0
            else
                State.StuckCount        = State.StuckCount + 1
                State.ConsecutiveStucks = State.ConsecutiveStucks + 1
                pcall(function() ai:StopMovement() end)

                if State.ConsecutiveStucks == 1 then
                    local curId = State.RouteNodeIds and State.RouteNodeIds[State.RouteIdx] or 0
                    local prevId = State.RouteNodeIds and State.RouteNodeIds[math.max(1, State.RouteIdx - 1)] or 0
                    local expT = os.clock() + 30.0
                    if curId > 0 and prevId > 0 and curId ~= prevId then
                        State.EdgePenalties[EdgeKey(prevId, curId)] = expT
                    end
                    local nearId, bestD = nil, 1e9
                    for _, n in ipairs(State.Nodes) do
                        local d = Bridge.Dist(humanPos, n.pos)
                        if d < bestD then
                            bestD = d
                            nearId = n.id
                        end
                    end
                    if curId > 0 and nearId and curId ~= nearId then
                        State.EdgePenalties[EdgeKey(nearId, curId)] = expT
                    end

                    local yaw = (Bridge.GetActorRot(survivor) or { Yaw = 0.0 }).Yaw
                    local esc = FindOpenEscapeDir(world, humanPos, yaw, ignore)
                    State.RecoveryStage            = 1
                    State.RecoveryTimer            = 0.85
                    State.RecoveryDir              = esc and { X = esc.fx, Y = esc.fy } or { X = 0.0, Y = 1.0 }
                    State.ForceReplanAfterRecovery = true
                    State.NavStatusStr             = "CornerBreakout"
                    Logger.Info("HumanNav corner breakout (disp=" .. string.format("%.0fcm", disp) .. ")")
                    return true, { Yaw = Bridge.YawFromVec(State.RecoveryDir.X, State.RecoveryDir.Y) }, false
                else
                    State.ConsecutiveStucks = 0
                    HumanNav.BlacklistNearestNode(State.FinalGoal, 35.0)
                    State.NavStatusStr = "ReassigningGoal"
                    Logger.Info("HumanNav stuck twice on current target -> Blacklisted & requesting new target.")
                    return false, nil, true
                end
            end
        end
    end

    -- 3. Advance macro-waypoints (tighter tolerance on DoorCenters & Level01 House graph)
    local targetPt = State.FinalGoal
    if State.RouteWaypoints and #State.RouteWaypoints > 0 then
        while State.RouteIdx < #State.RouteWaypoints do
            local isDoor = State.RouteDoorFlags and State.RouteDoorFlags[State.RouteIdx]
            local tol = State.HasNavMesh and 250.0 or (isDoor and 75.0 or 115.0)
            if Bridge.Dist2D(humanPos, State.RouteWaypoints[State.RouteIdx]) < tol then
                State.RouteIdx = State.RouteIdx + 1
            else
                break
            end
        end
        targetPt = State.RouteWaypoints[State.RouteIdx] or State.FinalGoal
    end
    State.CurrentSubTarget = targetPt

    -- Endpoint-stall guard: if standing right at final waypoint on L01 yet actual FinalGoal is still > 190cm away, switch target
    local atFinalWaypoint = (not State.RouteWaypoints) or (State.RouteIdx >= #State.RouteWaypoints)
    local distToTarget2D = Bridge.Dist2D(humanPos, targetPt)
    if (not State.HasNavMesh) and atFinalWaypoint and distToTarget2D < 48.0 and Bridge.Dist2D(humanPos, State.FinalGoal) > 190.0 then
        State.EndpointStallTimer = State.EndpointStallTimer + dt
        if State.EndpointStallTimer >= 0.8 then
            State.EndpointStallTimer = 0.0
            HumanNav.BlacklistNearestNode(State.FinalGoal, 35.0)
            State.NavStatusStr = "EndpointStall"
            Logger.Info("HumanNav reached nearest node but goal remains blocked -> switching target")
            return false, nil, true
        end
    else
        State.EndpointStallTimer = 0.0
    end

    -- 4. Execute movement along NavMesh (Level02) OR Waypoints + Whiskers (Level01)
    if State.HasNavMesh then
        local now = os.clock()
        if (now - State.LastReplanTime) >= Config.HUMAN.NAV_REPLAN_INTERVAL then
            State.LastReplanTime = now
            local res = 0
            pcall(function()
                res = ai:MoveToLocation(targetPt, 70.0, true, true, true, false, nil, true)
            end)
            State.NavStatusStr = (res == 2 or res == 1)
                and (State.UseDangerDetour and "NavMesh+AStar" or "NavMeshDirect")
                or "NavDirectSteer"
        end
    else
        State.NavStatusStr = (State.RouteDoorFlags and State.RouteDoorFlags[State.RouteIdx])
            and "DoorTunnelSteer"
            or "HouseBFS+Whisker"
    end

    local dx = targetPt.X - humanPos.X
    local dy = targetPt.Y - humanPos.Y
    local desiredYaw = Bridge.YawFromVec(dx, dy)

    local moveStatus = 0
    if State.HasNavMesh then
        pcall(function() moveStatus = ai:GetMoveStatus() end) -- 3 = Moving
    end

    local centerBlocked, bestWhisker, clearScores = HumanNav.SampleWhiskers(world, humanPos, desiredYaw, ignore)
    if (not State.HasNavMesh) or moveStatus ~= 3 then
        if atFinalWaypoint and distToTarget2D < 25.0 then
            -- Hold steady at final waypoint without micro-oscillating
            return false, { Yaw = desiredYaw, Target = targetPt }, false
        end
        local isDoorTarget = (not State.HasNavMesh) and State.RouteDoorFlags and State.RouteDoorFlags[State.RouteIdx]
        local centerClear = clearScores and clearScores[4] and clearScores[4].clear or 165.0
        local useWhisker = centerBlocked and bestWhisker and ((not isDoorTarget) or centerClear < 55.0)
        if useWhisker then
            pcall(function() survivor:AddMovementInput({ X = bestWhisker.fx, Y = bestWhisker.fy, Z = 0.0 }, 1.0, false) end)
            desiredYaw = Bridge.YawFromVec(bestWhisker.fx, bestWhisker.fy)
        else
            local dLen = math.sqrt(dx * dx + dy * dy)
            if dLen > 10.0 then
                pcall(function() survivor:AddMovementInput({ X = dx / dLen, Y = dy / dLen, Z = 0.0 }, 1.0, false) end)
            end
        end
    end

    return false, { Yaw = desiredYaw, Target = targetPt }, false
end

-- Pick escape goal far from Slenderman & DangerZones; penalizes dead ends & respects NodeBlacklist / excludePos
function HumanNav.PickEscapeGoal(world, humanPos, threatPos, dangerZones, lateralBiasDeg, excludePos)
    if #State.Nodes == 0 then
        local dx = humanPos.X - threatPos.X
        local dy = humanPos.Y - threatPos.Y
        local l = math.sqrt(dx * dx + dy * dy)
        if l < 1.0 then dx, dy, l = 1.0, 0.0, 1.0 end
        local raw = { X = humanPos.X + (dx / l) * 2800.0, Y = humanPos.Y + (dy / l) * 2800.0, Z = humanPos.Z }
        if State.HasNavMesh then
            local okN, proj = Bridge.ProjectPointToNav(world, raw, { X = 600.0, Y = 600.0, Z = 900.0 })
            if okN and proj then return proj end
        end
        return raw
    end

    local toThreatX = threatPos.X - humanPos.X
    local toThreatY = threatPos.Y - humanPos.Y
    local ttLen = math.sqrt(toThreatX * toThreatX + toThreatY * toThreatY)
    if ttLen > 1.0 then
        toThreatX = toThreatX / ttLen
        toThreatY = toThreatY / ttLen
    end

    local now = os.clock()
    local minMoveDist = State.HasNavMesh and 1200.0 or 550.0
    local bestNode, bestScore = nil, -1e12

    for _, n in ipairs(State.Nodes) do
        local isBlacklisted = (State.NodeBlacklist[n.id] or 0.0) > now
        local nearExclude = excludePos and (Bridge.Dist2D(n.pos, excludePos) < 450.0)
        local skipDoorCenter = (not State.HasNavMesh) and n.isDoorCenter

        if (not isBlacklisted) and (not nearExclude) and (not skipDoorCenter) then
            local distHuman = Bridge.Dist2D(humanPos, n.pos)
            if distHuman >= minMoveDist then
                local distThreat = Bridge.Dist2D(threatPos, n.pos)
                local dirX = (n.pos.X - humanPos.X) / distHuman
                local dirY = (n.pos.Y - humanPos.Y) / distHuman
                local towardThreat = dirX * toThreatX + dirY * toThreatY
                local dirPenalty = (towardThreat > 0.10) and (towardThreat * 4200.0) or 0.0

                local deg = #n.adj
                local topoBonus = 0.0
                if deg <= 1 then
                    topoBonus = -2200.0
                elseif deg == 2 then
                    topoBonus = -500.0
                elseif deg >= 4 then
                    topoBonus = 800.0
                end

                local dangerPen = DangerCostAt(n.pos, dangerZones) * 0.45
                local jukeBonus = 0.0
                if lateralBiasDeg and math.abs(towardThreat) < 0.55 then
                    jukeBonus = 850.0
                end
                local score = distThreat - 0.30 * distHuman - dirPenalty - dangerPen + topoBonus + jukeBonus
                if score > bestScore then
                    bestScore = score
                    bestNode = n
                end
            end
        end
    end

    if bestNode then return bestNode.pos end
    for _, n in ipairs(State.Nodes) do
        if (not n.isDoorCenter) and Bridge.Dist2D(humanPos, n.pos) >= 300.0 then
            return n.pos
        end
    end
    return State.Nodes[1].pos
end

function HumanNav.GetNavState()        return State.NavStatusStr end
function HumanNav.GetCurrentDest()     return State.CurrentSubTarget or State.FinalGoal end
function HumanNav.GetStuckCount()      return State.StuckCount end
function HumanNav.GetOpenedDoorCount() return State.OpenedDoorCount end

return HumanNav
