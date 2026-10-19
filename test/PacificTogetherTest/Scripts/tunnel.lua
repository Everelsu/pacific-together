-- X5: run any scenario through the native UDP tunnel (run-test.ps1 -Tunnel "udp [lag=ms] [loss=pct] [hold=s]").
-- The client opens 10.77.0.1:<port>; the native layer carries the packets over a loopback link socket on <port>+1000.
-- Mutations: notunnelpeer (the client never maps 10.77.0.1, so it cannot join), tunnelbypass (the client opens the real
-- 127.0.0.1 address, so tunnel_carried fails), nolag (no emulation, so tunnel_lag_seen fails).
local M = {}

local spec = os.getenv("PT_TUNNEL") or ""
local opt = {}
for k, v in spec:gmatch("(%a+)=([%d%.]+)") do opt[k] = tonumber(v) end
M.lag, M.loss, M.hold = opt.lag or 0, opt.loss or 0, opt.hold

function M.host(host)
    if (os.getenv("PT_MUTATE") or "") == "tunnelbypass" then return host end
    return "10.77.0.1:" .. host:match(":(%d+)$")
end

function M.wrap(T, steps, realHost)
    local port = tonumber(realHost:match(":(%d+)$"))
    local linkPort = port + 1000
    local maxPing, monitor = 0, nil
    local function stats() return PTNative_TunnelStats and PTNative_TunnelStats() or "missing" end
    local function stat(k) return tonumber(stats():match(k .. "=(%d+)")) or 0 end
    -- UE's own view, logged only: PlayerState.Ping x 4 (the remote players' on the host, our own on the client)
    local function ping()
        local best = -1
        for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
            if T.inWorld(pc) and (T.ROLE == "client") == pc:IsLocalController() and pc.PlayerState:IsValid() then
                best = math.max(best, pc.PlayerState.Ping * 4)
            end
        end
        return best
    end
    local function up()
        local ok
        if T.ROLE == "host" then
            ok = PTNative_TunnelUdp(linkPort)
        else
            ok = PTNative_TunnelUdp(0) and (T.MUTATE == "notunnelpeer" or PTNative_TunnelPeer("10.77.0.1", "127.0.0.1:" .. linkPort))
        end
        if ok and T.MUTATE ~= "nolag" and (M.lag > 0 or M.loss > 0) then PTNative_TunnelEmulate(M.lag, M.loss) end
        -- shipping UE compiles NetEmulation out; this shows in the engine log whether the console knows it
        if T.ROLE == "host" and M.lag > 0 then T.console("NetEmulation.PktLag 0") end
        T.log("PT|info tunnel up=%s spec='%s' %s", tostring(ok), spec, stats())
        if monitor then return ok == true end
        monitor = LoopInGameThreadWithDelay(5000, function()
            local okp, p = pcall(ping)
            if okp and p > maxPing then maxPing = p end
            T.log("PT|info tunnel ping=%s max=%d %s %s", okp and tostring(p) or "err", maxPing, T.state(), stats())
        end)
        return ok == true
    end

    local out = { { check = "tunnel_up", timeout = 120, cond = up } }
    for _, s in ipairs(steps) do out[#out + 1] = s end
    if M.lag > 0 then
        -- both sides delay their own sends, so the probes' round trip is about 2 x lag; the minimum, because game-thread
        -- stalls (map loads) only ever add to a sample
        out[#out + 1] = { check = "tunnel_lag_seen", timeout = 90, cond = function() return stat("pongs") >= 10 and stat("rttMin") >= M.lag * 2 * 0.8 end }
    end
    if M.hold then
        out[#out + 1] = { wait = M.hold }
        out[#out + 1] = { check = "tunnel_session_held", timeout = 5, cond = function()
            if T.ROLE == "host" then return T.pcs() == 2 end
            return T.netMode() == "client"
        end }
    end
    out[#out + 1] = { check = "tunnel_carried", timeout = 10, cond = function()
        T.log("PT|info tunnel final %s maxPing=%d", stats(), maxPing)
        return stat("in") > 20 and stat("out") > 20 and stat("peers") >= 1
    end }
    return out
end

return M
