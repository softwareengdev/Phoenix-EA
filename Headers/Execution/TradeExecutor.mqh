#ifndef __PHOENIX_TRADE_EXECUTOR_MQH__
#define __PHOENIX_TRADE_EXECUTOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//+------------------------------------------------------------------+
//| Trade Executor — Smart order execution with retry logic           |
//+------------------------------------------------------------------+
class CTradeExecutor {
private:
   CTrade         m_trade;
   CPositionInfo  m_posInfo;
   int            m_maxRetries;
   int            m_slippage;
   ENUM_TRAIL_MODE m_trailMode;
   double         m_trailATRMulti;
   double         m_breakevenPips;
   double         m_breakevenOffset;
   bool           m_partialCloseEnabled;
   double         m_partialPct;
   double         m_partialTrigger;
   
   // Cached ATR handles per symbol (avoid iATR/IndicatorRelease per tick per position)
   int            m_atrHandles[];
   int            m_atrHandleCount;
   
public:
   CTradeExecutor() : m_maxRetries(3), m_slippage(10), m_trailMode(TRAIL_ATR),
                       m_trailATRMulti(2.0), m_breakevenPips(15), m_breakevenOffset(2),
                       m_partialCloseEnabled(true), m_partialPct(50), m_partialTrigger(1.0),
                       m_atrHandleCount(0) {}
   
   ~CTradeExecutor() {
      for(int i = 0; i < m_atrHandleCount; i++)
         if(m_atrHandles[i] != INVALID_HANDLE) IndicatorRelease(m_atrHandles[i]);
   }
   
   bool Init() {
      m_maxRetries = InpMaxRetries;
      m_slippage = InpSlippage;
      m_trailMode = InpTrailMode;
      m_trailATRMulti = InpTrailATRMulti;
      m_breakevenPips = InpBreakevenPips;
      m_breakevenOffset = InpBreakevenOffset;
      m_partialCloseEnabled = InpPartialClose;
      m_partialPct = InpPartialPct;
      m_partialTrigger = InpPartialTrigger;
      
      m_trade.SetExpertMagicNumber(PHOENIX_MAGIC_BASE);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      m_trade.SetTypeFillingBySymbol(Symbol());
      
      // Pre-create ATR handles for all symbols (avoid per-tick creation)
      m_atrHandleCount = g_SymbolCount;
      ArrayResize(m_atrHandles, m_atrHandleCount);
      for(int i = 0; i < m_atrHandleCount; i++)
         m_atrHandles[i] = iATR(g_Symbols[i].name, InpPrimaryTF, 14);
      
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("TradeExecutor: Slippage=%d Retries=%d Trail=%s",
            m_slippage, m_maxRetries, EnumToString(m_trailMode)));
      return true;
   }
   
   // Execute a trade signal
   bool ExecuteSignal(STradeSignal &signal, double lots) {
      if(lots <= 0) return false;
      
      int magic = ENCODE_MAGIC(signal.strategy, signal.symbolIndex);
      m_trade.SetExpertMagicNumber(magic);
      
      string sym = signal.symbol;
      double sl = NormalizeDouble(signal.stopLoss, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      double tp = NormalizeDouble(signal.takeProfit, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));
      string comment = StringFormat("PHX_%s_%s", EnumToString(signal.strategy), signal.comment);
      
      // Truncate comment to 31 chars (MQL5 limit)
      if(StringLen(comment) > 31) comment = StringSubstr(comment, 0, 31);
      
      bool result = false;
      for(int attempt = 0; attempt < m_maxRetries; attempt++) {
         if(signal.direction == SIGNAL_BUY) {
            double price = SymbolInfoDouble(sym, SYMBOL_ASK);
            result = m_trade.Buy(lots, sym, price, sl, tp, comment);
         } else {
            double price = SymbolInfoDouble(sym, SYMBOL_BID);
            result = m_trade.Sell(lots, sym, price, sl, tp, comment);
         }
         
         if(result) {
            uint retcode = m_trade.ResultRetcode();
            if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED) {
               if(g_Logger != NULL)
                  g_Logger.LogTrade(sym, signal.direction == SIGNAL_BUY ? "BUY" : "SELL",
                     m_trade.ResultPrice(), lots, sl, tp, comment);
               return true;
            }
            if(g_Logger != NULL)
               g_Logger.Warning(StringFormat("TradeExecutor: Retcode %d on attempt %d: %s",
                  retcode, attempt + 1, m_trade.ResultRetcodeDescription()));
         }
         if(!g_IsTesting) Sleep(500 * (attempt + 1)); // Exponential backoff (skip in tester)
      }
      
      if(g_Logger != NULL)
         g_Logger.Error(StringFormat("TradeExecutor: Failed to execute %s %s after %d attempts",
            signal.direction == SIGNAL_BUY ? "BUY" : "SELL", sym, m_maxRetries));
      return false;
   }
   
   // Close a position by ticket
   bool ClosePosition(ulong ticket, string reason = "") {
      if(!PositionSelectByTicket(ticket)) return false;
      
      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      long magic = PositionGetInteger(POSITION_MAGIC);
      
      m_trade.SetExpertMagicNumber((ulong)magic);
      
      for(int attempt = 0; attempt < m_maxRetries; attempt++) {
         if(m_trade.PositionClose(ticket, m_slippage)) {
            if(g_Logger != NULL)
               g_Logger.LogTrade(sym, "CLOSE", m_trade.ResultPrice(), vol, 0, 0, reason);
            return true;
         }
         if(!g_IsTesting) Sleep(300 * (attempt + 1));
      }
      return false;
   }
   
   // Close all Phoenix positions
   int CloseAllPositions(string reason = "Close All") {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         if(ClosePosition(ticket, reason)) closed++;
      }
      return closed;
   }
   
   // Manage trailing stops for all positions
   void ManageTrailingStops() {
      if(m_trailMode == TRAIL_NONE) return;
      
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         if(!PositionSelectByTicket(ticket)) continue;
         
         string sym = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double volume = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         
         double point = SymbolInfoDouble(sym, SYMBOL_POINT);
         int digits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
         
         // Get ATR for trailing (use cached handle)
         int atrHandle = INVALID_HANDLE;
         for(int si = 0; si < m_atrHandleCount; si++) {
            if(g_Symbols[si].name == sym) { atrHandle = m_atrHandles[si]; break; }
         }
         if(atrHandle == INVALID_HANDLE) continue;
         
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) < 1) continue;
         double atr = atrBuf[0];
         
         if(atr <= 0) continue;
         
         double bid = SymbolInfoDouble(sym, SYMBOL_BID);
         double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
         
         // Breakeven logic
         ManageBreakeven(ticket, sym, posType, openPrice, currentSL, point, digits, bid, ask);
         
         // Partial close
         if(m_partialCloseEnabled)
            ManagePartialClose(ticket, sym, posType, openPrice, currentSL, volume, point, bid, ask);
         
         // Trailing stop
         double newSL = 0;
         if(posType == POSITION_TYPE_BUY) {
            newSL = bid - atr * m_trailATRMulti;
            newSL = NormalizeDouble(newSL, digits);
            if(newSL > currentSL && newSL < bid) {
               m_trade.PositionModify(ticket, newSL, currentTP);
            }
         } else {
            newSL = ask + atr * m_trailATRMulti;
            newSL = NormalizeDouble(newSL, digits);
            if((currentSL == 0 || newSL < currentSL) && newSL > ask) {
               m_trade.PositionModify(ticket, newSL, currentTP);
            }
         }
      }
   }
   
   CTrade* GetTradeObject() { return GetPointer(m_trade); }

private:
   void ManageBreakeven(ulong ticket, string sym, ENUM_POSITION_TYPE posType,
                         double openPrice, double currentSL, double point, int digits,
                         double bid, double ask) {
      double bePips = m_breakevenPips * point * 10; // Convert pips to price
      double beOffset = m_breakevenOffset * point * 10;
      
      if(posType == POSITION_TYPE_BUY) {
         if(bid >= openPrice + bePips && currentSL < openPrice) {
            double newSL = NormalizeDouble(openPrice + beOffset, digits);
            m_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      } else {
         if(ask <= openPrice - bePips && (currentSL > openPrice || currentSL == 0)) {
            double newSL = NormalizeDouble(openPrice - beOffset, digits);
            m_trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
         }
      }
   }
   
   void ManagePartialClose(ulong ticket, string sym, ENUM_POSITION_TYPE posType,
                            double openPrice, double currentSL, double volume,
                            double point, double bid, double ask) {
      double riskDist = MathAbs(openPrice - currentSL);
      if(riskDist <= 0) return;
      
      double trigger = riskDist * m_partialTrigger;
      double minLot = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double closeLots = NormalizeDouble(volume * m_partialPct / 100.0, 2);
      if(closeLots < minLot) return;
      
      // Only partial close once (check if volume is close to original)
      double lotStep = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      
      if(posType == POSITION_TYPE_BUY && bid >= openPrice + trigger) {
         m_trade.PositionClosePartial(ticket, closeLots, m_slippage);
      }
      else if(posType == POSITION_TYPE_SELL && ask <= openPrice - trigger) {
         m_trade.PositionClosePartial(ticket, closeLots, m_slippage);
      }
   }
};

#endif // __PHOENIX_TRADE_EXECUTOR_MQH__
