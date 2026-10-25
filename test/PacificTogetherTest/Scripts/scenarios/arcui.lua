-- Immersion lane 2026-10-25: the ARC device sits behind the seats in co-op (D12), out of view, so the overlay shows its energy as
-- "ARC <collected> / <required>" (overlay.lua, TextBlock PTArc) on both sides in run maps during a session. Gateway fixture: the
-- host's ARC holds 7.0 / 1.0; the guest's copy is written by guestact.lua's g.act.arc mirror, so both lines must read the same.
-- Run: tools/run-test.ps1 -Scenario arcui -Fixture gateway -Headless     Mutation: nooverlay (no widget: both sides fail)
return function(T)
    local L = require("scenarios.sessionlib")(T)
    local got = {}
    local function has(kind)
        while true do
            local k, d = PTNative_MsgPoll("t.")
            if not k then break end
            got[k] = d
        end
        return got[kind] ~= nil
    end
    local function arcLine()
        for _, t in ipairs(FindAllOf("TextBlock") or {}) do
            if t:IsValid() and t:GetFName():ToString() == "PTArc" and t:GetVisibility() ~= 1 then return t:GetText():ToString() end
        end
        return ""
    end
    local function shown() local s = arcLine(); return s:match("^ARC [%d.]+ / [%d.]+$") ~= nil end

    if T.ROLE == "host" then
        local steps = {}
        local function add(s) steps[#steps + 1] = s end
        for _, s in ipairs(T.loadFixture((os.getenv("PT_FIXTURE") or ""):match("[^,]+") or "gateway")) do add(s) end
        add({ check = "host_listen_zone", timeout = 60, cond = function() return T.netMode() == "listen" and T.listening() end })
        add({ check = "host_guest_in_zone", timeout = 300, cond = function() return L.guestChar() ~= nil end })
        add({ check = "host_arc_line_shown", timeout = 30, cond = function() T.log("PT|info host arc line '%s'", arcLine()); return shown() end })
        add({ check = "host_guest_arc_line_equal", timeout = 60, cond = function()
            if not has("t.arc") then return false end
            T.log("PT|info host '%s' guest '%s'", arcLine(), got["t.arc"])
            return got["t.arc"] == arcLine() and shown()
        end })
        add({ wait = 3 })
        return steps
    end

    return {
        T.onMap("RB_MainMenu", 90),
        { check = "client_in_zone", timeout = 400, cond = function() return T.netMode() == "client" and T.map() ~= "RB_MainMenu" and T.cls(T.myPawn()) == T.CHAR end },
        { wait = 8 }, -- the host's g.act.arc mirror writes the guest's charge
        { check = "client_arc_line_shown", timeout = 30, cond = function() T.log("PT|info guest arc line '%s'", arcLine()); return shown() end },
        { run = function() PTNative_MsgToHost(T.localPC():GetAddress(), "t.arc", arcLine()) end },
        { wait = 5 },
    }
end
