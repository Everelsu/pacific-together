-- PT2 garage stations (PLAN G2, D21): the guest uses the stations with its own game's UI, the HOST performs each action on the shared
-- resources, and the result reaches both sides through the syncs that already exist (loot.lua world items and garage storage, progression.lua
-- research graph, garage.lua installed upgrades). Notes: docs/spikes/PT2-stations.md.
--   g.st.shred  spec<LF>spec...  Part Shredder: items the guest put in and shredded; the host puts them in ITS shredder and runs it,
--                                the products come out of the host's dispenser (world items, loot.lua shows them to the guest)
--   g.st.buy    node path        Research: the guest's PurchaseNode on a node; the host pays and unlocks (PurchaseNode + the bench's own
--                                OnNodePurchased, which prints the blueprint or upgrade kit); progression.lua then shows it as purchased on the guest
--   g.st.up     spawner<TAB>cls  Garage upgrade the guest built at a spawner (InstallSpecificUpgrade); the host installs it too, garage.lua shows it back
-- Guest side, what must NOT happen locally: the shredder's products (they would be a second copy), the research cost (the host pays).
-- Fabrication (craft, "Craft Recipe Asset") stays local on the guest: its garage materials ride loot.lua's storage sync, the product is the guest's.
-- Inert in single player (Q7).
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local net = require("net")
local ids = require("ids")
local garage = require("garage")
local ov = require("overlay")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "nostations" then return M end

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function guest() return common.netMode() == "client" and safety.active() end
local function host() return common.netMode() == "listen" and safety.active() end
local function real(o) return valid(o) and not o:GetFullName():find("/Engine/Transient", 1, true) end
local function first(class)
    for _, o in ipairs(FindAllOf(class) or {}) do if real(o) then return o end end
end
local function fullpath(o) return o:GetFullName():match("^%S+ (.+)$") end

-- Part Shredder -------------------------------------------------------------------------------------------------------------

local SHRED = "/Game/Gameplay/CarGarage/Stations/PartShredder/BP_Garage_PartShredder.BP_Garage_PartShredder_C"
local shredded, shredAt = {}, 0 -- guest: specs of what the local shredder took, sent once the run is over

local function shredHook(self, inst)
    if not guest() then return end
    local i = inst:get()
    if not valid(i) then return end
    shredded[#shredded + 1] = ids.spec(i)
    shredAt = os.clock()
    -- the local products would be a second copy of what the host's shredder makes
    local s = self:get()
    pcall(function() s.SmashedProducts:Empty() end)
end

local kick = false
net.on("g.st.shred", function(_, data)
    if not host() then return end
    local s = first("BP_Garage_PartShredder_C")
    if not s then log("PT|st shred: host has no shredder installed"); return end
    local c, n = s.BP_InventoryContainerComponent, 0
    local lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
    for spec in data:gmatch("[^\n]+") do
        local a = ids.archetype(spec:match("^[^:]+"))
        if a then
            local inst = lib:CreateItemInstance(UEHelpers.GetWorld(), a, 0)
            ids.setProps(inst, spec)
            local r = {}
            c:AddItem(inst, r)
            if r.Added then n = n + 1 end
        end
    end
    kick = n > 0
    log("PT|st shred %d items put in the host's shredder", n)
    if n > 0 then ov.post(ov.other() .. " is using the part shredder", "good", "st.shred") end
end)

local function hostShredder()
    if not (kick and host()) then return end
    local s = first("BP_Garage_PartShredder_C")
    if not s or s.IsShredding then return end
    kick = false
    s:OnTransactionEnd(s.BP_InventoryContainerComponent) -- what closing the shredder's container does
end

-- Research ------------------------------------------------------------------------------------------------------------------

local buying = false -- guest: inside the game's own PurchaseNode, whose cost recipe must not run here

net.on("g.st.buy", function(_, data)
    if not host() then return end
    local node = StaticFindObject(data)
    local g = FindFirstOf("BaseGenericGraphState")
    local im = FindFirstOf("BP_InventoryManager_C")
    if not (valid(node) and valid(g) and valid(im)) then log("PT|st buy: no node or graph %s", data); return end
    if g:HasNodeBeenPurchased(node) then return end
    im:SetActiveTier(3, true, true) -- what the research station's screen sets: pay from backpack, garage and car
    local ok = g:PurchaseNode(node)
    log("PT|st buy %s -> %s", data:match("[^:]+$"), tostring(ok))
    if ok then
        local bench = first("BP_Garage_InventingBench_C")
        if bench then pcall(function() bench:OnNodePurchased(node) end) end -- the printed blueprint / upgrade kit
        ov.post(ov.other() .. " researched " .. data:match("[^:]+$"), "good", "st.buy")
    end
end)

local function buyPre(_, node)
    if not guest() then return end
    local n = node:get()
    if not valid(n) then return end
    buying = true
    log("PT|st buy intent %s", n:GetFullName():match("[^:]+$"))
    net.toHost("g.st.buy", fullpath(n))
end
local function buyPost() buying = false end

local function execPre(_, _, _, inputs, outputs)
    if not buying then return end
    inputs:get():Empty(); outputs:get():Empty()
end

-- Garage upgrades -----------------------------------------------------------------------------------------------------------

net.on("g.st.up", function(_, data)
    if not host() then return end
    local name, cls = data:match("^([^\t]+)\t(.+)$")
    local s
    for _, o in ipairs(FindAllOf("BP_GarageInstallation_Spawner_C") or {}) do
        if real(o) and o:GetFName():ToString() == name then s = o end
    end
    local c = ids.asset(cls)
    if not (s and c) then log("PT|st up: no spawner or class %s", tostring(data)); return end
    s:InstallSpecificUpgrade(c, false)
    log("PT|st up installed %s on %s", cls:match("[^.]+$"), name)
    ov.post(ov.other() .. " built " .. cls:match("[^.]+$"):gsub("^UP_Garage_", ""), "good", "st.up")
end)

local function upHook(self, cls)
    if not guest() or garage.applying then return end
    local c = cls:get()
    if not valid(c) then return end
    local path = fullpath(c)
    log("PT|st up intent %s on %s", path:match("[^.]+$"), self:get():GetFName():ToString())
    net.toHost("g.st.up", self:get():GetFName():ToString() .. "\t" .. path)
end

-- hooks: the Blueprint classes load after the main menu, so they are retried ------------------------------------------------------

local HOOKS = {
    { SHRED .. ":ShredItem", nil, shredHook },
    { "/Script/PenDriverPro.BaseGenericGraphState:PurchaseNode", buyPre, buyPost },
    { "/Script/PenDriverInventory.InventoryRecipe:ExecuteRecipe", execPre },
    { "/Game/Gameplay/CarGarage/BP_GarageInstallation_Spawner.BP_GarageInstallation_Spawner_C:InstallSpecificUpgrade", nil, upHook },
}
local done = {}
local function hookAll()
    for i, h in ipairs(HOOKS) do
        if not done[i] then
            local function wrap(fn)
                return fn and function(...)
                    local ok, err = pcall(fn, ...)
                    if not ok then log("PT|error stations hook %d %s", i, tostring(err)) end
                end
            end
            -- Blueprint functions: one callback (it runs after the function, as in guestact.lua); the native PurchaseNode takes pre and post
            local ok
            if h[2] and h[3] then ok = pcall(RegisterHook, h[1], wrap(h[2]), wrap(h[3])) else ok = pcall(RegisterHook, h[1], wrap(h[2] or h[3])) end
            if ok then done[i] = true; log("PT|stations hooked %d", i) end
        end
    end
end

LoopInGameThreadWithDelay(500, function()
    if common.netMode() == "client" then
        local ok, err = pcall(hookAll)
        if not ok then log("PT|error stations hook %s", tostring(err)) end
        if #shredded > 0 and os.clock() - shredAt > 0.4 then
            net.toHost("g.st.shred", table.concat(shredded, "\n"))
            log("PT|st shred intent %d items", #shredded)
            shredded = {}
        end
    elseif host() then
        local ok, err = pcall(hostShredder)
        if not ok then log("PT|error stations host %s", tostring(err)) end
    end
end)

return M
