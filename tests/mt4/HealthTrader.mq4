//+------------------------------------------------------------------+
//|                                                 HealthTrader.mq4 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test EA (not shipped) for EA Health Monitor MT4, run in the MT4  |
//| Strategy Tester (tester trades only). It trades a seeded random  |
//| mix on every new bar: several magic numbers and "manual" (magic  |
//| 0) orders with comments, stop loss / take profit, partial closes |
//| ("from #" chains), full closes and close-by. Every InpSnapBars   |
//| bars and at the end it writes a snapshot:                        |
//|   <tag>_<SYM>_<TF>_<k>_orders.csv  the raw orders (history in    |
//|        its reading order, then the open ones)                    |
//|   <tag>_<SYM>_<TF>_<k>_stats.csv   its own book (HealthLive.mqh  |
//|        EHRefresh: the whole history)                             |
//| and <tag>_<SYM>_<TF>_snaps.csv (k, now, day start).              |
//| tests/mt4/check_mt4.py turns the raw orders into deals on its    |
//| own and compares everything with tests/reference.py.             |
//| Run it in the MT4 Strategy Tester (open prices), once per symbol |
//| with the inputs in tests/mt4/configs.tsv.                        |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict
#include "..\\..\\Indicators\\EAHealth\\HealthLive.mqh"

input string InpTag      = "eh";
input int    InpSeed     = 1;
input int    InpSnapBars = 400;      // bars between snapshots
input int    InpMaxOpen  = 12;       // most open orders

int      g_k=0,g_bars=0,g_ops=0,g_fail=0;
int      g_err[8];                     // refusals by error code (the most common ones)
int      g_errc[8];
datetime g_last_bar=0;
EHLive   g_all;
string   g_base;
int      g_snap=INVALID_HANDLE;
bool     g_done=false;
long     MAGICS[4]={0,11,22,771500};
string   COMMENTS[4]={"","TrendEA","Grid v2","Swing EA"};
int      LOTS[5]={1,2,3,5,10};             // order sizes in minimum lots (the symbol's own lot rules)

int Rnd(const int n) { return(MathRand()%n); }

void Refused()
  {
   g_fail++;
   int e=GetLastError();
   for(int i=0; i<8; i++)
      if(g_errc[i]==0 || g_err[i]==e)
        { g_err[i]=e; g_errc[i]++; return; }
  }

int OnInit()
  {
   MathSrand(InpSeed);
   g_base=StringFormat("%s_%s_%s",InpTag,_Symbol,StringSubstr(EnumToString((ENUM_TIMEFRAMES)_Period),7));
   EHLiveInit(g_all,"");
   g_snap=FileOpen(g_base+"_snaps.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(g_snap,"k,now,day\n");
   return(INIT_SUCCEEDED);
  }

//--- the indicator through iCustom with its default inputs (it has no buffers: the call runs its OnCalculate, a smoke test;
//--- the MT4 tester gives it no chart, so its panel cannot be read)
void RunIndicator()
  {
   iCustom(NULL,0,"EAHealth\\EAHealthMonitor",0,0);
  }

void Trade()
  {
   int r=Rnd(100);
   RefreshRates();
   if(r<35 && OrdersTotal()<InpMaxOpen)
     {
      int m=Rnd(4),type=Rnd(2);
      double lots=MarketInfo(_Symbol,MODE_MINLOT)*LOTS[Rnd(5)],price=(type==OP_BUY ? Ask : Bid),sl=0,tp=0;
      if(Rnd(10)<4)
        {
         double d=(100+Rnd(400))*_Point;      // 100-500 points: some trades end at the stop or the target
         sl=NormalizeDouble(type==OP_BUY ? price-d : price+d,_Digits);
         tp=NormalizeDouble(type==OP_BUY ? price+d : price-d,_Digits);
        }
      g_ops++;
      if(OrderSend(_Symbol,type,lots,price,50,sl,tp,COMMENTS[m],(int)MAGICS[m],0,clrNONE)<0)
         Refused();
      return;
     }
   int n=OrdersTotal();
   if(n==0)
      return;
   if(!OrderSelect(Rnd(n),SELECT_BY_POS,MODE_TRADES) || OrderType()>OP_SELL)
      return;
   int    tk=OrderTicket(),type=OrderType();
   double lots=OrderLots(),price=(type==OP_BUY ? Bid : Ask);
   double mn=MarketInfo(_Symbol,MODE_MINLOT),st=MarketInfo(_Symbol,MODE_LOTSTEP);
   double half=MathFloor(lots/2.0/st+1e-9)*st;
   if(r<60 && half>=mn-1e-9)                 // partial close: half, rounded down to the lot step
     {
      g_ops++;
      if(!OrderClose(tk,NormalizeDouble(half,2),price,50,clrNONE))
         Refused();
     }
   else
      if(r<80)
        {
         g_ops++;
         if(!OrderClose(tk,lots,price,50,clrNONE))
            Refused();
        }
      else
         if(r<88)                               // close by an opposite order
            for(int i=0; i<n; i++)
               if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderType()<=OP_SELL && OrderType()!=type)
                 {
                  g_ops++;
                  if(!OrderCloseBy(tk,OrderTicket(),clrNONE))
                     Refused();
                  break;
                 }
  }

void WriteOrders(const string name)
  {
   int f=FileOpen(name,FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,"pool,ticket,type,open_time,close_time,magic,lots,profit,swap,commission,comment\n");
   for(int pass=0; pass<2; pass++)
     {
      int n=(pass==0 ? OrdersHistoryTotal() : OrdersTotal());
      for(int i=0; i<n; i++)
         if(OrderSelect(i,SELECT_BY_POS,pass==0 ? MODE_HISTORY : MODE_TRADES))
           {
            string c=OrderComment();
            StringReplace(c,",",";");
            FileWriteString(f,StringFormat("%s,%d,%d,%I64d,%I64d,%d,%.2f,%.17g,%.17g,%.17g,%s\n",pass==0 ? "history" : "open",
                            OrderTicket(),OrderType(),(long)OrderOpenTime(),pass==0 ? (long)OrderCloseTime() : 0,
                            OrderMagicNumber(),OrderLots(),OrderProfit(),OrderSwap(),OrderCommission(),c));
           }
     }
   FileClose(f);
  }

void WriteBook(const int f,const string book,EHLive &L)
  {
   for(int i=0; i<L.b.nst; i++)
     {
      EHStat s=L.b.st[i];
      string nm=EHName(L,s);
      StringReplace(nm,",",";");
      FileWriteString(f,StringFormat("%s,%I64d,%d,%d,%d,%d,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%I64d,%d,%.17g,%s\n",book,
                      s.magic,s.n,s.w,s.l,s.deals,s.gp,s.gl,s.net,s.curve,s.peak,s.maxdd,s.today,s.last,s.open,s.floating,nm));
     }
  }

void Snapshot()
  {
   RunIndicator();
   EHRefresh(g_all);
   string b=StringFormat("%s_%d",g_base,g_k);
   WriteOrders(b+"_orders.csv");
   int f=FileOpen(b+"_stats.csv",FILE_WRITE|FILE_TXT|FILE_ANSI);
   FileWriteString(f,"book,magic,n,w,l,deals,gp,gl,net,curve,peak,maxdd,today,last,open,floating,name\n");
   WriteBook(f,"all",g_all);
   FileClose(f);
   FileWriteString(g_snap,StringFormat("%d,%I64d,%I64d\n",g_k,(long)EHServerNow(),g_all.day));
   g_k++;
  }

void OnTick()
  {
   datetime bt=iTime(NULL,0,0);
   if(bt==g_last_bar)
      return;
   g_last_bar=bt;
   g_bars++;
   Trade();
   if(g_bars%InpSnapBars==0)
      Snapshot();
  }

void Finish()
  {
   if(g_done)
      return;
   g_done=true;
   Snapshot();
   FileClose(g_snap);
   string why="";
   for(int i=0; i<8 && g_errc[i]>0; i++)
      why+=StringFormat(" %d x%d",g_err[i],g_errc[i]);
   PrintFormat("Dump4 %s.csv: %d bars, %d trade operations (%d refused:%s), %d snapshots, history %d orders, open %d",
               g_base,g_bars,g_ops,g_fail,why,g_k,OrdersHistoryTotal(),OrdersTotal());
  }

double OnTester()
  {
   Finish();
   return(0.0);
  }

void OnDeinit(const int reason)
  {
   Finish();
  }
//+------------------------------------------------------------------+
