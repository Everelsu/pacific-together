-- The guest sees the host's run (W3, W4, W6, G3). The host owns the world; the guest's process only mirrors it.
--   anomalies  the host replicates its hazards (every BP_Base_Hazard: Tourists, Bunnies, grabbers, Tesla ...), the zone storm
--              and the exit portals (SetReplicates + movement, always relevant); the guest destroys what it simulated itself.
--   run state  once a second the host sends time of day, weather overrides, instability, storm manager state and the picked
--              gateway ("g.world.state"); the guest applies them through the game's own setters.
--   story      the guest's mission manager cannot start missions and its narrative-beat actors are removed: it is a bystander.
-- Everything is inert outside a session (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local safety = require("safety")
local log = common.log
local ov = require("overlay")

local M = { enabled = os.getenv("PT_MUTATE") ~= "noworldsync" } -- the test mutation switches the module off

local function first(c) for _, o in ipairs(FindAllOf(c) or {}) do if o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) then return o end end end
local function live(o) return o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) and not o:GetFullName():find("/Engine/Transient", 1, true) end
local function firstLive(c) for _, o in ipairs(FindAllOf(c) or {}) do if live(o) then return o end end end
local function each(class, fn) for _, o in ipairs(FindAllOf(class) or {}) do if live(o) then fn(o) end end end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error world %s %s", what, tostring(err)) end
end
local function short(o) return (o and o:IsValid()) and o:GetFName():ToString() or "none" end

local WI = StaticFindObject("/Game/Gameplay/Hazards/BaseHazard/BP_Base_Hazard_WorldItem.BP_Base_Hazard_WorldItem_C")
local REPLICATED = { "BP_Base_Hazard_C", "BP_ZoneStorm_Base_C", "BP_LevelTransition_ExitPortal_C" }

-- weather override struct (build 21896301): field names carry the Blueprint GUIDs
local OV = { "Priority_2_E0B18C1F4F7065861D754CBC1717C0F4", "RainAmount_6_1DF01C624F8A4DABBCF2D9B45FEE5251", "FogAmount_7_DF39641648DD1C067F04379E79B4AC5F",
    "WindAmount_11_AA5396694831838AD8399192FA714B4C", "DarknessAmount_12_C1E6970E406443EC371A029B6E403FA3", "ZoneStormAmount_29_0E19DE884D969BB97E764EBE017A5607",
    "AcidAmount_31_1713ABA54AE616BBBC74EEB59EFF6CF2", "Identifier_26_37794E45404F7D45933471B6A50F260C", "OverrideSpeedMult_34_B5D9F9C34E787BDD5826CA97FDFF7EFA" }
local ID = 8
local INSTAB = { TagName = FName("WB.WorldState.Instability.Current") }

local function whiteboard()
    local pm = StaticFindObject("/Script/PenDriverPro.Default__BaseProgressionManager")
    local w = pm:IsValid() and UEHelpers.GetWorld():IsValid() and pm:GetRouteWhiteboard(UEHelpers.GetWorld()) or nil
    return (w and w:IsValid()) and w or nil
end

-- ---------------------------------------------------------------- host

local function replicate()
    for _, class in ipairs(REPLICATED) do
        each(class, function(o)
            if o.RemoteRole ~= 0 or not o:HasAuthority() then return end
            if WI:IsValid() and class == "BP_Base_Hazard_C" and o:IsA(WI) then return end -- item actors need their item instance: not today
            o:SetReplicates(true)
            o:SetReplicateMovement(true)
            o.bAlwaysRelevant = true -- the default 15000 uu cull would hide anomalies from a guest across the map
            o.NetUpdateFrequency = 10
            o:ForceNetUpdate()
        end)
    end
end

local function f(v) return string.format("%.4f", v) end

local function snapshot()
    local L = {}
    local function add(k, v) L[#L + 1] = k .. "\t" .. tostring(v) end
    local tod = first("BP_ToDManager_C")
    if tod then
        local r = {}
        tod["Get Current Time Of Day"](tod, r)
        add("tod", f(r["Returned Time Of Day"] or 0))
        local p = tod["Target TOD Preset"]
        add("preset", (p and p:IsValid()) and p:GetFullName():gsub("^%S+ ", "") or "")
        add("cur", table.concat({ f(tod.TOD_Override_Rain_Current), f(tod.TOD_Override_Fog_Current), f(tod.TOD_Override_Wind_Current),
            f(tod.TOD_Override_Darkness_Current), f(tod["TOD Override Zone Storm Current"]), f(tod["TOD Override Acid Current"]), f(tod.TOD_Override_SpeedMult) }, "|"))
        local a = tod.TargetWeatherOverrideArray
        for i = 1, a:GetArrayNum() do
            local e, v = a[i], {}
            for j, k in ipairs(OV) do
                local x = e[k]
                v[j] = j == ID and x:ToString() or f(x)
            end
            add("ov", table.concat(v, "|"))
        end
    end
    local wb = whiteboard()
    if wb then add("instab", f(wb:GetTagFloat(INSTAB, true, 0))) end
    local sm = first("BP_StormManager_C")
    if sm then
        add("storm", table.concat({ sm.CurrentStormState, tostring(sm.RedWallActive), f(sm.TimeBeforeInstabilityStarts), f(sm.FinalInstabilityTollerance), f(sm.StormAudioVisualIntensity) }, "|"))
        add("gate", short(sm.EvolvedGatewayExit))
    end
    local st = firstLive("BP_ZoneStorm_Base_C")
    if st then add("wall", table.concat({ f(st.Vol_Rad_Main), f(st.Vol_Rad_Weak), tostring(st.Collapsed) }, "|")) end
    return table.concat(L, "\n")
end

local function hostTick()
    replicate()
    local data = snapshot()
    net.toGuests("g.world.state", data)
end

-- ---------------------------------------------------------------- guest

local lastState = 0 -- os.clock() of the last state from the host

local function parse(data)
    local s = { ov = {} }
    for line in (data .. "\n"):gmatch("(.-)\n") do
        local k, v = line:match("^([^\t]+)\t(.*)$")
        if k == "ov" then s.ov[#s.ov + 1] = v elseif k then s[k] = v end
    end
    return s
end

local function split(s) local t = {} for x in (s .. "|"):gmatch("(.-)|") do t[#t + 1] = x end return t end

local function applyTime(s)
    local tod = first("BP_ToDManager_C")
    if not tod then return end
    if s.tod then
        local r = {}
        tod["Get Current Time Of Day"](tod, r)
        local d = math.abs((r["Returned Time Of Day"] or 0) - tonumber(s.tod))
        if math.min(d, 1 - d) > 0.002 then tod["Set Current Time Of Day"](tod, tonumber(s.tod)) end
    end
    if s.preset and s.preset ~= "" then
        local cur = tod["Target TOD Preset"]
        if not (cur and cur:IsValid() and cur:GetFullName():gsub("^%S+ ", "") == s.preset) then
            local c = StaticFindObject(s.preset)
            if c and c:IsValid() then tod["Set New TOD Target"](tod, c) end
        end
    end
    -- overrides by identifier: add or replace the host's, remove the rest
    local want = {}
    for _, line in ipairs(s.ov) do
        local v = split(line)
        want[v[ID]] = true
        local st = {}
        for j, k in ipairs(OV) do st[k] = j == ID and FName(v[j]) or tonumber(v[j]) end
        tod:AddTODWeatherOverride(st)
    end
    local a = tod.TargetWeatherOverrideArray
    local drop = {}
    for i = 1, a:GetArrayNum() do
        local id = a[i][OV[ID]]:ToString()
        if not want[id] then drop[#drop + 1] = id end
    end
    for _, id in ipairs(drop) do tod:RemoveTODWeatherOverride(FName(id)) end
    if s.cur then
        local c = split(s.cur)
        tod:SetCurrentWeatherOverrideValues(tonumber(c[1]), tonumber(c[2]), tonumber(c[3]), tonumber(c[4]), tonumber(c[5]), tonumber(c[6]), tonumber(c[7]))
    end
end

local function applyStorm(s)
    local wb = whiteboard()
    if wb and s.instab then wb:SetTagFloat(INSTAB, tonumber(s.instab)) end
    local sm = first("BP_StormManager_C")
    if sm and s.storm then
        local v = split(s.storm)
        sm.CurrentStormState = tonumber(v[1])
        sm.RedWallActive = v[2] == "true"
        sm.TimeBeforeInstabilityStarts = tonumber(v[3])
        sm.FinalInstabilityTollerance = tonumber(v[4])
        sm.StormAudioVisualIntensity = tonumber(v[5])
    end
    local st = firstLive("BP_ZoneStorm_Base_C")
    if st and s.wall then
        local v = split(s.wall)
        st.Vol_Rad_Main, st.Vol_Rad_Weak, st.Collapsed = tonumber(v[1]), tonumber(v[2]), v[3] == "true"
    end
    -- the gateway the host summoned: its portal is the picked exit here too
    if sm and s.gate and s.gate ~= "none" and short(sm.EvolvedGatewayExit) ~= s.gate then
        each("BP_LevelTransition_ExitPortal_C", function(p)
            if short(p) == s.gate then
                p.IsPickedExit = true
                sm["Select Exit Portal Actor"](sm, p)
                ov.post("Gateway summoned", "good")
            end
        end)
    end
end

-- anything this process simulated on its own: after the host's state has been flowing for a few seconds, only replicated copies (Role 1) stay
local function cleanGuest()
    if os.clock() - lastState > 5 or os.clock() - (M.since or os.clock()) < 5 then return end
    for _, class in ipairs(REPLICATED) do
        each(class, function(o)
            if o.Role == 1 then
                -- the host's copy decides where it is: the guest's own motion code stays off (position updates: g.world.pos)
                if class == "BP_Base_Hazard_C" and not (WI:IsValid() and o:IsA(WI)) then o:SetActorTickEnabled(false) end
                return
            end
            if WI:IsValid() and class == "BP_Base_Hazard_C" and o:IsA(WI) then return end
            o:K2_DestroyActor()
        end)
    end
    -- G3: story drivers of the guest's own game
    each("NarrativeBeatActor", function(o) if o.Role ~= 1 then o:K2_DestroyActor() end end)
end

net.on("g.world.state", function(_, data)
    if not M.enabled then return end
    M.since = M.since or os.clock()
    lastState = os.clock()
    local s = parse(data)
    try("time", applyTime, s)
    try("storm", applyStorm, s)
end)

-- G3: the mission-manager pre-hooks that keep the guest from starting a story live in story.lua.

LoopInGameThreadWithDelay(1000, function()
    if not M.enabled or not safety.active() then M.since = nil return end
    if safety.guest() then try("clean", cleanGuest) else try("host", hostTick) end
end)

-- Level-placed hazards (grabbers) keep simulating on the guest and ignore replicated movement: the host sends the positions
-- of those that moved and the guest puts its copies there (same name on both sides). Between updates the guest's own motion shows.
local sent, beat = {}, 0
LoopInGameThreadWithDelay(250, function()
    if not M.enabled or not safety.active() or safety.guest() then return end
    beat = beat + 1
    if beat % 8 == 0 then sent = {} end -- everything again every 2 s (a late guest, a copy that drifted)
    try("pos", function()
        local L = {}
        each("BP_Base_Hazard_C", function(o)
            if WI:IsValid() and o:IsA(WI) then return end
            local n, l = o:GetFName():ToString(), o:K2_GetActorLocation()
            local p = sent[n]
            if not p or math.abs(p.X - l.X) + math.abs(p.Y - l.Y) + math.abs(p.Z - l.Z) > 20 then
                sent[n] = { X = l.X, Y = l.Y, Z = l.Z }
                L[#L + 1] = string.format("%s\t%.1f\t%.1f\t%.1f", n, l.X, l.Y, l.Z)
            end
        end)
        if #L > 0 then net.toGuests("g.world.pos", table.concat(L, "\n")) end
    end)
end)

net.on("g.world.pos", function(_, data)
    if not M.enabled then return end
    try("pos", function()
        local at = {}
        for line in data:gmatch("[^\n]+") do
            local n, x, y, z = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
            if n then at[n] = { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) } end
        end
        each("BP_Base_Hazard_C", function(o)
            local l = at[o:GetFName():ToString()]
            if l then o:K2_SetActorLocation(l, false, {}, true) end
        end)
    end)
end)

M.snapshot = snapshot
return M
