-- In-game overlay (M6): top right, a version label plus a session status line, and under it a short feed of what the mod
-- syncs ("<name> entered the car", "2 items taken from the trunk x3"). A UMG widget built from Lua (UserWidget ->
-- CanvasPanel -> VerticalBox -> TextBlocks), never hit-testable. The label shows from the main menu on, also in single
-- player; the feed only takes messages during a session. overlay.post(text, kind, key): kind picks the colour
-- ("info" default, "warn", "good"); lines with the same key that are still visible merge into one with a count.
local UEHelpers = require("UEHelpers")
local common = require("common")
local safety = require("safety")
local log = common.log

local M = {}
if os.getenv("PT_MUTATE") == "nooverlay" then
    function M.post() end
    function M.other() return "Player" end
    function M.settled() return false end
    return M
end

local LINES, LIFE, FADE, SETTLE = 5, 6, 1.5, 6 -- visible lines, seconds a line lives, fade-out, seconds into a session before loot-style chatter is allowed
local Z = 10000
local COLOR = { -- linear RGB: off-white text, a teal accent for the status, muted warn and good
    label = { R = 0.78, G = 0.78, B = 0.74 }, status = { R = 0.25, G = 0.8, B = 0.72 },
    info = { R = 0.78, G = 0.78, B = 0.74 }, warn = { R = 0.9, G = 0.45, B = 0.3 }, good = { R = 0.3, G = 0.75, B = 0.5 },
}

local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end

-- a hot reload leaves the old widget in the viewport: take it out
for _, b in ipairs(FindAllOf("VerticalBox") or {}) do
    if b:IsValid() and b:GetFName():ToString() == "PTOverlayBox" then
        pcall(function() b:GetOuter():GetOuter():RemoveFromParent() end)
    end
end

local ui = nil -- { widget, label, status, lines = { TextBlock... }, cache = {} }
local feed = {} -- { text, kind, key, n, t0 }
local sessionSince, names, seen = nil, {}, {} -- session age; remote player names now / ever (host side)
local wasConnected, hostName = false, nil

local function text(tree, name, size, kind)
    local t = StaticConstructObject(StaticFindObject("/Script/UMG.TextBlock"), tree, FName(name))
    t:SetJustification(2) -- right
    t:SetShadowOffset({ X = 1.5, Y = 1.5 })
    t:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 1 })
    local f = t.Font
    f.Size = size
    t:SetFont(f)
    t:SetColorAndOpacity({ SpecifiedColor = { R = COLOR[kind].R, G = COLOR[kind].G, B = COLOR[kind].B, A = 1 }, ColorUseRule = 0 })
    return t
end

local function build()
    local pc = UEHelpers.GetPlayerController()
    if not valid(pc) then return end
    local w = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary"):Create(pc, StaticFindObject("/Script/UMG.UserWidget"), pc)
    if not valid(w) or not valid(w.WidgetTree) then return end
    local tree = w.WidgetTree
    local canvas = StaticConstructObject(StaticFindObject("/Script/UMG.CanvasPanel"), tree, FName("PTOverlayRoot"))
    local box = StaticConstructObject(StaticFindObject("/Script/UMG.VerticalBox"), tree, FName("PTOverlayBox"))
    tree.RootWidget = canvas
    local slot = canvas:AddChildToCanvas(box)
    slot:SetAnchors({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
    slot:SetAlignment({ X = 1, Y = 0 })
    slot:SetPosition({ X = -18, Y = 12 })
    slot:SetAutoSize(true)
    local n = { widget = w, cache = {}, lines = {} }
    local function add(t) box:AddChildToVerticalBox(t):SetHorizontalAlignment(3) end -- right
    n.label = text(tree, "PTVersion", 18, "label"); add(n.label)
    n.status = text(tree, "PTStatus", 16, "status"); add(n.status)
    for i = 1, LINES do
        n.lines[i] = text(tree, "PTFeed" .. i, 16, "info")
        n.lines[i]:SetVisibility(1)
        add(n.lines[i])
    end
    n.label:SetText(FText("Pacific Together " .. common.MOD_VERSION))
    -- nothing of it takes input or hit tests: the whole tree is HitTestInvisible
    box:SetVisibility(3); canvas:SetVisibility(3); w:SetVisibility(3)
    w:AddToViewport(Z)
    return n
end

local function set(t, key, value) -- only touch the widget when something changed
    if ui.cache[key] ~= value then ui.cache[key] = value; t:SetText(FText(value)) end
end

-- "%d" in the text is the running count of a coalesced burst, "{s}" its plural; without "%d" a repeat shows as "x3"
local function label(l)
    local t = l.fmt:gsub("{s}", l.n == 1 and "" or "s")
    local c, hit = t:gsub("%%d", tostring(l.n))
    if hit > 0 then return c end
    return l.n > 1 and (t .. "  x" .. l.n) or t
end

local function render()
    local now = os.clock()
    for i = #feed, 1, -1 do if now - feed[i].t0 > LIFE then table.remove(feed, i) end end
    for i, t in ipairs(ui.lines) do
        local l = feed[math.max(1, #feed - LINES + 1) + i - 1] -- newest at the bottom, the last LINES shown
        local vis = l and 3 or 1
        if ui.cache["v" .. i] ~= vis then ui.cache["v" .. i] = vis; t:SetVisibility(vis) end
        if l then
            set(t, "t" .. i, label(l))
            if ui.cache["k" .. i] ~= l.kind then
                ui.cache["k" .. i] = l.kind
                local c = COLOR[l.kind] or COLOR.info
                t:SetColorAndOpacity({ SpecifiedColor = { R = c.R, G = c.G, B = c.B, A = 1 }, ColorUseRule = 0 })
            end
            local a = math.min(1, (LIFE - (now - l.t0)) / FADE)
            t:SetRenderOpacity(a)
        end
    end
end

-- feed ------------------------------------------------------------------------------------------------------------

local function push(fmt, kind, key, n)
    local now = os.clock()
    for _, l in ipairs(feed) do
        if now - l.t0 <= LIFE and ((key and l.key == key) or (not key and l.fmt == fmt and now - l.t0 < 3)) then
            if key then l.n = l.n + (n or 1); l.fmt = fmt end
            l.t0 = now
            return
        end
    end
    feed[#feed + 1] = { fmt = fmt, kind = kind or "info", key = key, n = n or 1, t0 = now }
    if #feed > LINES * 2 then table.remove(feed, 1) end
end

-- messages only during a session: post("Rex took %d item{s} from the trunk", "info", "loot.trunk", 2)
function M.post(fmt, kind, key, n)
    if not safety.active() then return end
    push(fmt, kind, key, n)
end

-- the other player's name as this side knows it
function M.other() return hostName or next(names) or "Player" end

-- false until a few seconds into a session: the first full state sync is not news
function M.settled() return sessionSince ~= nil and os.clock() - sessionSince > SETTLE end

function M.state() -- for tests: what the widget should hold
    return { label = "Pacific Together " .. common.MOD_VERSION, status = ui and ui.cache.status or "", lines = #feed }
end

-- status ----------------------------------------------------------------------------------------------------------

local function playerStates(w)
    local out = {}
    local gs = w.GameState
    if valid(gs) then
        local a = gs.PlayerArray
        for i = 1, #a do if valid(a[i]) then out[#out + 1] = a[i] end end
    end
    return out
end

local function realName(ps)
    local n = ps:GetPlayerName():ToString()
    return not n:find("PT|", 1, true) and n ~= "" and n or nil
end

local function status()
    local mode = common.netMode()
    local w = UEHelpers.GetWorld()
    local s = package.loaded["session"]
    local join = s and s.join
    local connected, str = false, ""
    if mode == "listen" and valid(w) then
        local cur, ping = {}, 0
        for _, ps in ipairs(playerStates(w)) do
            local pc = ps:GetOwner()
            if valid(pc) and not pc:IsLocalController() then
                local n = realName(ps)
                if n then cur[n] = true; ping = math.max(ping, ps.Ping * 4) end
            end
        end
        local count = 0
        for n in pairs(cur) do
            count = count + 1
            if not names[n] then
                push(n .. (seen[n] and " rejoined" or " joined"), "good")
                seen[n] = true
            end
        end
        for n in pairs(names) do if not cur[n] then push(n .. " left", "warn") end end
        names = cur
        if count > 0 then connected, str = true, string.format("Host \194\183 %d guest%s \194\183 %d ms", count, count == 1 and "" or "s", ping) end
    elseif mode == "client" or (join and s.wanted()) then
        local mine = valid(w) and UEHelpers.GetPlayerController()
        local host
        if mode == "client" and valid(w) and valid(mine) and valid(mine.PlayerState) then
            for _, ps in ipairs(playerStates(w)) do
                if ps:GetFullName() ~= mine.PlayerState:GetFullName() and realName(ps) then host = ps end
            end
            if host then
                hostName = realName(host)
                connected, str = true, string.format("Guest \194\183 %s \194\183 %d ms", hostName, mine.PlayerState.Ping * 4)
            end
        end
        if not connected then str = "Joining " .. tostring(join or "the host") .. "\226\128\166" end
        if connected and not wasConnected then push("Connected to " .. hostName, "good") end
        if not connected and wasConnected then push("Connection lost, rejoining", "warn") end
    end
    if connected then sessionSince = sessionSince or os.clock() else sessionSince, hostName = nil, nil end
    wasConnected = connected
    set(ui.status, "status", str)
    local v = str == "" and 1 or 3
    if ui.cache.sv ~= v then ui.cache.sv = v; ui.status:SetVisibility(v) end
end

-- A map change frees the widget with its world, and a call on the dead handle crashed the game (AV in a guest's zone load):
-- let go of it before the load and build a fresh one once the new world is up.
local tick, loading = 0, nil
RegisterLoadMapPreHook(function()
    pcall(function() if ui then ui.widget:RemoveFromParent() end end)
    ui, loading = nil, os.clock()
end)
RegisterLoadMapPostHook(function() loading = nil end)

local function update()
    if loading and os.clock() - loading < 30 then return end
    if ui == nil or not valid(ui.widget) or not ui.widget:IsInViewport() then
        ui = build()
        log("PT|overlay built=%s", tostring(ui ~= nil))
        if not ui then return end
        tick = 0
    end
    tick = tick + 1
    if tick % 5 == 1 then status() end
    render()
end

LoopInGameThreadWithDelay(100, function()
    local ok, err = pcall(update)
    if not ok then log("PT|error overlay %s", tostring(err)) end
end)

return M
