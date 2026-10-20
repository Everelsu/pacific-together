"""Self-test of the game MCP actions family (ext_actions.py): drives server.py over stdio like an agent, in a real 1-player headless
garage session from the garage fixture. Walks 5 m, jumps, interacts with a door and a container, enters the car, starts it and drives
5 s, gives and picks up items, then promotes the journal to a scenario skeleton (deleted again unless --keep).
    python tools/gamemcp/selftest_actions.py [--root C:/PTLanes/mcpA] [--port 7921] [--fixtures-dir <main>/local/fixtures] [--keep]
Exit code 0 = every check passed. Needs a free game slot (docs/TESTING.md, "Parallel lanes").
"""
import argparse
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from selftest import Client  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
results = []


def step(c, label, tool, check=None, expect_error=False, show=2500, **args):
    """runs one tool; check(text) -> bool is an extra assertion on the result text"""
    t0 = time.time()
    err, text = c.tool(tool, **args)
    ok = err == expect_error and (check is None or bool(check(text)))
    results.append(ok)
    print(f"\n### {label}: {tool} {'PASS' if ok else 'FAIL'} ({time.time() - t0:.1f}s)\n{text[:show]}{'...' if len(text) > show else ''}")
    return text


def num(rx, text, group=1):
    m = re.search(rx, text)
    return float(m.group(group)) if m else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/PTLanes/mcpA")
    ap.add_argument("--port", type=int, default=7921)
    ap.add_argument("--fixtures-dir", default=None)
    ap.add_argument("--keep", action="store_true", help="keep the promoted scenario file")
    a = ap.parse_args()
    root = a.root
    c = Client()
    names = {t["name"] for t in c.rpc("tools/list")["tools"]}
    want = {"teleport", "look_at", "move_to", "jump", "crouch", "sprint", "interact", "enter_car", "exit_car", "car_start", "drive", "car_stop",
            "give_item", "spawn_item", "spawn_actor", "pickup", "drop", "inventory", "item_search", "journal", "promote"}
    results.append(want <= names)
    print("action tools registered:", want <= names, sorted(want - names))

    step(c, "car tools refuse the client side", "drive", expect_error=True, root=root, side="client")
    start = dict(root=root, port=a.port, players=1, fixture="garage", headless=True, seconds=1800)
    if a.fixtures_dir:
        start["fixtures_dir"] = a.fixtures_dir
    step(c, "start garage fixture", "session_start", **start)
    try:
        # 1. player: walk 5 m on open floor
        step(c, "teleport to the start of the walk", "teleport", root=root, location=[2300, 3386, 125], exact=True,
             check=lambda t: (num(r"off by ([\d.]+) uu", t) or 999) < 30)
        t = step(c, "walk 5 m", "move_to", root=root, location=[2800, 3386, 125], radius=20,
                 check=lambda t: "arrived" in t and abs((num(r"walked ([\d.]+) uu", t) or 0) - 500) < 60)
        step(c, "look at the car", "look_at", root=root, actor="nearest BP_PlayerCarNew_C", check=lambda t: num(r"error ([\d.]+) deg", t) is not None and num(r"error ([\d.]+) deg", t) < 1)
        step(c, "jump", "jump", root=root, check=lambda t: (num(r"peak ([\d.]+) uu", t) or 0) > 40 and "landed" in t)
        step(c, "crouch", "crouch", root=root, on=True, check=lambda t: "-> true" in t)
        step(c, "stand", "crouch", root=root, on=False, check=lambda t: "-> false" in t)
        step(c, "sprint on", "sprint", root=root, on=True, check=lambda t: "-> 2" in t)
        step(c, "sprint off", "sprint", root=root, on=False, check=lambda t: "-> 1" in t)

        # 2. interaction: a door (its state changes) and a container (its menu opens)
        # (the nearest door to the player is a locked exterior one: it fires the entry points and changes nothing)
        step(c, "interact with a door", "interact", root=root,
             target="/Game/Maps/RunProto/Garage_Art.Garage_Art:PersistentLevel.BP_Door_Single_GarageToStore",
             check=lambda t: "InteractPressed" in t and "target changes:" in t and "no scalar property" not in t)
        step(c, "interact with a container", "interact", root=root, target="nearest BP_Garage_InOutBox_C",
             check=lambda t: "InteractPressed" in t and "menu_open=true" in t)

        # 3. car: enter through the game's door interaction, start, drive 5 s, stop, leave
        step(c, "enter the car", "enter_car", root=root, check=lambda t: "playerCarState=1" in t and "game's own door interaction" in t)
        step(c, "start the car", "car_start", root=root, check=lambda t: "gearbox=0" in t.splitlines()[-1] and "parkingBrake=false" in t.splitlines()[-1])
        step(c, "drive forward 5 s", "drive", root=root, throttle=1.0, seconds=5,
             check=lambda t: (num(r"moved ([\d.]+) uu", t) or 0) > 500)
        step(c, "stop and park", "car_stop", root=root, check=lambda t: "gearbox=1" in t.splitlines()[-1])
        step(c, "leave the car", "exit_car", root=root, check=lambda t: "playerCarState=0" in t)

        # 4. items
        step(c, "teleport to open floor", "teleport", root=root, location=[2497, 3200, 125], exact=True)
        step(c, "item search", "item_search", root=root, query="scrap_steel", check=lambda t: "IA_Resource_Raw_Scrap_Steel" in t)
        step(c, "give 3 scrap steel", "give_item", root=root, item="Raw_Scrap_Steel", count=3,
             check=lambda t: "0 -> 3" in t and "Raw_Scrap_Steel x3" in t)
        spawned = step(c, "spawn a world item", "spawn_item", root=root, item="Raw_Scrap_Steel", location=[2497, 3300, 130])
        m = re.search(r"for pickup\): \S+ (\S+)", spawned)
        results.append(m is not None)
        if m:
            step(c, "pick it up by interacting", "pickup", root=root, target=m.group(1),
                 check=lambda t: "FALLBACK" not in t and "3 -> 4" in t)
        step(c, "backpack shows 4", "inventory", root=root, check=lambda t: "Raw_Scrap_Steel x4" in t)
        step(c, "drop slot 0", "drop", root=root, slot=0, check=lambda t: "4 -> 3" in t)

        # 5. journal and promote
        j = step(c, "journal", "journal", root=root, tail=5)
        step(c, "promote to a scenario skeleton", "promote", root=root, name="selftest_actions_demo", overwrite=True,
             check=lambda t: "wrote" in t)
        scen = REPO / "test" / "PacificTogetherTest" / "Scripts" / "scenarios" / "selftest_actions_demo.lua"
        text = scen.read_text(encoding="utf-8") if scen.exists() else ""
        results.append("T.act_begin" in text and "TODO check" in text and 'loadFixture("garage")' in text)
        print("\npromoted scenario head:\n" + "\n".join(text.splitlines()[:30]))
        if not a.keep:
            scen.unlink(missing_ok=True)
    finally:
        step(c, "stop", "session_stop", root=root)
    print(f"\n{sum(results)}/{len(results)} checks passed")
    c.p.stdin.close()
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
