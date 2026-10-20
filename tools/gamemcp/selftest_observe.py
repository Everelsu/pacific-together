"""Self-test of the observe tools (watch with args, watch_property, net_stats, events, screenshot_burst) on a test pair.
    python tools/gamemcp/selftest_observe.py [--root C:/PTLanes/mcpO] [--port 7931] [--skip-shot] [--reuse]
Starts a real 2-player headless session (--reuse: use the one already running on the root), then a 1-player windowed one for the burst.
Exit code 0 = every step passed.
"""
import argparse
import sys
import threading
import time
from pathlib import Path

from selftest import Client, results, step


def acting(root, delay, lua):
    c2 = Client()  # the watching call holds the first client's pipe
    t = threading.Timer(delay, lambda: c2.tool("eval", root=root, lua=lua))
    t.start()
    return t


def has(text, *needles):
    ok = all(n in text for n in needles)
    results.append(ok)
    print(f"   -> contains {needles}: {'PASS' if ok else 'FAIL'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/PTLanes/mcpO")
    ap.add_argument("--port", type=int, default=7931)
    ap.add_argument("--skip-shot", action="store_true")
    ap.add_argument("--reuse", action="store_true")
    a = ap.parse_args()
    root = a.root
    c = Client()
    tools = [t["name"] for t in c.rpc("tools/list")["tools"]]
    results.append(all(n in tools for n in ("watch_property", "net_stats", "screenshot_burst", "events")))

    if not a.reuse:
        step(c, "start 2 players headless", "session_start", root=root, port=a.port, players=2, headless=True, seconds=1800, ready_timeout=1500)
    try:
        step(c, "events baseline (join seen)", "events", root=root, since="30m", show=1800)

        t = acting(root, 1.5, "local p = myPawn(); p:Jump(); p:K2_SetActorLocation({X=100,Y=200,Z=300}, false, {}, false); return p")
        txt = step(c, "watch with args and results", "watch", root=root, filter="Character:Jump|K2_SetActorLocation", seconds=4, args=True, results=True, show=2500)
        t.join()
        has(txt, "NewLocation=", "<-", "ReturnValue=")

        t = acting(root, 1.5, 'local c = FindFirstOf("BP_InventoryContainerComponent_C"); c:GetInventoryName({}); c:GetAllItems({}); return c')
        txt = step(c, "watch an inventory function with args and results", "watch", root=root, filter="InventoryContainerComponent_C:Get", seconds=4, args=True, results=True, show=1800)
        t.join()
        has(txt, "<-", "Stored Items=")

        t = acting(root, 1.0, "myPawn():Jump()")
        txt = step(c, "watch_property pawn while jumping", "watch_property", root=root, target="PDP_MainCharacter_C",
                   properties=["K2_GetActorLocation()", "CharacterMovement.MovementMode"], seconds=3, interval_ms=100, show=1800)
        t.join()
        has(txt, "K2_GetActorLocation()", "MovementMode")

        txt = step(c, "net_stats both sides", "net_stats", root=root, seconds=2, show=2500)
        has(txt, "packets_per_s", "frame_time_ms", "ping_ms")

        step(c, "servertravel (map change)", "eval", root=root, lua='console("servertravel /Game/Maps/RunProto/RB_Garage?listen")')
        time.sleep(40)
        txt = step(c, "events after the map change", "events", root=root, since="60s", show=2500)
        has(txt, "map load start", "map loaded")
        step(c, "events on the client", "events", root=root, side="client", since="60s", show=1500)
    finally:
        step(c, "stop", "session_stop", root=root)

    if not a.skip_shot:
        step(c, "start 1 player windowed", "session_start", root=root, port=a.port, players=1, headless=False, seconds=900, ready_timeout=1500)
        try:
            txt = step(c, "screenshot_burst 3", "screenshot_burst", root=root, count=3, interval_ms=600)
            paths = [l for l in txt.splitlines() if l.lower().endswith(".png")]
            results.append(len(paths) == 3 and all(Path(p).is_file() for p in paths))
        finally:
            step(c, "stop", "session_stop", root=root)
    print(f"\n{sum(results)}/{len(results)} checks passed")
    c.p.stdin.close()
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
