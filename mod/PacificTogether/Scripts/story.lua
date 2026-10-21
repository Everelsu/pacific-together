-- The guest experiences the host's story (G3, G4). The host owns the story; the guest's quest manager only shows it.
--   quest state   twice a second the host sends its active objectives (objective asset, active mission asset, completed-task mask);
--                 the guest starts/stops the same ones through its own quest manager so its HUD and journal show them. Only this
--                 module may start things on the guest ("applying"): the game's own StartMission/StartObjective/AdvanceObjective
--                 calls on a guest stay nulled, so the guest cannot start or branch a story of its own.
--   dialogue      the host's dialogue manager sequence (radio transmissions, voice lines) is played on the guest the same way
--                 (subtitles and audio are the game's own, played locally).
--   cutscenes     the host's playing level sequence is played on the guest (if the guest has it).
-- Everything is inert outside a session (Q7).
local common = require("common")
local net = require("net")
local safety = require("safety")
local log = common.log

local M = { enabled = os.getenv("PT_MUTATE") ~= "nostory" } -- the test mutation switches the mirror off (the guest stays a bystander)

local function live(o) return o and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function try(what, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then log("PT|error story %s %s", what, tostring(err)) end
    return ok
end
local function path(o) return (o:GetFullName():gsub("^%S+ ", "")) end
local function load(p)
    local o = StaticFindObject(p)
    if o and o:IsValid() then return o end
    pcall(LoadAsset, p)
    o = StaticFindObject(p)
    if o and o:IsValid() then return o end
end
local function quests() local q = FindFirstOf("BP_QuestManager_C") return live(q) and q or nil end
local function dialogue() local d = FindFirstOf("BP_DialogueManager_C") return live(d) and d or nil end

local applying = false -- true only while this module starts something on the guest

-- G3: the guest's own game starts nothing. A pre-hook cannot cancel a call, so the mission is nulled (unguarded, StartMission on a guest crashes).
for _, fn in ipairs({ "StartMission", "StartObjective", "AdvanceObjective" }) do
    local ok, err = pcall(RegisterHook, "/Script/PenDriverPro.BaseMissionManager:" .. fn, function(self, a)
        if not applying and safety.guest() then pcall(function() a:set(nil) end) end
    end)
    if not ok then log("PT|error story hook %s %s", fn, tostring(err)) end
end

-- ---------------------------------------------------------------- host

local lastQuest, lastSent = "", 0

local function questState()
    local q = quests()
    if not q then return "" end
    local L = {}
    local a = q.ActiveObjectives
    for i = 1, a:GetArrayNum() do
        local s = a[i]
        local ms = s.ActiveMissionState
        if live(s.Objective) and live(ms) and live(ms.Data) then
            local ts, mask = ms.TaskStates, {}
            for j = 1, ts:GetArrayNum() do mask[j] = ts[j].bCompleted and "1" or "0" end
            L[#L + 1] = string.format("o\t%s\t%s\t%s", path(s.Objective), path(ms.Data), table.concat(mask))
        end
    end
    return table.concat(L, "\n")
end

local lastSay
local function hostTick()
    local s = questState()
    if s ~= lastQuest or os.clock() - lastSent > 3 then -- again every 3 s for a late guest
        lastQuest, lastSent = s, os.clock()
        net.toGuests("g.story.quest", s)
    end
end

local function dialogueTick()
    local d = dialogue()
    local seq = d and d.CurrentlyPlayingSequence
    if not live(seq) then lastSay = nil return end
    if seq == lastSay then return end
    lastSay = seq
    net.toGuests("g.story.say", string.format("%s\t%d", path(seq), seq.Priority))
end

local lastSeq = {}
local function cutsceneTick()
    for _, a in ipairs(FindAllOf("LevelSequenceActor") or {}) do
        if live(a) and not a:GetFullName():find("/Engine/Transient", 1, true) then
            local pl = a:GetSequencePlayer()
            local playing = live(pl) and pl:IsPlaying()
            local seq = playing and a:GetSequence()
            local n = a:GetFName():ToString()
            if playing and live(seq) and not lastSeq[n] then
                net.toGuests("g.story.cut", string.format("%s	%s", n, path(seq)))
                lastSeq[n] = true
            elseif not playing then lastSeq[n] = nil end
        end
    end
end

-- story props the host's story spawns (narrative resources): replicated like world.lua's hazards; the guest drops its own copies
local PROPS = { "BP_Resource_Narrative_Q01_RadioBitsGrabbable_C" }
local function propsTick()
    for _, class in ipairs(PROPS) do
        for _, o in ipairs(FindAllOf(class) or {}) do
            if live(o) and o.RemoteRole == 0 and o:HasAuthority() then
                o:SetReplicates(true)
                o.bAlwaysRelevant = true
                o:ForceNetUpdate()
            end
        end
    end
end
local function guestProps()
    for _, class in ipairs(PROPS) do
        for _, o in ipairs(FindAllOf(class) or {}) do
            if live(o) and o.Role ~= 1 then o:K2_DestroyActor() end
        end
    end
end

-- ---------------------------------------------------------------- guest

local function activeOn(q, objPath)
    local a = q.ActiveObjectives
    for i = 1, a:GetArrayNum() do
        local s = a[i]
        if live(s.Objective) and path(s.Objective) == objPath then return s end
    end
end

local function applyQuest(data)
    local q = quests()
    if not q then return end
    local want = {}
    for line in data:gmatch("[^\n]+") do
        local _, obj, mis, mask = line:match("^(o)\t([^\t]+)\t([^\t]+)\t([01]*)$")
        if obj then
            want[obj] = true
            local st = activeOn(q, obj)
            local o, m = load(obj), load(mis)
            if o and m then
                applying = true
                local ok, err = pcall(function()
                    if not st then
                        q:StartObjective(o, true, false)
                        st = activeOn(q, obj)
                        log("PT|story guest start objective %s mission %s", obj, mis)
                    end
                    local cur = st and st.ActiveMissionState
                    if st and not (live(cur) and live(cur.Data) and path(cur.Data) == mis) then
                        st:StartNextMission(m)
                        log("PT|story guest mission -> %s", mis)
                    end
                    local ms = st and st.ActiveMissionState
                    if ms and live(ms) then -- the tasks the host completed (tasks run in parallel: a mask, not an index)
                        local ts = ms.TaskStates
                        for i = 1, math.min(#mask, ts:GetArrayNum()) do
                            if mask:sub(i, i) == "1" and not ts[i].bCompleted then pcall(ms.ForceCompleteTask, ms, ms.Tasks[i]) end
                        end
                    end
                end)
                applying = false
                if not ok then log("PT|error story apply %s %s", obj, tostring(err)) end
            end
        end
    end
    -- objectives the host no longer has active
    local drop = {}
    local a = q.ActiveObjectives
    for i = 1, a:GetArrayNum() do
        local s = a[i]
        if live(s.Objective) and not want[path(s.Objective)] then drop[#drop + 1] = s.Objective end
    end
    for _, o in ipairs(drop) do
        applying = true
        pcall(q.StopObjective, q, o, true)
        applying = false
        log("PT|story guest stop objective %s", path(o))
    end
end

net.on("g.story.quest", function(_, data)
    if not M.enabled or not safety.guest() then return end
    try("quest", applyQuest, data)
end)

net.on("g.story.say", function(_, data)
    if not M.enabled or not safety.guest() then return end
    try("say", function()
        local p, pr = data:match("^([^\t]+)\t(%d+)$")
        local d, seq = dialogue(), p and load(p)
        if not (d and seq) then return end
        if d.CurrentlyPlayingSequence == seq then return end
        applying = true
        d:PlaySequence(seq, tonumber(pr), nil)
        applying = false
        log("PT|story guest dialogue %s", p)
    end)
end)

-- G3 cutscenes: the guest plays the host's level sequence when it has the same one placed; its own game triggers none
net.on("g.story.cut", function(_, data)
    if not M.enabled or not safety.guest() then return end
    try("cut", function()
        local n, p = data:match("^([^	]+)	([^	]+)$")
        for _, a in ipairs(FindAllOf("LevelSequenceActor") or {}) do
            if live(a) and a:GetFName():ToString() == n then
                local pl = a:GetSequencePlayer()
                if live(pl) and not pl:IsPlaying() then pl:Play() log("PT|story guest cutscene %s %s", n, p) end
                return
            end
        end
        log("PT|story guest has no cutscene %s", n)
    end)
end)

LoopInGameThreadWithDelay(500, function()
    if not M.enabled or not safety.active() then return end
    if safety.guest() then try("props", guestProps) return end
    try("host", hostTick)
    try("cut", cutsceneTick)
    try("props", propsTick)
end)
LoopInGameThreadWithDelay(200, function()
    if not M.enabled or not safety.active() or safety.guest() then return end
    try("say", dialogueTick)
end)

return M
