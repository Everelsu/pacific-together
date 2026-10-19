-- X7: the host drives (bot input), the guest rides as passenger; both log the car every frame on the shared QPC clock.
-- The guest connects through tools/udp-lag.ps1 (HOST port + 1), which delays each direction by the last "PT|lag ms=<n>"
-- the guest printed (NetEmulation.PktLag is compiled out of the Shipping exe). Run it with tools/run-car.ps1.
-- The guest cycles placement modes and lags (PHASES); tools/car-error.ps1 turns the logs into error numbers.
-- Mutations: freeze (guest never places its kinematic car), nodedupe (guest keeps its own car copy).
return function(T)
    local L = require("scenarios.carlib")(T)
    local log, ROLE, MUTATE = T.log, T.ROLE, T.MUTATE
    local PHASE_S = 18
    local PHASES = { { "phys", 0 } }
    for _, lag in ipairs({ 0, 100, 150 }) do
        for _, m in ipairs({ "snap", "interp", "motion" }) do PHASES[#PHASES + 1] = { m, lag } end
    end
    local S = { frames = 0 }

    local function fpsCounter(tag)
        local n, t0 = 0, L.now()
        LoopInGameThreadWithDelay(1, function()
            n = n + 1
            local t = L.now()
            if t - t0 >= 5 then log("PT|info %s fps=%.1f", tag, n / (t - t0)); n, t0 = 0, t end
        end)
    end

    if ROLE == "host" then
        local moved, start = 0, nil
        return {
            T.onMap("RB_MainMenu", 90),
            { run = function() T.console("t.MaxFPS 60") end },
            { wait = 5 },
            { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
            { check = "host_listen_garage", timeout = 120, cond = function() return T.netMode() == "listen" and T.map() == "RB_Garage" end },
            { check = "host_two_pcs", timeout = 240, cond = function() return T.pcs() == 2 end },
            { wait = 10 },
            L.spawnGuestStep(),
            { wait = 10 },
            { run = function() S.pc, S.char = L.enterCar(L.car()) end },
            { wait = 6 },
            { run = function() local car = L.car(); if not L.possessing(car) then L.forcePossess(car, S.char) end end },
            { check = "host_in_driver_seat", timeout = 10, cond = function() return L.possessing(L.car()) end },
            { check = "host_seated_guest", timeout = 10, cond = function()
                local car = L.car()
                L.seat(L.guest, car, (L.passengerLocal(car, S.char)))
                return L.guest:GetAttachParentActor():GetFullName() == car:GetFullName()
            end },
            { run = function()
                local car = L.car()
                log("PT|info car net: replicates=%s replicateMovement=%s netUpdate=%s minNetUpdate=%s priority=%s", tostring(car.bReplicates),
                    tostring(car.bReplicateMovement), tostring(car.NetUpdateFrequency), tostring(car.MinNetUpdateFrequency), tostring(car.NetPriority))
                -- already true in the garage (logged above); kept so a car the game spawns without it still moves on the guest
                car:SetReplicateMovement(true)
                L.startEngine(car)
                fpsCounter("host")
            end },
            { wait = 3 },
            { run = function()
                local car = L.car()
                start = car:K2_GetActorLocation()
                L.drive(car, 4)
                local last, startRot, still = nil, car:K2_GetActorRotation(), { t = L.now(), p = start }
                LoopInGameThreadWithDelay(1, function()
                    if not L.driving then return end
                    pcall(function()
                        local p, r = car:K2_GetActorLocation(), car:K2_GetActorRotation()
                        if last then moved = moved + L.d(p, last) end
                        last = p
                        -- the bot ends up against a wall and the car sleeps (run 20261019-204735): put it back where it started
                        if L.d(p, still.p) > 100 then still = { t = L.now(), p = p }
                        elseif L.now() - still.t > 3 then
                            car:K2_SetActorLocationAndRotation(start, startRot, false, {}, true)
                            log("PT|carreset")
                            still = { t = L.now(), p = start }
                        end
                        log("PT|carh t=%.4f x=%.1f y=%.1f z=%.1f yaw=%.2f", L.now(), p.X, p.Y, p.Z, r.Yaw)
                    end)
                end)
                -- the guest's ping as the host sees it, to confirm the proxy's lag
                LoopInGameThreadWithDelay(2000, function()
                    local ok, err = pcall(function() log("PT|ping ms=%d", L.guest.Controller.PlayerState.Ping * 4) end)
                    if not ok and not S.pingErr then S.pingErr = true; log("PT|info ping error %s", tostring(err)) end
                end)
            end },
            { check = "host_car_moving", timeout = 20, cond = function() return L.d(L.car():K2_GetActorLocation(), start) > 200 end },
            { wait = #PHASES * PHASE_S + 40 },
            { check = "host_drove", timeout = 1, cond = function() log("PT|info host drove %.0f uu", moved); return moved > 5000 end },
            { run = function() L.driving = false end },
            { wait = 5 },
        }
    end

    local before, ph, seat0, seatDev = 0, 0, nil, 0
    local proxy = T.HOST:gsub(":(%d+)$", function(p) return ":" .. (tonumber(p) + 1) end)
    local steps = {
        T.onMap("RB_MainMenu", 90),
        { run = function()
            T.console("t.MaxFPS 60")
            StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = 120
            log("PT|lag ms=0")
        end },
        { check = "client_connected_garage", timeout = 300, cond = function() return T.netMode() == "client" and T.map() == "RB_Garage" end,
          tick = (function()
              local nextTry = 0
              return function(t)
                  if t < nextTry or T.map() ~= "RB_MainMenu" or T.netMode() == "client" then return end
                  nextTry = t + 30
                  T.console("open " .. proxy)
              end
          end)() },
        { check = "client_possessed", timeout = 90, cond = function() return T.cls(T.myPawn()) == T.CHAR end },
        { check = "client_seated", timeout = 90, cond = function()
            local p, car = T.myPawn():GetAttachParentActor(), L.car()
            return p:IsValid() and car ~= nil and p:GetFullName() == car:GetFullName()
        end },
        { run = function() before = #L.localCopies(); if MUTATE ~= "nodedupe" then L.dedupe() end end },
        { check = "client_one_car", timeout = 5, cond = function()
            local names = {}
            for _, c in ipairs(FindAllOf("BaseNewCar") or {}) do
                if c:IsValid() and T.inWorld(c) then
                    names[#names + 1] = string.format("%s role=%s at %s beingDestroyed=%s rootDestroyed=%s rendered=%s", T.name(c), tostring(c.Role), L.fmt(c:K2_GetActorLocation()),
                        tostring(c:IsActorBeingDestroyed()), tostring(c.RootComponent:IsValid() and c.RootComponent:IsBeingDestroyed()), tostring(c:WasRecentlyRendered(0.5)))
                end
            end
            log("PT|info local copies before=%d after=%d gobblers=%d (on the replicated car %d) cars: %s", before, #L.localCopies(), L.count("BP_Carpart_Internal_Gobbler_C"),
                #L.attachedOf(L.car(), "BP_Carpart_Internal_Gobbler_C"), table.concat(names, "; "))
            return before >= 1 and #L.localCopies() == 0 and #L.cars() == 1
        end },
        { run = function()
            local car, me = L.car(), T.myPawn()
            L.ride(me)
            L.mode, L.logRep = "phys", true
            L.onFrame = function(now, c)
                local p, r = c:K2_GetActorLocation(), c:K2_GetActorRotation()
                log("PT|carc t=%.4f x=%.1f y=%.1f z=%.1f yaw=%.2f ph=%d", now, p.X, p.Y, p.Z, r.Yaw, ph)
                -- the passenger must ride at a fixed car-local spot whatever we do to the car
                if ph >= 2 then
                    local sl = L.toLocal(c, me:K2_GetActorLocation())
                    seat0 = seat0 or sl
                    seatDev = math.max(seatDev, L.d(sl, seat0))
                end
            end
            L.follow(car)
            fpsCounter("client")
        end },
        { check = "client_sees_car_moving", timeout = 60, cond = function() return #L.buf >= 10 end },
    }
    for i, p in ipairs(PHASES) do
        steps[#steps + 1] = { run = function()
            local mode = (MUTATE == "freeze" and p[1] ~= "phys") and "freeze" or p[1]
            if mode ~= "phys" and L.mode == "phys" then L.kinematic(L.car()) end
            log("PT|info phase %d ends: delay=%.0f ms target=%.0f ms", ph, L.delay * 1000, L.delayTarget * 1000)
            L.mode, ph = mode, i
            -- adaptive render delay belongs to the recommended mode only; interp keeps the fixed 100 ms
            L.adaptive = mode == "motion"
            if not L.adaptive then L.delay = 0.1 end
            log("PT|lag ms=%d", p[2])
            log("PT|carphase n=%d mode=%s lag=%d t=%.4f", i, mode, p[2], L.now())
        end }
        steps[#steps + 1] = { wait = PHASE_S }
    end
    steps[#steps + 1] = { check = "client_passenger_stayed", timeout = 1, cond = function() log("PT|info passenger drift %.2f uu", seatDev); return seat0 ~= nil and seatDev < 5 end }
    steps[#steps + 1] = { run = function() log("PT|carphase n=0 mode=end lag=0 t=%.4f", L.now()); L.onFrame = nil end }
    return steps
end
