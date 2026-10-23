-- P7 (D17): the other player's name over their head, fading out with distance. Each side spawns its own local
-- TextRenderActor on the other player's character; nothing replicates and nothing exists outside a session.
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local health = require("health")
local log = common.log

local M = { NEAR = 1500, FAR = 5000 } -- uu: full strength up to NEAR, gone at FAR
local CHAR = "PDP_MainCharacter_C"
local HEIGHT = 115 -- uu above the capsule centre, just over the head
-- translucent, so the colour's alpha fades the text (the default text material is opaque)
local MAT = "/Engine/EngineMaterials/AntiAliasedTextMaterialTranslucent.AntiAliasedTextMaterialTranslucent"

function M.alpha(d) return math.max(0, math.min(1, (M.FAR - d) / (M.FAR - M.NEAR))) end

local tags, others, pc, nextScan = {}, {}, nil, 0

-- TextRender draws offline fonts only (256 Latin glyphs; the game's other fonts are runtime fonts it cannot draw), so a name with other
-- letters (Cyrillic: squares, 2026-10-23) is drawn by a UMG TextBlock in the default font instead, at the projected head position.
local uiN = 0 -- blocks handed out
local ui = nil -- { widget, canvas, tree, blocks = {} }
local function needsUi(label) return os.getenv("PT_MUTATE") ~= "nocyr" and label:find("[Ä-ÿ]") ~= nil end -- UTF-8 lead byte above U+00FF
local function uiBlock(i)
    if not (ui and ui.widget:IsValid()) then
        local w = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, StaticFindObject("/Script/UMG.UserWidget"), pc)
        if not (w and w:IsValid() and w.WidgetTree:IsValid()) then return nil end
        local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), w.WidgetTree, FName("PTNameTagRoot"))
        w.WidgetTree.RootWidget = canvas
        w:SetVisibility(3); canvas:SetVisibility(3)
        w:AddToViewport(9000)
        ui = { widget = w, canvas = canvas, blocks = {} }
    end
    local b = ui.blocks[i]
    if not (b and b.text:IsValid()) then
        local t = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), ui.widget.WidgetTree, FName("PTNameTag" .. i))
        t:SetJustification(1) -- center
        t:SetShadowOffset({ X = 1.5, Y = 1.5 })
        t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 1 })
        local f = t.Font; f.Size = 18; t:SetFont(f)
        local slot = ui.canvas:AddChildToCanvas(t)
        slot:SetAutoSize(true)
        slot:SetAlignment({ X = 0.5, Y = 1 })
        b = { text = t, slot = slot }
        ui.blocks[i] = b
    end
    return b
end
local function hideUi(tag)
    if tag.ui and tag.ui.text:IsValid() then tag.ui.text:SetVisibility(1) end
end
-- name above the tag's position; false when it is behind us or the tag is faded out
local function showUi(tag, i, label, a)
    local b = uiBlock(i)
    if not b then return end
    tag.ui = b
    local v = {}
    local ok = a > 0 and pc:ProjectWorldLocationToScreen(tag.text:K2_GetComponentLocation(), v, false)
    if not ok then b.text:SetVisibility(1); return end
    local scale = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary"):GetViewportScale(pc)
    b.slot:SetPosition({ X = v.X / scale, Y = v.Y / scale })
    if b.shown ~= label then b.shown = label; b.text:SetText(FText(label)) end
    b.text:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = a }, ColorUseRule = 0 })
    b.text:SetVisibility(3)
end

-- the other players' characters as of the last scan (mapmark.lua shares them)
function M.others() return others end

-- grows with distance past 4 m, so the name keeps about the same size on screen
local function fitSize(tag, d)
    local size = math.floor(16 * math.max(1, d / 400))
    if size ~= tag.size then tag.size = size; tag.text:SetWorldSize(size) end
end

local function playerName(char)
    local ps = char.PlayerState
    return ps:IsValid() and ps:GetPlayerName():ToString() or ""
end

local function spawnTag(char)
    local gs = UEHelpers.GetGameplayStatics()
    local l = char:K2_GetActorLocation()
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = l.X, Y = l.Y, Z = l.Z + HEIGHT }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local a = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(char, StaticFindObject("/Script/Engine.TextRenderActor"), xf, 1, nil), xf)
    local t = a.TextRender
    t:SetHorizontalAlignment(1) -- EHTA_Center
    t:SetVerticalAlignment(1)   -- EVRTA_TextCenter
    local mat = StaticFindObject(MAT)
    if not mat:IsValid() then mat = LoadAsset(MAT) end
    if mat and mat:IsValid() then t:SetTextMaterial(mat) end
    t:SetAbsolute(false, true, false) -- world rotation, so it can face our camera whatever the character does
    a:K2_AttachToActor(char, FName("None"), 1, 1, 1, false) -- keep world
    return { actor = a, text = t, name = nil }
end

-- the characters of this world that are not ours; FindAllOf walks every object, so only every 2 s
local function scan()
    others, pc = {}, nil
    local wn = UEHelpers.GetWorld():GetFullName()
    for _, p in ipairs(FindAllOf("PlayerController") or {}) do
        if p:IsValid() and p:IsLocalController() and p:GetWorld():GetFullName() == wn then pc = p end
    end
    local me = pc and pc.Pawn
    for _, c in ipairs(FindAllOf(CHAR) or {}) do
        if c:IsValid() and c:GetWorld():GetFullName() == wn and not (me and me:IsValid() and c:GetFullName() == me:GetFullName()) then
            others[#others + 1] = c
        end
    end
end

local function update()
    local active = safety.active()
    if active and os.time() >= nextScan then nextScan = os.time() + 2; scan() end
    local pcm = active and pc and pc:IsValid() and pc.PlayerCameraManager
    local cam = pcm and pcm:IsValid() and pcm:GetCameraLocation()
    local seen = {}
    for _, c in ipairs(cam and others or {}) do
        if c:IsValid() then
            local key = c:GetFullName()
            local tag = tags[key]
            if not (tag and tag.actor:IsValid()) then tag = spawnTag(c); tags[key] = tag end
            seen[key] = true
            -- P4: the other player's health under the name (health.lua), once they have reported it
            local n = playerName(c)
            local hp = health.label()
            local label = hp and (n .. "\n" .. hp) or n
            local viaUi = needsUi(label)
            if label ~= tag.name or viaUi ~= tag.viaUi then tag.name, tag.viaUi = label, viaUi; tag.text:SetText(viaUi and "" or label) end
            local p = tag.text:K2_GetComponentLocation()
            local dx, dy, dz = cam.X - p.X, cam.Y - p.Y, cam.Z - p.Z
            local d = math.sqrt(dx * dx + dy * dy + dz * dz)
            local a = M.alpha(d)
            fitSize(tag, d)
            tag.actor:K2_SetActorRotation({ Pitch = 0, Yaw = math.deg(math.atan(dy, dx)), Roll = 0 }, false)
            tag.text:SetTextRenderColor({ R = 255, G = 255, B = 255, A = math.floor(a * 255 + 0.5) })
            tag.actor:SetActorHiddenInGame(a <= 0)
            if viaUi then
                if not tag.idx then uiN = uiN + 1; tag.idx = uiN end
                showUi(tag, tag.idx, label, a)
            else
                hideUi(tag)
            end
        end
    end
    -- the other player left, or the session ended: their tag goes with them
    for key, tag in pairs(tags) do
        if not seen[key] then
            hideUi(tag)
            if tag.actor:IsValid() then tag.actor:K2_DestroyActor() end
            tags[key] = nil
        end
    end
end

-- a map change frees every object we hold (the tags die with their world): forget them before it happens
RegisterLoadMapPreHook(function() tags, others, pc, nextScan, ui, uiN = {}, {}, nil, 0, nil, 0 end)

LoopInGameThreadWithDelay(50, function()
    local ok, err = pcall(update)
    if not ok then log("PT|error nametag %s", tostring(err)) end
end)

return M
