-- Message channel (native msg.cpp) in a live two-player session: the guest sends N ordered messages and one big one
-- (split into chunks) to the host, the host checks order, sender and bytes and echoes everything back, the guest checks
-- the echoes. Mutation: nocapture (the native layer stops catching chunks: nothing arrives).
local N, BIG = 50, 20000

return function(T)
    local L = require("scenarios.sessionlib")(T)

    -- every byte value except NUL, so the round trip is byte-exact
    local function big()
        local t = {}
        for i = 0, BIG - 1 do t[#t + 1] = string.char(1 + (i * 7) % 255) end
        return table.concat(t)
    end
    local BIGDATA = big()

    local got = {}
    local function drain()
        while true do
            local kind, data, from = PTNative_MsgPoll("t.")
            if not kind then return end
            got[#got + 1] = { kind = kind, data = data, from = from }
        end
    end
    local function ordered(kind)
        local seen = 0
        for _, m in ipairs(got) do
            if m.kind == kind then
                if tonumber(m.data) ~= seen + 1 then return false, seen end
                seen = seen + 1
            end
        end
        return seen == N, seen
    end
    local function bigOk(kind)
        for _, m in ipairs(got) do if m.kind == kind then return m.data == BIGDATA, #m.data end end
        return false, 0
    end

    if T.ROLE == "host" then
        local guest
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.listening() and T.map() == "RB_Garage" end },
            { check = "host_guest_joined", timeout = 240, cond = function() return T.pcs() == 2 and #L.remotePCs() == 1 end },
            { run = function() guest = L.remotePCs()[1] end },
            { check = "host_got_ordered", timeout = 60, cond = function() drain(); return (ordered("t.seq")) end },
            { check = "host_got_big", timeout = 30, cond = function() drain(); return (bigOk("t.big")) end },
            { check = "host_sender_is_guest", timeout = 5, cond = function()
                for _, m in ipairs(got) do if m.from ~= guest:GetAddress() then return false end end
                return #got > 0
            end },
            { run = function()
                for i = 1, N do PTNative_MsgToGuest(guest:GetAddress(), "t.echo", tostring(i)) end
                T.log("PT|info echo big sent=%s", tostring(PTNative_MsgToGuest(guest:GetAddress(), "t.bigecho", BIGDATA)))
            end },
            { check = "host_rejects_oversize", timeout = 5, cond = function() return PTNative_MsgToGuest(guest:GetAddress(), "t.x", string.rep("x", 40000)) == false end },
            { run = function() T.log("PT|info stats %s", PTNative_MsgStats()) end },
            { wait = 15 },
        }
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_joined_garage", timeout = 240, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end },
        { check = "client_possessed", timeout = 60, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { run = function()
            local pc = T.localPC():GetAddress()
            for i = 1, N do PTNative_MsgToHost(pc, "t.seq", tostring(i)) end
            T.log("PT|info big sent=%s", tostring(PTNative_MsgToHost(pc, "t.big", BIGDATA)))
        end },
        { check = "client_got_echo_ordered", timeout = 90, cond = function() drain(); return (ordered("t.echo")) end },
        { check = "client_got_big_echo", timeout = 30, cond = function() drain(); return (bigOk("t.bigecho")) end },
        { run = function() T.log("PT|info stats %s", PTNative_MsgStats()) end },
        { wait = 5 },
    }
end
