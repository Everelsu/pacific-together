"""Game MCP extension: observe and measure (watch_property, net_stats, screenshot_burst, events). See docs/gamemcp/observe.md.
Lua side: test/PacificTogetherTest/Scripts/mcp_observe.lua. Loaded by server.py (load_extensions)."""
import re
import time
from datetime import datetime, timedelta, timezone


def register(tools, api):
    ToolError, lua_call, ROOT, SIDE, S = api.ToolError, api.lua_call, api.ROOT, api.SIDE, api.S
    DEFAULT_ROOT = api.DEFAULT_ROOT

    def pngs(side, root):
        shots = api.side_dir(root, side) / "PenDriverPro" / "Saved" / "Screenshots"
        return shots, {p: p.stat().st_mtime for p in shots.rglob("*.png")} if shots.exists() else {}

    # ------------------------------------------------------------ watch_property
    def t_watch_property(target, properties, seconds=5, interval_ms=100, side="host", root=DEFAULT_ROOT, cap=8):
        props = "|".join(properties) if isinstance(properties, list) else properties
        seconds = min(float(seconds), 120)
        jid = int(lua_call("mcp_wp_start", side, root, target, props, max(int(interval_ms), 20), seconds, int(cap)))
        time.sleep(seconds + 0.3)
        return lua_call("mcp_wp_read", side, root, jid)

    # ------------------------------------------------------------ screenshot_burst
    def t_screenshot_burst(side="host", root=DEFAULT_ROOT, count=3, interval_ms=500):
        s = api.load_session(root)
        if s and s.get("headless"):
            raise ToolError("this session is headless (-nullrhi): nothing is rendered. session_stop, then session_start with headless=false")
        count = max(1, min(int(count), 30))
        shots, before = pngs(side, root)
        t0 = time.time()
        lua_call("mcp_burst_start", side, root, count, int(interval_ms))
        deadline = time.time() + count * max(interval_ms, 100) / 1000 + 30
        new = []
        while time.time() < deadline:
            new = [p for p in (shots.rglob("*.png") if shots.exists() else []) if p not in before or p.stat().st_mtime > before[p]]
            if len(new) >= count:
                break
            time.sleep(0.5)
        time.sleep(1)  # let the last file finish writing
        new = sorted(new, key=lambda p: p.stat().st_mtime)
        if not new:
            raise ToolError(f"no new PNG under {shots} within the wait (is the window rendering? minimized windows may not)")
        note = "" if len(new) >= count else f"\n-- only {len(new)} of {count} files appeared (HighResShot can skip a shot while the previous one is still being written; use a longer interval_ms)"
        return "\n".join(str(p) for p in new) + f"\n-- {len(new)} PNG(s) in {time.time() - t0:.1f}s, oldest first" + note

    # ------------------------------------------------------------ net_stats
    def t_net_stats(root=DEFAULT_ROOT, seconds=2):
        seconds = max(1.0, min(float(seconds), 30))
        started = {}
        for side in ("host", "client"):
            try:
                started[side] = int(lua_call("mcp_net_start", side, root, seconds))
            except ToolError as e:
                started[side] = f"no answer: {e}"
        time.sleep(seconds + 0.3)
        out = []
        for side, jid in started.items():
            out.append(f"== {side}\n" + (jid if isinstance(jid, str) else lua_call("mcp_net_read", side, root, jid)))
        return "\n".join(out)

    # ------------------------------------------------------------ events
    def parse_since(since):
        if not since:
            return None
        since = str(since).strip()
        m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*([smh])", since)
        if m:
            return datetime.now() - timedelta(seconds=float(m.group(1)) * {"s": 1, "m": 60, "h": 3600}[m.group(2)])
        for f in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%H:%M:%S", "%H:%M"):
            try:
                t = datetime.strptime(since, f)
                return t if t.year > 1900 else datetime.combine(datetime.now().date(), t.time())
            except ValueError:
                pass
        raise ToolError("since must be like '90s', '5m', '2h', '13:58:00' or '2026-10-20 13:58:00' (local time)")

    GAME_RULES = [  # (regex on a PenDriverPro.log line, label)
        (r"LogLoad: LoadMap: (\S+)", "map load start {0}"),
        (r"LogLoad: Took ([\d.]+) seconds to LoadMap\((\S+)\)", "map loaded {1} in {0}s"),
        (r"LogNet: ServerTravel: (.*)", "server travel {0}"),
        (r"LogNet: Welcomed by server \(Level: (.*?), Game", "welcomed by server, level {0}"),
        (r"LogNet: NotifyAcceptingConnection accepted from: (\S+)", "connection accepted from {0}"),
        (r"LogNet: Join succeeded: (.+)", "player joined: {0}"),
        (r"LogNet: .*(?:UNetConnection::Close|Connection closed|Closing connection|Client disconnect|TIMED OUT|timed out|Logout).*", "connection/player left: {line}"),
        (r"LogNet: Error.*", "net error: {line}"),
        (r"(?:Fatal error|Unhandled Exception|Assertion failed|Ensure condition failed|Critical error|LogWindows: Error|LogOutputDevice: Error).*", "CRASH/ERROR: {line}"),
    ]

    def t_events(side="host", root=DEFAULT_ROOT, since=None, limit=200, include_status=False):
        t_from = parse_since(since)
        d = api.side_dir(root, side)
        events = []  # (local time, source, text)
        ue4ss = d / api.BIN / "ue4ss" / "UE4SS.log"
        game = d / "PenDriverPro" / "Saved" / "Logs" / "PenDriverPro.log"
        if ue4ss.exists():
            for line in ue4ss.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)\]\s*(.*)", line)
                if not m or "PT|" not in m.group(2):
                    continue
                if not include_status and re.search(r"PT\|(status|repl) ", m.group(2)):
                    continue
                events.append((datetime.strptime(m.group(1)[:26], "%Y-%m-%d %H:%M:%S.%f"), "mod", m.group(2)[m.group(2).index("PT|"):]))
        if game.exists():
            for line in game.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"\[(\d{4})\.(\d\d)\.(\d\d)-(\d\d)\.(\d\d)\.(\d\d):(\d+)\]\[\s*\d+\](.*)", line)
                if not m:
                    continue
                body = m.group(8)
                for rx, fmt in GAME_RULES:
                    r = re.search(rx, body)
                    if r:
                        t = datetime(*map(int, m.groups()[:6]), int(m.group(7)) * 1000, tzinfo=timezone.utc).astimezone().replace(tzinfo=None)  # UE log time is UTC
                        events.append((t, "game", fmt.format(*r.groups(), line=body.strip())))
                        break
        if t_from:
            events = [e for e in events if e[0] >= t_from]
        events.sort(key=lambda e: e[0])
        total = len(events)
        events = events[-int(limit):]
        lines = []  # identical consecutive events collapse into "xN"
        for t, src, text in events:
            line = f"{t:%H:%M:%S}.{t.microsecond // 1000:03d} [{src}] {text[:150]}"
            if lines and lines[-1][0][13:] == line[13:]:
                lines[-1][1] += 1
            else:
                lines.append([line, 1])
        lines = [l + (f"  x{n}" if n > 1 else "") for l, n in lines]
        head = f"-- {total} event(s) on {side}" + (f" since {t_from:%Y-%m-%d %H:%M:%S}" if t_from else "") + (f", last {len(events)} shown" if total > len(events) else "")
        return head + "\n" + "\n".join(lines)

    tools["watch_property"] = (
        t_watch_property,
        "Poll properties of an object (full name / path) or of every live instance of a class (capped) on the game thread for N seconds and return a timestamped change log. "
        "A property is a name, a dotted chain (Pawn.PlayerState.Score) or a no-argument function call (K2_GetActorLocation()). Do the action meanwhile with a parallel eval.",
        dict(target=S, properties={"type": ["string", "array"], "items": S, "description": "e.g. [\"Health\", \"K2_GetActorLocation()\"] or \"A|B\""},
             seconds={"type": "number"}, interval_ms={"type": "integer", "description": "default 100, minimum 20"}, side=SIDE, root=ROOT,
             cap={"type": "integer", "description": "max instances when target is a class name (default 8)"}),
        ["target", "properties"])
    tools["screenshot_burst"] = (
        t_screenshot_burst,
        "N in-engine screenshots interval_ms apart in a NON-headless session (motion review: car feel, animation). Returns the PNG paths, oldest first.",
        dict(side=SIDE, root=ROOT, count={"type": "integer", "description": "1-30, default 3"}, interval_ms={"type": "integer", "description": "default 500, minimum 100"}), [])
    tools["net_stats"] = (
        t_net_stats,
        "Network view of both sides over a short window (default 2 s): UDP packets and bytes in/out per second (socket level), the net driver's configured and measured tick rate, "
        "connections, per-player ping, and frame time (ms avg/p50/p95/max). Lost packets are not exposed by the game's reflection and are reported as such.",
        dict(root=ROOT, seconds={"type": "number", "description": "window length, 1-30, default 2"}), [])
    tools["events"] = (
        t_events,
        "Compact timeline of the game's important events from UE4SS.log and PenDriverPro.log: map loads, travel, player join/leave, connections, possess changes and player count "
        "(PT|observe lines), PT| lines of our mods, crashes/errors. since = '90s', '5m', '13:58:00' or a local date-time; none = everything.",
        dict(side=SIDE, root=ROOT, since={"type": "string"}, limit={"type": "integer", "description": "newest N events, default 200"},
             include_status={"type": "boolean", "description": "also the periodic PT|status and PT|repl lines (default false)"}), [])
