-- D16 probe (docs/research/crash-reports.md), one game. Reads the Sentry plugin's settings as the game loaded them
-- (DefaultEngine.ini plus any Saved/Config override) and finds its subsystem. Values only, the DSN is never printed.
-- PT_SENTRY_EXPECT=off: an override in Saved/Config sets InitAutomatically=False and an empty DsnUrl; the check
-- fails without it, which is the mutation (run once with and once without the override).
return function(T)
    local expectOff = os.getenv("PT_SENTRY_EXPECT") == "off"
    local function settings()
        local s = StaticFindObject("/Script/Sentry.Default__SentrySettings")
        if not s:IsValid() then return nil end
        return { init = s.InitAutomatically, dsn = #s.DsnUrl:ToString(), release = s.Release:ToString(), symbols = s.UploadSymbolsAutomatically }
    end
    local function report(tag)
        local v = settings()
        local sub = T.first("SentrySubsystem")
        T.log("PT|info sentry %s settings=%s init=%s dsnLen=%s release=%q uploadSymbols=%s subsystem=%s", tag, tostring(v ~= nil),
            tostring(v and v.init), tostring(v and v.dsn), v and v.release or "", tostring(v and v.symbols), T.name(sub))
        return v, sub
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "sentry_settings_loaded", timeout = 10, cond = function()
            local v, sub = report("menu")
            if not v or not sub then return false end
            if expectOff then return v.init == false and v.dsn == 0 end
            return v.dsn > 0
        end },
        -- the window in which the runner's caller looks for crashpad_handler.exe under this copy
        { wait = 40 },
        { run = function()
            local sub = T.first("SentrySubsystem")
            if sub and os.getenv("PT_SENTRY_CLOSE") == "1" then sub:Close(); T.log("PT|info sentry Close() called") end
        end },
        { wait = 30 },
        { run = function() report("end") end },
    }
end
