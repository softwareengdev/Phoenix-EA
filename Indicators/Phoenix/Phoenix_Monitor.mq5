//+------------------------------------------------------------------+
//|                                           Phoenix_Monitor.mq5    |
//|                    PHOENIX EA — Dashboard & Monitoring Panel       |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Phoenix Trading Systems"
#property link        "https://github.com/softwareengdev/Phoenix-EA"
#property version     "1.00"
#property description "PHOENIX Monitoring Dashboard"
#property description "Displays real-time EA status, P&L, strategy metrics"
#property indicator_chart_window
#property indicator_plots 0

#include <Phoenix\Core\Defines.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input int      InpDashX          = 10;        // Dashboard X position
input int      InpDashY          = 30;        // Dashboard Y position
input int      InpWidth          = 380;       // Dashboard width
input color    InpBgColor        = C'20,20,30';  // Background color
input color    InpTextColor      = clrWhite;     // Text color
input color    InpProfitColor    = clrLime;      // Profit color
input color    InpLossColor      = clrOrangeRed; // Loss color
input color    InpHeaderColor    = clrGold;      // Header color
input int      InpFontSize       = 9;            // Font size

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
string g_prefix = "PHX_DASH_";
int    g_lineHeight = 16;
int    g_currentY = 0;

//+------------------------------------------------------------------+
//| Create text label                                                 |
//+------------------------------------------------------------------+
void CreateLabel(const string name, int x, int y, const string text,
                 color clr = clrWhite, int fontSize = 9, string font = "Consolas")
{
   string fullName = g_prefix + name;
   
   if(ObjectFind(0, fullName) < 0)
   {
      ObjectCreate(0, fullName, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, fullName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, fullName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, fullName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, fullName, OBJPROP_HIDDEN, true);
   }
   
   ObjectSetInteger(0, fullName, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, fullName, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, fullName, OBJPROP_TEXT, text);
   ObjectSetString(0, fullName, OBJPROP_FONT, font);
   ObjectSetInteger(0, fullName, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, fullName, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Create background rectangle                                       |
//+------------------------------------------------------------------+
void CreateBackground(int x, int y, int width, int height, color bgColor)
{
   string name = g_prefix + "BG";
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrDarkSlateGray);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
}

//+------------------------------------------------------------------+
//| Draw a horizontal line separator                                  |
//+------------------------------------------------------------------+
void DrawSeparator(const string id, int y)
{
   CreateLabel("sep_" + id, InpDashX + 5, y, 
               "────────────────────────────────────────────",
               clrDarkSlateGray, InpFontSize - 1);
}

//+------------------------------------------------------------------+
//| Get Phoenix positions info                                        |
//+------------------------------------------------------------------+
void GetPhoenixStats(int &totalPos, double &totalProfit, double &totalLots,
                     int stratCounts[], double stratProfits[])
{
   totalPos = 0;
   totalProfit = 0;
   totalLots = 0;
   ArrayInitialize(stratCounts, 0);
   ArrayInitialize(stratProfits, 0);
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;
      
      totalPos++;
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      totalProfit += profit;
      totalLots += PositionGetDouble(POSITION_VOLUME);
      
      int strat = (int)GET_STRATEGY_FROM_MAGIC(magic);
      if(strat >= 0 && strat < MAX_STRATEGIES)
      {
         stratCounts[strat]++;
         stratProfits[strat] += profit;
      }
   }
}

//+------------------------------------------------------------------+
//| Get today's closed P&L                                            |
//+------------------------------------------------------------------+
double GetTodayPnL()
{
   double pnl = 0;
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   HistorySelect(today, TimeCurrent());
   
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
      
      pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
           + HistoryDealGetDouble(ticket, DEAL_SWAP)
           + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return pnl;
}

//+------------------------------------------------------------------+
//| Update dashboard                                                  |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int y = InpDashY;
   int x = InpDashX + 10;
   int xVal = InpDashX + 200;
   
   //--- Get data
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double marginLevel = (margin > 0) ? (equity / margin * 100) : 0;
   
   int totalPos = 0;
   double floatingPnl = 0, totalLots = 0;
   int stratCounts[MAX_STRATEGIES];
   double stratProfits[MAX_STRATEGIES];
   ArrayResize(stratCounts, MAX_STRATEGIES);
   ArrayResize(stratProfits, MAX_STRATEGIES);
   GetPhoenixStats(totalPos, floatingPnl, totalLots, stratCounts, stratProfits);
   
   double todayPnl = GetTodayPnL();
   double totalPnl = todayPnl + floatingPnl;
   
   // Calculate drawdown
   double peakBalance = MathMax(balance, equity);
   
   //--- Background
   CreateBackground(InpDashX, InpDashY, InpWidth, 420, InpBgColor);
   
   //--- Header
   CreateLabel("title", x, y, "   PHOENIX EA v" + PHOENIX_VERSION, InpHeaderColor, InpFontSize + 2, "Consolas Bold");
   y += g_lineHeight + 8;
   DrawSeparator("h1", y);
   y += g_lineHeight;
   
   //--- Account Info
   CreateLabel("lbl_bal", x, y, "Balance:", InpTextColor, InpFontSize);
   CreateLabel("val_bal", xVal, y, StringFormat("%.2f %s", balance, AccountInfoString(ACCOUNT_CURRENCY)), InpTextColor, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_eq", x, y, "Equity:", InpTextColor, InpFontSize);
   CreateLabel("val_eq", xVal, y, StringFormat("%.2f", equity), 
               equity >= balance ? InpProfitColor : InpLossColor, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_margin", x, y, "Free Margin:", InpTextColor, InpFontSize);
   CreateLabel("val_margin", xVal, y, StringFormat("%.2f (%.0f%%)", freeMargin, marginLevel), InpTextColor, InpFontSize);
   y += g_lineHeight;
   
   DrawSeparator("h2", y);
   y += g_lineHeight;
   
   //--- P&L Section
   CreateLabel("lbl_today", x, y, "Today P&L:", InpTextColor, InpFontSize);
   CreateLabel("val_today", xVal, y, StringFormat("%+.2f", todayPnl),
               todayPnl >= 0 ? InpProfitColor : InpLossColor, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_float", x, y, "Floating P&L:", InpTextColor, InpFontSize);
   CreateLabel("val_float", xVal, y, StringFormat("%+.2f", floatingPnl),
               floatingPnl >= 0 ? InpProfitColor : InpLossColor, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_total", x, y, "Total P&L:", InpTextColor, InpFontSize);
   CreateLabel("val_total", xVal, y, StringFormat("%+.2f", totalPnl),
               totalPnl >= 0 ? InpProfitColor : InpLossColor, InpFontSize + 1);
   y += g_lineHeight;
   
   DrawSeparator("h3", y);
   y += g_lineHeight;
   
   //--- Positions Section
   CreateLabel("lbl_pos", x, y, "Open Positions:", InpTextColor, InpFontSize);
   CreateLabel("val_pos", xVal, y, StringFormat("%d (%.2f lots)", totalPos, totalLots), InpTextColor, InpFontSize);
   y += g_lineHeight;
   
   //--- Strategy breakdown
   string stratNames[] = {"Trend", "MeanRev", "Breakout", "Scalper", "Hybrid"};
   for(int s = 0; s < MathMin(4, MAX_STRATEGIES); s++)
   {
      if(stratCounts[s] > 0 || true)
      {
         color sColor = (stratProfits[s] >= 0) ? InpProfitColor : InpLossColor;
         CreateLabel("lbl_s" + IntegerToString(s), x + 10, y, 
                     StringFormat("  %s:", stratNames[s]), clrDarkGray, InpFontSize);
         CreateLabel("val_s" + IntegerToString(s), xVal, y,
                     StringFormat("%d pos  %+.2f", stratCounts[s], stratProfits[s]),
                     sColor, InpFontSize);
         y += g_lineHeight;
      }
   }
   
   DrawSeparator("h4", y);
   y += g_lineHeight;
   
   //--- System Status
   MqlDateTime dt;
   TimeCurrent(dt);
   string sessionStr = "N/A";
   int hour = dt.hour;
   if(hour >= 12 && hour < 16) sessionStr = "LONDON-NY OVERLAP";
   else if(hour >= 7 && hour < 16) sessionStr = "LONDON";
   else if(hour >= 12 && hour < 21) sessionStr = "NEW YORK";
   else if(hour >= 0 && hour < 9) sessionStr = "TOKYO";
   else sessionStr = "OFF-HOURS";
   
   CreateLabel("lbl_session", x, y, "Session:", InpTextColor, InpFontSize);
   CreateLabel("val_session", xVal, y, sessionStr, clrCyan, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_server", x, y, "Server Time:", InpTextColor, InpFontSize);
   CreateLabel("val_server", xVal, y, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), InpTextColor, InpFontSize);
   y += g_lineHeight;
   
   CreateLabel("lbl_spread", x, y, "Spread " + _Symbol + ":", InpTextColor, InpFontSize);
   double spread = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   CreateLabel("val_spread", xVal, y, StringFormat("%.1f pts", spread), 
               spread > 20 ? InpLossColor : InpTextColor, InpFontSize);
   y += g_lineHeight;
   
   DrawSeparator("h5", y);
   y += g_lineHeight;
   
   //--- Footer
   CreateLabel("footer", x, y, "  Phoenix Trading Systems 2026", clrDarkGray, InpFontSize - 1);
   
   //--- Resize background
   CreateBackground(InpDashX, InpDashY, InpWidth, y - InpDashY + 20, InpBgColor);
   
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                          |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetTimer(2); // Update every 2 seconds
   UpdateDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_prefix);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                                |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   UpdateDashboard();
   return rates_total;
}

//+------------------------------------------------------------------+
//| Timer function                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateDashboard();
}
//+------------------------------------------------------------------+
