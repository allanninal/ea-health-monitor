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
//| MT4 edition: the same statistics (everything above EHLoadHistory |
//| is the MT5 file unchanged); MT4 keeps orders, not deals, so      |
//| EHLoadHistory turns its orders into deals (see there).           |
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

//--- MT4 keeps orders, not deals. Each buy/sell order becomes an opening deal (its open time and lots) and, once closed,
//--- a closing deal (close time, lots, profit, swap, commission: MT4 books the commission at the close). A partial close
//--- leaves the rest open under a new ticket whose comment is "from #<ticket>": all parts of one order are one position
//--- (the first ticket), so a trade counts when its last part closes, as in MT5. Open orders give their opening deals,
//--- as MT5's history holds the opening deals of open positions. Deals in time order (opening before closing deals in
//--- the same second, else in the order they were read). The history is what the terminal's Account History tab holds.
//--- names[i]: the comment of an EA's opening deal (MT4's own close comments removed), else "".
long EHFromTicket(const string c)
  {
   if(StringFind(c,"from #")!=0)
      return(0);
   return(StringToInteger(StringSubstr(c,6)));
  }

string EHCleanComment(string c)
  {
   if(StringFind(c,"from #")==0 || StringFind(c,"to #")==0 || StringFind(c,"partial close")==0 || StringFind(c,"close hedge")==0)
      return("");
   int k=StringFind(c,"[");                    // "[sl]", "[tp]", "[so]" added when the server closed it
   if(k==0)                                   // MQL4 StringSubstr(c,0,0) returns the whole string
      c="";
   else
      if(k>0)
         c=StringSubstr(c,0,k);
   StringTrimRight(c);
   return(c);
  }

int EHLoadHistory(EHDeal &out[],string &names[])
  {
   ArrayResize(out,0);
   ArrayResize(names,0);
//--- the orders: history first, then the open ones
   int nh=OrdersHistoryTotal(),no=OrdersTotal(),n=0;
   long   tk[],par[],ot[],ct[],mg[];
   double lt[],pf[],sw[],cm[];
   string cmt[];
   ArrayResize(tk,nh+no); ArrayResize(par,nh+no); ArrayResize(ot,nh+no); ArrayResize(ct,nh+no); ArrayResize(mg,nh+no);
   ArrayResize(lt,nh+no); ArrayResize(pf,nh+no); ArrayResize(sw,nh+no); ArrayResize(cm,nh+no); ArrayResize(cmt,nh+no);
   for(int pass=0; pass<2; pass++)
      for(int i=0; i<(pass==0 ? nh : no); i++)
        {
         if(!OrderSelect(i,SELECT_BY_POS,pass==0 ? MODE_HISTORY : MODE_TRADES) || OrderType()>OP_SELL)
            continue;                            // balance, credit, pending orders: not trades
         tk[n]=OrderTicket(); cmt[n]=OrderComment(); par[n]=EHFromTicket(cmt[n]);
         ot[n]=(long)OrderOpenTime(); ct[n]=(pass==0 ? (long)OrderCloseTime() : 0); mg[n]=OrderMagicNumber();
         lt[n]=OrderLots(); pf[n]=OrderProfit(); sw[n]=OrderSwap(); cm[n]=OrderCommission();
         n++;
        }
//--- position of each order: follow "from #" to the first ticket (tickets sorted for the lookup)
   double idx[][2];
   ArrayResize(idx,n);
   for(int i=0; i<n; i++)
     { idx[i][0]=(double)tk[i]; idx[i][1]=i; }
   if(n>1)
      ArraySort(idx);
   long root[];
   ArrayResize(root,n);
   for(int i=0; i<n; i++)
     {
      long r=tk[i],p=par[i];
      for(int guard=0; p!=0 && guard<10000; guard++)
        {
         r=p;
         p=0;
         int lo=0,hi=n-1;                        // binary search for ticket r
         while(lo<=hi)
           {
            int mid=(lo+hi)/2;
            if(idx[mid][0]<(double)r)
               lo=mid+1;
            else
               if(idx[mid][0]>(double)r)
                  hi=mid-1;
               else
                 { p=par[(int)idx[mid][1]]; break; }
           }
        }
      root[i]=r;
     }
//--- the deals, then sorted by time, opening first, then reading order (exact in a double up to 2^20 deals)
   int nd=0;
   EHDeal dl[];
   string dn[];
   double key[][2];
   ArrayResize(dl,2*n); ArrayResize(dn,2*n); ArrayResize(key,2*n);
   for(int i=0; i<n; i++)
      for(int e=0; e<2; e++)
        {
         if(e==1 && ct[i]==0)
            continue;
         dl[nd].time=(e==0 ? ot[i] : ct[i]); dl[nd].pos=root[i]; dl[nd].magic=mg[i];
         dl[nd].entry=(e==0 ? EH_IN : EH_OUT); dl[nd].volume=lt[i];
         dl[nd].profit=(e==0 ? 0 : pf[i]); dl[nd].swap=(e==0 ? 0 : sw[i]); dl[nd].commission=(e==0 ? 0 : cm[i]); dl[nd].fee=0;
         dn[nd]=(e==0 && mg[i]!=0 ? EHCleanComment(cmt[i]) : "");
         key[nd][0]=((double)dl[nd].time*2.0+e)*1048576.0+nd;
         key[nd][1]=nd;
         nd++;
        }
   ArrayResize(key,nd);
   if(nd>1)
      ArraySort(key);
   ArrayResize(out,nd);
   ArrayResize(names,nd);
   for(int i=0; i<nd; i++)
     {
      out[i]=dl[(int)key[i][1]];
      names[i]=dn[(int)key[i][1]];
     }
   return(nd);
  }

#endif
//+------------------------------------------------------------------+
