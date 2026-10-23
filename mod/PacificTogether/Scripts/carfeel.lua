-- PT1 car feel: what the host's car and the radios do is heard and seen by the guest too (messages g.feel.*).
--   radios (both ways, last writer wins): garage stereo on/off, car radio on/off, radio volume, station skips, and the
--     playlist order (the game shuffles it per process, so the host's order is copied to the guest and a skip is the same
--     track on both sides). Polled every 200 ms against the last value sent or received; a received value is applied
--     and remembered, so it is never echoed back.
--   car (host -> guest): the guest's replicated car has its vehicle controller off, so its audio and speedometer read zeros.
--     The host sends throttle, normalised speed (the engine's veh_speed RTPC input), signed speed, the speedometer needle,
--     horn and wipers; the guest writes them after each tick of its AC_CarAudio and speedometer (post-hooks), starts and
--     stops the horn through the car's own audio component, and toggles the wipers through the car's own event.
--     Ignition, gear, headlights and doors already arrive through car.lua.
-- Inert in single player: nothing runs without a listening host that has a guest, or a client.
local UEHelpers = require("UEHelpers")
local common = require("common")
local net = require("net")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "nofeel" then
    log("PT|carfeel disabled (mutation nofeel)")
    return M
end

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local first = common.first
local function now()
    local s, p = {}, {}
    UEHelpers.GetGameplayStatics():GetAccurateRealTime(s, p)
    return s.Seconds + p.PartialSeconds
end
local function mode() return common.netMode() end
local function active() return mode() == "client" or (mode() == "listen" and #net.guests() > 0) end
local function send(kind, data)
    if mode() == "client" then net.toHost(kind, data) else net.toGuests(kind, data) end
end
local function carCar()
    local ok, car = pcall(require, "car")
    return ok and type(car) == "table" and car.theCar and car.theCar(mode() == "listen") or nil
end
local ownedCache = {} -- class -> { car address, object }: the lookup walked every AC_CarAudio_C twice a tick
RegisterLoadMapPreHook(function() ownedCache = {} end)
local function ownedBy(class, car)
    local c = ownedCache[class]
    if c and c[1] == car:GetAddress() and valid(c[2]) then return c[2] end
    for _, o in ipairs(FindAllOf(class) or {}) do
        if valid(o) then
            local own = class == "AC_CarAudio_C" and o:GetOwner() or o:GetAttachParentActor()
            if valid(own) and own:GetFullName() == car:GetFullName() then ownedCache[class] = { car:GetAddress(), o }; return o end
        end
    end
end

-- radios ---------------------------------------------------------------------------------------------------------------

local last = {}
local function radioState()
    local mm, cm = first("BP_MusicManager_C"), first("BP_CarManager_C")
    if not mm or not cm then return end
    return { gs = mm.GarageStereoOn and 1 or 0, cr = cm.CarState_RadioOnOff and 1 or 0, vol = math.floor(mm.MusicVolume * 100 + 0.5) }, mm, cm
end
local function pack(t)
    local r = {}
    for k, v in pairs(t) do r[#r + 1] = k .. "=" .. v end
    table.sort(r)
    return table.concat(r, ";")
end
local function applyRadio(k, v, mm, cm)
    if k == "gs" then
        mm:SetGarageStereoOn(v == 1)
        local st = first("BP_Garage_Stereo_01_C")
        if st then
            pcall(function() if v == 1 then st:TurnStereoVisualsOn(true) else st:TurnStereoVisualsOff(true) end end)
            pcall(function() st:UpdateIcon() end)
        end
    elseif k == "cr" then cm:SetCarRadioOnOffState(v == 1, true)
    elseif k == "vol" then mm:SetRadioVolume(v / 100) end
end
net.on("g.feel.r", function(_, data)
    local s, mm, cm = radioState()
    if not s then return end
    for k, v in data:gmatch("(%w+)=(%-?%d+)") do
        v = tonumber(v)
        if s[k] ~= v then
            local ok, err = pcall(applyRadio, k, v, mm, cm)
            if not ok then log("PT|error feel radio %s %s", k, tostring(err)) end
            log("PT|feel radio %s=%d applied", k, v)
        end
    end
    s = radioState()
    for k in data:gmatch("(%w+)=") do last[k] = s[k] end
end)

local function playlistNames(mm)
    local r = {}
    mm.RadioPlaylist:ForEach(function(_, e) r[#r + 1] = e:get():GetFName():ToString() end)
    return r
end
local plSent, plAt = nil, 0
net.on("g.feel.pl", function(_, data)
    if mode() ~= "client" then return end
    local mm = first("BP_MusicManager_C")
    if not mm then return end
    local byName = {}
    mm.RadioPlaylist:ForEach(function(_, e) local o = e:get(); byName[o:GetFName():ToString()] = o end)
    local i = 0
    for name in data:gmatch("[^,]+") do
        local o = byName[name]
        i = i + 1
        if o and i <= mm.RadioPlaylist:GetArrayNum() then mm.RadioPlaylist[i] = o end
    end
    log("PT|feel playlist %d entries, first %s", i, playlistNames(mm)[1] or "?")
end)
net.on("g.feel.k", function(_, data)
    local mm = first("BP_MusicManager_C")
    if not mm then return end
    pcall(function() mm:SkipTrack(tonumber(data) or 1) end)
    log("PT|feel skip %s applied", data)
end)

local hookedRadio = false
local function hookRadio()
    if hookedRadio then return end
    local ok, err = pcall(RegisterHook, "/Game/Gameplay/Inventory/GenericItemProperties/Components/BP_RadioComponent.BP_RadioComponent_C:ChangeChannel", function(_, dir)
        local okc, e = pcall(function()
            if not active() then return end
            local d = dir:get()
            send("g.feel.k", tostring(d))
            log("PT|feel skip %d sent", d)
        end)
        if not okc then log("PT|error feel skip hook %s", tostring(e)) end
    end)
    if ok then hookedRadio = true else log("PT|error feel hook ChangeChannel %s", tostring(err)) end
end

local lastGuests = 0
local function radioTick()
    hookRadio()
    local s, mm = radioState()
    if not s then return end
    local host = mode() == "listen"
    local n = host and #net.guests() or 0
    local changed = {}
    if host and n > lastGuests then -- a guest arrived: it gets everything
        changed, plSent = s, nil
        for k, v in pairs(s) do last[k] = v end
    else
        for k, v in pairs(s) do
            if last[k] == nil then last[k] = v
            elseif last[k] ~= v then changed[k] = v; last[k] = v end
        end
    end
    lastGuests = n
    if next(changed) then
        send("g.feel.r", pack(changed))
        log("PT|feel radio sent %s", pack(changed))
    end
    if host then
        local names = playlistNames(mm)
        local fp = #names .. ":" .. table.concat(names, ",", 1, math.min(3, #names))
        -- a track that fails to start reshuffles the list every tick (headless, no sound): at most one message a second
        if fp ~= plSent and now() - plAt > 1 then
            plSent, plAt = fp, now()
            send("g.feel.pl", table.concat(names, ","))
        end
    end
end

-- car ------------------------------------------------------------------------------------------------------------------

local feel -- on the guest: the host's latest values
local role, cap, gcar, gaudio, gsp = "none", { veh_engineLoad = 0, veh_speed = 0, veh_speed_direction = 0 }, nil, nil, nil
local function fresh() return feel ~= nil and now() - feel.at < 2.5 end

-- The engine, wheel and speed sounds are fed by the car audio Blueprint through the native SetRTPCValue, from the vehicle
-- controller, which is off on the guest's car. Post hooks never fire for these Blueprint ticks, so the host takes the exact
-- values the game hands to Wwise and the guest swaps them in at the same call (and in the speedometer arm's rotation call).
local hookedAudio = false
local RTPC, ARM = "/Script/AkAudio.AkGameplayStatics:SetRTPCValue", "/Script/Engine.SceneComponent:K2_SetRelativeLocationAndRotation"
local hookIds = {}
local function unhookAudio()
    if not hookedAudio then return end
    for fn, ids in pairs(hookIds) do pcall(UnregisterHook, fn, ids[1], ids[2]) end
    hookIds, hookedAudio = {}, false
end
local function hookAudio()
    if hookedAudio then return end
    local ok, id1, id2 = pcall(RegisterHook, RTPC, function(_, rtpc, val)
        if role ~= "client" and role ~= "listen" then return end
        local okc, e = pcall(function()
            local n = rtpc:get():GetFName():ToString()
            if cap[n] == nil and n ~= "veh_speed_slowRelease" then return end
            if role == "listen" then cap[n] = val:get(); return end
            if not fresh() then return end
            if n == "veh_speed" or n == "veh_speed_slowRelease" then
                val:set(feel.cs)
                if valid(gaudio) then gaudio.CurrentSpeed = feel.cs end
            elseif n == "veh_speed_direction" then val:set(feel.dir)
            elseif n == "veh_engineLoad" then val:set(feel.load) end
        end)
        if not okc then log("PT|error feel rtpc hook %s", tostring(e)) end
    end)
    if not ok then log("PT|error feel hook SetRTPCValue %s", tostring(id1)); return end
    hookIds[RTPC] = { id1, id2 }
    ok, id1, id2 = pcall(RegisterHook, ARM, function(self, _, rot)
        if role ~= "client" or not valid(gsp) or not fresh() then return end
        local okc, e = pcall(function()
            if self:get():GetAddress() == gsp.SpeedArm:GetAddress() then rot:set(feel.arm) end
        end)
        if not okc then log("PT|error feel arm hook %s", tostring(e)) end
    end)
    if not ok then log("PT|error feel hook speedometer %s", tostring(id1)); return end
    hookIds[ARM] = { id1, id2 }
    hookedAudio = true
end

local function sample(car)
    local cm = first("BP_CarManager_C")
    local ca, sp = ownedBy("AC_CarAudio_C", car), ownedBy("BP_CarPart_Internal_Speedometer_C", car)
    if not cm or not ca then return end
    local arm = { Pitch = 0, Yaw = 0, Roll = 0 }
    if sp and valid(sp.SpeedArm) then arm = sp.SpeedArm.RelativeRotation end
    return string.format("%.2f	%.3f	%d	%.3f	%.1f	%.1f	%.1f	%d	%d", cap.veh_engineLoad, cap.veh_speed, cap.veh_speed_direction,
        ca.ThrottleAccumCurrent, arm.Pitch, arm.Yaw, arm.Roll, cm.HornOn and 1 or 0, cm.WiperBladesOnOff and 1 or 0)
end

local lastCar, lastCarAt = nil, 0
local function hostCarTick()
    if not active() then lastCar = nil; return end
    local car = carCar()
    if not car then return end
    local s = sample(car)
    if not s then return end
    local t = now()
    if s ~= lastCar or t - lastCarAt > 1 then
        send("g.feel.c", s)
        lastCar, lastCarAt = s, t
    end
end

local function refreshGuest()
    gcar = carCar()
    gaudio = gcar and ownedBy("AC_CarAudio_C", gcar) or nil
    gsp = gcar and ownedBy("BP_CarPart_Internal_Speedometer_C", gcar) or nil
end

local hornApplied, wiperAt = nil, -10
net.on("g.feel.c", function(_, data)
    if mode() ~= "client" then return end
    local f = {}
    for x in (data .. "	"):gmatch("([^	]*)	") do f[#f + 1] = tonumber(x) end
    if #f < 9 then log("PT|error feel car message incomplete"); return end
    feel = { load = f[1], cs = f[2], dir = f[3], acc = f[4], arm = { Pitch = f[5], Yaw = f[6], Roll = f[7] }, horn = f[8], wip = f[9], at = now() }
    local car = carCar()
    if not car then return end
    local ca, cm = ownedBy("AC_CarAudio_C", car), first("BP_CarManager_C")
    if ca and hornApplied ~= feel.horn then
        if pcall(function() ca:Call_CarHorn_Active(feel.horn == 1) end) then hornApplied = feel.horn end
        log("PT|feel horn %d", feel.horn)
    end
    if cm and (cm.WiperBladesOnOff and 1 or 0) ~= feel.wip and feel.at - wiperAt >= 1 then
        wiperAt = feel.at
        pcall(function() car:ToggleWiperBlades() end)
        log("PT|feel wipers %d", feel.wip)
    end
end)

LoopInGameThreadWithDelay(100, function()
    role = mode()
    local ok, err = pcall(function()
        if active() then hookAudio() else unhookAudio() end
        if role == "client" then refreshGuest() elseif role == "listen" then hostCarTick() end
    end)
    if not ok then log("PT|error feel car tick %s", tostring(err)) end
end)
-- the guest's controller is off, so its throttle input (the engine load and wheel spin sounds) is the host's
LoopInGameThreadWithDelay(16, function()
    if feel and valid(gcar) and fresh() then
        pcall(function()
            gcar.VehicleController.ThrottleInput = feel.load
            if valid(gaudio) and math.abs(gaudio.ThrottleAccumCurrent - feel.acc) > 0.3 then gaudio.ThrottleAccumCurrent = feel.acc end
        end)
    end
end)
LoopInGameThreadWithDelay(200, function()
    if mode() == "standalone" or mode() == "none" then last, plSent, lastGuests, feel, hornApplied = {}, nil, 0, nil, nil; return end
    local ok, err = pcall(radioTick)
    if not ok then log("PT|error feel radio tick %s", tostring(err)) end
end)
return M
