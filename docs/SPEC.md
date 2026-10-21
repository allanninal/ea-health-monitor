# EA Health Monitor: specification

An indicator (read-only, no trading). One core, `mql5/Include/EAHealth/HealthCore.mqh` (MT4: `mql4/Indicators/EAHealth/HealthCore.mqh`),
with a Python twin, `tests/reference.py`, that follows it operation for operation.

## Grouping
- Every deal belongs to its POSITION; a position belongs to the magic number of its opening (IN) deal. A manual close of
  an EA's trade (an out deal with magic 0) therefore stays with that EA. Magic 0 = manual trades.
- Balance, credit and other non-trade deals are ignored.
- MT4 keeps orders, not deals: each buy or sell order becomes an opening deal (open time, lots) and, once closed, a closing
  deal (close time, lots, profit, swap, commission). A partial close leaves the rest open under a new ticket whose comment is
  `from #<ticket>`; all parts of one order are one position.

## Per magic (closed history, in deal time order)
- Realized P/L curve: each trade deal adds profit + swap + commission + fee at its time (entry commissions included).
- Max drawdown: the largest fall of that curve from its running peak (the peak starts at 0), in money.
- A trade = a position whose OUT volume reached its IN volume; its net = the sum over all its deals. A reversing deal
  (IN/OUT) closes the trade and opens the next with the volume beyond.
- N trades, W (net > 0), L (net < 0), win rate W/N, GP (gross profit), GL (gross loss), profit factor GP/GL, expectancy
  (GP - GL) / N.
- Today: realized P/L of the deals since the server day start. Last deal time.

## Live (open positions of that magic)
- Open count; floating = profit + swap (MT4: + commission, which MT4 books at the close).

## Names
- The "Names" input (`magic=name,...`), else the comment of the EA's first opening deal (first 14 characters) plus the magic
  number, else `#<magic>`; magic 0 is "Manual".

## Panel
One row per magic in the order each first traded, then manual (if shown), then a total. The total's max drawdown is the
largest of the rows, not the drawdown of the account.
