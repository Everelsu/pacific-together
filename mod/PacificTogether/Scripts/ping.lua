-- PT2 ping: look at something, press middle mouse (G if UE4SS cannot bind the mouse), and both players see a marker there for
-- ~8 s and hear a short HUD sound. The marker is a local TextRenderActor (like nametag.lua): "Name / item / distance",
-- turned to our camera each frame. One ping per player: a new one replaces the old. The guest's ping goes to the host
-- (g.ping.send), the host shows it and tells every guest (g.ping.show); the host's own ping goes straight to the guests.
-- Message data: "name\tx\ty\tz\tlabel". Inert in single player: the key does nothing without a session.
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local safety = require("safety")
local log = common.log

local M = { LIFE = tonumber(os.getenv("PT_PING_LIFE") or "") or 8, REACH = 30000 }
local OFF = os.getenv("PT_MUTATE") == "noping" -- tests only
local MAT = "/Engine/EngineMaterials/AntiAliasedTextMaterialTranslucent.AntiAliasedTextMaterialTranslucent"
local SOUND = "hud_log_entry_new_appear" -- the game's own short HUD blip (UMG_LogBook_Notification)
local SOUND_PATH = "/Game/WwiseAudio/Events/UI/ui_hud/" .. SOUND .. "." .. SOUND
local ITEM_NEAR = 90 -- uu: an item or container this close to the view ray counts as aimed at

local marks = {} -- player name -> { actor, text, loc, name, label, t0 }
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function localPC()
    local pc = UEHelpers.GetPlayerController()
    return valid(pc) and pc or nil
end
local function nameOf(pc)
    local ps = pc and pc.PlayerState
    return (ps and ps:IsValid()) and ps:GetPlayerName():ToString() or "Player"
end

-- "BP_Lootable_Glovebox_C" -> "Lootable Glovebox"
local function pretty(c) return (c:gsub("^BP_", ""):gsub("_C$", ""):gsub("_", " "):gsub("(%l)(%u)", "%1 %2")) end

-- what the player aims at: the world item's title, or a container's class name; nil for plain geometry
local function describe(origin, dir, dist)
    local best, bestD
    local function consider(a, name)
        if not valid(a) or a:GetAttachParentActor():IsValid() then return end
        local l = a:K2_GetActorLocation()
        local vx, vy, vz = l.X - origin.X, l.Y - origin.Y, l.Z - origin.Z
        local t = vx * dir.X + vy * dir.Y + vz * dir.Z -- along the ray
        if t < 0 or t > dist + ITEM_NEAR then return end
        local px, py, pz = vx - dir.X * t, vy - dir.Y * t, vz - dir.Z * t
        local d = math.sqrt(px * px + py * py + pz * pz)
        if d < ITEM_NEAR and (not bestD or d < bestD) then best, bestD = name(a), d end
    end
    for _, a in ipairs(FindAllOf("BP_WorldItem_C") or {}) do
        consider(a, function(o)
            local ok, t = pcall(function() return o.Instance.Archetype.Title:ToString() end)
            return ok and t ~= "" and t or pretty(o:GetClass():GetFName():ToString())
        end)
    end
    for _, a in ipairs(FindAllOf("BP_Lootable_Base_C") or {}) do
        consider(a, function(o) return pretty(o:GetClass():GetFName():ToString()) end)
    end
    return best
end

-- the player's real view: camera position and direction, a line trace along it. Returns the hit point and what is aimed at.
function M.trace()
    local pc = localPC()
    local pcm = pc and pc.PlayerCameraManager
    if not (pcm and pcm:IsValid()) then return end
    local o, r = pcm:GetCameraLocation(), pcm:GetCameraRotation()
    local cp, sp, cy, sy = math.cos(math.rad(r.Pitch)), math.sin(math.rad(r.Pitch)), math.cos(math.rad(r.Yaw)), math.sin(math.rad(r.Yaw))
    local dir = { X = cp * cy, Y = cp * sy, Z = sp }
    local e = { X = o.X + dir.X * M.REACH, Y = o.Y + dir.Y * M.REACH, Z = o.Z + dir.Z * M.REACH }
    local ignore = {}
    if valid(pc.Pawn) then ignore[1] = pc.Pawn end
    -- from inside the car the ray starts in the car (the Pawn is the character, the car is what it sits in)
    local okc, car = pcall(function() return require("car").theCar(common.netMode() == "listen") end)
    if okc and valid(car) then ignore[#ignore + 1] = car end
    local okh, ch = pcall(function() return FindFirstOf("BP_MainCharacterManager_C").CharacterActor end)
    if okh and valid(ch) then ignore[#ignore + 1] = ch end
    local hit = {}
    local ok = UEHelpers.GetKismetSystemLibrary():LineTraceSingle(UEHelpers.GetWorldContextObject(), o, e, 0, false, ignore, 0, hit, true,
        { R = 0, G = 0, B = 0, A = 0 }, { R = 0, G = 0, B = 0, A = 0 }, 0)
    if not ok then return end
    local p = hit.ImpactPoint
    local dist = math.sqrt((p.X - o.X) ^ 2 + (p.Y - o.Y) ^ 2 + (p.Z - o.Z) ^ 2)
    return { x = p.X, y = p.Y, z = p.Z, label = describe(o, dir, dist) }
end

local function sound()
    pcall(function()
        local ak = StaticFindObject("/Script/AkAudio.Default__AkGameplayStatics")
        local ev = StaticFindObject(SOUND_PATH)
        local zero, rot = { X = 0, Y = 0, Z = 0 }, { Pitch = 0, Yaw = 0, Roll = 0 }
        if ev:IsValid() then ak:PostEventAtLocation(ev, zero, rot, "", UEHelpers.GetWorldContextObject())
        else ak:PostEventAtLocationByName(SOUND, zero, rot, UEHelpers.GetWorldContextObject()) end
    end)
end

local function drop(key)
    local m = marks[key]
    if m and valid(m.actor) then m.actor:K2_DestroyActor() end
    marks[key] = nil
end

local function spawn(x, y, z)
    local gs = UEHelpers.GetGameplayStatics()
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = x, Y = y, Z = z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local a = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(UEHelpers.GetWorldContextObject(), StaticFindObject("/Script/Engine.TextRenderActor"), xf, 1, nil), xf)
    a:K2_SetActorLocation({ X = x, Y = y, Z = z }, false, {}, true) -- the spawn transform alone left it at the origin
    local t = a.TextRender
    t:SetHorizontalAlignment(1)
    t:SetVerticalAlignment(2) -- EVRTA_TextBottom: the last line ("v") sits on the point
    local mat = StaticFindObject(MAT)
    if not mat:IsValid() then mat = LoadAsset(MAT) end
    if mat and mat:IsValid() then t:SetTextMaterial(mat) end
    t:SetTextRenderColor({ R = 255, G = 210, B = 70, A = 255 })
    return a, t
end

-- show (or replace) the marker of one player
function M.show(key, name, x, y, z, label)
    if OFF or not safety.active() then return end
    drop(key)
    local a, t = spawn(x, y, z)
    marks[key] = { actor = a, text = t, loc = { X = x, Y = y, Z = z }, name = name, label = label or "", t0 = os.clock(), shown = nil, size = nil }
    sound()
    log("PT|ping show %s %.0f %.0f %.0f '%s'", name, x, y, z, label or "")
end

-- host: a ping from a guest (or from ourselves) goes to everyone
local function everyone(key, name, line)
    local x, y, z, label = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not (x and y and z) then return end
    M.show(key, name, x, y, z, label)
    net.toGuests("g.ping.show", key .. "\t" .. name .. "\t" .. x .. "\t" .. y .. "\t" .. z .. "\t" .. label)
end

net.on("g.ping.send", function(pc, data) if common.netMode() == "listen" then everyone(tostring(pc:GetAddress()), nameOf(pc), data) end end)
net.on("g.ping.show", function(_, data)
    if common.netMode() ~= "client" then return end
    local key, name, x, y, z, label = data:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$")
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if key and x and y and z then M.show(key, name, x, y, z, label) end
end)

-- what the key does; returns the hit used (nil when nothing was aimed at or no session)
function M.press()
    if OFF or not safety.active() then return end
    local mode = common.netMode()
    if mode ~= "listen" and mode ~= "client" then return end
    local h = M.trace()
    if not h then return end
    local line = string.format("%.0f\t%.0f\t%.0f\t%s", h.x, h.y, h.z, h.label or "")
    log("PT|ping press %s", line:gsub("\t", " "))
    if mode == "listen" then everyone("host", nameOf(localPC()), line) else net.toHost("g.ping.send", line) end
    return h
end

-- the markers now up: { name, actor, text, x, y, z, age }
function M.markers()
    local r = {}
    for k, m in pairs(marks) do
        if valid(m.actor) then
            r[#r + 1] = { name = m.name, actor = m.actor, text = m.text, label = m.label, x = m.loc.X, y = m.loc.Y, z = m.loc.Z, age = os.clock() - m.t0 }
        end
    end
    return r
end

local function update()
    local pc = localPC()
    local pcm = pc and pc.PlayerCameraManager
    local cam = valid(pcm) and pcm:GetCameraLocation()
    for key, m in pairs(marks) do
        if not valid(m.actor) or os.clock() - m.t0 > M.LIFE or not safety.active() then
            drop(key)
        elseif cam then
            local dx, dy, dz = cam.X - m.loc.X, cam.Y - m.loc.Y, cam.Z - m.loc.Z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            local meters = math.floor(d / 100 + 0.5)
            local txt = (m.label ~= "" and (m.name .. "\n" .. m.label) or m.name) .. "\n" .. meters .. " m\nv"
            if txt ~= m.shown then m.shown = txt; m.text:SetText(txt) end
            -- keeps about the same size on screen: grows with distance
            local size = math.floor(18 * math.max(1, d / 500))
            if size ~= m.size then m.size = size; m.text:SetWorldSize(size) end
            m.actor:K2_SetActorRotation({ Pitch = 0, Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, false)
        end
    end
end

-- a map change frees every object we hold
RegisterLoadMapPreHook(function() marks = {} end)

-- the key only raises a flag that this loop handles: an ExecuteInGameThread per press, spammed, crashed both games inside
-- UE4SS ("Ref was not function", playtest 2026-10-22); at most one ping per half second
local wanted, lastPress = false, -1
LoopInGameThreadWithDelay(50, function()
    if wanted then
        wanted = false
        if os.clock() - lastPress >= 0.5 then
            lastPress = os.clock()
            local ok, err = pcall(M.press)
            if not ok then log("PT|error ping press %s", tostring(err)) end
        end
    end
    local ok, err = pcall(update)
    if not ok then log("PT|error ping %s", tostring(err)) end
end)

-- middle mouse; if UE4SS has no such key (or cannot bind it) the fallback is G
local KEY = (Key and Key.MIDDLE_MOUSE_BUTTON) and "MIDDLE_MOUSE_BUTTON" or "G"
local function bind(k) return pcall(RegisterKeyBind, Key[k], function() wanted = true end) end
local ok = bind(KEY)
if not ok and KEY ~= "G" then KEY = "G"; ok = bind(KEY) end
-- the test mod is another Lua state: its scenario presses the key through the console ("ptping"), same handler
pcall(RegisterConsoleCommandHandler, "ptping", function() wanted = true return true end)
log("PT|ping key %s bound=%s", KEY, tostring(ok))

return M
