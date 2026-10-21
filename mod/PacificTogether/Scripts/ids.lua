-- Item containers as plain data: "archetype path=count,..." strings that both players can compare, send and apply.
-- Items are rebuilt from their archetype, so per-item state (durability, upgrades) does not travel.
-- shortcut: archetype + count only; carry per-item properties when playtests show it matters.
local UEHelpers = require("UEHelpers")

local M = {}

function M.alive(o) return o and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

-- "ItemArchetype /Game/x/IA_A.IA_A" -> "/Game/x/IA_A"
local function path(a) return (a:GetFullName():match("^%S+ (.+)$"):gsub("%.[^%./]+$", "")) end

local archs = {} -- path -> archetype object
local function archetype(p)
    local a = archs[p]
    if a and a:IsValid() then return a end
    local full = p .. "." .. p:match("[^/]+$")
    a = StaticFindObject(full)
    if not a:IsValid() then pcall(LoadAsset, full); a = StaticFindObject(full) end
    if a:IsValid() then archs[p] = a end
    return a:IsValid() and a or nil
end

local function system()
    local s = FindFirstOf("InventorySystem")
    if s and s:IsValid() then return s end
    return StaticFindObject("/Script/PenDriverInventory.Default__InventorySystem")
end

function M.count(container)
    local items, have = {}, {}
    container:GetAllItems(items)
    for _, it in ipairs(items) do
        local a = it:get().Archetype
        local p = path(a)
        have[p] = (have[p] or 0) + 1
        archs[p] = a
    end
    return have
end

function M.encode(have)
    local keys = {}
    for p in pairs(have) do keys[#keys + 1] = p end
    table.sort(keys)
    for i, p in ipairs(keys) do keys[i] = p .. "=" .. have[p] end
    return table.concat(keys, ",")
end

function M.decode(s)
    local want = {}
    for p, n in s:gmatch("([^,=]+)=(%d+)") do want[p] = tonumber(n) end
    return want
end

-- make the container hold exactly `want` (path -> count)
function M.apply(container, want)
    local have = M.count(container)
    for p, n in pairs(have) do
        local w = want[p] or 0
        if n > w then container:RemoveItemsOfType(archetype(p), n - w) end
    end
    for p, w in pairs(want) do
        local a = archetype(p)
        for _ = 1, w - (have[p] or 0) do
            if a then container:AddItem(StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary"):CreateItemInstance(UEHelpers.GetWorld(), a, 0), true) end
        end
    end
end

function M.path2(o) return o:GetFullName():match("^%S+ (.+)$") end
M.path, M.archetype, M.system = path, archetype, system
return M
