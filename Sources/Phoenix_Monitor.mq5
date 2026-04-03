//+------------------------------------------------------------------+
//|                                              Phoenix_Monitor.mq5  |
//|                     Copyright 2025, Phoenix Trading Systems       |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2025, Phoenix Trading Systems"
#property link        "https://github.com/softwareengdev/Phoenix-EA"
#property version     "3.00"
#property description "Phoenix EA Dashboard Monitor"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input color  InpColorHeader    = clrOrangeRed;     // Header Color
input color  InpColorPositive  = clrLime;           // Positive P/L Color
input color  InpColorNegative  = clrRed;            // Negative P/L Color
input color  InpColorText      = clrWhite;          // Text Color
input color  InpColorBg        = C'22,22,46';       // Background Color
input int    InpFontSize       = 9;                 // Font Size
input int    InpXOffset        = 20;                // X Position
input int    InpYOffset        = 30;                // Y Position
input int    InpMagicBase      = 770000;            // Phoenix Magic Base
input int    InpRefreshMs      = 1000;              // Refresh interval (ms)

//--- Internal
string g_ObjPrefix = "PHX_MON_";
int    g_LineHeight;
datetime g_LastUpdate = 0;

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_LineHeight = InpFontSize + 6;
   EventSetMillisecondTimer(InpRefreshMs);
   DrawDashboard();
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, g_ObjPrefix);
}

//+------------------------------------------------------------------+
//| Calculate (required for indicator)                                |
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
   return rates_total;
}

//+------------------------------------------------------------------+
//| Timer event                                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   DrawDashboard();
}

//+------------------------------------------------------------------+
//| Draw the dashboard                                                |
//+------------------------------------------------------------------+
void DrawDashboard()
{
   //--- Clear previous objects
   ObjectsDeleteAll(0, g_ObjPrefix);

   int y = InpYOffset;
   int x = InpXOffset;

   //--- Background panel
   string bgName = g_ObjPrefix + "BG";
   ObjectCreate(0, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bgName, OBJPROP_XDISTANCE, x - 10);
   ObjectSetInteger(0, bgName, OBJPROP_YDISTANCE, y - 10);
   ObjectSetInteger(0, bgName, OBJPROP_XSIZE, 320);
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, 400);
   ObjectSetInteger(0, bgName, OBJPROP_BGCOLOR, InpColorBg);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bgName, OBJPROP_BORDER_COLOR, InpColorHeader);
   ObjectSetInteger(0, bgName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bgName, OBJPROP_BACK, false);

   //--- Header
   CreateLabel("Header", x, y, "🔥 PHOENIX MONITOR v3.0", InpColorHeader, InpFontSize + 2);
   y += g_LineHeight + 8;

   //--- Account info
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   CreateLabel("Equity", x, y, StringFormat("Equity: %.2f %s", equity, currency), InpColorText, InpFontSize);
   y += g_LineHeight;
   CreateLabel("Balance", x, y, StringFormat("Balance: %.2f %s", balance, currency), InpColorText, InpFontSize);
   y += g_LineHeight;
   CreateLabel("Margin", x, y, StringFormat("Margin: %.2f | Free: %.2f", margin, freeMargin), InpColorText, InpFontSize);
   y += g_LineHeight + 4;

   //--- Separator
   CreateLabel("Sep1", x, y, "─────────────────────────────", clrDarkSlateGray, InpFontSize - 2);
   y += g_LineHeight;

   //--- Position summary
   int totalPos = 0;
   double totalPnL = 0;
   int buyCount = 0, sellCount = 0;
   double buyPnL = 0, sellPnL = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic < InpMagicBase || magic >= InpMagicBase + 1000) continue;

      totalPos++;
      double pnl = PositionGetDouble(POSITION_PROFIT) +
                    PositionGetDouble(POSITION_SWAP);
      totalPnL += pnl;

      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      { buyCount++; buyPnL += pnl; }
      else
      { sellCount++; sellPnL += pnl; }
   }

   color pnlColor = (totalPnL >= 0) ? InpColorPositive : InpColorNegative;
   CreateLabel("Positions", x, y, StringFormat("Open Positions: %d", totalPos), InpColorText, InpFontSize);
   y += g_LineHeight;
   CreateLabel("BuySell", x, y, StringFormat("Buy: %d (%.2f) | Sell: %d (%.2f)", buyCount, buyPnL, sellCount, sellPnL), InpColorText, InpFontSize);
   y += g_LineHeight;
   CreateLabel("FloatPnL", x, y, StringFormat("Floating P/L: %.2f", totalPnL), pnlColor, InpFontSize);
   y += g_LineHeight + 4;

   //--- Separator
   CreateLabel("Sep2", x, y, "─────────────────────────────", clrDarkSlateGray, InpFontSize - 2);
   y += g_LineHeight;

   //--- Strategy breakdown
   CreateLabel("StratHeader", x, y, "Strategy Performance:", InpColorHeader, InpFontSize);
   y += g_LineHeight;

   string strategies[] = {"TREND", "MEANREV", "BREAKOUT", "SCALPER"};
   for(int s = 0; s < 4; s++)
   {
      int stratTrades = 0;
      double stratPnL = 0;

      if(HistorySelect(0, TimeCurrent()))
      {
         for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket <= 0) continue;
            long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            if(magic < InpMagicBase || magic >= InpMagicBase + 1000) continue;
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry != DEAL_ENTRY_OUT) continue;

            int stratIdx = (int)((magic - InpMagicBase) / 100);
            if(stratIdx == s)
            {
               stratTrades++;
               stratPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                           HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                           HistoryDealGetDouble(ticket, DEAL_SWAP);
            }
         }
      }

      color sColor = (stratPnL >= 0) ? InpColorPositive : InpColorNegative;
      CreateLabel("Strat" + IntegerToString(s), x, y,
         StringFormat("  %s: %d trades | P/L: %.2f", strategies[s], stratTrades, stratPnL),
         sColor, InpFontSize);
      y += g_LineHeight;
   }

   y += 4;
   CreateLabel("Sep3", x, y, "─────────────────────────────", clrDarkSlateGray, InpFontSize - 2);
   y += g_LineHeight;

   //--- Drawdown
   double peakEquity = equity;
   // Simple peak tracking from balance
   if(balance > peakEquity) peakEquity = balance;
   double dd = (peakEquity > 0) ? (peakEquity - equity) / peakEquity * 100.0 : 0;
   color ddColor = (dd < 5) ? InpColorPositive : (dd < 15 ? clrYellow : InpColorNegative);

   CreateLabel("DD", x, y, StringFormat("Current DD: %.1f%%", dd), ddColor, InpFontSize);
   y += g_LineHeight;

   //--- Spread
   double spread = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - SymbolInfoDouble(Symbol(), SYMBOL_BID);
   double spreadPts = spread / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   CreateLabel("Spread", x, y, StringFormat("Spread: %.1f pts (%s)", spreadPts, Symbol()), InpColorText, InpFontSize);
   y += g_LineHeight;

   //--- Time
   CreateLabel("Time", x, y, StringFormat("Server: %s", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS)),
      clrDarkGray, InpFontSize - 1);
   y += g_LineHeight;

   //--- Resize background
   ObjectSetInteger(0, bgName, OBJPROP_YSIZE, y - InpYOffset + 20);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper: Create text label                                         |
//+------------------------------------------------------------------+
void CreateLabel(string id, int x, int y, string text, color clr, int fontSize)
{
   string name = g_ObjPrefix + id;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}
//+------------------------------------------------------------------+
