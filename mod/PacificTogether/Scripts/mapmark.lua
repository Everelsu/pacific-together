-- P8 (D17): where the other player is. Two runtime components on the other player's replicated character, each side its
-- own, nothing replicates and nothing exists outside a session (docs/spikes/PT2-map.md):
--   * a MinimapPlugin MapIconComponent: the ARC screen in the car draws it (the only spatial map the game has)
--   * the game's own HUD objective marker (SC_GenericObjective -> UMG_GenericObjective, edge-clamped on screen), shown
--     only past HANDOVER uu with "<name> <metres> m"; closer than that the name tag (nametag.lua) does the job
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local nametag = require("nametag")
local log = common.log

local M = { HANDOVER = 3000 } -- uu, 30 m: where the name tag is already half faded (nametag NEAR 1500, FAR 5000)
if os.getenv("PT_MUTATE") == "nomapmark" then return M end

local ICON = "/Script/MinimapPlugin.MapIconComponent"
local HUD = "/Game/UI/NavigationSystems/SC_GenericObjective.SC_GenericObjective_C"
local XF = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = 0, Y = 0, Z = 0 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
local TYPE_BLUE = 3 -- EObjectiveMarkerDisplayType: the blue quest marker, with text

local marks = {} -- character full name -> { icon, hud, shown, text }

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

local function class(path)
    local c = StaticFindObject(path)
    if not c:IsValid() then c = LoadAsset(path) end
    return c
end

local function carIcon()
    local wn = UEHelpers.GetWorld():GetFullName()
    for _, c in ipairs(FindAllOf("BP_PlayerCarNew_C") or {}) do
        if valid(c) and c:GetWorld():GetFullName() == wn and valid(c.MapIcon) then return c.MapIcon end
    end
end

-- nil until the car (and so the style to copy) exists
local function addIcon(char)
    local s = carIcon()
    if not s then return nil end
    local icon = char:AddComponentByClass(class(ICON), false, XF, false)
    icon.IconTexture, icon.IconMaterial_UMG, icon.IconMaterial_Canvas = s.IconTexture, s.IconMaterial_UMG, s.IconMaterial_Canvas
    icon:SetIconSize(s.IconSize, s.IconSizeUnit)
    icon:SetIconZOrder(s.IconZOrder + 1)
    icon:SetIconDrawColor({ R = 0.2, G = 0.8, B = 1.0, A = 1.0 })
    icon:SetIconVisible(true)
    return icon
end

local function addHud(char)
    local c = char:AddComponentByClass(class(HUD), false, XF, false)
    c.UpdatePositionOnTick = true
    c:ActivateObjective() -- creates the widget (UMG_GenericObjective) and puts it on the screen
    if valid(c.MainIconWidget) then
        c:SetMarkerVisuals(TYPE_BLUE, FText(""))
        c.MainIconWidget:SetVisibility(2) -- hidden until past HANDOVER
    end
    return c
end

local function update()
    local list = safety.active() and nametag.others() or {}
    local pc = UEHelpers.GetPlayerController()
    local cam = valid(pc) and valid(pc.PlayerCameraManager) and pc.PlayerCameraManager:GetCameraLocation()
    local seen = {}
    for _, ch in ipairs(list) do
        if valid(ch) then
            local key = ch:GetFullName()
            local m = marks[key] or {}
            marks[key], seen[key] = m, true
            if not valid(m.icon) then m.icon = addIcon(ch) end
            if not valid(m.hud) then m.hud = addHud(ch) end
            local w = valid(m.hud) and m.hud.MainIconWidget
            if cam and w and valid(w) then
                local l = ch:K2_GetActorLocation()
                local d = math.sqrt((cam.X - l.X) ^ 2 + (cam.Y - l.Y) ^ 2 + (cam.Z - l.Z) ^ 2)
                local show = d > M.HANDOVER
                if show then
                    local ps = ch.PlayerState
                    local text = (valid(ps) and ps:GetPlayerName():ToString() or "") .. " " .. math.floor(d / 100 + 0.5) .. " m"
                    if text ~= m.text then m.text = text; w.TaskText:SetText(FText(text)) end
                    w.ObjectiveText:SetVisibility(0)
                end
                if show ~= m.shown then m.shown = show; w:SetVisibility(show and 0 or 2) end
            end
        end
    end
    -- the other player left (or the session ended): the markers go with them
    for key, m in pairs(marks) do
        if not seen[key] then
            if valid(m.hud) then m.hud:DeactivateObjective(false); m.hud:K2_DestroyComponent(m.hud) end
            if valid(m.icon) then m.icon:K2_DestroyComponent(m.icon) end
            marks[key] = nil
        end
    end
end

-- The ARC map's terrain and roads are a capture the map bounds take at level start; on the guest it came out blank (only
-- icons, hand playtest 2026-10-23), a RecaptureMinimap once the world is there drew it like the host's (seen live).
-- s after the guest first sees this map's bounds: one capture, once the world has streamed in (each capture held a rendered
-- guest's frame 0.8-1.9 s; two of them, at 10 and 40 s, rendered profile 2026-10-24)
local RECAPTURE = { 30 }
local captureSeen, captureDone = nil, 0

-- a map change frees every object we hold: forget them before it happens
RegisterLoadMapPreHook(function() marks, captureSeen, captureDone = {}, nil, 0 end)

LoopInGameThreadWithDelay(250, function()
    local ok, err = pcall(update)
    if not ok then log("PT|error mapmark %s", tostring(err)) end
end)
LoopInGameThreadWithDelay(1000, function()
    if not safety.guest() or captureDone >= #RECAPTURE then return end
    local ok, err = pcall(function()
        local b = FindFirstOf("BP_GobblerMapBounds_C")
        if not (b and b:IsValid()) then return end
        captureSeen = captureSeen or os.clock()
        if os.clock() - captureSeen >= RECAPTURE[captureDone + 1] then
            captureDone = captureDone + 1
            b:RecaptureMinimap()
            log("PT|mapmark guest map recaptured n=%d", captureDone)
        end
    end)
    if not ok then log("PT|error mapmark recapture %s", tostring(err)) end
end)

return M
