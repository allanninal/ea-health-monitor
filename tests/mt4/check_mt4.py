# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
"""EA Health Monitor MT4 against tests/reference.py, from the snapshots of tests/mt4/HealthTrader.mq4.

    python3 tests/mt4/check_mt4.py <folder with the snapshot files>

For every snapshot: the raw MT4 orders are turned into deals HERE, independently of HealthCore.mqh's EHLoadHistory
(each buy/sell order an opening deal at its open time and lots, a closed one also a closing deal with its profit, swap
and commission; the parts of a partly closed order, linked by "from #<ticket>" comments, are one position; time order,
opening deals first in a second, then reading order), then reference.compute gives the statistics per magic for the
whole history. Compared with _stats.csv, the test EA's own book (HealthLive.mqh EHRefresh): every statistic, open trades,
floating (profit + swap + commission of the open orders) and the row name.
The MT4 tester gives an indicator run through iCustom no chart, so the panel itself cannot be read there; the book is
what the panel shows."""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reference import compute  # noqa: E402

FL = ("gp", "gl", "net", "curve", "peak", "maxdd", "today")


def close(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b))


def clean(c):
    if c.startswith(("from #", "to #", "partial close", "close hedge")):
        return ""
    return c.split("[")[0].rstrip()


def deals_of(orders):
    """orders: rows of _orders.csv (file order). Returns deals and the comment of each opening deal (EA orders)."""
    od = [o for o in orders if int(o["type"]) <= 1]
    # "from #43", also "from #43[sl]" when the rest was closed by the server: the leading digits (as StringToInteger)
    par = {int(o["ticket"]): (int(re.match(r"\d*", o["comment"][6:])[0] or 0) if o["comment"].startswith("from #") else 0)
           for o in od}
    out = []
    for o in od:
        r, p = int(o["ticket"]), par[int(o["ticket"])]
        while p:
            r, p = p, par.get(p, 0)
        mg, lots = int(o["magic"]), float(o["lots"])
        out.append((int(o["open_time"]), 0, len(out), dict(time=int(o["open_time"]), pos=r, magic=mg, entry="in", volume=lots,
                    profit=0.0, swap=0.0, commission=0.0, fee=0.0), clean(o["comment"]) if mg else ""))
        if int(o["close_time"]):
            out.append((int(o["close_time"]), 1, len(out), dict(time=int(o["close_time"]), pos=r, magic=mg, entry="out",
                        volume=lots, profit=float(o["profit"]), swap=float(o["swap"]), commission=float(o["commission"]),
                        fee=0.0), ""))
    out.sort(key=lambda x: (x[0], x[1], x[2]))
    return [x[3] for x in out], [x[4] for x in out]


def check_snapshot(base: Path, day):
    orders = list(csv.DictReader(open(f"{base}_orders.csv")))
    deals, names = deals_of(orders)
    opened = {}
    for o in orders:
        if o["close_time"] == "0" and int(o["type"]) <= 1:
            x = opened.setdefault(int(o["magic"]), [0, 0.0])
            x[0] += 1
            x[1] += float(o["profit"]) + float(o["swap"]) + float(o["commission"])
    first = {}
    for d, nm in zip(deals, names):
        if d["entry"] == "in" and d["magic"] and nm and d["magic"] not in first:
            first[d["magic"]] = nm
    mt = {}
    for r in csv.DictReader(open(f"{base}_stats.csv")):
        mt.setdefault(r["book"], []).append(r)
    probs = []
    books = {}
    for book in ("all",):
        ref = compute(deals, day_start=day)
        for m, s in ref.items():
            s["open"], s["floating"] = opened.get(m, [0, 0.0])
            nm = first.get(m, "")
            s["name"] = "Manual" if m == 0 else (f"{nm[:14]} #{m}" if nm else f"#{m}")
        books[book] = ref
        rows = mt.get(book, [])
        if [int(r["magic"]) for r in rows] != list(ref):
            probs.append(f"{book}: magics/order {[r['magic'] for r in rows]} vs {list(ref)}")
            continue
        for r in rows:
            s = ref[int(r["magic"])]
            for c in ("n", "w", "l", "deals", "last", "open"):
                if int(r[c]) != int(s[c]):
                    probs.append(f"{book} {r['magic']}.{c} {r[c]} vs {s[c]}")
            for c in FL + ("floating",):
                if not close(float(r[c]), s[c]):
                    probs.append(f"{book} {r['magic']}.{c} {r[c]} vs {s[c]}")
            if r["name"] != s["name"].replace(",", ";"):
                probs.append(f"{book} {r['magic']}.name '{r['name']}' vs '{s['name']}'")
    ref = books["all"]
    trades = sum(s["n"] for s in ref.values())
    return probs, len(orders), trades, len(ref)


def main(root: Path) -> bool:
    allok, snaps, trades_last = True, 0, 0
    for sf in sorted(root.glob("*_snaps.csv")):
        stem = sf.name[:-len("_snaps.csv")]
        bad_here, last = 0, None
        for r in csv.DictReader(open(sf)):
            probs, no, nt, nm = check_snapshot(root / f"{stem}_{r['k']}", int(r["day"]))
            snaps += 1
            bad_here += bool(probs)
            last = (no, nt, nm)
            if probs:
                print(f"FAIL {stem} snapshot {r['k']}: " + "; ".join(probs[:5]))
        allok &= bad_here == 0
        if last:
            trades_last += last[1]
            print(("PASS " if not bad_here else "FAIL ") + f"{stem:28} snapshots ok {snaps_of(sf) - bad_here}/{snaps_of(sf)}  "
                  f"final: {last[0]} orders, {last[1]} trades, {last[2]} rows")
    print(f"\n{'ALL PASS' if allok and snaps else 'FAILURES'} ({snaps} snapshots, "
          f"{trades_last} trades in the final snapshots)")
    return bool(allok and snaps)


def snaps_of(sf):
    return sum(1 for _ in csv.DictReader(open(sf)))


if __name__ == "__main__":
    sys.exit(0 if main(Path(sys.argv[1])) else 1)
