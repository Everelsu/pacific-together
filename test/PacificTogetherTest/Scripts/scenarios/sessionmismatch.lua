-- S4 refusal with the real host mod. The guest has no PT_JOIN, so its own mod stays out; the test plays a guest that
-- (1) sends a hello with a wrong mod version, (2) sends no hello at all. The host must refuse both with a reason and
-- never give them a character. Mutations: match (the hello carries the right versions, so refusal 1 must FAIL), hello2
-- (the second guest sends a valid hello, so refusal 2 must FAIL).
return function(T)
    local L = require("scenarios.sessionlib")(T)

    if T.ROLE == "host" then
        local spawned = false
        local function refused(id)
            return { check = id, timeout = 60, cond = function()
                spawned = spawned or L.guestChar() ~= nil
                assert(not spawned, "the refused guest got a character")
                return T.pcs() == 1
            end }
        end
        return {
            T.onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE) end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            { check = "host_saw_bad_guest", timeout = 240, cond = function() return T.pcs() == 2 end },
            refused("host_refused_bad_hello"),
            { check = "host_saw_silent_guest", timeout = 240, cond = function() return T.pcs() == 2 end },
            refused("host_refused_no_hello"),
            { wait = 10 },
        }
    end

    local reason
    RegisterHook("/Script/Engine.PlayerController:ClientWasKicked", function(self, r) reason = r:get():ToString(); T.log("PT|info kicked: %s", reason) end)
    local function send(s) T.log("PT|info sending %s", s); T.localPC():ServerChangeName(s) end
    local function badHello() send(T.hello(T.MUTATE ~= "match" and "0.0.0-mismatch" or nil)) end
    local function connected() return T.netMode() == "client" and T.map() == "RB_Garage" and T.localPC() ~= nil end
    local function kicked(id, want, timeout)
        return { check = id, timeout = timeout or 60, cond = function()
            assert(T.cls(T.myPawn()) ~= T.CHAR, "possessed a character")
            return T.map() == "RB_MainMenu" and reason ~= nil and reason:find(want, 1, true) ~= nil
        end }
    end
    return {
        T.onMap("RB_MainMenu", 90),
        T.join("client_connected_bad", "RB_Garage", 210, 30),
        { check = "client_controller_ready", timeout = 30, cond = connected },
        { wait = 2 },
        { run = badHello },
        kicked("client_refused_bad_hello", "mod mismatch"),
        { run = function() T.log("PT|info reason 1: %s", tostring(reason)); reason = nil end },
        { wait = 5 },
        T.join("client_connected_silent", "RB_Garage", 120, 60),
        { wait = 2 },
        { run = function() if T.MUTATE == "hello2" then send(T.hello()) end end },
        kicked("client_refused_no_hello", "no handshake", 130), -- the host waits 90 s (session.lua HELLO_WAIT_MS)
        { run = function() T.log("PT|info reason 2: %s", tostring(reason)) end },
    }
end
