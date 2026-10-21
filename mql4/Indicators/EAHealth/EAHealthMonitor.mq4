//+------------------------------------------------------------------+
//|                                              EAHealthMonitor.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Free indicator: one table row per Expert Advisor (magic number)  |
//| on the account, plus manual trades and a total: closed trades,   |
//| net result, win rate, profit factor, max drawdown of its realized|
//| result, today's result, open positions and their floating P/L.   |
//| A manual close of an EA's trade stays with that EA. Reads the    |
//| account history only; it never trades.                           |
//| Core: HealthCore.mqh                                             |
//| MT4 edition: the same statistics, panel and inputs; MT4's orders |
//| are read as deals (HealthCore.mqh, HealthLive.mqh).              |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property link      "https://www.allanninal.dev/mql5"
#property version   "1.00"
#property description "Per-EA results on one panel: trades, net, win rate, profit factor, max drawdown, today, open trades, floating P/L."
#property description "Grouped by magic number; manual trades on their own row. Reads the history only, never trades."
#property indicator_chart_window
#property indicator_buffers 0

#include "HealthLive.mqh"
#include "Panel.mqh"

input string InpNames      = "";       // Names: magic=name, comma separated (e.g. 771500=Trend EA,0=Manual)
input bool   InpManual     = true;     // Show manual trades (magic 0)
input bool   InpHideIdle   = false;    // Hide EAs with no trade in the period and nothing open
input ENUM_SD_CORNER InpCorner = SD_TOP_LEFT;   // Panel corner
input int    InpX           = 10;      // Distance from the side, pixels
input int    InpY           = 20;      // Distance from the top or bottom, pixels
input int    InpFontSize    = 9;       // Font size
input color  InpColPanel    = C'22,27,36';      // Panel colour
input color  InpColCell     = C'30,36,48';      // Cell colour
input color  InpColText     = C'232,237,243';   // Text colour
input color  InpColMuted    = C'120,130,145';   // Header colour
input color  InpColPos      = C'38,166,98';     // Positive colour
input color  InpColNeg      = C'226,74,70';     // Negative colour

const string PRODUCT="EA Health Monitor";
const string PREFIX ="EHM_";

EHLive   g_L;
CSDPanel g_panel;
long     g_rows[];                         // magic of each panel row (the last row is the total)
string   g_sig="";
ulong    g_last_ms=0;
bool     g_ready=false;

color Sign(const double v) { return(v>0.005 ? InpColPos : (v<-0.005 ? InpColNeg : InpColText)); }

void Show()
  {
//--- rows: EAs in the order they first traded, manual, then the total
   long rows[];
   ArrayResize(rows,0);
   for(int i=0; i<g_L.b.nst; i++)
     {
      EHStat s=g_L.b.st[i];
      if(s.magic==0 && !InpManual)
         continue;
      if(InpHideIdle && s.n==0 && s.open==0 && s.deals==0)
         continue;
      int k=ArraySize(rows);
      ArrayResize(rows,k+1);
      rows[k]=s.magic;
     }
   string sig="";
   for(int i=0; i<ArraySize(rows); i++)
      sig+=IntegerToString(rows[i])+"|"+EHName(g_L,g_L.b.st[EHStatIdx(g_L.b,rows[i])])+";";
   if(sig!=g_sig)
     {
      string heads[9]={"Trades","Net","Win %","PF","Max DD","Today","Open","Floating","Last deal"},labels[];
      ArrayResize(labels,ArraySize(rows)+1);
      for(int i=0; i<ArraySize(rows); i++)
         labels[i]=EHName(g_L,g_L.b.st[EHStatIdx(g_L.b,rows[i])]);
      labels[ArraySize(rows)]="All";
      g_panel.Layout(heads,labels);
      g_sig=sig;
      ArrayCopy(g_rows,rows);
      ArrayResize(g_rows,ArraySize(rows));
     }
   EHStat tot;
   ZeroMemory(tot);
   int r=0;
   for(; r<ArraySize(g_rows); r++)
     {
      EHStat s=g_L.b.st[EHStatIdx(g_L.b,g_rows[r])];
      string tip=StringFormat("%s (magic %I64d): %d trades, %d won, %d lost; gross profit %s, gross loss %s; expectancy %s per trade",
                              EHName(g_L,s),s.magic,s.n,s.w,s.l,EHMoney(s.gp),EHMoney(s.gl),EHMoney(EHExpectancy(s)))+
                   ". Last deal "+(s.last>0 ? TimeToString((datetime)s.last,TIME_DATE|TIME_MINUTES) : "-");
      Row(r,s,tip);
      tot.n+=s.n; tot.w+=s.w; tot.l+=s.l; tot.gp+=s.gp; tot.gl+=s.gl; tot.net+=s.net; tot.today+=s.today;
      tot.open+=s.open; tot.floating+=s.floating; tot.last=MathMax(tot.last,s.last);
      tot.maxdd=MathMax(tot.maxdd,s.maxdd);
     }
   Row(r,tot,"All rows together. Max DD here is the largest of the rows, not the drawdown of the account.");
   g_panel.SetTitle(StringFormat("%s  (%s)",PRODUCT,AccountInfoString(ACCOUNT_CURRENCY)));
   ChartRedraw();
  }

void Row(const int r,const EHStat &s,const string tip)
  {
   double pf=EHPF(s);
   g_panel.SetCell(r,0,IntegerToString(s.n),InpColText,InpColCell,tip);
   g_panel.SetCell(r,1,EHMoney(s.net,true),Sign(s.net),InpColCell,tip);
   g_panel.SetCell(r,2,s.n>0 ? DoubleToString(EHWinRate(s),0)+"%" : "-",InpColText,InpColCell,tip);
   g_panel.SetCell(r,3,pf==EMPTY_VALUE ? "no loss" : (s.n>0 ? DoubleToString(pf,2) : "-"),InpColText,InpColCell,tip);
   g_panel.SetCell(r,4,s.maxdd>0.005 ? "-"+EHMoney(s.maxdd) : "0.00",s.maxdd>0.005 ? InpColNeg : InpColText,InpColCell,
                   tip+". Max DD: the largest fall of the realized result from its high.");
   g_panel.SetCell(r,5,EHMoney(s.today,true),Sign(s.today),InpColCell,tip);
   g_panel.SetCell(r,6,IntegerToString(s.open),InpColText,InpColCell,tip);
   g_panel.SetCell(r,7,s.open>0 ? EHMoney(s.floating,true) : "-",Sign(s.floating),InpColCell,tip);
   g_panel.SetCell(r,8,EHAgo(s.last),InpColMuted,InpColCell,tip);
  }

void Tick()
  {
   ulong now=EHNowMs();
   if(g_last_ms!=0 && now-g_last_ms<2000)
      return;
   g_last_ms=now;
   EHRefresh(g_L);
   Show();
  }

int OnInit()
  {
   if(InpFontSize<7 || InpFontSize>14)
     {
      Print(PRODUCT,": font size 7-14");
      return(INIT_PARAMETERS_INCORRECT);
     }
   IndicatorShortName(PRODUCT);
   EHLiveInit(g_L,InpNames);
   g_panel.Setup(PREFIX+"t_",PRODUCT,InpCorner,InpX,InpY,InpFontSize,InpColPanel,InpColText,InpColMuted);
   g_panel.SetRowHead("EA");
   g_sig="-";
   g_ready=true;
   EventSetTimer(2);
   Tick();
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_panel.Destroy();
   ObjectsDeleteAll(0,PREFIX);
  }

void OnTimer()
  {
   if(g_ready)
      Tick();
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id==CHARTEVENT_CHART_CHANGE)
      g_panel.ChartResized();
   else
      if(id==CHARTEVENT_OBJECT_CLICK)
        {
         int row,col;
         g_panel.Click(sparam,row,col);            // the collapse button
        }
  }

//--- the full form (MT5 uses the short one): MT4 cannot run a short-form indicator through iCustom
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(g_ready)
      Tick();
   return(rates_total);
  }
//+------------------------------------------------------------------+
