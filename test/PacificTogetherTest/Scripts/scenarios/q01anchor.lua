-- Q01 Mission_C "Take the Anchor" (BPMT_HasItem_HandSlot, Stable L) done by the guest counts on the host (story.lua reportTasks).
-- Friend's Steam play 2026-10-25: the guest pulled the anchors, the host's task never completed and Q01 restarted after every run
-- (a missing CheckCar/CheckZETI read as a truthy TrivialObject, so every hand/backpack task was taken for a trunk check).
-- Run: tools/run-test.ps1 -Scenario q01anchor -Fixture pt8-q01 -Headless      Mutation nostoryprog: no report (check FAILS).
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local ANCHOR = "/Game/Gameplay/Inventory/Items/Resources/Anchor/AnchorBlue/IA_Resource_Anchor_Stable_L.IA_Resource_Anchor_Stable_L"
    local got = {}
    local function g(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind]
    end
    -- Mission_C's task 3 (UniqueName GrabbedAnchor) on this side
    local function grabbed()
        local q = T.first("BP_QuestManager_C")
        local a = q and q.ActiveObjectives
        for i = 1, a and a:GetArrayNum() or 0 do
            local ms = a[i].ActiveMissionState
            if ms:IsValid() and ms.Data:GetFName():ToString() == "QD_Q01_Mission_C" then
                for j = 1, ms.Tasks:GetArrayNum() do
                    if ms.Tasks[j].UniqueName:ToString() == "GrabbedAnchor" then return ms.TaskStates[j].bCompleted end
                end
            end
        end
    end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture("pt8-q01")) do add(s) end
        add({ check = "host_on_q01_mission_c", timeout = 30, cond = function() return grabbed() == false end })
        add({ check = "host_guest_in_garage", timeout = 240, cond = function() return L.guestChar() ~= nil end })
        add({ wait = 5 })
        add({ check = "host_task_open_before", timeout = 5, cond = function() return grabbed() == false end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.hold", "1") end })
        add({ check = "guest_holds_anchor", timeout = 60, cond = function() return g("t.held") == "1" end })
        add({ check = "host_task_done_by_guest", timeout = 30, cond = function() return grabbed() == true end })
        add({ run = function() PTNative_MsgToGuest(L.remotePCs()[1]:GetAddress(), "t.done", "1") end })
        add({ wait = 3 })
        return steps
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_garage", timeout = 400, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" and T.cls(T.myPawn()) == T.CHAR end },
        { check = "guest_told_hold", timeout = 300, cond = function() return g("t.hold") ~= nil end },
        { run = function()
            local m = T.first("BP_InventoryManager_C")
            if not StaticFindObject(ANCHOR):IsValid() then LoadAsset(ANCHOR) end
            m.Inventory_PlayerHand:GetSlot(0):RemoveAllItems({})
            m:GiveItemToPlayer(StaticFindObject(ANCHOR))
            for i = 0, m.Inventory_Player:GetNumSlots() - 1 do
                local s = m.Inventory_Player:GetSlot(i)
                if s:GetNumItems() > 0 and s:GetCurrentArchetype():GetFName():ToString() == "IA_Resource_Anchor_Stable_L" then
                    s:TransferStackIntoContainer(m.Inventory_PlayerHand, {}); break
                end
            end
        end },
        { check = "guest_task_done_locally", timeout = 20, cond = function()
            local ok = grabbed() == true
            if ok then PTNative_MsgToHost(T.localPC():GetAddress(), "t.held", "1") end
            return ok
        end },
        { check = "guest_reports", timeout = 300, cond = function() return g("t.done") ~= nil end },
    }
end
