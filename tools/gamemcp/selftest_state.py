"""Self-test of the state and sync tools (snapshot, compare, diff_snapshots, fixture_save), driven through the MCP server over stdio.
    python tools/gamemcp/selftest_state.py [--root C:/PTLanes/mcpS] [--port 7911] [--fixtures-dir <main>/local/fixtures] [--skip-zone]
Runs a real 2-player garage session, then a 1-player zone fixture session. Exit code 0 = every check passed.
"""
import argparse
import json
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from selftest import Client  # noqa: E402

results = []


def step(c, label, tool, expect_error=False, show=1200, **args):
    t0 = time.time()
    err, text = c.tool(tool, **args)
    ok = err == expect_error
    results.append(ok)
    print(f"\n### {label}: {tool} {'PASS' if ok else 'FAIL'} ({time.time() - t0:.1f}s)\n{text[:show]}{'...' if len(text) > show else ''}")
    return text


def check(label, cond):
    results.append(bool(cond))
    print(f"### check {label}: {'PASS' if cond else 'FAIL'}")
    return cond


def js(text):
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return {}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/PTLanes/mcpS")
    ap.add_argument("--port", type=int, default=7911)
    ap.add_argument("--fixtures-dir", default="C:/Users/ikeepcalm/Documents/PacificTogether/local/fixtures")
    ap.add_argument("--skip-zone", action="store_true")
    a = ap.parse_args()
    root, fx = a.root, a.fixtures_dir
    c = Client()
    tools = [t["name"] for t in c.rpc("tools/list")["tools"]]
    check("state tools registered", all(t in tools for t in ("snapshot", "compare", "diff_snapshots", "fixture_save")))
    step(c, "bad domain is an error", "snapshot", expect_error=True, domain="nope", root=root)
    step(c, "real install refused", "snapshot", expect_error=True, domain="car", root=r"C:\Program Files (x86)\Steam\steamapps\common\Pacific Drive")
    step(c, "diff of a missing snapshot is an error", "diff_snapshots", expect_error=True, a="nothing-host", b="nothing-host", root=root)

    step(c, "start 2 players garage", "session_start", root=root, port=a.port, players=2, headless=True, seconds=2400, fixtures_dir=fx)
    try:
        for dom in ("players", "car", "inventory", "run", "world"):
            for side in ("host", "client"):
                d = js(step(c, f"snapshot {dom} {side}", "snapshot", root=root, domain=dom, side=side, show=700))
                check(f"{dom}/{side} is JSON of that domain", d.get("domain") == dom or d.get("too_large_for_reply"))

        for dom in ("players", "car", "inventory", "run", "world"):
            r = js(step(c, f"compare {dom} (garage, 2 players)", "compare", root=root, domain=dom, show=3500))
            check(f"compare {dom} returned a summary", "summary" in r)
            if dom == "car":
                s = r["summary"]
                # known duplicates (client-actor-survey.md): the client builds a local car and a second part set
                dup = [e for e in r.get("only_client", []) if isinstance(e, dict) and "BP_PlayerCarNew_C" in json.dumps(e)]
                pa = [d for d in r.get("differ", []) if isinstance(d, dict) and d["path"].startswith("part_actors")]
                check("compare car shows the client-local car copy (only_client) or doubled part actors", dup or pa)

        # a difference made on the host only must show up (the compare can fail)
        step(c, "snapshot before", "snapshot", root=root, domain="car", side="host", save_as="before", show=200)
        step(c, "host lights on", "eval", root=root, lua="local cm = first('BP_CarManager_C'); cm:SetCarLightsOn(true); return cm.CarLightsOn")
        time.sleep(1)
        step(c, "snapshot after", "snapshot", root=root, domain="car", side="host", save_as="after", show=200)
        r = js(step(c, "diff_snapshots before-host after-host", "diff_snapshots", root=root, a="before-host", b="after-host", show=1500))
        check("diff_snapshots sees lights_on change", any(d["path"] == "manager.lights_on" for d in r.get("differ", [])))
        r = js(step(c, "compare car after host-only change", "compare", root=root, domain="car", show=1500))
        check("compare sees the host-only lights_on", any(d["path"] == "manager.lights_on" for d in r.get("differ", [])))
        step(c, "host lights off", "eval", root=root, lua="local cm = first('BP_CarManager_C'); cm:SetCarLightsOn(false); return cm.CarLightsOn")

        r = js(step(c, "compare lua expression", "compare", root=root, lua="{cars = #(FindAllOf('BP_PlayerCarNew_C') or {}), map = T.map()}", show=800))
        check("lua compare: map equal, car count differs host vs client", r.get("summary", {}).get("fields_equal", 0) >= 1 and any(d["path"] == "cars" for d in r.get("differ", [])))

        name = f"mcpS-selftest-{int(time.time())}"
        out = js(step(c, "fixture_save new", "fixture_save", root=root, name=name, fixtures_dir_path=fx, note="state tools selftest, safe to delete", show=900))
        check("fixture written", (Path(fx) / name / "fixture.txt").is_file() and any((Path(fx) / name).glob("*.sav")))
        step(c, "fixture_save refuses overwrite", "fixture_save", expect_error=True, root=root, name=name, fixtures_dir_path=fx)
        out2 = js(step(c, "fixture_save overwrite=true", "fixture_save", root=root, name=name, fixtures_dir_path=fx, overwrite=True, show=400))
        check("overwrite keeps the slot", out.get("slot") == out2.get("slot"))
        garage_fx = name
    finally:
        step(c, "stop", "session_stop", root=root)

    if not a.skip_zone:
        step(c, "start 1 player zone fixture", "session_start", root=root, port=a.port, players=1, headless=True, seconds=1500, fixture="zone", fixtures_dir=fx)
        try:
            for dom in ("players", "car", "inventory", "run", "world"):
                step(c, f"snapshot {dom} (zone, host only)", "snapshot", root=root, domain=dom, save_as=f"zone-{dom}", show=900)
            step(c, "compare needs a client", "compare", expect_error=True, root=root, domain="run")
        finally:
            step(c, "stop", "session_stop", root=root)

        # the garage fixture saved above must load through run-test.ps1 -Fixture (fixture.json -> PT_FIXTURE_SPEC)
        step(c, "start from the new fixture", "session_start", root=root, port=a.port, players=1, headless=True, seconds=900, fixture=garage_fx, fixtures_dir=fx)
        try:
            st = step(c, "state after fixture load", "eval", root=root, lua="return state()", show=300)
            check("new fixture loaded into the garage", "map=RB_Garage" in st)
        finally:
            step(c, "stop", "session_stop", root=root)
    shutil.rmtree(Path(fx) / garage_fx, ignore_errors=True)  # only the throwaway fixture this run made
    print(f"\n{sum(results)}/{len(results)} checks passed")
    c.p.stdin.close()
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
