local UEHelpers = require("UEHelpers")

local M = {
    MOD_VERSION = "0.0.5",
    PROTOCOL_VERSION = 1,
}

function M.log(fmt, ...) print("[PacificTogether] " .. string.format(fmt, ...) .. "\n") end

function M.netMode()
    local ksl, wco = UEHelpers.GetKismetSystemLibrary(), UEHelpers.GetWorldContextObject()
    if not wco:IsValid() then return "none" end
    if ksl:IsStandalone(wco) then return "standalone" end
    return ksl:IsServer(wco) and "listen" or "client"
end

return M
