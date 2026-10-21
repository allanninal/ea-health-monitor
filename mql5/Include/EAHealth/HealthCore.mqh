//+------------------------------------------------------------------+
//|                                                   HealthCore.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Per-magic statistics from the account's deal history, used by   |
//| EA Health Monitor. Spec: docs/SPEC.md; tested against            |
//| tests/reference.py.                                              |
//|   A deal belongs to its position, a position to the magic number |
//|   of its opening deal (a manual close of an EA trade stays with  |
//|   the EA). Realized curve = profit+swap+commission+fee per deal; |
//|   max drawdown = largest fall from its running peak (from 0).    |
//|   A trade = a position whose closed volume reached its opened    |
//|   volume; win rate, profit factor and expectancy as usual.      |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#ifndef HEALTHCORE_MQH
#define HEALTHCORE_MQH

#define EH_IN    0
#define EH_OUT   1
#define EH_INOUT 2
#define EH_OUTBY 3
#define EH_EPS   1e-8

struct EHDeal
  {
   long   time;
   long   pos;
   long   magic;
   int    entry;                       // EH_IN / EH_OUT / EH_INOUT / EH_OUTBY
   double volume,profit,swap,commission,fee;
  };

struct EHStat
  {
   long   magic;
   int    n,w,l,deals;
   double gp,gl,net,curve,peak,maxdd,today;
   long   last;                        // time of the latest deal
   //--- live
   int    open;
   double floating;
   string name;                        // from the user's list, else the latest deal comment
  };

struct EHPos
  {
   long   pos;
   long   magic;
   double vol,net;
  };

struct EHBook
  {
   EHStat st[];
   int    nst;
   EHPos  ps[];
   int    nps;
   int    hint;                        // last position slot found (deals of one position come close together)
  };

void EHInit(EHBook &b)
  {
   ArrayResize(b.st,0,16); b.nst=0;
   ArrayResize(b.ps,0,256); b.nps=0; b.hint=0;
  }

int EHStatIdx(EHBook &b,const long magic)
  {
   for(int i=0; i<b.nst; i++)
      if(b.st[i].magic==magic)
         return(i);
   int k=b.nst++;
   ArrayResize(b.st,b.nst,16);
   b.st[k].magic=magic; b.st[k].n=0; b.st[k].w=0; b.st[k].l=0; b.st[k].deals=0;
   b.st[k].gp=0; b.st[k].gl=0; b.st[k].net=0; b.st[k].curve=0; b.st[k].peak=0; b.st[k].maxdd=0; b.st[k].today=0;
   b.st[k].last=0; b.st[k].open=0; b.st[k].floating=0; b.st[k].name="";
   return(k);
  }

int EHPosIdx(EHBook &b,const long pos)
  {
   if(b.hint<b.nps && b.ps[b.hint].pos==pos)
      return(b.hint);
   for(int i=b.nps-1; i>=0; i--)               // recent positions first
      if(b.ps[i].pos==pos)
        { b.hint=i; return(i); }
   return(-1);
  }

//--- one deal, in time order; day_start: the server day start (seconds). Returns the row (stat index) it went to.
int EHAdd(EHBook &b,const EHDeal &d,const long day_start)
  {
   double pnl=d.profit+d.swap+d.commission+d.fee;
   int pi=EHPosIdx(b,d.pos);
   if(d.entry==EH_IN)
     {
      if(pi<0)
        {
         pi=b.nps++;
         ArrayResize(b.ps,b.nps,256);
         b.ps[pi].pos=d.pos; b.ps[pi].magic=d.magic; b.ps[pi].vol=0; b.ps[pi].net=0;
         b.hint=pi;
        }
      b.ps[pi].vol+=d.volume;
     }
   else
      if(pi<0)                                   // the opening deal is not in the history: use this deal's magic
        {
         pi=b.nps++;
         ArrayResize(b.ps,b.nps,256);
         b.ps[pi].pos=d.pos; b.ps[pi].magic=d.magic; b.ps[pi].vol=d.volume; b.ps[pi].net=0;
         b.hint=pi;
        }
   int si=EHStatIdx(b,b.ps[pi].magic);
   b.ps[pi].net+=pnl;
   b.st[si].curve+=pnl;
   b.st[si].peak=MathMax(b.st[si].peak,b.st[si].curve);
   b.st[si].maxdd=MathMax(b.st[si].maxdd,b.st[si].peak-b.st[si].curve);
   b.st[si].net+=pnl;
   b.st[si].deals++;
   if(d.time>=day_start)
      b.st[si].today+=pnl;
   b.st[si].last=MathMax(b.st[si].last,d.time);
   bool closed=false;
   double rest=0;
   if(d.entry==EH_OUT || d.entry==EH_OUTBY)
     {
      b.ps[pi].vol-=d.volume;
      closed=(b.ps[pi].vol<=EH_EPS);
     }
   else
      if(d.entry==EH_INOUT)
        {
         rest=d.volume-b.ps[pi].vol;              // the part beyond the open volume opens the other way
         closed=true;
        }
   if(closed)
     {
      double net=b.ps[pi].net;
      b.st[si].n++;
      if(net>0)
        { b.st[si].w++; b.st[si].gp+=net; }
      else
         if(net<0)
           { b.st[si].l++; b.st[si].gl+=-net; }
      b.ps[pi].vol=(d.entry==EH_INOUT ? MathMax(rest,0.0) : 0.0);
      b.ps[pi].net=0;
      if(b.ps[pi].vol<=EH_EPS)                  // fully closed: forget it, so lookups stay short on long histories
        {
         b.nps--;
         if(pi<b.nps)
            b.ps[pi]=b.ps[b.nps];
         b.hint=0;
        }
     }
   return(si);
  }
double EHWinRate(const EHStat &s)    { return(s.n>0 ? 100.0*s.w/s.n : 0); }
double EHPF(const EHStat &s)         { return(s.gl>0 ? s.gp/s.gl : (s.gp>0 ? EMPTY_VALUE : 0)); }   // EMPTY_VALUE = no losses
double EHExpectancy(const EHStat &s) { return(s.n>0 ? (s.gp-s.gl)/s.n : 0); }

#endif
//+------------------------------------------------------------------+
