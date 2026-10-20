"""Game MCP "actions" family: make a player do things in a running test game, one call each (see docs/gamemcp/actions.md).
Each tool starts an action in test/PacificTogetherTest/Scripts/mcp_actions.lua through the live console and polls it until it
finishes; the result says which game code path did the work and what the game's state is afterwards.
Also records every eval/call/action of the session to <root>/mcp-journal.jsonl and turns it into a scenario skeleton (promote)."""
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
JOURNAL = "mcp-journal.jsonl"
CAR_TOOLS = {"enter_car", "exit_car", "car_start", "drive", "car_stop"}


def register(tools, api):
    ToolError, S, ROOT, SIDE = api.ToolError, api.S, api.ROOT, api.SIDE
    DEFAULT_ROOT = api.DEFAULT_ROOT

    # ------------------------------------------------------------ Lua literals
    def lua(v):
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(v)
        if v is None:
            return "nil"
        if isinstance(v, dict):
            return "{" + ", ".join(f"[{api.lua_str(k)}] = {lua(x)}" for k, x in v.items() if x is not None) + "}"
        if isinstance(v, (list, tuple)):
            return "{" + ", ".join(lua(x) for x in v) + "}"
        return api.lua_str(v)

    def point(location):
        """[x, y, z] | "x,y,z" | {x, y, z} -> dict(x=, y=, z=)"""
        if location is None:
            return {}
        if isinstance(location, str):
            try:
                location = [float(p) for p in re.split(r"[,\s]+", location.strip().strip("()[]")) if p]
            except ValueError:
                raise ToolError(f"location '{location}' is not 'x,y,z'")
        if isinstance(location, dict):
            location = [location.get("x", location.get("X")), location.get("y", location.get("Y")), location.get("z", location.get("Z"))]
        if len(location) != 3 or any(c is None for c in location):
            raise ToolError("location must be three numbers: [x, y, z]")
        return dict(zip("xyz", (float(c) for c in location)))

    # ------------------------------------------------------------ journal
    def journal_path(root):
        return api.check_root(root) / JOURNAL

    def record(root, tool, side, args, ok, result):
        try:
            entry = {"t": datetime.now(timezone.utc).isoformat(timespec="seconds"), "tool": tool, "side": side, "args": args, "ok": ok,
                     "result": str(result)[:400]}
            with open(journal_path(root), "a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except Exception:
            pass  # the journal never breaks a tool

    def read_journal(root):
        p = journal_path(root)
        return [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()] if p.exists() else []

    # ------------------------------------------------------------ running an action
    def run_action(name, opts, side, root, timeout):
        if name in CAR_TOOLS and side != "host":
            raise ToolError(f"{name} runs on the host: the car is host-authoritative (a guest's own car copy is not the real car)")
        ok, text = api.run_lua(f"return act_begin({api.lua_str(name)}, {lua(opts)})", side, root, timeout=20)
        if not ok:
            raise ToolError(text)
        jid = int(text.strip().splitlines()[-1])
        deadline = time.time() + timeout
        while time.time() < deadline:
            time.sleep(0.3)
            ok, text = api.run_lua(f"return act_poll({jid})", side, root, timeout=20)
            if not ok:
                raise ToolError(text)
            if text != "pending":
                state, _, body = text.partition("\n")
                if state == "err":
                    raise ToolError(f"{name} failed: {body}")
                return body
        api.run_lua(f"return act_cancel({jid})", side, root, timeout=10)
        raise ToolError(f"{name} did not finish within {timeout} s (cancelled)")

    def target_opts(location=None, actor=None):
        o = point(location)
        if actor:
            o["actor"] = actor
        if not o:
            raise ToolError("give a location [x, y, z] or an actor (object path, or 'nearest <Class>')")
        return o

    # name -> (opts builder: tool arguments -> Lua opts, timeout in s given the arguments). promote replays through these too.
    OPTS = {
        "teleport": (lambda location=None, actor=None, offset=150, exact=False: dict(target_opts(location, actor), offset=offset, exact=exact), lambda k: 20),
        "look_at": (lambda location=None, actor=None: target_opts(location, actor), lambda k: 20),
        "move_to": (lambda location=None, actor=None, timeout=15, radius=80, sprint=False: dict(target_opts(location, actor), timeout=timeout, radius=radius, sprint=bool(sprint)),
                    lambda k: float(k.get("timeout", 15)) + 10),
        "jump": (lambda: {}, lambda k: 15),
        "crouch": (lambda on=True: {"on": bool(on)}, lambda k: 15),
        "sprint": (lambda on=True: {"on": bool(on)}, lambda k: 15),
        "interact": (lambda target, hold=None, approach=True, component=None: {"actor": target, "hold": hold, "approach": bool(approach), "component": component}, lambda k: 30),
        "enter_car": (lambda approach=True: {"approach": bool(approach)}, lambda k: 60),
        "exit_car": (lambda: {}, lambda k: 40),
        "car_start": (lambda: {}, lambda k: 30),
        "drive": (lambda throttle=1.0, steer=0.0, brake=0.0, seconds=3.0: {"throttle": throttle, "steer": steer, "brake": brake, "seconds": seconds},
                  lambda k: float(k.get("seconds", 3)) + 20),
        "car_stop": (lambda park=True: {"park": bool(park)}, lambda k: 30),
        "give_item": (lambda item, count=1: {"item": item, "count": count}, lambda k: 30),
        "spawn_item": (lambda item, location=None, actor=None: dict(target_opts(location, actor), item=item), lambda k: 30),
        "spawn_actor": (lambda class_name, location=None, actor=None: dict(target_opts(location, actor), **{"class": class_name}), lambda k: 30),
        "pickup": (lambda target, approach=True: {"actor": target, "approach": bool(approach)}, lambda k: 40),
        "drop": (lambda slot=0: {"slot": slot}, lambda k: 30),
    }

    def make_tool(name):
        build, timeout = OPTS[name]

        def tool(side="host", root=DEFAULT_ROOT, **kw):
            opts = build(**kw)
            try:
                res = run_action(name, opts, side, root, timeout(kw))
            except ToolError as e:
                record(root, name, side, kw, False, e)
                raise
            record(root, name, side, kw, True, res)
            return res
        tool.__name__ = "t_" + name
        return tool

    def t_inventory(side="host", root=DEFAULT_ROOT):
        return api.lua_call("act_inventory", side, root)

    def t_item_search(query, side="host", root=DEFAULT_ROOT):
        return api.lua_call("act_item_search", side, root, query)

    # ------------------------------------------------------------ 5. journal + promote
    def t_journal(root=DEFAULT_ROOT, tail=30):
        rows = read_journal(root)
        lines = [f"{r['t']} {r['tool']} side={r['side']} {'ok' if r['ok'] else 'FAILED'} {json.dumps(r['args'], ensure_ascii=False)[:160]}" for r in rows[-int(tail):]]
        return f"{len(rows)} entr(ies) in {journal_path(root)}\n" + "\n".join(lines)

    def lua_long(s):
        n = 1
        while f"]{'=' * n}]" in s:
            n += 1
        return f"[{'=' * n}[{s}]{'=' * n}]"

    def t_promote(name, root=DEFAULT_ROOT, overwrite=False):
        if not re.fullmatch(r"[a-z][a-z0-9_]{1,40}", name):
            raise ToolError("name must be lower-case letters, digits and _ (a Lua module name)")
        rows = read_journal(root)
        start = max([i for i, r in enumerate(rows) if r["tool"] == "session_start"], default=-1)
        sess = rows[start]["args"] if start >= 0 else {}
        # failed calls and interactions the game refused ("NOT interactable") are explorations, not steps
        steps_in = [r for r in rows[start + 1:] if r["ok"] and r["tool"] in set(OPTS) | {"eval", "call"} and "NOT interactable" not in r["result"]]
        if not steps_in:
            raise ToolError("the journal has no successful actions since the last session_start: explore first")
        out_path = REPO / "test" / "PacificTogetherTest" / "Scripts" / "scenarios" / f"{name}.lua"
        if out_path.exists() and not overwrite:
            raise ToolError(f"{out_path} exists (overwrite=true replaces it)")
        fixture, mp = sess.get("fixture"), sess.get("map")
        players = sess.get("players", 1)
        sides = {r["side"] for r in steps_in}
        L = []
        L.append(f"-- Generated by the game MCP `promote` from {journal_path(root)} on {datetime.now().strftime('%Y-%m-%d %H:%M')}.")
        L.append("-- A SKELETON: it replays the explored actions and proves almost nothing yet. Every `check` below only passes when the")
        L.append("-- action finished without error. Replace each TODO with an assertion on the state the action's result printed (the")
        L.append("-- journal's `result` field has it), give it a mutation (docs/TESTING.md, \"Mutations\"), then drop this paragraph.")
        run = f"powershell -File tools\\run-test.ps1 -Scenario {name} -Clients {players} -Headless -Root <your test pair> -Port <your port>"
        if fixture:
            run += f" -Fixture {fixture} -FixturesDir <main checkout>\\local\\fixtures"
        L.append(f"-- Run: {run}")
        if "client" in sides or players == 2:
            L.append("-- TODO: this journal used a client; the client's steps are in the same file, selected by T.ROLE. Add the join steps")
            L.append("-- (T.join, see scenarios/interact.lua) and a sync point so the host's steps wait for the client.")
        L.append("return function(T)")
        L.append("    local steps, id = {}, nil")
        L.append("    local function add(s) steps[#steps + 1] = s end")
        if fixture:
            L.append(f"    if T.ROLE == \"host\" then for _, s in ipairs(T.loadFixture({api.lua_str(fixture)})) do add(s) end end")
        else:
            mapname = (mp or "/Game/Maps/RunProto/RB_Garage").rsplit("/", 1)[-1]
            L.append(f"    if T.ROLE == \"host\" then add(T.onMap(\"RB_MainMenu\", 90)); add({{ run = function() T.console(\"open {mp or '/Game/Maps/RunProto/RB_Garage'}?listen\") end }}); add(T.onMap({api.lua_str(mapname)}, 120)) end")
        L.append("    local function act(n, name, opts, timeout)")
        L.append("        add({ run = function() id = T.act_begin(name, opts) end })")
        L.append("        add({ check = string.format(\"step%d_%s\", n, name), timeout = timeout, cond = function()")
        L.append("            local done, text, ok = T.act_done(id)")
        L.append("            if done then T.log(\"PT|info step%d %s: %s\", n, name, (text or \"\"):gsub(\"\\n\", \" | \")) end")
        L.append("            return done and ok")
        L.append("        end })")
        L.append("    end")
        for n, r in enumerate(steps_in, 1):
            tool, side, args = r["tool"], r["side"], r["args"]
            role = side
            L.append("")
            L.append(f"    -- {n}. {tool} {json.dumps(args, ensure_ascii=False)[:150]}")
            L.append(f"    --    explored result: {r['result'].splitlines()[0][:150] if r['result'] else ''}")
            L.append(f"    if T.ROLE == {api.lua_str(role)} then")
            if tool == "eval":
                L.append(f"        add({{ run = function() T.mcp_run({lua_long(args['lua'])}) end }})")
            elif tool == "call":
                a = args.get("args_json", "[]")
                a = json.loads(a) if isinstance(a, str) else a
                call = f"return mcp_call({api.lua_str(args['object_path'])}, {api.lua_str(args['function'])}" + "".join(", " + api.lua_val(x) for x in a) + ")"
                L.append(f"        add({{ run = function() T.mcp_run({lua_long(call)}) end }})")
            else:
                opts = OPTS[tool][0](**args)
                tmo = OPTS[tool][1](args) + 15
                # runtime actors carry a per-run number (BP_WorldItem_C_2147460984): a replay needs "nearest <Class>"
                m = re.search(r"\.(\w+_C)_\d{6,}$", str(opts.get("actor", "")))
                if m:
                    L.append(f"        -- the explored actor {opts['actor'].rsplit('.', 1)[-1]} exists only in that run: replaying with the nearest {m.group(1)}")
                    opts["actor"] = f"nearest {m.group(1)}"
                elif re.search(r"_\d{6,}$", str(opts.get("actor", ""))):
                    L.append("        -- TODO: this actor's name has a per-run number and will not exist in a new run: find it by class or position")
                L.append(f"        act({n}, {api.lua_str(tool)}, {lua(opts)}, {int(tmo)})")
            L.append(f"        -- TODO check: assert on the state after this step ({tool}); copy the numbers from the explored result above")
            L.append("    end")
        L.append("")
        L.append("    return steps")
        L.append("end")
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text("\n".join(L) + "\n", encoding="utf-8")
        return f"wrote {out_path} ({len(steps_in)} step(s) from the journal; session {'fixture ' + fixture if fixture else 'map ' + str(mp or 'garage')}, {players} player(s)). Fill in the TODO checks, then run it as the header says."

    # ------------------------------------------------------------ journal wrappers around the base tools
    def wrap(tool, key_args=()):
        fn, d, props, req = tools[tool]

        def wrapped(**kw):
            root, side = kw.get("root", DEFAULT_ROOT), kw.get("side", "host")
            if tool == "session_start":
                try:
                    journal_path(root).unlink(missing_ok=True)
                except Exception:
                    pass
            try:
                res = fn(**kw)
            except Exception as e:
                if tool != "session_start":
                    record(root, tool, side, {k: v for k, v in kw.items() if k not in ("root", "side")}, False, e)
                raise
            record(root, tool, side, {k: v for k, v in kw.items() if k not in ("root", "side")}, True, res if isinstance(res, str) else json.dumps(res)[:300])
            return res
        tools[tool] = (wrapped, d, props, req)

    for t in ("session_start", "eval", "call"):
        wrap(t)

    # ------------------------------------------------------------ registration
    LOC = {"type": ["array", "string"], "items": {"type": "number"}, "description": "[x, y, z] in uu (1 m = 100 uu) or \"x,y,z\""}
    ACT_ = {"type": "string", "description": "actor: an object path / full name (from find), or \"nearest <Class>\" (nearest to the player)"}
    pair = dict(side=SIDE, root=ROOT)
    host = dict(root=ROOT, side={"type": "string", "enum": ["host"], "description": "car actions run on the host only"})
    CAR = " Host only (the car is host-authoritative)."

    T = {n: make_tool(n) for n in OPTS}
    t_teleport, t_look_at, t_move_to, t_jump, t_crouch, t_sprint, t_interact = (T[n] for n in ("teleport", "look_at", "move_to", "jump", "crouch", "sprint", "interact"))
    t_enter_car, t_exit_car, t_car_start, t_drive, t_car_stop = (T[n] for n in ("enter_car", "exit_car", "car_start", "drive", "car_stop"))
    t_give_item, t_spawn_item, t_spawn_actor, t_pickup, t_drop = (T[n] for n in ("give_item", "spawn_item", "spawn_actor", "pickup", "drop"))

    tools["teleport"] = (t_teleport, "Teleport the player next to an actor (offset uu away, default 150) or to an exact point, with the game's own character placement (K2_HandleSetCharacterLocation). Reports from/to and the error.",
                         dict(location=LOC, actor=ACT_, offset={"type": "number"}, exact={"type": "boolean", "description": "with an actor: land on it instead of beside it"}, **pair), [])
    tools["look_at"] = (t_look_at, "Turn the player's camera to a point or an actor (its interactable centre) with SetControlRotation; reports the angle error read back.",
                        dict(location=LOC, actor=ACT_, **pair), [])
    tools["move_to"] = (t_move_to, "Walk the player to a point or actor with the game's own movement input (Command Move Forward/Backward every frame, camera turned to the target) until within radius uu, stuck or timeout. Reports distance walked and left.",
                        dict(location=LOC, actor=ACT_, timeout={"type": "number", "description": "seconds, default 15"}, radius={"type": "number", "description": "uu, default 80"}, sprint={"type": "boolean"}, **pair), [])
    tools["jump"] = (t_jump, "Jump with the game's own input handler (Command Jump pressed/released); stands up first when crouched. Reports peak height and air time.", pair, [])
    tools["crouch"] = (t_crouch, "Crouch on/off with Command Crouch Toggle (only when the state differs); reports the state read back.", dict(on={"type": "boolean"}, **pair), [])
    tools["sprint"] = (t_sprint, "Sprint on/off with Command Sprint; reports ALS gait and max speed read back (the gait counts while moving).", dict(on={"type": "boolean"}, **pair), [])
    tools["interact"] = (t_interact, "Interact with an actor the way a player does: aim the camera at its highlight, wait until the game highlights it, press Command Interact (held for the interaction's duration), release. Reports which HighlightComponent entry points fired and backpack/menu before and after. Teleports next to it first if out of reach (approach=true, said in the result). On side=client the effect is client-local (X4): the result says so.",
                         dict(target=ACT_, hold={"type": "number", "description": "seconds to hold; default from the interaction's duration"}, approach={"type": "boolean"}, component={"type": "string", "description": "highlight component name, e.g. Highlight_EnterDoor"}, **pair), ["target"])
    tools["enter_car"] = (t_enter_car, "Get into the car: the game's door interaction first (Highlight_EnterDoor), then CommandEnterCar, then Possess(car) as a named fallback." + CAR,
                          dict(approach={"type": "boolean"}, **host), [])
    tools["exit_car"] = (t_exit_car, "Get out of the car (ManualActivate_ExitDoor, Possess(character) fallback)." + CAR, host, [])
    tools["car_start"] = (t_car_start, "Ignition on, gearbox to drive, handbrake off, with the car's own manual entry points. Reports car state before and after." + CAR, host, [])
    tools["drive"] = (t_drive, "Drive for N seconds with throttle/steer/brake (-1..1 / 0..1) through the car's input handlers every frame; the car must be entered and started. Returns position, speed, distance moved before and after." + CAR,
                      dict(throttle={"type": "number"}, steer={"type": "number"}, brake={"type": "number"}, seconds={"type": "number"}, **host), [])
    tools["car_stop"] = (t_car_stop, "Brake to a stop, then (park=true) gearbox to park and parking brake on. Returns car state." + CAR, dict(park={"type": "boolean"}, **host), [])
    tools["give_item"] = (t_give_item, "Put items into the player's backpack with the game's own BP_InventoryManager:GiveItemToPlayer (count times). item = full asset path, IA_Name, or a unique part of a loaded item's name (item_search lists them). Reads the backpack back.",
                          dict(item=S, count={"type": "integer"}, **pair), ["item"])
    tools["spawn_item"] = (t_spawn_item, "Spawn an item as a world pickup with InventorySystem:SpawnItemActor (at a point, or above an actor). Returns the spawned actor's full name for pickup.",
                           dict(item=S, location=LOC, actor=ACT_, **pair), ["item"])
    tools["spawn_actor"] = (t_spawn_actor, "Spawn any actor class (a path /Game/..../BP_X.BP_X_C, or a class that has a live instance) at a point or above an actor with the engine's deferred spawn.",
                            dict(class_name=S, location=LOC, actor=ACT_, **pair), ["class_name"])
    tools["pickup"] = (t_pickup, "Pick up a world item: the interact path (aim + Command Interact), then the character's own 'Pickup Actor' if the backpack did not grow (named in the result). Reports backpack count before and after.",
                       dict(target=ACT_, approach={"type": "boolean"}, **pair), ["target"])
    tools["drop"] = (t_drop, "Drop a backpack slot into the world: slot -> hand (TransferStackIntoContainer) -> BP_InventoryManager:PlayerDropHandItem.", dict(slot={"type": "integer"}, **pair), [])
    tools["inventory"] = (t_inventory, "List the player's backpack and hand contents (slot, item, count).", pair, [])
    tools["item_search"] = (t_item_search, "List loaded item archetype names containing a text (for give_item / spawn_item).", dict(query=S, **pair), ["query"])
    tools["journal"] = (t_journal, "Show the last entries of this session's journal (<root>/mcp-journal.jsonl: every eval, call and action since session_start).", dict(root=ROOT, tail={"type": "integer"}), [])
    tools["promote"] = (t_promote, "Turn the journal into a skeleton scenario test/PacificTogetherTest/Scripts/scenarios/<name>.lua that replays the actions with a TODO check after each; explore, then prove.",
                        dict(name={"type": "string", "description": "scenario name, lower_snake"}, root=ROOT, overwrite={"type": "boolean"}), ["name"])
