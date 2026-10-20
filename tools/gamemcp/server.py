"""Pacific Together game MCP: ask a RUNNING test game things (stdio, JSON-RPC 2.0, standard library only).
Talks to the test mod's live console (same file protocol as tools/repl.ps1). Test pairs only. See docs/GAME-MCP.md.

    python tools/gamemcp/server.py      # started by the agent through .mcp.json
"""
import ctypes
import json
import os
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VERSION = "0.1.0"
PROTOCOL = "2025-06-18"
CAP = 20000
BIN = Path("PenDriverPro/Binaries/Win64")
COPY = {"host": "client1", "client": "client2"}
DEFAULT_ROOT = "C:/PacificTogetherTest"
FORBIDDEN = [os.path.normcase(r"C:\Program Files (x86)\Steam"), os.path.normcase(r"C:\Program Files\Steam")]
if os.environ.get("LOCALAPPDATA"):
    FORBIDDEN.append(os.path.normcase(str(Path(os.environ["LOCALAPPDATA"]) / "PenDriverPro")))


class ToolError(Exception):
    pass


def cap(text, limit=CAP):
    text = str(text)
    if len(text) <= limit:
        return text
    return text[:limit] + f"\n... [truncated: {len(text) - limit} more chars of {len(text)}]"


# ---------------------------------------------------------------- safety and paths

def check_root(root):
    """Absolute path of a test pair; refuses the real install and anything that is not root/client1/PenDriverPro."""
    p = Path(root)
    for q in (os.path.normcase(os.path.abspath(p)), os.path.normcase(os.path.realpath(p))):
        if any(q == f or q.startswith(f + os.sep) for f in FORBIDDEN):
            raise ToolError(f"refusing '{root}': that is the real game install or save folder, only test pairs are allowed")
    if not (p / "client1" / "PenDriverPro").is_dir():
        raise ToolError(f"'{root}' is not a test pair (expected {p / 'client1' / 'PenDriverPro'}); make one with tools/setup-test.ps1")
    return p.resolve()


def side_dir(root, side):
    if side not in COPY:
        raise ToolError("side must be 'host' or 'client'")
    return check_root(root) / COPY[side]


def repl_dir(root, side):
    return side_dir(root, side) / BIN / "ue4ss" / "pt_repl"


def state_file(root):
    return check_root(root) / "gamemcp-session.json"


def load_session(root):
    f = state_file(root)
    return json.loads(f.read_text()) if f.exists() else None


def pid_alive(pid):
    h = ctypes.windll.kernel32.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
    if not h:
        return False
    code = ctypes.c_ulong()
    ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(h)
    return code.value == 259  # STILL_ACTIVE


def tail_text(path, n):
    try:
        return "\n".join(Path(path).read_text(encoding="utf-8", errors="replace").splitlines()[-n:])
    except OSError as e:
        return f"<{e}>"


# ---------------------------------------------------------------- live console (same files and id format as tools/repl.ps1)

def run_lua(lua, side="host", root=DEFAULT_ROOT, timeout=20):
    """Returns (ok, text). Raises ToolError when the game does not answer."""
    d = repl_dir(root, side)
    d.mkdir(parents=True, exist_ok=True)
    rid = uuid.uuid4().hex[:8]
    tmp, inp = d / "in.tmp", d / "in.lua"
    tmp.write_bytes(f"-- id={rid}\n{lua}".encode("utf-8"))  # no BOM: Lua chokes on one
    os.replace(tmp, inp)
    pat = re.compile(rf"=== id={rid} (ok|err)\r?\n(.*?)\r?\n=== end id={rid}", re.S)
    out = d / "out.txt"
    deadline = time.time() + timeout
    while time.time() < deadline:
        if out.exists():
            m = pat.search(out.read_text(encoding="utf-8", errors="replace"))
            if m:
                return m.group(1) == "ok", m.group(2)
        time.sleep(0.2)
    try:
        inp.unlink()
    except FileNotFoundError:
        pass
    raise ToolError(f"no answer within {timeout}s from the {side} (no session on {root}, still loading, or the game hangs; try session_status)")


def lua_str(s):
    return json.dumps(str(s))  # a JSON string literal is a valid Lua string literal for the text we pass


def lua_val(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if v is None:
        return "nil"
    if isinstance(v, dict) and "obj" in v:
        return f"mcp_obj({lua_str(v['obj'])})"
    if isinstance(v, str):
        return lua_str(v)
    raise ToolError(f"unsupported argument {v!r}: use numbers, strings, bools or {{\"obj\": \"<object path>\"}}")


def lua_call(fn, side, root, *args, timeout=30):
    ok, text = run_lua(f"return {fn}({', '.join(lua_val(a) for a in args)})", side, root, timeout)
    if not ok:
        raise ToolError(text)
    return text


# ---------------------------------------------------------------- session

def t_session_start(root=DEFAULT_ROOT, port=7777, players=1, fixture=None, map=None, headless=True, seconds=3600, ready_timeout=420):
    root_p = check_root(root)
    if players not in (1, 2):
        raise ToolError("players must be 1 or 2")
    old = load_session(root)
    if old and pid_alive(old["pid"]):
        raise ToolError(f"a session is already running on {root} (runner pid {old['pid']}); session_stop it first")
    for side in COPY:  # a leftover stop file would end the new session at once
        for f in ("stop", "in.lua", "in.tmp"):
            (repl_dir(root, side) / f).unlink(missing_ok=True)
    out = root_p / "gamemcp-session.log"
    cmd = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(REPO / "tools" / "run-test.ps1"),
           "-Scenario", "repl", "-Root", str(root_p), "-Clients", str(players), "-Port", str(port), "-Seconds", str(seconds)]
    if headless:
        cmd.append("-Headless")
    if fixture:
        cmd += ["-Fixture", fixture]
    env = dict(os.environ)
    if map:
        env["PT_MAP"] = map
    with open(out, "wb") as fh:
        proc = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT, env=env, cwd=str(REPO),
                                creationflags=0x08000000 | 0x00000200)  # CREATE_NO_WINDOW | CREATE_NEW_PROCESS_GROUP: survives the server, PowerShell still gets a console
    state_file(root).write_text(json.dumps({"pid": proc.pid, "log": str(out), "headless": bool(headless), "players": players, "port": port}))
    sides = ["host"] + (["client"] if players == 2 else [])
    t0 = time.time()
    answers = {}
    while time.time() - t0 < ready_timeout and len(answers) < len(sides):
        if not pid_alive(proc.pid):
            raise ToolError("the runner exited before the game answered:\n" + tail_text(out, 40))
        for s in sides:
            if s in answers:
                continue
            try:
                ok, text = run_lua("return state()", s, root, timeout=3)
                # host: listen (or standalone for a fixture) on a real map; client: connected to the host's map
                if ok and (("net=listen" in text or "net=standalone" in text) if s == "host" else "net=client" in text) and "map=RB_MainMenu" not in text and "map=none" not in text:
                    answers[s] = text
            except ToolError:
                pass
        time.sleep(2)
    if len(answers) < len(sides):
        raise ToolError(f"timeout after {ready_timeout}s waiting for {sides}; ready so far: {answers}. The runner (pid {proc.pid}) still runs: "
                        f"session_status or session_stop. Runner output:\n{tail_text(out, 20)}")
    return {"runner_pid": proc.pid, "runner_log": str(out), "seconds_to_ready": round(time.time() - t0), "state": answers}


def t_session_status(root=DEFAULT_ROOT):
    s = load_session(root)
    if not s:
        return "no session recorded for this root (session_start makes one)"
    res = {"runner_pid": s["pid"], "runner_alive": pid_alive(s["pid"]), "headless": s["headless"], "players": s["players"], "port": s["port"]}
    if res["runner_alive"]:
        for side in ["host"] + (["client"] if s["players"] == 2 else []):
            try:
                res[side] = run_lua("return state()", side, root, timeout=4)[1]
            except ToolError as e:
                res[side] = f"no answer: {e}"
    res["runner_output_tail"] = tail_text(s["log"], 8)
    return res


def t_session_stop(root=DEFAULT_ROOT, wait=90):
    s = load_session(root)
    for side in COPY:
        d = repl_dir(root, side)
        d.mkdir(parents=True, exist_ok=True)
        (d / "stop").write_bytes(b"")
    if not s:
        return "stop requested; no session was recorded by this tool"
    t0 = time.time()
    while time.time() - t0 < wait and pid_alive(s["pid"]):
        time.sleep(1)
    killed = pid_alive(s["pid"])
    if killed:  # only the runner we started, and its children (the games)
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(s["pid"])], capture_output=True)
    try:
        state_file(root).unlink()
    except FileNotFoundError:
        pass
    return {"stopped": True, "seconds": round(time.time() - t0), "killed_after_timeout": killed, "runner_output_tail": tail_text(s["log"], 12)}


# ---------------------------------------------------------------- game questions

def t_eval(lua, side="host", root=DEFAULT_ROOT, timeout=20):
    ok, text = run_lua(lua, side, root, timeout)
    if not ok:
        raise ToolError(text)
    return text


def t_find(class_name, side="host", root=DEFAULT_ROOT, limit=50, any_world=False):
    return lua_call("mcp_find", side, root, class_name, int(limit), bool(any_world))


def t_describe(target, side="host", root=DEFAULT_ROOT):
    return lua_call("mcp_describe", side, root, target)


def t_call(object_path, function, args_json="[]", side="host", root=DEFAULT_ROOT):
    args = json.loads(args_json) if isinstance(args_json, str) else args_json
    if not isinstance(args, list):
        raise ToolError("args_json must be a JSON list, e.g. [1, \"a\", true, {\"obj\": \"<path>\"}]")
    return lua_call("mcp_call", side, root, object_path, function, *args)


def t_watch(filter, seconds=5, side="host", root=DEFAULT_ROOT, max_calls=500):
    f = "|".join(filter) if isinstance(filter, list) else filter
    ok, text = run_lua(f"return PTNative_TraceStart({lua_str(f)}, {int(max_calls)})", side, root)
    if not ok:
        raise ToolError(text + "  (PTNative_TraceStart missing? build the DLL with tools/build-native.cmd, see docs/GAME-MCP.md)")
    try:
        time.sleep(min(float(seconds), 120))
    finally:
        ok, text = run_lua("local r = PTNative_TraceRead(); PTNative_TraceStop(); return r", side, root, timeout=30)
    lines = text.splitlines()
    if len(lines) > 1:
        t0 = int(lines[1].split("\t")[0])
        lines = [lines[0]] + [f"+{(int(l.split(chr(9))[0]) - t0) / 1000:.2f}ms" + l[l.index("\t"):] for l in lines[1:]]
    return "\n".join(lines) + f"\n-- {len(lines) - 1} call(s) of '{f}' in {seconds}s (ProcessEvent only: not Blueprint-to-Blueprint calls)"


def t_screenshot(side="host", root=DEFAULT_ROOT):
    s = load_session(root)
    if s and s.get("headless"):
        raise ToolError("this session is headless (-nullrhi): nothing is rendered. session_stop, then session_start with headless=false")
    shots = side_dir(root, side) / "PenDriverPro" / "Saved" / "Screenshots"
    before = {p: p.stat().st_mtime for p in shots.rglob("*.png")} if shots.exists() else {}
    run_lua('console("HighResShot 1")', side, root)
    deadline = time.time() + 30
    while time.time() < deadline:
        new = [p for p in (shots.rglob("*.png") if shots.exists() else []) if p not in before or p.stat().st_mtime > before[p]]
        if new:
            time.sleep(1)  # let the file finish writing
            return str(max(new, key=lambda p: p.stat().st_mtime))
        time.sleep(0.5)
    raise ToolError(f"no new PNG under {shots} within 30s (is the window rendering? minimized windows may not)")


def t_logs(side="host", root=DEFAULT_ROOT, pattern=None, tail=200, game_log=False):
    d = side_dir(root, side)
    path = d / "PenDriverPro" / "Saved" / "Logs" / "PenDriverPro.log" if game_log else d / BIN / "ue4ss" / "UE4SS.log"
    if not path.exists():
        raise ToolError(f"no log at {path}")
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    if pattern:
        rx = re.compile(pattern, re.I)
        lines = [l for l in lines if rx.search(l)]
    return "\n".join(lines[-int(tail):]) or "(no matching lines)"


def t_xref(command, name):
    atlas = REPO / "local" / "atlas"
    if not (atlas / "index" / "calls.tsv").exists():
        raise ToolError("the Blueprint atlas is not built locally (local/ is git-ignored). Ask the owner for local/atlas, see docs/GAME-MCP.md 'Setup'.")
    if command not in ("callers", "callees", "class", "find"):
        raise ToolError("command must be callers, callees, class or find")
    r = subprocess.run([sys.executable, "-I", str(atlas / "xref.py"), command, name], capture_output=True, text=True, encoding="utf-8", timeout=120)
    return r.stdout + r.stderr or "(no output)"


# ---------------------------------------------------------------- MCP plumbing

S = {"type": "string"}
ROOT = {"type": "string", "description": f"test pair folder (default {DEFAULT_ROOT}); must contain client1/PenDriverPro"}
SIDE = {"type": "string", "enum": ["host", "client"], "description": "host = client1, client = client2 (default host)"}

TOOLS = {
    "session_start": (t_session_start, "Start a live test game (scenario 'repl') on a test pair in the background and wait until it answers. 15-60 s headless; longer when the machine's game slots are full.",
                      dict(root=ROOT, port={"type": "integer"}, players={"type": "integer", "enum": [1, 2], "description": "1 = host only, 2 = host + joining client"},
                           fixture={"type": "string", "description": "fixture save(s) from local/fixtures, e.g. garage or zone (host standalone)"},
                           map={"type": "string", "description": "map path the host opens, e.g. /Game/Maps/RunProto/RB_Garage"},
                           headless={"type": "boolean", "description": "default true; false is needed for screenshot"}, seconds={"type": "integer"},
                           ready_timeout={"type": "integer"}), []),
    "session_status": (t_session_status, "Is the session on this root alive, and what does each side report (net mode, map, controllers)?", dict(root=ROOT), []),
    "session_stop": (t_session_stop, "End the session: asks both sides to stop, waits for the runner, kills only the runner it started if it hangs.", dict(root=ROOT), []),
    "eval": (t_eval, "Run Lua in the game (expression or block; out(...) prints lines, returned values are shown). All UE4SS globals and the test mod's helpers (state, first, map, console, ...) are in scope. Lua errors come back as tool errors.",
             dict(lua=S, side=SIDE, root=ROOT), ["lua"]),
    "find": (t_find, "Live objects of a class in the current world (full names). any_world=true also lists other worlds' leftovers and non-world objects (widgets).",
             dict(class_name=S, side=SIDE, root=ROOT, limit={"type": "integer"}, any_world={"type": "boolean"}), ["class_name"]),
    "describe": (t_describe, "Properties (with current values) and functions (with parameters) of an object (full name or path) or a class name (its first live instance), own class first, then parents. Capped.",
                 dict(target=S, side=SIDE, root=ROOT), ["target"]),
    "call": (t_call, "Call a UFunction on an object with simple args: numbers, strings, bools, {\"obj\": \"<path>\"}. Returns the return value and out params as lines. It changes the live game.",
             dict(object_path=S, function=S, args_json={"type": "string", "description": "JSON list, default []"}, side=SIDE, root=ROOT), ["object_path", "function"]),
    "watch": (t_watch, "Record every ProcessEvent UFunction call whose full name contains the filter (substring, case-insensitive; 'a|b' or a list = any of them) for N seconds, with the calling object. Do the action meanwhile with a parallel eval. Needs the native mod built with trace.cpp.",
              dict(filter={"type": ["string", "array"], "items": S}, seconds={"type": "number"}, side=SIDE, root=ROOT, max_calls={"type": "integer"}), ["filter"]),
    "screenshot": (t_screenshot, "Take an in-engine HighResShot in a NON-headless session and return the PNG's absolute path (open it with an image reader).", dict(side=SIDE, root=ROOT), []),
    "logs": (t_logs, "Recent lines of the copy's UE4SS.log (game_log=true: PenDriverPro.log), optionally filtered by a regex.",
             dict(side=SIDE, root=ROOT, pattern=S, tail={"type": "integer"}, game_log={"type": "boolean"}), []),
    "xref": (t_xref, "Query the local Blueprint atlas (local/atlas/xref.py): callers <Function|Class.Function>, callees <Class.Function>, class <Class>, find <substring>.",
             dict(command={"type": "string", "enum": ["callers", "callees", "class", "find"]}, name=S), ["command", "name"]),
}


# More tools live in ext_*.py next to this file (one family per file, so parallel work does not collide):
# each defines register(tools, api), where api is this module (run_lua, lua_call, check_root, ToolError, ROOT, SIDE, S, ...).
def load_extensions():
    import glob, importlib.util
    api = sys.modules[__name__]
    for path in sorted(glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ext_*.py"))):
        spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.register(TOOLS, api)


load_extensions()


def tool_list():
    return [{"name": n, "description": d, "inputSchema": {"type": "object", "properties": props, "required": req}}
            for n, (_, d, props, req) in TOOLS.items()]


def handle(msg):
    method, mid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if method == "initialize":
        return {"protocolVersion": params.get("protocolVersion", PROTOCOL), "capabilities": {"tools": {}},
                "serverInfo": {"name": "pacific-game", "version": VERSION},
                "instructions": "Ask a running Pacific Drive test game directly. session_start first (a test pair root, own port), then eval/find/describe/call/watch/screenshot/logs, "
                                "session_stop at the end. Exploring is not proving: turn an answer into a scenario check. Read docs/GAME-MCP.md."}
    if method == "tools/list":
        return {"tools": tool_list()}
    if method == "tools/call":
        name, args = params.get("name"), params.get("arguments") or {}
        if name not in TOOLS:
            raise KeyError(f"unknown tool {name}")
        try:
            result = TOOLS[name][0](**args)
            text = result if isinstance(result, str) else json.dumps(result, indent=1, ensure_ascii=False)
            return {"content": [{"type": "text", "text": cap(text)}], "isError": False}
        except Exception as e:
            return {"content": [{"type": "text", "text": cap(str(e) if isinstance(e, ToolError) else f"{type(e).__name__}: {e}")}], "isError": True}
    if method == "ping":
        return {}
    if mid is None:
        return None
    raise KeyError(f"method not found: {method}")


def main():
    sys.stdin.reconfigure(encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        try:
            result = handle(msg)
            if msg.get("id") is None:
                continue
            reply = {"jsonrpc": "2.0", "id": msg["id"], "result": result}
        except Exception as e:
            if msg.get("id") is None:
                continue
            reply = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601 if isinstance(e, KeyError) else -32603, "message": str(e)}}
        sys.stdout.write(json.dumps(reply, ensure_ascii=False) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
