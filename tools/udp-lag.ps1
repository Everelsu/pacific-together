# UDP relay that delays every packet by -Lag ms in each direction, between a test guest (connects to -Listen) and the
# host (-Target). NetEmulation.PktLag is compiled out of the Shipping exe, so lag runs need this instead.
# With -WatchLog, the last "PT|lag ms=<n>" line in that file sets the lag, so a scenario can change it mid-run.
param(
    [Parameter(Mandatory = $true)][int]$Listen,
    [Parameter(Mandatory = $true)][int]$Target,
    [string]$WatchLog = "",
    [int]$Lag = 0,
    [int]$Seconds = 3600
)
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

public static class LagRelay {
    // Thread.Sleep(1) sleeps 15.6 ms in a windowless process on Windows 11 (timeBeginPeriod is ignored there), so the
    // sender waits on a high-resolution waitable timer instead
    [DllImport("kernel32.dll")] static extern IntPtr CreateWaitableTimerExW(IntPtr attr, IntPtr name, uint flags, uint access);
    [DllImport("kernel32.dll")] static extern bool SetWaitableTimer(IntPtr h, ref long due, int period, IntPtr cb, IntPtr arg, bool resume);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr h, uint ms);
    static readonly IntPtr Timer = CreateWaitableTimerExW(IntPtr.Zero, IntPtr.Zero, 2, 0x1F0003);
    static void Nap() {
        if (Timer == IntPtr.Zero) { Thread.Sleep(1); return; }
        long due = -2000; // 200 us, relative
        SetWaitableTimer(Timer, ref due, 0, IntPtr.Zero, IntPtr.Zero, false);
        WaitForSingleObject(Timer, 0xFFFFFFFF);
    }
    static readonly Stopwatch Clock = Stopwatch.StartNew();
    static long NowUs() { return Clock.ElapsedTicks * 1000000L / Stopwatch.Frequency; }
    static volatile int lagMs;

    class Lane {
        public readonly Queue<KeyValuePair<long, byte[]>> Q = new Queue<KeyValuePair<long, byte[]>>();
        public long LastDue;
        public long Count;
        // never reorder: a packet is due no earlier than the one before it, also when the lag drops
        public void Push(byte[] d) {
            lock (Q) { long due = Math.Max(NowUs() + lagMs * 1000L, LastDue); LastDue = due; Q.Enqueue(new KeyValuePair<long, byte[]>(due, d)); Count++; }
        }
    }

    static UdpClient Socket(int port) {
        var u = new UdpClient(new IPEndPoint(IPAddress.Loopback, port));
        u.Client.IOControl(-1744830452, new byte[] { 0 }, null); // SIO_UDP_CONNRESET off: an ICMP reply must not kill Receive
        return u;
    }

    static void Log(string s) { Console.WriteLine("{0:F3} {1}", NowUs() / 1e6, s); }

    public static void Run(int listen, int target, string watch, int lag, int seconds) {
        lagMs = lag;
        var front = Socket(listen);
        var back = Socket(0);
        var host = new IPEndPoint(IPAddress.Loopback, target);
        IPEndPoint guest = null;
        var up = new Lane();
        var down = new Lane();
        new Thread(() => { var ep = new IPEndPoint(IPAddress.Any, 0); while (true) { try { var d = front.Receive(ref ep); guest = ep; up.Push(d); } catch (SocketException) { } } }) { IsBackground = true }.Start();
        new Thread(() => { var ep = new IPEndPoint(IPAddress.Any, 0); while (true) { try { var d = back.Receive(ref ep); down.Push(d); } catch (SocketException) { } } }) { IsBackground = true }.Start();
        new Thread(() => {
            while (true) {
                long now = NowUs();
                foreach (var lane in new[] { up, down }) {
                    while (true) {
                        byte[] d = null;
                        lock (lane.Q) { if (lane.Q.Count > 0 && lane.Q.Peek().Key <= now) d = lane.Q.Dequeue().Value; }
                        if (d == null) break;
                        try { if (lane == up) back.Send(d, d.Length, host); else if (guest != null) front.Send(d, d.Length, guest); } catch (SocketException) { }
                    }
                }
                Nap();
            }
        }) { IsBackground = true, Priority = ThreadPriority.AboveNormal }.Start();
        Log(string.Format("relay 127.0.0.1:{0} -> 127.0.0.1:{1} lag={2} ms watch={3} hiresTimer={4}", listen, target, lag, watch, Timer != IntPtr.Zero));
        long offset = 0;
        var rx = new Regex(@"PT\|lag ms=(\d+)");
        var end = NowUs() + seconds * 1000000L;
        while (NowUs() < end) {
            Thread.Sleep(100);
            if (watch == "" || !File.Exists(watch)) continue;
            try {
                using (var f = new FileStream(watch, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) {
                    if (f.Length < offset) offset = 0;
                    f.Seek(offset, SeekOrigin.Begin);
                    var buf = new byte[f.Length - offset];
                    int n = f.Read(buf, 0, buf.Length);
                    n = Array.LastIndexOf(buf, (byte)'\n', Math.Max(n - 1, 0)) + 1; // whole lines only
                    offset += n;
                    foreach (Match m in rx.Matches(Encoding.UTF8.GetString(buf, 0, n))) {
                        int v = int.Parse(m.Groups[1].Value);
                        if (v != lagMs) { lagMs = v; Log(string.Format("lag={0} ms (up {1} pkts, down {2} pkts so far)", v, up.Count, down.Count)); }
                    }
                }
            } catch (IOException) { }
        }
        Log(string.Format("done: up {0} pkts, down {1} pkts", up.Count, down.Count));
    }
}
'@
[LagRelay]::Run($Listen, $Target, $WatchLog, $Lag, $Seconds)
