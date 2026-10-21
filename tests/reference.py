# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""Python twin of mql5/Include/EAHealth/HealthCore.mqh: per-magic statistics from a deal history (docs/SPEC.md),
operation for operation, so MT5's output can be compared (tests/check_core.py).

    from reference import compute, synth
    deals = synth(seed=1)              # random hedging/netting-like history with partial and manual closes
    stats = compute(deals, day_start=0)
Deal: dict(time, pos, magic, entry 'in'|'out'|'inout'|'outby', volume, profit, swap, commission, fee)."""
import random

EPS = 1e-8


def compute(deals, day_start=0):
    pos = {}                                    # pos id -> [magic, open volume, net so far]
    st = {}

    def S(m):
        if m not in st:
            st[m] = dict(n=0, w=0, l=0, gp=0.0, gl=0.0, net=0.0, curve=0.0, peak=0.0, maxdd=0.0, today=0.0,
                         last=0, deals=0)
        return st[m]

    for d in deals:
        pnl = d["profit"] + d["swap"] + d["commission"] + d["fee"]
        p = pos.get(d["pos"])
        if d["entry"] == "in":
            if p is None:
                p = pos[d["pos"]] = [d["magic"], 0.0, 0.0]
            p[1] += d["volume"]
        elif p is None:                          # opening deal not in the history: use this deal's magic
            p = pos[d["pos"]] = [d["magic"], d["volume"], 0.0]
        m = p[0]
        s = S(m)
        p[2] += pnl
        s["curve"] += pnl
        s["peak"] = max(s["peak"], s["curve"])
        s["maxdd"] = max(s["maxdd"], s["peak"] - s["curve"])
        s["net"] += pnl
        s["deals"] += 1
        if d["time"] >= day_start:
            s["today"] += pnl
        s["last"] = max(s["last"], d["time"])
        closed = False
        if d["entry"] in ("out", "outby"):
            p[1] -= d["volume"]
            closed = p[1] <= EPS
        elif d["entry"] == "inout":
            rest = d["volume"] - p[1]               # the part beyond the open volume opens the other way
            closed = True
        if closed:
            s["n"] += 1
            if p[2] > 0:
                s["w"] += 1
                s["gp"] += p[2]
            elif p[2] < 0:
                s["l"] += 1
                s["gl"] += -p[2]
            if d["entry"] == "inout":
                p[1], p[2] = max(rest, 0.0), 0.0
            else:
                p[1], p[2] = 0.0, 0.0
            if p[1] <= EPS:
                del pos[d["pos"]]                    # fully closed: forgotten (as HealthCore.mqh)
    return st


def synth(seed=1, n_pos=400, magics=(0, 11, 22, 771500, 123456)):
    """Deals in time order: each position opens (with commission), may be closed in 1-3 parts, sometimes by hand
    (out deal magic 0), sometimes reversed (inout), some stay open."""
    rnd = random.Random(seed)
    ev = []
    t0 = 1_700_000_000
    for i in range(n_pos):
        m = rnd.choice(magics)
        t = t0 + rnd.randint(0, 3_000_000)
        vol = round(rnd.choice([0.01, 0.02, 0.05, 0.1, 0.3, 1.0]), 2)
        ev.append(dict(time=t, pos=1000 + i, magic=m, entry="in", volume=vol, profit=0.0, swap=0.0,
                       commission=-round(vol * 3.5, 2), fee=0.0))
        if rnd.random() < 0.1:
            continue                                         # still open
        parts = rnd.choice([1, 1, 1, 2, 3]) if vol >= 0.03 else 1
        left = vol
        for k in range(parts):
            t += rnd.randint(60, 200_000)
            v = left if k == parts - 1 else round(left / 2, 2)
            left = round(left - v, 2)
            kind = "out"
            if k == parts - 1 and rnd.random() < 0.05:
                kind = "inout"
                v = round(v + rnd.choice([0.01, 0.1]), 2)
            elif rnd.random() < 0.03:
                kind = "outby"
            ev.append(dict(time=t, pos=1000 + i, magic=0 if (m and rnd.random() < 0.15) else m, entry=kind,
                           volume=v, profit=round(rnd.gauss(0.5, 30) * v * 10, 2),
                           swap=round(rnd.gauss(0, 1), 2) if rnd.random() < 0.4 else 0.0,
                           commission=-round(v * 3.5, 2), fee=-0.05 if rnd.random() < 0.05 else 0.0))
    ev.sort(key=lambda d: (d["time"], d["pos"]))
    return ev
