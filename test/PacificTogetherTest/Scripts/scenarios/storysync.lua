-- M5 story (G3, G4): the guest experiences the host's story. Fixture `garage` (the intro mission Q00 is active), the guest joins by itself.
--   quest state: the guest's quest manager holds the host's objectives (objective, mission, completed tasks), also after the host's story steps on;
--   dialogue: a voice line the host plays is played on the guest too (same DialogueSequence);
--   the guest starts nothing of its own (its own StartMission stays nulled) and stays connected and controllable.
-- Run: tools/run-test.ps1 -Scenario storysync -Fixture garage -Headless
-- Mutation nostory: story.lua mirrors nothing (the guest stays a bystander): the checks FAIL.
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local SEQ = "/Game/Gameplay/VO/Expeditions/IntroPt2/DS_expIntro2_S01_Success_ThatWorkedAnd.DS_expIntro2_S01_Success_ThatWorkedAnd"
    local slow = (T.MUTATE == "nostory") and 0.2 or 1
    local function to(s) return math.max(15, math.floor(s * slow)) end

    local function qm() return T.first("BP_QuestManager_C") end
    local function strip(o) return (o:GetFullName():gsub("^%S+ ", "")) end
    local function flat(s) return (s:gsub("\n", " ; ")) end
    -- what the quest manager shows: one row per active objective, sorted
    local function read()
        local rows, a = {}, qm().ActiveObjectives
        for i = 1, a:GetArrayNum() do
            local s = a[i]
            local ms = s.ActiveMissionState
            local ts, mask = ms.TaskStates, {}
            for j = 1, ts:GetArrayNum() do mask[j] = ts[j].bCompleted and "1" or "0" end
            rows[#rows + 1] = string.format("%s|%s|%s", strip(s.Objective), (ms and ms:IsValid() and ms.Data:IsValid()) and strip(ms.Data) or "-", table.concat(mask))
        end
        table.sort(rows)
        return table.concat(rows, "\n")
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("garage")) do add(s) end
        add({ check = "host_listen", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        local start
        add({ run = function()
            start = read()
            T.log("PT|info host story: %s", flat(start))
            LoopInGameThreadWithDelay(1000, function() pcall(function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.quest", read()) end) end)
        end })
        add({ check = "host_has_story", timeout = 10, cond = function() return start ~= "" end })
        add({ wait = 25 })
        -- the host's story steps on
        add({ run = function() local ms = qm().ActiveObjectives[1].ActiveMissionState; ms:ForceCompleteTask(ms.Tasks[1]) end })
        add({ wait = 6 })
        add({ run = function() T.log("PT|info host story after advance: %s", flat(read())) end })
        add({ check = "host_story_changed", timeout = 10, cond = function() return read() ~= start end })
        add({ wait = 25 })
        -- a voice line
        add({ run = function()
            local d, s = T.first("BP_DialogueManager_C"), StaticFindObject(SEQ)
            d:PlaySequence(s, 3, nil)
            PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.say", SEQ:match("[^.]+$"))
        end })
        add({ check = "host_guest_alive", timeout = 30, cond = L.holds(10, function() return T.netMode() == "listen" and T.pcs() == 2 end) })
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
    local host, say
    local saw = {}
    local function drain()
        while true do
            local kind, data = PTNative_MsgPoll("t.")
            if not kind then return end
            if kind == "t.quest" then host = data elseif kind == "t.say" then say = data end
        end
    end
    local mission
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in", timeout = 400, cond = function() return T.netMode() == "client" and T.cls(T.myPawn()) == T.CHAR end },
        { run = function()
            LoopInGameThreadWithDelay(100, function()
                pcall(function()
                    local d = T.first("BP_DialogueManager_C")
                    local s = d and d.CurrentlyPlayingSequence
                    if s and s:IsValid() then saw[s:GetFName():ToString()] = true end
                end)
            end)
        end },
        { check = "guest_got_host_story", timeout = to(120), cond = function() drain(); return host ~= nil and host ~= "" end },
        { check = "guest_quest_matches_host", timeout = to(60), cond = function() drain(); local r = read(); T.log("PT|info guest story: %s | host: %s", flat(r), flat(host)); return r == host end },
        -- the host's story steps on: the guest follows
        { run = function() local h = host; host = nil; T.startQuest = h end },
        { check = "guest_follows_host_step", timeout = to(120), cond = function()
            drain()
            if not host or host == T.startQuest then return false end
            local r = read()
            T.log("PT|info guest story: %s | host: %s", flat(r), flat(host))
            return r == host
        end },
        { check = "guest_played_host_voice_line", timeout = to(90), cond = function() drain(); return say ~= nil and saw[say] == true end },
        -- the guest's own StartMission stays nulled (unguarded it crashes the guest)
        { run = function()
            mission = StaticFindObject("/Game/Gameplay/Quests/Q00_Intro/QD_Q00_Intro_Mission_A.QD_Q00_Intro_Mission_A")
            if mission and mission:IsValid() and T.MUTATE ~= "nostory" then pcall(function() qm():StartMission(mission, true) end) end
        end },
        { check = "guest_alive_after_story", timeout = to(60), cond = L.holds(12, function() return T.netMode() == "client" and T.myPawn() ~= nil end) },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.done", "1") end },
        { wait = 3 },
    }
end
