"""Self-test of the game MCP: starts server.py over stdio and drives it like an agent would, on a test pair.
    python tools/gamemcp/selftest.py [--root C:/PTLanes/probe] [--port 7801] [--skip-shot]
Runs a real 2-player headless session, then a 1-player non-headless one for the screenshot. Exit code 0 = every step passed.
"""
import argparse
import json
import subprocess
import sys
import threading
import time
from pathlib import Path

SERVER = Path(__file__).resolve().parent / "server.py"


class Client:
    def __init__(self):
        self.p = subprocess.Popen([sys.executable, str(SERVER)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.n = 0
        self.lock = threading.Lock()
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "selftest", "version": "0"}})

    def rpc(self, method, params=None):
        with self.lock:  # one request in flight: the server is sequential
            self.n += 1
            self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
            self.p.stdin.flush()
            reply = json.loads(self.p.stdout.readline())
        if "error" in reply:
            raise RuntimeError(reply["error"])
        return reply["result"]

    def tool(self, _name, **args):
        r = self.rpc("tools/call", {"name": _name, "arguments": args})
        return r["isError"], r["content"][0]["text"]


results = []


def step(c, label, _tool, expect_error=False, show=1500, **args):
    t0 = time.time()
    err, text = c.tool(_tool, **args)
    ok = err == expect_error
    results.append(ok)
    print(f"\n### {label}: {_tool} {'PASS' if ok else 'FAIL'} ({time.time() - t0:.1f}s)\n{text[:show]}{'...' if len(text) > show else ''}")
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default="C:/PTLanes/probe")
    ap.add_argument("--port", type=int, default=7801)
    ap.add_argument("--skip-shot", action="store_true")
    a = ap.parse_args()
    root = a.root
    c = Client()
    tools = [t["name"] for t in c.rpc("tools/list")["tools"]]
    print("tools:", tools)
    results.append(len(tools) == 11)

    step(c, "safety: real install refused", "eval", expect_error=True, lua="1", root=r"C:\Program Files (x86)\Steam\steamapps\common\Pacific Drive")
    step(c, "safety: not a test pair", "logs", expect_error=True, root=str(Path(__file__).parent))

    step(c, "start 2 players headless", "session_start", root=root, port=a.port, players=2, headless=True, seconds=1800)
    try:
        step(c, "eval host", "eval", root=root, lua="return state()")
        step(c, "eval client", "eval", root=root, side="client", lua="return state()")
        step(c, "eval lua error", "eval", root=root, expect_error=True, lua="error('boom')")
        found = step(c, "find car", "find", root=root, class_name="BP_PlayerCarNew_C")
        car = next((l for l in found.splitlines() if l.startswith("BP_PlayerCarNew_C ")), None)
        results.append(car is not None)
        if car:
            step(c, "describe car", "describe", root=root, target=car, show=2500)
            step(c, "call getter", "call", root=root, object_path=car, function="K2_GetActorLocation")
        # watch the host's character calls while the host jumps
        c2 = Client()  # the watch holds the first client's pipe for 5 s
        t = threading.Timer(1.5, lambda: c2.tool("eval", root=root, lua="local p = myPawn(); if p then p:Jump() end; return p"))
        t.start()
        step(c, "watch Jump/Landed during a jump", "watch", root=root, filter="Jump|Landed", seconds=5, show=2500)
        t.join()
        step(c, "xref class", "xref", command="find", name="BP_PlayerCarNew", show=800)
        step(c, "logs", "logs", root=root, pattern="PT\\|repl", tail=5)
        step(c, "screenshot refused when headless", "screenshot", root=root, expect_error=True)
        step(c, "status", "session_status", root=root)
    finally:
        step(c, "stop", "session_stop", root=root)

    if not a.skip_shot:
        step(c, "start 1 player windowed", "session_start", root=root, port=a.port, players=1, headless=False, seconds=900)
        try:
            shot = step(c, "screenshot", "screenshot", root=root)
            results.append(Path(shot).is_file() and shot.lower().endswith(".png"))
        finally:
            step(c, "stop", "session_stop", root=root)
    print(f"\n{sum(results)}/{len(results)} checks passed")
    c.p.stdin.close()
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
