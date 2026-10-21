//+------------------------------------------------------------------+
//|                                                        Panel.mqh |
//|                                      Copyright 2026, Allan Niñal |
//|                                  https://www.allanninal.dev/mql5 |
//+------------------------------------------------------------------+
//| A grid panel made of chart objects that all start with one       |
//| prefix: title bar, header row, one row label per row and one     |
//| button per cell. Only cells whose text or colours changed are    |
//| touched. Everything is removed by Destroy() (call it in          |
//| OnDeinit). If the chart refuses objects (e.g. in the tester) the |
//| panel simply stays silent.                                       |
//+------------------------------------------------------------------+
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 (see LICENSE)
#property strict

enum ENUM_SD_CORNER
  {
   SD_TOP_LEFT=0,      // Top left
   SD_TOP_RIGHT=1,     // Top right
   SD_BOTTOM_LEFT=2,   // Bottom left
   SD_BOTTOM_RIGHT=3   // Bottom right
  };

class CSDPanel
  {
private:
   string   m_p;
   long     m_chart;
   int      m_corner,m_ox,m_oy,m_fs;
   bool     m_collapsed,m_ok,m_built;
   int      m_rows,m_cols;
   string   m_title;
   string   m_rowhead;                  // header of the row-label column ("Symbol" unless set)
   string   m_heads[],m_labels[];
   string   m_txt[],m_tip[];
   color    m_fg[],m_bg[];
   color    m_c_panel,m_c_text,m_c_head;
   int      m_lw,m_cw,m_rh,m_pad,m_W,m_H,m_x0,m_y0,m_cwpx,m_chpx;
   bool     Put(const ENUM_OBJECT type,const string name,const int x,const int y,const int w,const int h,
                const string txt,const color fg,const color bg,const bool bold);
   void     Size();
public:
            CSDPanel(): m_rowhead("Symbol"),m_chart(0),m_collapsed(false),m_ok(true),m_built(false),m_rows(0),m_cols(0) {}
   void     Setup(const string prefix,const string title,const int corner,const int ox,const int oy,const int fontsize,
                  const color c_panel,const color c_text,const color c_head);
   void     Layout(const string &heads[],const string &labels[]);
   void     Rebuild();
   void     SetTitle(const string t);
   void     SetRowHead(const string h) { m_rowhead=h; }
   void     SetCell(const int r,const int c,const string txt,const color fg,const color bg,const string tip);
   bool     Click(const string name,int &row,int &col);
   bool     ChartResized();
   void     Destroy();
   string   Prefix() const { return(m_p); }
  };

void CSDPanel::Setup(const string prefix,const string title,const int corner,const int ox,const int oy,
                     const int fontsize,const color c_panel,const color c_text,const color c_head)
  {
   m_p=prefix; m_title=title; m_corner=corner; m_ox=ox; m_oy=oy; m_fs=MathMax(7,fontsize);
   m_c_panel=c_panel; m_c_text=c_text; m_c_head=c_head;
   m_chart=ChartID();
   m_collapsed=false;
   m_ok=true;
  }

void CSDPanel::Size()
  {
   m_rh=m_fs*2+6;
   m_pad=4;
   m_cwpx=(int)ChartGetInteger(m_chart,CHART_WIDTH_IN_PIXELS);
   m_chpx=(int)ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS);
   int maxl=StringLen(m_rowhead);
   for(int i=0; i<m_rows; i++)
      maxl=MathMax(maxl,StringLen(m_labels[i]));
   m_lw=(int)(maxl*m_fs*0.95)+14;
   int maxc=6;
   for(int i=0; i<m_rows*m_cols; i++)
      maxc=MathMax(maxc,StringLen(m_txt[i]));
   for(int i=0; i<m_cols; i++)
      maxc=MathMax(maxc,StringLen(m_heads[i]));
   m_cw=(int)(maxc*m_fs*0.95)+12;
   int body=(m_collapsed ? 0 : m_lw+m_cols*(m_cw+2)+2);
   m_W=m_pad*2+MathMax(body,(int)(StringLen(m_title)*m_fs*1.0)+m_rh*2);
   m_H=m_pad*2+m_rh+(m_collapsed ? 0 : (m_rh+2)*(m_rows+1));
   m_x0=((m_corner==SD_TOP_RIGHT || m_corner==SD_BOTTOM_RIGHT) ? m_cwpx-m_W-m_ox : m_ox);
   m_y0=((m_corner==SD_BOTTOM_LEFT || m_corner==SD_BOTTOM_RIGHT) ? m_chpx-m_H-m_oy : m_oy);
   m_x0=MathMax(0,m_x0);
   m_y0=MathMax(0,m_y0);
  }

bool CSDPanel::Put(const ENUM_OBJECT type,const string name,const int x,const int y,const int w,const int h,
                   const string txt,const color fg,const color bg,const bool bold)
  {
   if(ObjectFind(m_chart,name)<0 && !ObjectCreate(m_chart,name,type,0,0,0))
      return(false);
   ObjectSetInteger(m_chart,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(m_chart,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(m_chart,name,OBJPROP_YDISTANCE,y);
   if(type!=OBJ_LABEL)
     {
      ObjectSetInteger(m_chart,name,OBJPROP_XSIZE,w);
      ObjectSetInteger(m_chart,name,OBJPROP_YSIZE,h);
     }
   ObjectSetInteger(m_chart,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(m_chart,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(m_chart,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(m_chart,name,OBJPROP_BACK,false);
   ObjectSetInteger(m_chart,name,OBJPROP_ZORDER,type==OBJ_BUTTON ? 10 : 1);
   ObjectSetInteger(m_chart,name,OBJPROP_COLOR,fg);
   if(type==OBJ_BUTTON || type==OBJ_RECTANGLE_LABEL)
     {
      ObjectSetInteger(m_chart,name,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,name,OBJPROP_BORDER_COLOR,bg);
      if(type==OBJ_RECTANGLE_LABEL)
        {
         ObjectSetInteger(m_chart,name,OBJPROP_BORDER_TYPE,BORDER_FLAT);
         ObjectSetInteger(m_chart,name,OBJPROP_COLOR,m_c_head);
        }
     }
   if(type!=OBJ_RECTANGLE_LABEL)
     {
      ObjectSetString(m_chart,name,OBJPROP_FONT,bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(m_chart,name,OBJPROP_FONTSIZE,m_fs);
      ObjectSetString(m_chart,name,OBJPROP_TEXT,txt);
     }
   return(true);
  }

//--- (re)create every object from the cached text
void CSDPanel::Rebuild()
  {
   if(!m_ok)
      return;
   ObjectsDeleteAll(m_chart,m_p);
   Size();
   if(!Put(OBJ_RECTANGLE_LABEL,m_p+"bg",m_x0,m_y0,m_W,m_H,"",m_c_text,m_c_panel,false))
     {
      m_ok=false;                            // this chart takes no objects (tester, handle without a chart)
      return;
     }
   Put(OBJ_LABEL,m_p+"title",m_x0+m_pad+4,m_y0+m_pad+m_fs/2,0,0,m_title,m_c_text,0,true);
   Put(OBJ_BUTTON,m_p+"min",m_x0+m_W-m_pad-m_rh,m_y0+m_pad,m_rh,m_rh,m_collapsed ? "+" : "-",m_c_text,m_c_panel,true);
   m_built=true;
   if(m_collapsed)
     {
      ChartRedraw(m_chart);
      return;
     }
   int y=m_y0+m_pad+m_rh+2;
   Put(OBJ_LABEL,m_p+"hs",m_x0+m_pad+6,y+m_fs/2,0,0,m_rowhead,m_c_head,0,true);
   for(int c=0; c<m_cols; c++)
     {
      int x=m_x0+m_pad+m_lw+2+c*(m_cw+2);
      string n=m_p+"h"+IntegerToString(c);
      Put(OBJ_LABEL,n,x+(m_cw-(int)(StringLen(m_heads[c])*m_fs*0.8))/2,y+m_fs/2,0,0,m_heads[c],m_c_head,0,true);
     }
   for(int r=0; r<m_rows; r++)
     {
      int yy=y+(m_rh+2)*(r+1);
      Put(OBJ_BUTTON,m_p+"r"+IntegerToString(r),m_x0+m_pad,yy,m_lw,m_rh,m_labels[r],m_c_text,m_c_panel,true);
      for(int c=0; c<m_cols; c++)
        {
         string n=m_p+"c"+IntegerToString(r)+"_"+IntegerToString(c);
         int i=r*m_cols+c;
         Put(OBJ_BUTTON,n,m_x0+m_pad+m_lw+2+c*(m_cw+2),yy,m_cw,m_rh,m_txt[i],m_fg[i],m_bg[i],true);
         ObjectSetString(m_chart,n,OBJPROP_TOOLTIP,m_tip[i]);
        }
     }
   ChartRedraw(m_chart);
  }

void CSDPanel::Layout(const string &heads[],const string &labels[])
  {
   m_cols=ArraySize(heads);
   m_rows=ArraySize(labels);
   ArrayResize(m_heads,m_cols);
   ArrayResize(m_labels,m_rows);
   ArrayCopy(m_heads,heads);
   ArrayCopy(m_labels,labels);
   int n=m_rows*m_cols;
   ArrayResize(m_txt,n);
   ArrayResize(m_tip,n);
   ArrayResize(m_fg,n);
   ArrayResize(m_bg,n);
   for(int i=0; i<n; i++)
     {
      m_txt[i]="loading";
      m_tip[i]="";
      m_fg[i]=m_c_head;
      m_bg[i]=m_c_panel;
     }
   Rebuild();
  }

void CSDPanel::SetTitle(const string t)
  {
   if(t==m_title)
      return;
   m_title=t;
   if(m_ok && m_built)
      ObjectSetString(m_chart,m_p+"title",OBJPROP_TEXT,t);
  }

void CSDPanel::SetCell(const int r,const int c,const string txt,const color fg,const color bg,const string tip)
  {
   int i=r*m_cols+c;
   if(i<0 || i>=m_rows*m_cols)
      return;
   bool chg=(m_txt[i]!=txt || m_fg[i]!=fg || m_bg[i]!=bg);
   if(!chg && m_tip[i]==tip)
      return;
   m_txt[i]=txt; m_fg[i]=fg; m_bg[i]=bg; m_tip[i]=tip;
   if(!m_ok || !m_built || m_collapsed)
      return;
   string n=m_p+"c"+IntegerToString(r)+"_"+IntegerToString(c);
   if(chg)
     {
      ObjectSetString(m_chart,n,OBJPROP_TEXT,txt);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,fg);
      ObjectSetInteger(m_chart,n,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,n,OBJPROP_BORDER_COLOR,bg);
     }
   ObjectSetString(m_chart,n,OBJPROP_TOOLTIP,tip);
  }

//--- a click on one of our objects: row/col of the cell, (row,-1) for a row label, (-2,0) when handled (collapse)
bool CSDPanel::Click(const string name,int &row,int &col)
  {
   if(StringFind(name,m_p)!=0 || !m_ok)
      return(false);
   string rest=StringSubstr(name,StringLen(m_p));
   ObjectSetInteger(m_chart,name,OBJPROP_STATE,false);
   if(rest=="min")
     {
      m_collapsed=!m_collapsed;
      Rebuild();
      row=-2;
      col=0;
      return(true);
     }
   if(StringGetCharacter(rest,0)=='c')
     {
      string p[];
      if(StringSplit(StringSubstr(rest,1),'_',p)==2)
        {
         row=(int)StringToInteger(p[0]);
         col=(int)StringToInteger(p[1]);
         ChartRedraw(m_chart);
         return(true);
        }
     }
   if(StringGetCharacter(rest,0)=='r')
     {
      row=(int)StringToInteger(StringSubstr(rest,1));
      col=-1;
      ChartRedraw(m_chart);
      return(true);
     }
   return(false);
  }

//--- true (and re-lays out) when the chart size changed and the panel is anchored to a right/bottom corner
bool CSDPanel::ChartResized()
  {
   if(!m_ok || !m_built)
      return(false);
   int w=(int)ChartGetInteger(m_chart,CHART_WIDTH_IN_PIXELS),h=(int)ChartGetInteger(m_chart,CHART_HEIGHT_IN_PIXELS);
   if(w==m_cwpx && h==m_chpx)
      return(false);
   if(m_corner==SD_TOP_LEFT)
     {
      m_cwpx=w;
      m_chpx=h;
      return(false);
     }
   Rebuild();
   return(true);
  }

void CSDPanel::Destroy()
  {
   if(m_p!="")
     {
      ObjectsDeleteAll(m_chart,m_p);
      ChartRedraw(m_chart);
     }
   m_built=false;
  }
//+------------------------------------------------------------------+
