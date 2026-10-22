-- pt2-story (G3): story progression for the guest. Fixture `garage`, the guest joins by itself.
--   1) the host finishes missions (the game's own ForceComplete / StartObjective, the story script cascades): the guest's quest manager
--      shows the same active objectives AND holds the same finished missions/objectives (the journal's history reads those lists);
--   2) what the story granted reaches the guest: logbook entries, the finished-story whiteboard flags, garage upgrade flags;
--   3) a story task only the guest can do (it holds the item: "get the Doctor Gobbler") counts on the host.
-- Run: tools/run-test.ps1 -Scenario storyprog -Fixture garage -Headless
-- Mutation nostoryprog: no journal history, no whiteboard finish flags, no guest-done task routing: the checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local slow = (T.MUTATE == "nostoryprog") and 0.2 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end
    local P = "/Game/Gameplay/Quests/"

    local function qm() return T.first("BP_QuestManager_C") end
    local function strip(o) return (o:GetFullName():gsub("^%S+ ", "")) end
    local function load(p)
        local o = StaticFindObject(p)
        if not (o and o:IsValid()) then pcall(LoadAsset, p); o = StaticFindObject(p) end
        return o
    end
    -- what story progress looks like on one side, as lines "kind:value"
    local function state()
        local q, m = qm(), T.first("BP_ProgressionManager_C")
        local R = {}
        for i = 1, q.CompletedMissions:GetArrayNum() do R[#R + 1] = "cm:" .. strip(q.CompletedMissions[i]) end
        for i = 1, q.CompletedObjectives:GetArrayNum() do R[#R + 1] = "co:" .. strip(q.CompletedObjectives[i]) end
        for i = 1, q.ActiveObjectives:GetArrayNum() do
            local s = q.ActiveObjectives[i]
            local ms = s.ActiveMissionState
            R[#R + 1] = "act:" .. strip(s.Objective) .. "|" .. ((ms and ms:IsValid() and ms.Data:IsValid()) and strip(ms.Data) or "-")
        end
        m.GlobalWhiteboard.Entries:ForEach(function(k, v)
            local tag = k:get().TagName:ToString()
            if tag:find("^WB%.Missions%.") and tag:find("%.Completed$") or tag:find("^WB%.Quests%.") and tag:find("%.Completed$") then R[#R + 1] = "ct:" .. tag end
            if tag:find("^WB%.GarageUpgrades%.") or tag:find("^WB%.Scanning%.Garage%.") then R[#R + 1] = "up:" .. tag .. "=" .. string.format("%.2f", v:get()) end
        end)
        local lb = m.LogBook
        for i = 1, #lb.Entries do
            local o = lb.Entries[i].DataObject
            if o:IsValid() then R[#R + 1] = "lb:" .. strip(o) end
        end
        table.sort(R)
        return R
    end
    local function lines(s) local t = {} for l in s:gmatch("[^\n]+") do t[l] = true end return t end
    -- the host's lines of one kind that the guest lacks (or, for "act", differs on)
    local function missing(host, mine, kinds, both)
        local h, g, out = lines(host), lines(table.concat(mine, "\n")), {}
        for l in pairs(h) do
            local k = l:match("^(%a+):")
            if kinds[k] and not g[l] then out[#out + 1] = l end
        end
        if both then for l in pairs(g) do local k = l:match("^(%a+):") if both[k] and not h[l] then out[#out + 1] = "extra " .. l end end end
        table.sort(out)
        return out
    end
    local FIRST = { cm = true, co = true, ct = true, up = true, lb = true }

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        local function guestPC() return L.remotePCs()[1] end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ run = function()
            LoopInGameThreadWithDelay(1000, function()
                pcall(function() PTNative_MsgToGuest(guestPC():GetAddress(), "t.state", table.concat(state(), "\n")) end)
            end)
        end })
        add({ wait = 20 })
        -- 1) the story steps on: the intro mission is finished, the car-fix objective starts (what the story script does after the
        -- wake-up) and its first mission is replaced by C2; the fixture's garage satisfies the tasks and the story cascades on by itself
        add({ run = function()
            local q = qm()
            q.ActiveObjectives[1].ActiveMissionState:ForceComplete(true)
        end })
        add({ wait = 5 })
        add({ run = function()
            local q = qm()
            q:StartObjective(load(P .. "Q00/QD_Q00_FixCar_Objective.QD_Q00_FixCar_Objective"), true, false)
            local c2 = load(P .. "Q00/QD_Q00_Mission_C2.QD_Q00_Mission_C2")
            for i = 1, q.ActiveObjectives:GetArrayNum() do
                local s = q.ActiveObjectives[i]
                if strip(s.Objective):find("FixCar") then s:StartNextMission(c2) end
            end
        end })
        add({ wait = 12 })
        add({ check = "host_story_moved_on", timeout = 30, cond = function()
            local r = table.concat(state(), "\n")
            return r:find("cm:" .. P .. "Q00_Intro/QD_Q00_Intro_Mission_A", 1, true) and r:find("cm:" .. P .. "Q00/QD_Q00_Mission_C3", 1, true) ~= nil
        end })
        add({ run = function() T.log("PT|info host story: %s", table.concat(state(), " ; "):sub(1, 1500)) end })
        add({ wait = 25 })
        -- 3) a task for the guest: "get the Doctor Gobbler" (HasItem_PlayerInventory); the host's bag has none
        local function gobTask()
            local q = qm()
            for i = 1, q.ActiveObjectives:GetArrayNum() do
                local s = q.ActiveObjectives[i]
                if strip(s.Objective):find("InstallDoctorGobbler") then return s.ActiveMissionState, s.ActiveMissionState.TaskStates end
            end
        end
        add({ run = function() qm():StartObjective(load(P .. "Generic/QD_Generic_InstallDoctorGobbler.QD_Generic_InstallDoctorGobbler"), true, true) end })
        add({ check = "host_gobbler_task_open", timeout = 20, cond = function()
            local ms, ts = gobTask()
            return ms ~= nil and ts:GetArrayNum() >= 1 and not ts[1].bCompleted
        end })
        add({ wait = 20 })
        add({ run = function() PTNative_MsgToGuest(guestPC():GetAddress(), "t.give", "1") end })
        add({ check = "host_task_done_by_guest", timeout = to(60), cond = function()
            local ms, ts = gobTask()
            return ms ~= nil and ts[1].bCompleted
        end })
        add({ check = "host_guest_alive", timeout = 30, cond = L.holds(8, function() return T.netMode() == "listen" and T.pcs() == 2 end) })
        add({ check = "host_guest_finished", timeout = 700 * slow, cond = function()
            while true do
                local kind = PTNative_MsgPoll("t.")
                if not kind then return false end
                if kind == "t.done" then return true end
            end
        end })
        return steps
    end

    -- guest
    local host, give
    local function drain()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            if kind == "t.state" then host = data elseif kind == "t.give" then give = true end
        end
    end
    local stateAtGive
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in", timeout = 400, cond = function() return T.netMode() == "client" and T.cls(T.myPawn()) == T.CHAR end },
        -- 1) the finished missions and objectives are in the guest's lists, the active ones match
        { check = "guest_journal_history_matches_host", timeout = to(150), cond = function()
            drain()
            if not host or not host:find("Mission_C3", 1, true) then return false end
            local miss = missing(host, state(), { cm = true, co = true })
            if #miss > 0 then T.log("PT|info guest lacks %s", table.concat(miss, " ; "):sub(1, 600)) end
            return #miss == 0
        end },
        { check = "guest_active_story_matches_host", timeout = to(60), cond = function()
            drain()
            local miss = missing(host, state(), { act = true }, { act = true })
            if #miss > 0 then T.log("PT|info guest active differs %s", table.concat(miss, " ; "):sub(1, 600)) end
            return #miss == 0
        end },
        -- 2) the grants of the finished steps
        { check = "guest_has_story_unlocks", timeout = to(60), cond = function()
            drain()
            local miss = missing(host, state(), { ct = true, up = true, lb = true })
            if #miss > 0 then T.log("PT|info guest lacks %s", table.concat(miss, " ; "):sub(1, 600)) end
            return #miss == 0
        end },
        -- 3) the guest gets the item the task asks for
        { check = "guest_sees_gobbler_task", timeout = to(120), cond = function()
            drain()
            local q = qm()
            for i = 1, q.ActiveObjectives:GetArrayNum() do
                local s = q.ActiveObjectives[i]
                if strip(s.Objective):find("InstallDoctorGobbler") and s.ActiveMissionState:IsValid() then return true end
            end
            return false
        end },
        { check = "guest_told_to_get_gobbler", timeout = 120, cond = function() drain(); return give == true end },
        { run = function()
            local q = qm()
            local arch
            for i = 1, q.ActiveObjectives:GetArrayNum() do
                local s = q.ActiveObjectives[i]
                if strip(s.Objective):find("InstallDoctorGobbler") then arch = s.ActiveMissionState.Tasks[1].Archetype end
            end
            local lib = StaticFindObject("/Script/PenDriverInventory.Default__InventoryBlueprintLibrary")
            local im = T.first("BP_InventoryManager_C")
            im.Inventory_Player:AddItem(lib:CreateItemInstance(T.world(), arch, 0), true)
        end },
        { check = "guest_alive_after_story", timeout = to(90), cond = L.holds(25, function() drain(); return T.netMode() == "client" and T.myPawn() ~= nil end) },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
