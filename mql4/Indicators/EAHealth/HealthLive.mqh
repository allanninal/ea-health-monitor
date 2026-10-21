//+------------------------------------------------------------------+
//|                                                   HealthLive.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The live side of EA Health Monitor: the open positions per magic |
//| and the names: the user's list "magic=name,...", else the comment|
//| of the EA's first opening deal, "Manual" for magic 0.            |
//| MT4 edition: MT4 has no deal list to read from where it stopped, |
//| so the book is rebuilt from the orders (HealthCore.mqh) whenever |
//| they change (a trade opened, closed or partly closed); the open  |
//| trades' floating includes their commission (MT4 books it at the  |
//| close); the server clock keeps running while no ticks arrive.    |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef HEALTHLIVE_MQH
#define HEALTHLIVE_MQH

#include "HealthCore.mqh"

struct EHLive
  {
   EHBook b;
   string sig;                          // the orders the book was built from (history count, open tickets and lots)
   long   day;
   long   map_magic[];
   string map_name[];
  };

void EHLiveInit(EHLive &L,const string names)
  {
   EHInit(L.b);
   L.sig=""; L.day=-1;
   ArrayResize(L.map_magic,0);
   ArrayResize(L.map_name,0);
   string items[];
   int n=StringSplit(names,',',items);
   for(int i=0; i<n; i++)
     {
      string kv[];
      if(StringSplit(items[i],'=',kv)!=2)
         continue;
      StringTrimLeft(kv[0]); StringTrimRight(kv[0]); StringTrimLeft(kv[1]); StringTrimRight(kv[1]);
      int k=ArraySize(L.map_magic);
      ArrayResize(L.map_magic,k+1);
      ArrayResize(L.map_name,k+1);
      L.map_magic[k]=StringToInteger(kv[0]);
      L.map_name[k]=kv[1];
     }
  }

string EHMapped(const EHLive &L,const long magic)
  {
   for(int i=0; i<ArraySize(L.map_magic); i++)
      if(L.map_magic[i]==magic)
         return(L.map_name[i]);
   return("");
  }

//--- the server's time now. MQL4 has no TimeTradeServer and TimeCurrent stops between ticks (all weekend): the offset of
//--- the server from GMT is learnt from a fresh tick (a whole half hour within -12 h .. +14 h) and kept
datetime EHServerNow()
  {
   static long off=LONG_MIN;
   if(IsTesting())
      return(TimeCurrent());
   long d=(long)TimeCurrent()-(long)TimeGMT();
   long r=(long)MathRound(d/1800.0)*1800;
   if(MathAbs(d-r)<=120 && r>=-12*3600 && r<=14*3600)
      off=r;
   return(off==LONG_MIN ? TimeCurrent() : (datetime)((long)TimeGMT()+off));
  }

//--- server midnight of today
long EHDayStart()
  {
   MqlDateTime t;
   TimeToStruct(EHServerNow(),t);
   t.hour=0; t.min=0; t.sec=0;
   return((long)StructToTime(t));
  }

//--- bring the book up to date; true when anything changed
bool EHRefresh(EHLive &L)
  {
   long day=EHDayStart();
   string sig=IntegerToString(OrdersHistoryTotal())+"|";
   for(int i=OrdersTotal()-1; i>=0; i--)
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderType()<=OP_SELL)
         sig+=IntegerToString(OrderTicket())+":"+DoubleToString(OrderLots(),2)+",";
   bool restart=(sig!=L.sig || day!=L.day);
   if(restart)
     {
      EHInit(L.b);
      L.sig=sig; L.day=day;
      EHDeal dl[];
      string nm[];
      int n=EHLoadHistory(dl,nm);
      for(int i=0; i<n; i++)
        {
         EHAdd(L.b,dl[i],day);
         if(dl[i].entry==EH_IN && dl[i].magic!=0 && nm[i]!="")
           {
            int k=EHStatIdx(L.b,dl[i].magic);
            if(L.b.st[k].name=="")               // the first comment names it (comments that change per trade do not)
               L.b.st[k].name=nm[i];
           }
        }
     }
   bool chg=restart;
//--- open positions
   for(int i=0; i<L.b.nst; i++)
     { L.b.st[i].open=0; L.b.st[i].floating=0; }
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES) || OrderType()>OP_SELL)
         continue;
      int k=EHStatIdx(L.b,OrderMagicNumber());
      L.b.st[k].open++;
      L.b.st[k].floating+=OrderProfit()+OrderSwap()+OrderCommission();
     }
   return(chg);
  }

string EHName(const EHLive &L,const EHStat &s)
  {
   string m=EHMapped(L,s.magic);
   if(m!="")
      return(m);
   if(s.magic==0)
      return("Manual");
   string c=s.name;
   if(StringLen(c)>14)
      c=StringSubstr(c,0,14);
   return(c=="" ? "#"+IntegerToString(s.magic) : c+" #"+IntegerToString(s.magic));
  }

//--- seconds since a deal as "45m", "3h", "2d" (short, so the panel stays narrow)
string EHAgo(const long t)
  {
   if(t<=0)
      return("-");
   long s=MathMax(0,(long)EHServerNow()-t);
   if(s<3600)
      return(IntegerToString(s/60)+"m");
   if(s<86400*2)
      return(IntegerToString(s/3600)+"h");
   return(IntegerToString(s/86400)+"d");
  }

//--- 1234.5 -> "1,234.50", with a sign when asked
string EHMoney(const double v,const bool sign=false)
  {
   string s=DoubleToString(MathAbs(v),2);
   int dot=StringFind(s,".");
   string ip=StringSubstr(s,0,dot),out="";
   for(int i=StringLen(ip)-1,k=0; i>=0; i--,k++)
      out=(k>0 && k%3==0 ? StringSubstr(ip,i,1)+"," : StringSubstr(ip,i,1))+out;
   string r=out+StringSubstr(s,dot);
   if(v<0 && MathAbs(v)>=0.005)
      return("-"+r);
   return((sign && v>=0.005 ? "+" : "")+r);
  }

//--- "now" in ms: wall clock live, simulated server time in the tester (which runs far faster than real time)
ulong EHNowMs()
  {
   if(IsTesting())
      return((ulong)TimeCurrent()*1000);
   static ulong hi=0;                       // MQL4 has only the 32-bit GetTickCount: count its wraps (every 49.7 days)
   static uint  last=0;
   uint now=GetTickCount();
   if(now<last)
      hi+=((ulong)1<<32);
   last=now;
   return(hi+now);
  }

#endif
//+------------------------------------------------------------------+
