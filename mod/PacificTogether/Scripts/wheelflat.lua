-- Flat / blown tyres on the guest (playtest 2026-10-23 #9). The status effects SE_FlatTire / SE_BlownoutTire live on the wheel
-- item instances and call BP_CarManager:SetPartFlat(slot); the guest's car manager (handling tuning, audio, scan) reads that map
-- through GetPartFlat, but the effects are never applied on the guest, so its wheels were never flat. The host sends the four
-- slots' flat state, the guest sets the same in its car manager. Inert outside a session (Q7).
local common = require("common")
local net = require("net")
local safety = require("safety")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "noflat" }
local SLOTS = { "WheelFL", "WheelFR", "WheelRL", "WheelRR" }
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function slot(n) return { TagName = FName("Car.Equip.Essentials." .. n) } end

net.on("g.wheel.flat", function(_, data)
    if not (M.enabled and safety.guest()) then return end
    local cm = FindFirstOf("BP_CarManager_C")
    if not valid(cm) then return end
    for i, n in ipairs(SLOTS) do
        local want = data:sub(i, i) == "1"
        local o = {}
        cm:GetPartFlat(slot(n), o)
        if o["Is Flat"] ~= want then
            cm:SetPartFlat(slot(n), want)
            log("PT|wheel guest %s flat=%s", n, tostring(want))
        end
    end
end)

local lastSent, lastAt = "", 0
LoopInGameThreadWithDelay(1000, function()
    if not (M.enabled and safety.active() and not safety.guest()) then return end
    local ok, err = pcall(function()
        local cm = FindFirstOf("BP_CarManager_C")
        if not valid(cm) then return end
        local s = ""
        for _, n in ipairs(SLOTS) do
            local o = {}
            cm:GetPartFlat(slot(n), o)
            s = s .. (o["Is Flat"] and "1" or "0")
        end
        if s ~= lastSent or os.clock() - lastAt > 5 then lastSent, lastAt = s, os.clock(); net.toGuests("g.wheel.flat", s) end
    end)
    if not ok then log("PT|error wheelflat %s", tostring(err)) end
end)

return M
