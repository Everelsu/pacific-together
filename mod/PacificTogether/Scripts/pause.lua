-- Steam playtest 2026-10-23 #6/#11: with "Pause game while in inventories" on, the host's inventory-type menus paused the whole
-- listen server and the guest froze, then snapped back. While a guest is connected only the Esc menu (instigator "pausemenu")
-- may pause the game; the host tells the guest while it is paused so the guest's overlay shows "Paused by host".
local common = require("common")
local net = require("net")
local safety = require("safety")
local overlay = require("overlay")
local log = common.log

local M = {}
local OFF = os.getenv("PT_MUTATE") == "nopause" -- tests only

-- BP_UIManager:PauseGame is the game's one funnel to SetGamePaused (playermenu, logbook, map, ability and photo mode go through it)
local hooked = false
local function hook()
    -- a Blueprint hook given one callback runs after the body: take the pause back once it ran (PauseStates keeps one entry
    -- per instigator, and the pause menu's own entry keeps its pause)
    hooked = pcall(RegisterHook, "/Game/Systems/Managers/BP_UIManager.BP_UIManager_C:PauseGame", function(self, who, paused)
        if OFF or not paused:get() or not safety.active() then return end
        local name = who:get():ToString()
        -- the Esc menu keeps its pause; so does the test bot's own pause (safety scenarios check what a real pause does)
        if name:lower() == "pausemenu" or (name == "PacificTogetherTest" and os.getenv("PT_STATUS")) then return end
        self:get():PauseGame(who:get(), false, {})
        log("PT|pause refused %s", name)
    end)
end
hook() -- the class loads with the first map: retried until it exists

net.on("g.pause.s", function(_, data) if not OFF then overlay.hostPaused(data == "1") end end)

local was, sentAt = false, 0
LoopInGameThreadWithDelay(500, function()
    if not hooked then hook() end
    if OFF or common.netMode() ~= "listen" then return end
    local w = require("UEHelpers").GetWorld()
    local now = w:IsValid() and safety.active() and StaticFindObject("/Script/Engine.Default__GameplayStatics"):IsGamePaused(w)
    if now ~= was or (now and os.clock() - sentAt >= 1) then
        was, sentAt = now, os.clock()
        net.toGuests("g.pause.s", now and "1" or "0")
    end
end)

return M
