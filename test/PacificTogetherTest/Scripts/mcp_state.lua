-- State and sync snapshots for the game MCP (tools/gamemcp/ext_state.py, docs/gamemcp/state.md). Test copies only, never shipped.
-- T.mcp_snapshot(domain, detail) returns one JSON string describing a game domain on THIS side; T.mcp_json_eval(code) does the same
-- for an arbitrary Lua expression. Values are plain: numbers rounded, objects as class names or full names, never userdata.
local ARR = {}
local RF_WasLoaded = 0x00080000

local function arr(t) return setmetatable(t or {}, ARR) end

local function esc(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return m[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function enc(v, show)
    local t = type(v)
    if v == nil then return "null" end
    if t == "boolean" then return tostring(v) end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
        return (string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", ""))
    end
    if t == "string" then return esc(v) end
    if t == "table" then
        local parts = {}
        if getmetatable(v) == ARR then
            for i = 1, #v do parts[i] = enc(v[i], show) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local x = v[k]
            if x == nil then x = v[tonumber(k)] end
            parts[#parts + 1] = esc(k) .. ":" .. enc(x, show)
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return esc(show(v))
end

return function(T)
    local show, first, inWorld = T.show, T.first, T.inWorld
    local function r(o, k) local ok, v = pcall(function() return o[k] end); if ok then return v end end
    local function valid(o) return o ~= nil and type(o) == "userdata" and pcall(function() return o:IsValid() end) and o:IsValid() end
    local function cn(o) return valid(o) and o:GetClass():GetFName():ToString() or nil end
    local function fname(o) return valid(o) and o:GetFName():ToString() or nil end
    local function num(v) return type(v) == "number" and v or nil end
    local function bool(v) if type(v) == "boolean" then return v end end
    local function vec(v) if v and v.X then return arr({ v.X, v.Y, v.Z }) end end
    local function rot(v) if v and v.Pitch then return arr({ v.Pitch, v.Yaw, v.Roll }) end end
    local function call(o, fn, ...) local ok, a = pcall(function(...) return o[fn](o, ...) end, ...); if ok then return a end end
    local function outp(o, fn, ...) -- out params come back in a table keyed by parameter name
        local args = table.pack(...)
        args[args.n + 1] = {}
        local ok = pcall(function() o[fn](o, table.unpack(args, 1, args.n + 1)) end)
        if ok then return args[args.n + 1] end
    end
    local function path(o) return valid(o) and (o:GetFullName():match("^%S+ (.*)$")) or nil end
    local function nm(v) -- FName / FString / FText to string
        if v == nil then return nil end
        if type(v) == "string" then return v end
        local ok, s = pcall(function() return v:ToString() end)
        return ok and s or tostring(v)
    end
    local function tagname(t) local ok, s = pcall(function() return t:get().TagName:ToString() end); return ok and s or nil end
    local function hash(s) -- 32-bit string hash: equal state strings give equal hashes
        local h = 5381
        for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
        return string.format("%08x", h)
    end

    local function actorEntry(a)
        local e = { class = cn(a), name = fname(a), role = num(r(a, "Role")), rep = r(a, "bReplicates") and true or false }
        local loaded = pcall(function() return a:HasAnyFlags(RF_WasLoaded) end) and a:HasAnyFlags(RF_WasLoaded) or false
        e.loaded = loaded
        if loaded then e.key = cn(a) .. "|" .. path(a) end
        local l = call(a, "K2_GetActorLocation")
        e.loc = vec(l)
        return e
    end

    local function worldActors(class)
        local res = {}
        for _, a in ipairs(FindAllOf(class) or {}) do
            local ok, keep = pcall(function() return a:IsValid() and not a:GetFullName():find("Default__", 1, true) and inWorld(a) end)
            if ok and keep then res[#res + 1] = a end
        end
        return res
    end

    -- ---------------------------------------------------------------- health, items
    local hcByOuter
    local function buildHealth()
        hcByOuter = {}
        for _, hc in ipairs(FindAllOf("HealthComponentBase") or {}) do
            local ok, o = pcall(function() return hc:IsValid() and hc:GetOuter():GetFullName() end)
            if ok and o then hcByOuter[o] = hc end
        end
    end
    local function healthOf(actor)
        if not hcByOuter then buildHealth() end
        local hc = valid(actor) and hcByOuter and hcByOuter[actor:GetFullName()]
        if not hc then return nil end
        local ok, h, mx, pct, br, dead = pcall(function() return hc:HC_GetHealth(), hc:HC_GetMaxHealth(), hc:HC_GetHealthPercent(), hc:HC_IsBreaking(), hc:HC_IsDead() end)
        if ok then return { health = h, max = mx, pct = pct, breaking = br and true or false, dead = dead and true or false } end
    end

    -- ItemInstance data block (the game's own save form): only values that differ from the archetype defaults are in it, so an
    -- instance that never changed has no "Health"/"Durability" key. state = hash of the whole dump: equal items give equal hashes.
    local function itemState(inst)
        local ok, d = pcall(function() return inst:GetDataBlockDump():ToString() end)
        if not ok then return nil end
        local e = { state = hash(d) }
        for _, k in ipairs({ "Health", "Durability", "CurrentCharge", "Fatigue", "Fuel", "Charge" }) do
            local v = d:match('"' .. k .. '":%s*(%-?[%d%.eE%+%-]+)')
            if v then e[k:lower()] = tonumber(v) end
        end
        return e
    end
    local function archName(inst) local a = r(inst, "Archetype"); return valid(a) and fname(a) or nil end
    local function effects(sm, inst)
        local res = arr()
        if not valid(sm) then return res end
        local ok, list = pcall(function() return sm:GetStatusEffects(inst) end)
        if ok and type(list) == "table" then
            local n = {}
            for i = 1, #list do local c = cn(list[i]:get()) or "?"; n[c] = (n[c] or 0) + 1 end
            for c, k in pairs(n) do res[#res + 1] = k > 1 and (c .. " x" .. k) or c end
            table.sort(res)
        end
        return res
    end

    -- ---------------------------------------------------------------- domains
    local ROLES = { [0] = "None", "SimulatedProxy", "AutonomousProxy", "Authority" }
    local MODES = { [0] = "None", "Walking", "NavWalking", "Falling", "Swimming", "Flying", "Custom" }

    local function pawnEntry(p)
        local e = actorEntry(p)
        e.role_name = ROLES[e.role]
        e.rot = rot(call(p, "K2_GetActorRotation"))
        e.vel = vec(call(p, "GetVelocity"))
        local mv = r(p, "CharacterMovement")
        if valid(mv) then
            local m = num(r(mv, "MovementMode"))
            e.movement_mode = m and (MODES[m] or tostring(m)) or nil
        end
        e.crouched = bool(r(p, "bIsCrouched"))
        e.controlled = valid(r(p, "Controller"))
        e.hidden = bool(r(p, "bHidden"))
        local h = healthOf(p)
        if h then e.health = h end
        local par = call(p, "GetAttachParentActor")
        if valid(par) then e.attached_to = cn(par) end
        e.percent_in_car = num(r(p, "PercentInCar"))
        return e
    end

    local function playersDomain()
        local res = { players = arr(), controllers = arr(), pawns = arr() }
        for _, ps in ipairs(worldActors("PlayerState")) do
            local id = num(r(ps, "PlayerId"))
            local e = { key = "player:" .. tostring(id), id = id, name = nm(call(ps, "GetPlayerName")), spectator = r(ps, "bIsSpectator") }
            local pawn = r(ps, "PawnPrivate")
            if valid(pawn) then
                e.pawn = pawnEntry(pawn)
                local h = r(pawn, "AC_PlayerHealthReceiverHelper") -- the player's damage intake; the game keeps no plain health number on the pawn
                if valid(h) then e.storm_exposure = num(r(h, "PlayerStormExposureCurrent")); e.protected = bool(r(h, "playerProtected")) end
            end
            res.players[#res.players + 1] = e
        end
        local cmg = first("BP_MainCharacterManager_C")
        if valid(cmg) then
            local a = outp(cmg, "GetPlayerAlive")
            res.alive_local = a and bool(a.Alive)
        end
        for _, pc in ipairs(worldActors("PlayerController")) do
            local ps = r(pc, "PlayerState")
            local id = valid(ps) and num(r(ps, "PlayerId")) or nil
            local e = { key = "pc:" .. tostring(id), class = cn(pc), role = num(r(pc, "Role")), remote_role = num(r(pc, "RemoteRole")),
                is_local = call(pc, "IsLocalController") and true or false, player_id = id, pawn_class = cn(r(pc, "Pawn")),
                view_target = cn(call(pc, "GetViewTarget")) }
            e.role_name = ROLES[e.role]
            e.control_rot = rot(call(pc, "GetControlRotation"))
            res.controllers[#res.controllers + 1] = e
        end
        for _, p in ipairs(worldActors("Pawn")) do
            res.pawns[#res.pawns + 1] = pawnEntry(p)
        end
        return res
    end

    local function carDomain()
        local res = { cars = arr(), parts = arr() }
        local cm = first("BP_CarManager_C")
        if valid(cm) then
            local m = {
                ignition = num(r(cm, "CarIgnitionState")), gear = num(r(cm, "MyCarGearBox")), lights_on = r(cm, "CarLightsOn"),
                fuel = num(r(cm, "AggregateFuelCurrent")), fuel_max = num(r(cm, "AggregateFuelMax")),
                battery = num(r(cm, "AggregateBatteryCurrent")), battery_max = num(r(cm, "AggregateBatteryMax")),
                engine_broken = r(cm, "EngineBroken"), horn = r(cm, "HornOn"), radio_on = r(cm, "CarState_RadioOnOff"),
                car_state = num(r(cm, "PlayerCarState")), distance_driven = num(r(cm, "DistanceDriven")),
                mechanic_mode = r(cm, "MechanicMode"), invulnerable = r(cm, "IsInvunerable"), doors = {}, flat = {},
            }
            pcall(function() cm.DoorStates:ForEach(function(k, v) m.doors["door_" .. tostring(k:get())] = v:get() and true or false end) end)
            pcall(function() cm.PartsFlat:ForEach(function(k, v) m.flat[tagname(k) or "?"] = v:get() and true or false end) end)
            res.manager = m
            -- equipment: one entry per attached part, keyed by its slot tag
            buildHealth()
            local sm = first("BP_StatusEffectManager_C")
            local tags = outp(cm, "GetEquipmentSlots", true)
            local list = tags and tags.GameplayTags or {}
            for i = 1, #list do
                local slot = tagname(list[i])
                local e = { key = slot, slot = slot }
                local ins, has = {}, {}
                cm:GetItemInstanceEquippedInSlot(list[i]:get(), ins, has)
                if has.HasItem and valid(ins.Instance) then
                    local inst = ins.Instance
                    e.item = archName(inst)
                    local mo, hi = {}, {}
                    cm:GetManifestationForInstance(inst, hi, mo)
                    local h = healthOf(mo.Manifestation)
                    if h then for k, v in pairs(h) do e[k] = v end end
                    local st = itemState(inst)
                    if st then for k, v in pairs(st) do e[k] = v end end
                    e.effects = effects(sm, inst)
                    if slot and slot:find("Soul", 1, true) then res.quirks = e.effects end
                    e.flat = m.flat[slot]
                else
                    e.item = nil
                end
                res.parts[#res.parts + 1] = e
            end
        end
        for _, c in ipairs(worldActors("BaseNewCar")) do
            local e = pawnEntry(c)
            e.crouched, e.percent_in_car, e.hidden = nil, nil, nil
            local vc = r(c, "VehicleController")
            if valid(vc) then
                e.handbrake = num(r(vc, "HandbrakeInput")); e.throttle = num(r(vc, "ThrottleInput"))
                e.steer = num(r(vc, "SteerInput")); e.brake = num(r(vc, "BrakeInput"))
            end
            e.engine_on = r(c, "EngineOn")
            e.upside_down = r(c, "CarUpsideDownBinary")
            e.possessed = valid(r(c, "Controller"))
            res.cars[#res.cars + 1] = e
        end
        -- the part actors are not replicated: a client that built a local car has a second set (client-actor-survey.md)
        local pa = {}
        for _, a in ipairs(worldActors("BP_Manifestation_CarEquipment_C")) do local c = cn(a); pa[c] = (pa[c] or 0) + 1 end
        res.part_actors = pa
        return res
    end

    local function slotEntry(c, i, detail)
        local ok, e = pcall(function()
            local slot = c:GetSlot(i)
            if not valid(slot) or slot:IsEmpty() then return nil end
            local inst = slot:GetItem(0)
            local e = { i = i, item = archName(inst), n = slot:GetNumItems() }
            if detail then
                local st = itemState(inst)
                if st then for k, v in pairs(st) do e[k] = v end end
            end
            return e
        end)
        return ok and e or nil
    end

    local function containerEntry(c, title, nth, detail, role)
        local e = { key = title .. "#" .. nth, title = title, role = role, slots = c:GetNumSlots(), items = c:GetNumItems(), by_item = {} }
        local ns = e.slots
        local slots = arr()
        for i = 0, ns - 1 do
            local s = slotEntry(c, i, detail)
            if s then
                e.by_item[s.item or "?"] = (e.by_item[s.item or "?"] or 0) + s.n
                slots[#slots + 1] = s
            end
        end
        if detail then e.contents = slots end
        return e
    end

    local function inventoryDomain(detail)
        local res = { containers = arr() }
        local im = first("BP_InventoryManager_C")
        local roleOf = {}
        if valid(im) then
            local pi = outp(im, "GetPlayerInventory")
            if pi and valid(pi.Inventory_Player) then roleOf[pi.Inventory_Player:GetFullName()] = "player_pack" end
        end
        local titleRole = { Trunk = "car_trunk", Pack = "player_pack", Hands = "player_hands", Locker = "garage_locker", Storage = "garage_storage",
            ["Garage Stations"] = "garage_stations", ["Garage Fridge"] = "garage_fridge", Anchor = "anchor_juice", ["Gobbler Container"] = "arc" }
        local seen = {}
        for _, c in ipairs(FindAllOf("ItemContainer") or {}) do
            local ok, e = pcall(function()
                if not c:IsValid() or c:GetFullName():find("Default__", 1, true) then return nil end
                local title = nm(c.TitleText) or ""
                if title == "" then -- containers owned by item instances or managers: no stable order, counted only
                    res.untitled = res.untitled or { containers = 0, items = 0 }
                    res.untitled.containers = res.untitled.containers + 1
                    res.untitled.items = res.untitled.items + c:GetNumItems()
                    return nil
                end
                seen[title] = (seen[title] or 0) + 1
                if c:GetNumItems() == 0 and not roleOf[c:GetFullName()] and not titleRole[title] then return nil end -- empty and unnamed: noise
                return containerEntry(c, title, seen[title], detail, roleOf[c:GetFullName()] or titleRole[title])
            end)
            if ok and e then res.containers[#res.containers + 1] = e end
        end
        local cmg = first("BP_MainCharacterManager_C")
        if valid(cmg) then
            local hb = arr()
            pcall(function()
                local hbc = cmg.HotbarShortcuts
                local sc = hbc.Shortcuts
                for i = 1, #sc do
                    local s = sc[i]
                    local it = r(s, "ShortcutItem")
                    hb[#hb + 1] = { i = i - 1, item = valid(it) and archName(it) or nil }
                end
            end)
            res.hotbar = { cursor = num(r(cmg, "HotbarCursor")), slots = hb }
        end
        return res
    end

    local function runDomain()
        local res = { map = T.map(), net = T.netMode() }
        local gi = FindFirstOf("DrivingGameInstance")
        if valid(gi) then
            res.game = { master_seed = num(r(gi, "MasterSeed")), gameplay_state = num(r(gi, "CurrentGameplayState")), in_garage = r(gi, "bIsInGarage") }
        end
        local pm = first("BP_ProgressionManager_C")
        if valid(pm) then
            res.progression = { map_name = nm(r(pm, "CurrentMapName")), has_left_garage = r(pm, "HasLeftGarage"),
                reveals_consumed = num(r(pm, "RevealsConsumed")), reveals_max = num(r(pm, "MaxRevealCharges")),
                quirk_guesses_consumed = num(r(pm, "Quirk Guesses Consumed")), quirk_guesses_total = num(r(pm, "Quirk Guesses Total")),
                expedition_difficulty = num(r(pm, "CurrentExpeditionDifficulty")), run_results = nil }
            local rs = r(pm, "WorldState")
            if valid(rs) then
                res.route = { phase = num(r(rs, "CurrentPhase")), world_seed = num(r(rs, "WorldShapeRandSeed")), last_reset = num(r(rs, "LastResetReason")) }
                local leg = r(rs, "CurrentLeg")
                if valid(leg) then
                    local l = { active = r(leg, "Active"), visited = r(leg, "Visited"), discovered = r(leg, "Discovered"), reveal_state = num(r(leg, "RevealState")),
                        reveal_flags = num(r(leg, "RevealFlags")), navigate_flags = num(r(leg, "NavigateFlags")), modifiers = arr() }
                    local ml = r(leg, "MapLocation")
                    if valid(ml) then l.map_location = fname(ml) end
                    pcall(function() leg.AppliedModifiers:ForEach(function(_, v) l.modifiers[#l.modifiers + 1] = fname(v:get()) end) end)
                    res.route.current_leg = l
                end
            end
        end
        local st = first("BP_StormManager_C")
        if valid(st) then
            local s = { state = num(r(st, "CurrentStormState")), tolerance = num(r(st, "FinalInstabilityTollerance")),
                player_inside_strong = r(st, "PlayerInsideStrongStorm"), car_inside_strong = r(st, "CarInsideStrongStorm"),
                red_wall = r(st, "RedWallActive"), time_before_instability = num(r(st, "TimeBeforeInstabilityStarts")),
                playback_speed = num(r(st, "StormPlaybackSpeed")), player_left_start = r(st, "PlayerLeftStartingArea") }
            local t = outp(st, "GetCurrentInstabilityTime"); s.instability_time = t and num(t.CurrentInstabilityTime)
            local g = outp(st, "GetExitGateway")
            local gw = g and g.ExitGateway
            s.gateway_selected = valid(gw)
            if valid(gw) then s.gateway = actorEntry(gw) end
            res.storm = s
        end
        local portals = arr()
        for _, a in ipairs(worldActors("BP_LevelTransition_ExitPortal_C")) do portals[#portals + 1] = actorEntry(a) end
        res.exit_portals = portals
        local ok, arc = pcall(T.arcCharge)
        res.arc_charge = ok and arc or nil -- what the ARC screen shows
        local ag = first("BP_Carpart_Internal_Gobbler_C")
        if valid(ag) and valid(r(ag, "Instance")) then
            local inst = ag.Instance
            local st = itemState(inst) or {}
            res.arc_item = { item = archName(inst), state = st.state, charge = st.currentcharge } -- charge only once it differs from the default
        end
        return res
    end

    local WORLD_BASES = { "BP_Lootable_Base", "BaseItemSpawner", "ItemWorldManifestation", "BP_Base_Hazard", "LootableTemplate" }
    local WORLD_COUNTED = { "BaseSiteSpawnerActor", "BP_Spawn_GasBarrel_C", "BP_LeafSpawner_C" } -- run-spawn actors: counted by class, not listed
    local WORLD_LIMIT = 600
    local function worldDomain(detail)
        local res = { counts = {}, actors = arr(), truncated = false }
        local seen = {}
        local nTotal = 0
        local all = {}
        for _, b in ipairs(WORLD_BASES) do all[#all + 1] = { b, true } end
        for _, b in ipairs(WORLD_COUNTED) do all[#all + 1] = { b, false } end
        for _, bl in ipairs(all) do
            local base, listed = bl[1], bl[2]
            local ok, list = pcall(worldActors, base)
            for _, a in ipairs(ok and list or {}) do
                local full = a:GetFullName()
                if not seen[full] then
                    seen[full] = true
                    nTotal = nTotal + 1
                    local e = actorEntry(a)
                    e.base = base
                    if base == "BP_Lootable_Base" then
                        e.empty = r(a, "Empty")
                        local c = r(a, "InventoryContainer")
                        e.items = valid(c) and call(c, "GetNumItems") or nil
                    elseif base == "BaseItemSpawner" then
                        e.spawned = r(a, "SpawnedItem")
                    elseif base == "ItemWorldManifestation" then
                        local inst = r(a, "Instance")
                        e.item = valid(inst) and archName(inst) or nil
                    end
                    local k = e.class
                    local c = res.counts[k]
                    if not c then c = { n = 0, replicated = 0, authority = 0, loaded = 0, empty = 0 }; res.counts[k] = c end
                    c.n = c.n + 1
                    if e.rep then c.replicated = c.replicated + 1 end
                    if e.role == 3 then c.authority = c.authority + 1 end
                    if e.loaded then c.loaded = c.loaded + 1 end
                    if e.empty then c.empty = c.empty + 1 end
                    if listed then
                        if #res.actors < WORLD_LIMIT then res.actors[#res.actors + 1] = e else res.truncated = true end
                    end
                end
            end
        end
        res.total = nTotal
        return res
    end

    local DOMAINS = { players = playersDomain, car = carDomain, inventory = inventoryDomain, run = runDomain, world = worldDomain }

    -- JSON of one domain on this side. detail (inventory): every slot's item state; without it only per-container counts by item.
    function T.mcp_snapshot(domain, detail)
        local f = DOMAINS[domain]
        assert(f, "unknown domain '" .. tostring(domain) .. "' (players, car, inventory, run, world)")
        hcByOuter = nil -- rebuilt on first use: health components come and go with the actors
        local body = f(detail and true or false)
        body.domain, body.side, body.map = domain, T.ROLE, T.map()
        return enc(body, show)
    end

    -- JSON of an arbitrary Lua expression or block (like the console's eval), for compare(lua=...)
    function T.mcp_json_eval(code)
        local env = setmetatable({ T = T, show = show }, { __index = function(_, k) if T[k] ~= nil then return T[k] end return _G[k] end })
        local fn = load("return " .. code, "=cmp", "t", env) or load(code, "=cmp", "t", env)
        assert(fn, "cannot compile the Lua given to compare")
        local res = table.pack(fn())
        return enc(res.n <= 1 and res[1] or (function() local t = arr(); for i = 1, res.n do t[i] = res[i] end return t end)(), show)
    end

    T.mcp_arr = arr
    T.mcp_enc = function(v) return enc(v, show) end

    -- fixture_save: write the live state into a free slot through the game's own SaveGame; returns "slot=N map=M"
    function T.mcp_fixture_save(slot, saveType)
        local sm = T.saveMgr()
        sm:SetCurrentSlot(slot)
        sm:SaveGame(slot, "", saveType)
        return string.format("slot=%d map=%s net=%s", slot, T.map(), T.netMode())
    end
end
