# X7: guest-side car error versus the host, per phase of a carride run (PT|carh = host car per frame, PT|carc = guest
# car per frame, both on the shared QPC clock; PT|carphase = guest's mode and lag). Writes car-error.txt, adds its checks
# to summary.txt. Exit code 0 = all checks passed.
param([Parameter(Mandatory = $true)][string]$Results, [double]$Settle = 2.0)
$ErrorActionPreference = "Stop"
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;

public static class CarError {
    static double D(string s) { return double.Parse(s, CultureInfo.InvariantCulture); }
    static double[] Pct(List<double> v) {
        if (v.Count == 0) return new double[] { 0, 0, 0 };
        var s = v.OrderBy(x => x).ToList();
        return new double[] { v.Average(), s[(int)Math.Min(s.Count - 1, Math.Floor(0.95 * s.Count))], s[s.Count - 1] };
    }
    class Track {
        public List<double> T = new List<double>(), X = new List<double>(), Y = new List<double>(), Z = new List<double>();
        public double[] At(double t) {
            int i = T.BinarySearch(t); if (i < 0) i = ~i;
            if (i <= 0) return new[] { X[0], Y[0], Z[0] };
            if (i >= T.Count) return new[] { X[T.Count - 1], Y[T.Count - 1], Z[T.Count - 1] };
            double a = (t - T[i - 1]) / (T[i] - T[i - 1]);
            return new[] { X[i - 1] + (X[i] - X[i - 1]) * a, Y[i - 1] + (Y[i] - Y[i - 1]) * a, Z[i - 1] + (Z[i] - Z[i - 1]) * a };
        }
    }
    static double Dist(double[] a, double[] b) { return Math.Sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2])); }
    // how uneven a track looks on its own screen: RMS of each frame's speed against the track's own speed over +-100 ms, in %
    static double SelfJitter(List<double> t, List<double[]> p) {
        var e = new List<double>();
        int a = 0, b = 0;
        for (int i = 1; i < t.Count; i++) {
            while (t[a] < t[i] - 0.1) a++;
            while (b + 1 < t.Count && t[b + 1] <= t[i] + 0.1) b++;
            double dt = t[i] - t[i - 1], w = t[b] - t[a];
            if (dt <= 0 || w < 0.15) continue;
            double vs = Dist(p[b], p[a]) / w, vf = Dist(p[i], p[i - 1]) / dt;
            if (vs > 100) e.Add((vf - vs) / vs);
        }
        return e.Count > 0 ? Math.Sqrt(e.Select(x => x * x).Average()) * 100 : 0;
    }

    // returns report lines; checks are lines starting with PASS/FAIL
    public static string[] Run(string hostLog, string clientLog, double settle) {
        var outp = new List<string>();
        var num = @"(-?[\d.]+)";
        // time = the UE4SS log stamp (system clock, the same in both processes); the lines' own t= is per process
        // (GetAccurateRealTime counts from each game's start, run 20261019-194435 was 8 s apart)
        var st = @"\[([\d\- :.]+)\] \[Lua\] \[PacificTogetherTest\] ";
        Func<string, double> W = s => DateTime.ParseExact(s, "yyyy-MM-dd HH:mm:ss.fffffff", CultureInfo.InvariantCulture).Ticks / 1e7;
        string htext = File.ReadAllText(hostLog), ctext = File.ReadAllText(clientLog);
        var host = new Track();
        foreach (Match m in Regex.Matches(htext, st + @"PT\|carh t=\S+ x=" + num + " y=" + num + " z=" + num)) {
            host.T.Add(W(m.Groups[1].Value)); host.X.Add(D(m.Groups[2].Value)); host.Y.Add(D(m.Groups[3].Value)); host.Z.Add(D(m.Groups[4].Value));
        }
        // the host puts a stuck car back at its start; the jump is not part of driving, so 2 s after each reset are skipped
        var resets = Regex.Matches(htext, st + @"PT\|carreset").Cast<Match>().Select(m => W(m.Groups[1].Value)).ToList();
        var pings =Regex.Matches(htext, st + @"PT\|ping ms=(\d+)").Cast<Match>().Select(m => new[] { W(m.Groups[1].Value), D(m.Groups[2].Value) }).ToList();
        var phases = Regex.Matches(ctext, st + @"PT\|carphase n=(\d+) mode=(\S+) lag=(\d+)").Cast<Match>()
            .Select(m => new { N = int.Parse(m.Groups[2].Value), Mode = m.Groups[3].Value, Lag = int.Parse(m.Groups[4].Value), T = W(m.Groups[1].Value) }).ToList();
        var cl = Regex.Matches(ctext, st + @"PT\|carc t=\S+ x=" + num + " y=" + num + " z=" + num + @" yaw=\S+ ph=(\d+)").Cast<Match>()
            .Select(m => new { T = W(m.Groups[1].Value), P = new[] { D(m.Groups[2].Value), D(m.Groups[3].Value), D(m.Groups[4].Value) }, Ph = int.Parse(m.Groups[5].Value) }).ToList();
        var reps = Regex.Matches(ctext, st + @"PT\|crep ").Cast<Match>().Select(m => W(m.Groups[1].Value)).ToList();
        outp.Add(string.Format("host frames {0}, client frames {1}, snapshots {2}, phases {3}", host.T.Count, cl.Count, reps.Count, phases.Count));
        if (host.T.Count < 100 || cl.Count < 100 || phases.Count < 2) { outp.Add("FAIL  car logs present  too few samples"); return outp.ToArray(); }
        outp.Add("PASS  car logs present  ");
        outp.Add("phase mode   lag | frames fps | hostSpeed | sameTime err mean/p95/max | best delay ms | residual mean/p95/max | speedVsHost% | selfJitter client/host % | stalls% | snapGap ms mean/p95/max | ping ms");
        var basePings = new List<double>();
        for (int k = 0; k < phases.Count; k++) {
            var ph = phases[k];
            if (ph.Mode == "end") continue;
            double t0 = ph.T + settle, t1 = k + 1 < phases.Count ? phases[k + 1].T : cl[cl.Count - 1].T;
            var s = cl.Where(c => c.Ph == ph.N && c.T >= t0 && c.T < t1 && c.T < host.T[host.T.Count - 1] && !resets.Any(r0 => c.T > r0 - 0.2 && c.T < r0 + 2)).ToList();
            if (s.Count < 30) { outp.Add(string.Format("{0} {1} {2}: only {3} samples", ph.N, ph.Mode, ph.Lag, s.Count)); continue; }
            var e0 = s.Select(c => Dist(c.P, host.At(c.T))).ToList();
            double bestTau = 0, bestMean = double.MaxValue;
            for (int ms = 0; ms <= 600; ms += 2) {
                double tau = ms / 1000.0, sum = 0;
                foreach (var c in s) sum += Dist(c.P, host.At(c.T - tau));
                if (sum / s.Count < bestMean) { bestMean = sum / s.Count; bestTau = tau; }
            }
            // in a host frame over 100 ms the host's car moves only 22-88 % (median 38 %) of its speed (physics step cap,
            // run 20261020-113456), so the host's own picture hesitates while the guest's motion clock stays even; such a
            // hitch and the 1.5 s after its end (at the guest's delay; the motion clock needs ~1 s to catch up) are left
            // out and counted
            var hitches = new List<double[]>();
            for (int i = 1; i < host.T.Count; i++) if (host.T[i] - host.T[i - 1] > 0.1) hitches.Add(new[] { host.T[i - 1], host.T[i] });
            int before = s.Count;
            s = s.Where(c => !hitches.Any(h => c.T - bestTau > h[0] - 0.1 && c.T - bestTau < h[1] + 1.5)).ToList();
            if (s.Count < before / 2) {
                // a host that hitches all the time is no measurement; motion phases fail rather than pass on a few frames
                bool chk = ph.Mode == "motion" || ph.Mode == "freeze";
                outp.Add(string.Format("{0}{1} {2} {3}: only {4} of {5} frames left after host hitches", chk ? "FAIL  car " : "", ph.N, ph.Mode, ph.Lag, s.Count, before));
                continue;
            }
            e0 = s.Select(c => Dist(c.P, host.At(c.T))).ToList();
            int hitchSkipped = before - s.Count;
            var res = s.Select(c => Dist(c.P, host.At(c.T - bestTau))).ToList();
            // per-frame speed of the guest's car versus the host's speed over the same (delayed) interval
            var jit = new List<double>(); int stalls = 0, moving = 0; var hs = new List<double>();
            for (int i = 1; i < s.Count; i++) {
                double dt = s[i].T - s[i - 1].T; if (dt <= 0) continue;
                double vc = Dist(s[i].P, s[i - 1].P) / dt;
                double vh = Dist(host.At(s[i].T - bestTau), host.At(s[i - 1].T - bestTau)) / dt;
                hs.Add(vh);
                if (vh > 100) { moving++; if (vc < 1) stalls++; jit.Add((vc - vh) / vh); }
            }
            double jitRms = jit.Count > 0 ? Math.Sqrt(jit.Select(x => x * x).Average()) * 100 : 0;
            double cSelf = SelfJitter(s.Select(c => c.T).ToList(), s.Select(c => c.P).ToList());
            var hi = Enumerable.Range(0, host.T.Count).Where(i => host.T[i] >= t0 - bestTau && host.T[i] < s[s.Count - 1].T - bestTau).ToList();
            double hSelf = SelfJitter(hi.Select(i => host.T[i]).ToList(), hi.Select(i => new[] { host.X[i], host.Y[i], host.Z[i] }).ToList());
            double stallPct = moving > 0 ? 100.0 * stalls / moving : 0;
            var gaps = new List<double>();
            for (int i = 1; i < reps.Count; i++) if (reps[i] >= t0 && reps[i] < t1) gaps.Add((reps[i] - reps[i - 1]) * 1000);
            var pp = pings.Where(p => p[0] >= t0 && p[0] < t1).Select(p => p[1]).OrderBy(x => x).ToList();
            double ping = pp.Count > 0 ? pp[pp.Count / 2] : -1;
            var hg = new List<double>();
            for (int i = 1; i < host.T.Count; i++) if (host.T[i] >= t0 && host.T[i] < t1) hg.Add((host.T[i] - host.T[i - 1]) * 1000);
            var hgp = Pct(hg);
            // the frames with the largest error, and how long the host frame before them took
            var worst = s.Select((c, i) => new { E = res[i], T = c.T }).OrderByDescending(x => x.E).Take(3)
                .Select(x => { int j = host.T.BinarySearch(x.T - bestTau); if (j < 0) j = ~j; j = Math.Max(1, Math.Min(host.T.Count - 1, j));
                    return string.Format(CultureInfo.InvariantCulture, "{0:F0}uu@hostFrame{1:F0}ms", x.E, (host.T[j] - host.T[j - 1]) * 1000); });
            outp.Add(string.Format(CultureInfo.InvariantCulture, "   host frame ms mean/p95/max {0:F0}/{1:F0}/{2:F0}; guest frames skipped after host hitches {4}; worst residuals {3}",
                hgp[0], hgp[1], hgp[2], string.Join(" ", worst), hitchSkipped));
            var a = Pct(e0); var r = Pct(res); var g = Pct(gaps);
            double fps = s.Count / (s[s.Count - 1].T - s[0].T);
            outp.Add(string.Format(CultureInfo.InvariantCulture, "{0,2} {1,-6} {2,3} | {3,5} {4,4:F0} | {5,6:F0} | {6,6:F1} {7,6:F1} {8,6:F1} | {9,4:F0} | {10,5:F1} {11,5:F1} {12,6:F1} | {13,5:F1} | {19,5:F1} {20,5:F1} | {14,5:F1} | {15,5:F1} {16,5:F1} {17,6:F1} | {18:F0}",
                ph.N, ph.Mode, ph.Lag, s.Count, fps, hs.Count > 0 ? hs.Average() : 0, a[0], a[1], a[2], bestTau * 1000, r[0], r[1], r[2], jitRms, stallPct, g[0], g[1], g[2], ping, cSelf, hSelf));
            string id = string.Format("phase{0}_{1}_lag{2}", ph.N, ph.Mode, ph.Lag);
            if (ph.Lag == 0 && ping >= 0) basePings.Add(ping);
            if (ph.Lag > 0 && ping >= 0 && basePings.Count > 0) {
                // the engine's ping includes a frame or two on each side (~40 ms at 30-40 fps), so compare against lag 0
                double added = ping - basePings.Average();
                bool ok = Math.Abs(added - 2 * ph.Lag) <= 30;
                outp.Add(string.Format("{0}  car {1} rtt  ping={2:F0} ms, {3:F0} over lag 0, want {4}+-30", ok ? "PASS" : "FAIL", id, ping, added, 2 * ph.Lag));
            }
            if (ph.Mode == "motion" || ph.Mode == "freeze") {
                // the adaptive render delay drifts slowly (100 -> 160 ms in a phase, run 20261020-110239); a few % of playback
                // speed is invisible, so the path is compared per 2 s window, each against its own best delay
                var local = new List<double>(); double dMin = double.MaxValue, dMax = 0;
                for (double w0 = s[0].T; w0 < s[s.Count - 1].T; w0 += 2) {
                    var ws = s.Where(c => c.T >= w0 && c.T < w0 + 2).ToList();
                    if (ws.Count < 10) continue;
                    double bt = 0, bm = double.MaxValue;
                    for (int ms = 0; ms <= 600; ms += 4) {
                        double tau = ms / 1000.0, m = ws.Average(c => Dist(c.P, host.At(c.T - tau)));
                        if (m < bm) { bm = m; bt = tau; }
                    }
                    dMin = Math.Min(dMin, bt); dMax = Math.Max(dMax, bt);
                    local.AddRange(ws.Select(c => Dist(c.P, host.At(c.T - bt))));
                }
                var lr = Pct(local);
                // C2 smooth: no frozen frames, the path within 10 uu of the host's (after its delay), frame-to-frame speed no
                // more uneven than twice the host's own picture (+5 points), delay <= lag + the 250 ms render-delay cap + 50
                // and the car must have been driving (a parked car passes everything)
                double hMean = hs.Count > 0 ? hs.Average() : 0;
                bool ok = hMean > 150 && stallPct < 1 && lr[1] <= 10 && cSelf <= 2 * hSelf + 5 && bestTau * 1000 <= ph.Lag + 300;
                outp.Add(string.Format(CultureInfo.InvariantCulture, "{0}  car {1} smooth  hostSpeed={7:F0} stalls={2:F1}% localResidualP95={8:F1} (one delay {3:F1}) selfJitter={4:F1}% (host {5:F1}%) delay={6:F0}ms ({9:F0}-{10:F0})",
                    ok ? "PASS" : "FAIL", id, stallPct, r[1], cSelf, hSelf, bestTau * 1000, hMean, lr[1], dMin * 1000, dMax * 1000));
            }
        }
        return outp.ToArray();
    }
}
'@
$lines = [CarError]::Run((Join-Path $Results "host-UE4SS.log"), (Join-Path $Results "client-UE4SS.log"), $Settle)
$lines | Set-Content -Encoding utf8 (Join-Path $Results "car-error.txt")
$lines | Write-Host
$checks = @($lines | Where-Object { $_ -match "^(PASS|FAIL)  " })
$summary = Join-Path $Results "summary.txt"
if (Test-Path $summary) { $checks | Add-Content -Encoding utf8 $summary }
if (@($checks | Where-Object { $_ -like "FAIL*" }).Count -or -not $checks.Count) { exit 1 } else { exit 0 }
