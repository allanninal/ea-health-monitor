# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""HealthCore.mqh against tests/reference.py on synthetic deal histories.

    python3 tests/check_core.py write <dir>   # writes deals_<k>.csv (synthetic, seeded)
    python3 tests/check_core.py check <dir>   # compares stats_<k>.csv written by the EAHealthDump script
Seeds: SETS below."""
import csv
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from reference import compute, synth  # noqa: E402

SETS = [dict(seed=1), dict(seed=2, n_pos=2000), dict(seed=3, magics=(0,)), dict(seed=4, n_pos=50),
        dict(seed=5, n_pos=800, magics=(7, 8)), dict(seed=6, n_pos=3000, magics=tuple(range(30)))]
COLS = ["time", "pos", "magic", "entry", "volume", "profit", "swap", "commission", "fee"]


def write(d: Path):
    d.mkdir(parents=True, exist_ok=True)
    for k, kw in enumerate(SETS):
        with open(d / f"deals_{k}.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(COLS)
            for x in synth(**kw):
                w.writerow([x[c] for c in COLS])


def read_deals(p: Path):
    out = []
    for r in csv.DictReader(open(p)):
        out.append(dict(time=int(r["time"]), pos=int(r["pos"]), magic=int(r["magic"]), entry=r["entry"],
                        **{c: float(r[c]) for c in ("volume", "profit", "swap", "commission", "fee")}))
    return out


def close(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def check(d: Path):
    bad = 0
    for k in range(len(SETS)):
        name = f"deals_{k}.csv"
        sp, dp = d / f"stats_{k}.csv", d / name
        if not dp.exists() or not sp.exists():
            print(f"{name}: missing")
            bad += 1
            continue
        ref = compute(read_deals(dp), day_start=0)
        mt = {int(r["magic"]): r for r in csv.DictReader(open(sp))}
        diffs = []
        if set(mt) != set(ref):
            diffs.append(f"magics mt5 {sorted(mt)} ref {sorted(ref)}")
        for m, s in ref.items():
            r = mt.get(m)
            if r is None:
                continue
            for c in ("n", "w", "l", "deals", "last"):
                if int(r[c]) != int(s[c]):
                    diffs.append(f"{m}.{c} {r[c]} vs {s[c]}")
            for c in ("gp", "gl", "net", "curve", "peak", "maxdd", "today"):
                if not close(float(r[c]), s[c]):
                    diffs.append(f"{m}.{c} {r[c]} vs {s[c]}")
        trades = sum(s["n"] for s in ref.values())
        ndeals = sum(s["deals"] for s in ref.values())
        print(f"{name:14} magics {len(ref):3} deals {ndeals:6} trades {trades:5}  {'OK' if not diffs else 'DIFF ' + '; '.join(diffs[:4])}")
        bad += bool(diffs)
    print("ALL PASS" if not bad else f"FAILURES {bad}")
    return bad == 0


if __name__ == "__main__":
    mode, d = sys.argv[1], Path(sys.argv[2])
    sys.exit(0 if (write(d) if mode == "write" else check(d)) in (None, True) else 1)
