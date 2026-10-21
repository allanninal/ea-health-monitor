//+------------------------------------------------------------------+
//|                                                 EAHealthDump.mq5 |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| Test tool (read-only). Feeds the synthetic deal lists that       |
//| tests/check_core.py wrote (Common\Files\ehtest\deals_<n>.csv)    |
//| through HealthCore.mqh and writes the statistics per magic to    |
//| Common\Files\ehtest\stats_<n>.csv for the Python comparison.     |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property copyright "Copyright 2026, Allan Niñal <https://www.allanninal.dev/mql5>"
#property version   "1.00"
#property script_show_inputs
#include <EAHealth/HealthCore.mqh>

input int    InpFiles   = 6;          // deals_0 .. deals_<n-1>
input long   InpDay     = 0;          // day start (seconds)
input string InpSuffix  = "";         // added to the stats file names
input bool   InpCloseWhenDone = false;

int Entry(const string s) { return(s=="in" ? EH_IN : (s=="out" ? EH_OUT : (s=="inout" ? EH_INOUT : EH_OUTBY))); }

void WriteStats(const EHBook &b,const string name)
  {
   int f=FileOpen("ehtest\\"+name,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   FileWriteString(f,"magic,n,w,l,deals,gp,gl,net,curve,peak,maxdd,today,last\n");
   for(int i=0; i<b.nst; i++)
      FileWriteString(f,StringFormat("%I64d,%d,%d,%d,%d,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%.17g,%I64d\n",b.st[i].magic,b.st[i].n,
                      b.st[i].w,b.st[i].l,b.st[i].deals,b.st[i].gp,b.st[i].gl,b.st[i].net,b.st[i].curve,b.st[i].peak,
                      b.st[i].maxdd,b.st[i].today,b.st[i].last));
   FileClose(f);
  }

void OnStart()
  {
   for(int k=0; k<InpFiles && !IsStopped(); k++)
     {
      int f=FileOpen(StringFormat("ehtest\\deals_%d.csv",k),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(f==INVALID_HANDLE)
        { PrintFormat("EAHealthDump: deals_%d.csv missing",k); continue; }
      FileReadString(f);                         // header
      EHBook b;
      EHInit(b);
      int n=0;
      while(!FileIsEnding(f))
        {
         string line=FileReadString(f);
         string v[];
         if(StringSplit(line,',',v)<9)
            continue;
         EHDeal d;
         d.time=StringToInteger(v[0]); d.pos=StringToInteger(v[1]); d.magic=StringToInteger(v[2]); d.entry=Entry(v[3]);
         d.volume=StringToDouble(v[4]); d.profit=StringToDouble(v[5]); d.swap=StringToDouble(v[6]);
         d.commission=StringToDouble(v[7]); d.fee=StringToDouble(v[8]);
         EHAdd(b,d,InpDay);
         n++;
        }
      FileClose(f);
      WriteStats(b,StringFormat("stats_%d%s.csv",k,InpSuffix));
      PrintFormat("EAHealthDump: deals_%d: %d deals, %d magics",k,n,b.nst);
     }
   int h=FileOpen("ehtest\\DONE.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
   FileWriteString(h,"DONE\n");
   FileClose(h);
   if(InpCloseWhenDone)
      TerminalClose(0);
  }
//+------------------------------------------------------------------+
