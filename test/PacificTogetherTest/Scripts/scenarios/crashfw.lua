-- D23 / Q9 proof scenario: safety_crash (the guest crashes on purpose, the host checks the crash folder, our marker and that no
-- CrashReportClient process ran) plus a check that CrashReportClient.exe really sits in the guest's copy, so "no
-- CrashReportClient process" is not true only because the file is missing. Run it through tools/q9-firewall.ps1 (elevated): that
-- script puts the exe into the guest copy, blocks outbound traffic for the copies' exes with a firewall rule and audits blocked
-- connections. Never run it by hand without that rule: with the exe present, a failed refusal would upload the crash report.
return function(T)
    local steps = require("scenarios.safety_crash")(T)
    if T.ROLE ~= "host" then return steps end
    local L = require("scenarios.safety_lib")
    table.insert(steps, 1, { check = "host_crc_exe_in_guest_copy", timeout = 1, cond = function()
        local exe = L.saved():gsub("\\client1\\", "\\client2\\"):gsub("\\PenDriverPro\\Saved$", "\\Engine\\Binaries\\Win64\\CrashReportClient.exe")
        local f = io.open(exe, "rb")
        if f then f:close() end
        return f ~= nil or os.getenv("PT_Q9") ~= "1"
    end })
    return steps
end
