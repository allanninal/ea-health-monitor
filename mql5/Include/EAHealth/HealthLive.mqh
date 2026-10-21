//+------------------------------------------------------------------+
//|                                                   HealthLive.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| The live side of EA Health Monitor: reads only the deals added   |
//| since the last refresh (a new day or a shorter history starts    |
//| again), the open positions per magic, and the names: the user's  |
//| list "magic=name,...", else the comment of the EA's first        |
//| opening deal, "Manual" for magic 0.                              |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef HEALTHLIVE_MQH
#define HEALTHLIVE_MQH

#include "HealthCore.mqh"

struct EHLive
  {
   EHBook b;
   int    done;                         // history deals processed
   ulong  last_ticket;                  // ticket of deal done-1 (older deals synced in later move it: start again)
   long   day;
   long   map_magic[];
   string map_name[];
  };

void EHLiveInit(EHLive &L,const string names)
  {
   EHInit(L.b);
   L.done=0; L.day=-1; L.last_ticket=0;
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

//--- server midnight of today
long EHDayStart()
  {
   MqlDateTime t;
   TimeToStruct(TimeTradeServer(),t);
   t.hour=0; t.min=0; t.sec=0;
   return((long)StructToTime(t));
  }

//--- bring the book up to date; true when anything changed
bool EHRefresh(EHLive &L)
  {
   long day=EHDayStart();
   if(!HistorySelect(0,TimeCurrent()+86400))
      return(false);
   int n=HistoryDealsTotal();
   bool restart=(n<L.done || day!=L.day || (L.done>0 && HistoryDealGetTicket(L.done-1)!=L.last_ticket));
   if(restart)
     {
      EHInit(L.b);
      L.done=0; L.day=day;
     }
   bool chg=restart;
   for(int i=L.done; i<n; i++)
     {
      ulong t=HistoryDealGetTicket(i);
      if(t==0)
         continue;
      long type=HistoryDealGetInteger(t,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL)
         continue;
      long en=HistoryDealGetInteger(t,DEAL_ENTRY);
      EHDeal d;
      d.time=HistoryDealGetInteger(t,DEAL_TIME);
      d.pos=HistoryDealGetInteger(t,DEAL_POSITION_ID);
      d.magic=HistoryDealGetInteger(t,DEAL_MAGIC);
      d.entry=(en==DEAL_ENTRY_IN ? EH_IN : (en==DEAL_ENTRY_OUT ? EH_OUT : (en==DEAL_ENTRY_INOUT ? EH_INOUT : EH_OUTBY)));
      d.volume=HistoryDealGetDouble(t,DEAL_VOLUME);
      d.profit=HistoryDealGetDouble(t,DEAL_PROFIT);
      d.swap=HistoryDealGetDouble(t,DEAL_SWAP);
      d.commission=HistoryDealGetDouble(t,DEAL_COMMISSION);
      d.fee=HistoryDealGetDouble(t,DEAL_FEE);
      EHAdd(L.b,d,day);
      if(d.entry==EH_IN && d.magic!=0)
        {
         string cm=HistoryDealGetString(t,DEAL_COMMENT);
         int k=EHStatIdx(L.b,d.magic);
         if(cm!="" && L.b.st[k].name=="")       // the first comment names it (comments that change per trade do not)
            L.b.st[k].name=cm;
        }
      chg=true;
     }
   L.done=n;
   L.last_ticket=(n>0 ? HistoryDealGetTicket(n-1) : 0);
//--- open positions
   for(int i=0; i<L.b.nst; i++)
     { L.b.st[i].open=0; L.b.st[i].floating=0; }
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0)
         continue;
      int k=EHStatIdx(L.b,PositionGetInteger(POSITION_MAGIC));
      L.b.st[k].open++;
      L.b.st[k].floating+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
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
   long s=MathMax(0,(long)TimeTradeServer()-t);
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
   if(MQLInfoInteger(MQL_TESTER))
      return((ulong)TimeCurrent()*1000);
   return(GetTickCount64());
  }

#endif
//+------------------------------------------------------------------+
