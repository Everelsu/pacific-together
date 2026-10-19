-- Q9: the guest crashes on purpose (PTNative_TestCrash) during a session; the host then checks what the crash left in the
-- guest's copy: a new crash folder with our PacificTogether-crash.txt marker, and no CrashReportClient process started.
-- Sentry is never initialised by this build (see docs/spikes/M2-safety.md), so nothing could upload there either.
-- -Mutate crc: the native layer lets CrashReportClient start (test-only switch), so host_no_crashreportclient FAILs.
-- The runner treats the crash as expected for this scenario (tools/run-test.ps1 $CrashExpected).
return function(T)
    local L = require("scenarios.safety_lib")
    if T.ROLE == "client" then
        return {
            T.onMap("RB_MainMenu", 90),
            T.join("client_connected_garage", "RB_Garage", 210, 30),
            { wait = 10 },
            -- the crash ends this side: report done first so the runner does not wait for it
            { run = function() T.log("PT|done side=%s", T.ROLE); PTNative_TestCrash(T.MUTATE == "crc") end },
        }
    end
    local crashes, old, found = nil, {}, nil
    local function dirs()
        local r, p = {}, io.popen('dir /b /ad "' .. crashes .. '" 2>nul')
        for d in p:read("a"):gmatch("[^\r\n]+") do r[#r + 1] = d end
        p:close()
        return r
    end
    local function crcRunning() return L.children("CrashReportClient.exe", crashes:match("^(.*)\\PenDriverPro\\Saved\\Crashes$")) end
    return {
        T.onMap("RB_MainMenu", 90),
        { run = function()
            crashes = L.saved():gsub("\\client1\\", "\\client2\\") .. "\\Crashes"
            for _, d in ipairs(dirs()) do old[d] = true end
            T.log("PT|info guest crash folder %s, %d old", crashes, #dirs())
        end },
        { wait = 3 },
        { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
        { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
        { check = "host_two_pcs", timeout = 240, cond = function() return T.pcs() == 2 end },
        { check = "host_guest_crash_folder", timeout = 120, cond = function()
            for _, d in ipairs(dirs()) do if not old[d] then found = crashes .. "\\" .. d end end
            return found ~= nil
        end },
        { wait = 15 }, -- CrashReportClient starts a moment after the crash folder is written
        { check = "host_crash_marker", timeout = 5, cond = function()
            local m = L.read(found .. "\\PacificTogether-crash.txt")
            T.log("PT|info marker %s: %s", found, tostring(m))
            return m ~= nil and m:find("Pacific Together crash marker", 1, true) ~= nil and m:find("guest=true", 1, true) ~= nil
        end },
        { check = "host_no_crashreportclient", timeout = 1, cond = function() local n = crcRunning(); T.log("PT|info CrashReportClient processes: %s", tostring(n)); return n == 0 end },
    }
end
