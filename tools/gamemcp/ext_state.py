"""State and sync tools of the game MCP: snapshot, compare, diff_snapshots, fixture_save. See docs/gamemcp/state.md.
The Lua side is test/PacificTogetherTest/Scripts/mcp_state.lua (T.mcp_snapshot, T.mcp_json_eval, T.mcp_fixture_save)."""
import datetime
import json
import math
import re
import shutil
import subprocess
import time
from pathlib import Path

DOMAINS = ["players", "car", "inventory", "run", "world"]
TRANSFORM_KEYS = {"loc", "rot", "vel", "control_rot"}
ANGLE_KEYS = {"rot", "control_rot"}
IGNORE_DEFAULT = ["name", "side", "role", "role_name", "remote_role", "rep", "is_local", "controlled", "possessed"]
ID_FIELDS = ["key", "class", "item", "slot", "title", "base", "loc", "role", "rep", "loaded"]  # shown for entries present on one side only
LIST_CAP = 60


def register(tools, api):
    ToolError, S, ROOT, SIDE = api.ToolError, api.S, api.ROOT, api.SIDE

    # ------------------------------------------------------------ capture
    def capture(domain, lua, side, root, detail):
        if lua:
            text = api.lua_call("mcp_json_eval", side, root, lua, timeout=60)
        else:
            if domain not in DOMAINS:
                raise ToolError(f"domain must be one of {DOMAINS}")
            text = api.lua_call("mcp_snapshot", side, root, domain, bool(detail), timeout=90)
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            raise ToolError(f"the {side} did not return JSON ({e}): {text[:300]}")

    def snap_dir(root):
        d = api.check_root(root) / "mcp-snapshots"
        d.mkdir(exist_ok=True)
        return d

    def fixtures_dir(given=None):
        """git-ignored fixtures live in the main checkout, which a worktree does not have."""
        import os
        if given:
            return Path(given)
        if os.environ.get("PT_FIXTURES_DIR"):
            return Path(os.environ["PT_FIXTURES_DIR"])
        local = api.REPO / "local" / "fixtures"
        if local.is_dir():
            return local
        r = subprocess.run(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], cwd=str(api.REPO), capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return Path(r.stdout.strip()).parent / "local" / "fixtures"
        raise ToolError("cannot find local/fixtures: pass fixtures_dir")

    # ------------------------------------------------------------ diff engine
    class Diff:
        def __init__(self, tol, vtol, radius, ignore, la, lb):
            self.tol, self.vtol, self.radius, self.ignore = tol, vtol, radius, set(ignore)
            self.la, self.lb = la, lb
            self.equal = {}      # top-level section -> equal field count
            self.diffs, self.only_a, self.only_b = [], [], []
            self.ignored = 0
            self.top = ""

        def eq_scalar(self, a, b, key):
            if isinstance(a, bool) or isinstance(b, bool) or not (isinstance(a, (int, float)) and isinstance(b, (int, float))):
                return a == b
            d = abs(a - b)
            if key in ANGLE_KEYS:
                d = min(d % 360, 360 - d % 360)
            return d <= (self.tol if key in TRANSFORM_KEYS else self.vtol)

        def ok(self):
            self.equal[self.top] = self.equal.get(self.top, 0) + 1

        def walk(self, a, b, path, key=""):
            if isinstance(a, dict) and isinstance(b, dict):
                for k in sorted(set(a) | set(b)):
                    if k in self.ignore:
                        self.ignored += 1
                        continue
                    p = f"{path}.{k}" if path else k
                    if not path:
                        self.top = k
                    if k not in a:
                        self.only_b.append({"path": p, "value": self.short(b[k])})
                    elif k not in b:
                        self.only_a.append({"path": p, "value": self.short(a[k])})
                    else:
                        self.walk(a[k], b[k], p, k)
            elif isinstance(a, list) and isinstance(b, list):
                if any(isinstance(x, dict) for x in a + b):
                    self.walk_entities(a, b, path)
                elif len(a) == len(b) and all(self.eq_scalar(x, y, key) for x, y in zip(a, b)):
                    self.ok()
                else:
                    self.diffs.append({"path": path, self.la: a, self.lb: b})
            elif self.eq_scalar(a, b, key):
                self.ok()
            else:
                self.diffs.append({"path": path, self.la: a, self.lb: b})

        def short(self, v):
            if isinstance(v, dict):
                s = {k: v[k] for k in ID_FIELDS if k in v}
                return s or {"fields": sorted(v)[:8]}
            if isinstance(v, list):
                return f"list[{len(v)}]"
            return v

        def walk_entities(self, a, b, path):
            def ekey(e):
                if "key" in e:
                    return e["key"]
                if "i" in e and "class" not in e:
                    return f"i:{e['i']}"
                return None

            def label(e, n):
                return ekey(e) or f"{e.get('class', '?')}~{n}"

            ka, kb, ua, ub = {}, {}, [], []
            for lst, km, un in ((a, ka, ua), (b, kb, ub)):
                for e in lst:
                    if not isinstance(e, dict):
                        continue
                    k = ekey(e)
                    if k is None:
                        un.append(e)
                    else:
                        while k in km:
                            k += "'"
                        km[k] = e
            pairs = [(k, ka[k], kb[k]) for k in sorted(ka) if k in kb]
            for k in sorted(ka):
                if k not in kb:
                    self.only_a.append({"path": f"{path}[{k}]", "value": self.short(ka[k])})
            for k in sorted(kb):
                if k not in ka:
                    self.only_b.append({"path": f"{path}[{k}]", "value": self.short(kb[k])})
            # no stable key: class + nearest position (greedy, closest pairs first, within match_radius)
            groups = {}
            for side, un in ((0, ua), (1, ub)):
                for e in un:
                    groups.setdefault(e.get("class", "?"), ([], []))[side].append(e)
            for cls in sorted(groups):
                ga, gb = groups[cls]
                cand = []
                for i, x in enumerate(ga):
                    for j, y in enumerate(gb):
                        d = math.dist(x["loc"], y["loc"]) if x.get("loc") and y.get("loc") else 0.0
                        if d <= self.radius:
                            cand.append((d, i, j))
                cand.sort()
                used_a, used_b, n = set(), set(), 0
                for d, i, j in cand:
                    if i in used_a or j in used_b:
                        continue
                    used_a.add(i); used_b.add(j); n += 1
                    pairs.append((f"{cls}~{n}", ga[i], gb[j]))
                for i, x in enumerate(ga):
                    if i not in used_a:
                        self.only_a.append({"path": f"{path}[{cls}@{x.get('loc')}]", "value": self.short(x)})
                for j, y in enumerate(gb):
                    if j not in used_b:
                        self.only_b.append({"path": f"{path}[{cls}@{y.get('loc')}]", "value": self.short(y)})
            for k, x, y in pairs:
                self.walk(x, y, f"{path}[{k}]")

        def result(self):
            def cut(lst):
                return lst[:LIST_CAP] + ([f"... {len(lst) - LIST_CAP} more"] if len(lst) > LIST_CAP else [])

            by_field = {}
            for d in self.diffs:
                f = re.sub(r"\[.*?\]", "[]", d["path"])
                f = re.sub(r"(part_actors|counts|by_item|flat|doors)\.[^.\[]+", r"\1.*", f)  # map keys are data, not field names
                by_field[f] = by_field.get(f, 0) + 1
            return {
                "summary": {f"fields_equal": sum(self.equal.values()), "fields_differ": len(self.diffs),
                            f"only_{self.la}": len(self.only_a), f"only_{self.lb}": len(self.only_b), "ignored_fields": self.ignored,
                            "equal_by_section": self.equal},
                "differ_by_field": dict(sorted(by_field.items(), key=lambda kv: -kv[1])),
                "differ": cut(self.diffs), f"only_{self.la}": cut(self.only_a), f"only_{self.lb}": cut(self.only_b),
                "tolerances": {"transform": self.tol, "value": self.vtol, "match_radius": self.radius, "ignored_field_names": sorted(self.ignore)},
            }

    def run_diff(a, b, la, lb, tolerance, value_tolerance, match_radius, ignore):
        d = Diff(tolerance, value_tolerance, match_radius, IGNORE_DEFAULT if ignore is None else ignore, la, lb)
        d.walk(a, b, "")
        return d.result()

    # ------------------------------------------------------------ tools
    def t_snapshot(domain, side="host", root=api.DEFAULT_ROOT, save_as=None, detail=False):
        data = capture(domain, None, side, root, detail)
        if save_as:
            if not re.fullmatch(r"[\w.-]+", save_as):
                raise ToolError("save_as must be a plain name (letters, digits, _ - .)")
            f = snap_dir(root) / f"{save_as}-{side}.json"
            f.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
            data = {"saved": str(f), **data}
        text = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
        if len(text) > api.CAP - 1000:  # too big for one reply: keep the file, return the shape
            f = snap_dir(root) / f"_last-{domain}-{side}.json"
            f.write_text(json.dumps(data, indent=1, ensure_ascii=False), encoding="utf-8")
            return {"too_large_for_reply": f"{len(text)} chars", "saved": str(f),
                    "sections": {k: (f"list[{len(v)}]" if isinstance(v, list) else f"dict[{len(v)}]" if isinstance(v, dict) else v) for k, v in data.items()}}
        return text

    def t_compare(domain=None, lua=None, root=api.DEFAULT_ROOT, tolerance=2.0, value_tolerance=0.05, match_radius=500.0, detail=True, ignore=None):
        if not domain and not lua:
            raise ToolError("give a domain (players, car, inventory, run, world) or a lua expression")
        sess = api.load_session(root)
        if sess and sess.get("players") == 1:
            raise ToolError("this session has one player: compare needs host and client (session_start players=2). snapshot works on a single side")
        h = capture(domain, lua, "host", root, detail)
        c = capture(domain, lua, "client", root, detail)
        return run_diff(h, c, "host", "client", float(tolerance), float(value_tolerance), float(match_radius), ignore)

    def load_snap(name, root):
        p = Path(name)
        if not p.is_file():
            p = snap_dir(root) / (name if name.endswith(".json") else name + ".json")
        if not p.is_file():
            raise ToolError(f"no saved snapshot '{name}' (looked for {p}); names are <save_as>-<side>, e.g. before-host")
        return json.loads(p.read_text(encoding="utf-8"))

    def t_diff_snapshots(a, b, root=api.DEFAULT_ROOT, tolerance=2.0, value_tolerance=0.05, match_radius=500.0, ignore=None):
        da, db = load_snap(a, root), load_snap(b, root)
        for d in (da, db):
            d.pop("saved", None)
        return run_diff(da, db, "a", "b", float(tolerance), float(value_tolerance), float(match_radius), ignore)

    def t_fixture_save(name, side="host", root=api.DEFAULT_ROOT, overwrite=False, save_type=1, note=None, fixtures_dir_path=None, slot=None):
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,40}", name):
            raise ToolError("name must be letters, digits, _ or - (max 40)")
        fx = fixtures_dir(fixtures_dir_path)
        target = fx / name
        old = sorted(target.glob("*.sav")) if target.is_dir() else []
        if old and not overwrite:
            raise ToolError(f"fixture '{name}' already exists in {fx}; pass overwrite=true to replace it")
        saves = api.side_dir(root, side) / "PenDriverPro" / "Saved" / "SaveGames"
        used = {int(m.group(1)) for d in fx.glob("*") for p in d.glob("odsave*.sav") if (m := re.fullmatch(r"odsave(\d+)\.sav", p.name))}
        used |= {int(m.group(1)) for p in saves.glob("odsave*.sav") if (m := re.fullmatch(r"odsave(\d+)\.sav", p.name))}
        if old:
            used -= {int(re.search(r"(\d+)", p.name).group(1)) for p in old}  # an overwritten fixture keeps its slot
        if slot is None:  # the game has 9 slots (GetMaxSaveSlots); 7-9 belong to the built-in fixtures, 1-6 are ours
            slot = next((s for s in range(1, 7) if s not in used), None)
            if slot is None:
                raise ToolError("all slots 1-6 are taken by other fixtures; pass slot=<1-9> to share one (fixtures that share a slot cannot be loaded in the same run)")
        if not 1 <= int(slot) <= 9:
            raise ToolError("slot must be 1-9 (the game's GetMaxSaveSlots is 9)")
        slot = int(slot)
        state = api.lua_call("state", side, root)
        t0 = time.time()
        info = api.lua_call("mcp_fixture_save", side, root, slot, int(save_type), timeout=60)
        sav = saves / f"odsave{slot}.sav"
        deadline = time.time() + 40
        while time.time() < deadline and not (sav.exists() and sav.stat().st_mtime >= t0 - 1):
            time.sleep(0.5)
        if not (sav.exists() and sav.stat().st_mtime >= t0 - 1):
            raise ToolError(f"SaveGame returned ({info}) but no new {sav} appeared within 40 s; see logs")
        time.sleep(1)  # let the writer finish
        target.mkdir(parents=True, exist_ok=True)
        for p in old:
            p.unlink()
        shutil.copy2(sav, target / sav.name)
        m = re.search(r"map=(\S+)", state)
        mapname = m.group(1) if m else "?"
        facts = []
        try:
            run = capture("run", None, side, root, False)
            car = capture("car", None, side, root, False)
            facts.append(f"ARC charge {run.get('arc_charge')}, route phase {run.get('route', {}).get('phase')}, storm state {run.get('storm', {}).get('state')}")
            cm = car.get("manager", {})
            facts.append(f"car fuel {cm.get('fuel')}/{cm.get('fuel_max')}, battery {cm.get('battery')}/{cm.get('battery_max')}, {len(car.get('parts', []))} equipment slots")
            inv = capture("inventory", None, side, root, False)
            top = sorted(inv["containers"], key=lambda c: -c["items"])[:3]
            facts.append("biggest containers: " + ", ".join(f"{c['title']} {c['items']}" for c in top))
        except Exception as e:  # the save is what matters
            facts.append(f"(state summary failed: {e})")
        (target / "fixture.json").write_text(json.dumps({"slot": slot, "map": mapname}), encoding="utf-8")
        (target / "fixture.txt").write_text(
            f"{name}: live state of a running test session, map {mapname} ({state}).\n"
            f"slot {slot} (odsave{slot}.sav), made {datetime.date.today().isoformat()} on build 21896301 from {api.COPY[side]} of a test pair.\n"
            f"Made with the game MCP tool fixture_save: T.saveMgr():SetCurrentSlot({slot}); SaveGame({slot}, \"\", {int(save_type)}) "
            f"(save type 1 = MANUAL, 2 = AUTOSAVE), then odsave{slot}.sav copied from the copy's Saved\\SaveGames.\n"
            f"State when saved: {'; '.join(facts)}.\n" + (f"Note: {note}\n" if note else "")
            + "fixture.json carries slot and map for run-test.ps1 -Fixture (new fixtures need no entry in fixtures.lua).\n", encoding="utf-8")
        return {"fixture": name, "dir": str(target), "slot": slot, "map": mapname, "sav_bytes": (target / sav.name).stat().st_size, "state": state,
                "load_with": f"run-test.ps1 -Scenario repl -Fixture {name} -FixturesDir {fx}  (or session_start fixture={name} fixtures_dir={fx})"}

    snapshot_doc = ("Structured JSON of one game domain on one side: players (state of each player, controller and pawn), car (player car actors, car manager, "
                    "every equipment slot with item, health, status effects, quirks), inventory (containers by role, hotbar; detail=true adds every slot), "
                    "run (map, route/leg, storm/instability, gateway, ARC charge), world (loot/containers/hazards/world items by class with role, replication, loaded/emptied state). "
                    "save_as writes <root>/mcp-snapshots/<name>-<side>.json. See docs/gamemcp/state.md.")
    tools["snapshot"] = (t_snapshot, snapshot_doc,
                         dict(domain={"type": "string", "enum": DOMAINS}, side=SIDE, root=ROOT, save_as={"type": "string", "description": "file name stem; written as <root>/mcp-snapshots/<save_as>-<side>.json"},
                              detail={"type": "boolean", "description": "inventory: list every slot with item state (default per-container counts only)"}), ["domain"])
    tools["compare"] = (t_compare, "Run the same snapshot (domain) or Lua expression (lua: an expression or block returning a plain value/table) on host AND client and return a field-by-field diff: counts of equal fields, differing fields (host vs client), entries present on one side only. Transforms use tolerance (units), other numbers value_tolerance; entries match by key, else class + nearest position within match_radius. Needs a 2-player session.",
                        dict(domain={"type": "string", "enum": DOMAINS}, lua=S, root=ROOT, tolerance={"type": "number", "description": "transform tolerance, default 2.0 (cm / degrees)"},
                             value_tolerance={"type": "number", "description": "other numbers, default 0.05"}, match_radius={"type": "number", "description": "max distance for class+position matching, default 500"},
                             detail={"type": "boolean", "description": "default true (per-slot inventory)"}, ignore={"type": "array", "items": S, "description": f"field names not compared, default {IGNORE_DEFAULT}"}), [])
    tools["diff_snapshots"] = (t_diff_snapshots, "Diff two saved snapshots (names as written by snapshot save_as, e.g. before-host and after-host, or file paths): same side over time, before/after an action.",
                               dict(a=S, b=S, root=ROOT, tolerance={"type": "number"}, value_tolerance={"type": "number"}, match_radius={"type": "number"}, ignore={"type": "array", "items": S}), ["a", "b"])
    tools["fixture_save"] = (t_fixture_save, "Save the CURRENT live state of a running session as a new fixture in the main checkout's local/fixtures/<name>/ (SaveGame to a free slot 1-6, .sav copy, fixture.txt, fixture.json). Refuses to overwrite an existing fixture unless overwrite=true.",
                             dict(name=S, side=SIDE, root=ROOT, overwrite={"type": "boolean"}, save_type={"type": "integer", "description": "1 = MANUAL (default), 2 = AUTOSAVE"}, note=S,
                                  fixtures_dir_path={"type": "string", "description": "override the fixtures folder (default: <main checkout>/local/fixtures)"},
                                  slot={"type": "integer", "description": "save slot 1-9 (default: first free of 1-6)"}), ["name"])
