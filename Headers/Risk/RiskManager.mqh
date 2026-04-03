//+------------------------------------------------------------------+
//|                                                  RiskManager.mqh |
//|                         Phoenix EA — Risk Management Layer        |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_RISK_MANAGER_MQH__
#define __PHOENIX_RISK_MANAGER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

class CCircuitBreaker;
class CDrawdownGuard;

//+------------------------------------------------------------------+
//| Risk Manager — Position sizing and validation                     |
//+------------------------------------------------------------------+
class CRiskManager {
private:
   double m_riskPercent;
   double m_kellyFraction;
   double m_minRR;
   int    m_maxPositions;
   
   CCircuitBreaker *m_circuitBreaker;
   CDrawdownGuard  *m_drawdownGuard;

public:
   CRiskManager() : m_riskPercent(3.0), m_kellyFraction(0.25), m_minRR(1.0), m_maxPositions(5),
                     m_circuitBreaker(NULL), m_drawdownGuard(NULL) {}
   
   bool Init(CCircuitBreaker *cb, CDrawdownGuard *ddg) {
      m_circuitBreaker = cb;
      m_drawdownGuard = ddg;
      m_riskPercent = GetRiskForMode(g_AccountMode);
      m_kellyFraction = InpKellyFraction;
      m_minRR = InpMinRiskReward;
      m_maxPositions = GetMaxPositionsForMode(g_AccountMode);
      
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("RiskManager: Risk=%.1f%% Kelly=%.2f MaxPos=%d Mode=%s",
            m_riskPercent, m_kellyFraction, m_maxPositions, EnumToString(g_AccountMode)));
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate position size based on risk                             |
   //+------------------------------------------------------------------+
   double CalculateLotSize(string symbol, double entryPrice, double stopLoss) {
      if(entryPrice <= 0 || stopLoss <= 0) return 0;
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity < MIN_EQUITY_USD) return 0;
      
      // Apply drawdown guard scaling
      double riskPct = m_riskPercent;
      if(m_drawdownGuard != NULL) {
         riskPct *= m_drawdownGuard.GetRiskMultiplier();
      }
      
      double riskAmount = equity * riskPct / 100.0;
      double slDistance = MathAbs(entryPrice - stopLoss);
      
      if(slDistance <= 0) return 0;
      
      // Calculate base lot size
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      
      if(tickSize <= 0 || tickValue <= 0) return 0;
      
      double lots = riskAmount / (slDistance / tickSize * tickValue);
      
      // Apply Kelly criterion if we have enough history
      lots = ApplyKelly(lots);
      
      // Normalize
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      if(lotStep <= 0) lotStep = 0.01;
      lots = MathMax(lots, minLot);
      lots = MathMin(lots, maxLot);
      lots = MathFloor(lots / lotStep) * lotStep;
      lots = NormalizeDouble(lots, 2);
      
      // Final margin check
      if(!ValidateMargin(symbol, lots)) {
         lots = minLot;
         if(!ValidateMargin(symbol, lots)) return 0;
      }
      
      return lots;
   }
   
   //+------------------------------------------------------------------+
   //| Validate if a new trade is allowed                                |
   //+------------------------------------------------------------------+
   bool CanOpenTrade(STradeSignal &signal) {
      // Check circuit breaker
      if(m_circuitBreaker != NULL && !m_circuitBreaker.IsTradingAllowed()) {
         if(g_Logger != NULL) g_Logger.Debug("RiskManager: Circuit breaker active, trade blocked");
         return false;
      }
      
      // Check max positions
      int openPos = CountOpenPositions();
      if(openPos >= m_maxPositions) {
         if(g_Logger != NULL) g_Logger.Debug(StringFormat("RiskManager: Max positions reached (%d/%d)", openPos, m_maxPositions));
         return false;
      }
      
      // Check R:R
      if(signal.riskReward < m_minRR) {
         if(g_Logger != NULL) g_Logger.Debug(StringFormat("RiskManager: R:R too low (%.2f < %.2f)", signal.riskReward, m_minRR));
         return false;
      }
      
      // Check if already have position on this symbol with same strategy
      if(HasPositionForSymbolStrategy(signal.symbol, signal.strategy)) {
         return false;
      }
      
      // Check minimum equity
      if(AccountInfoDouble(ACCOUNT_EQUITY) < MIN_EQUITY_USD) {
         if(g_Logger != NULL) g_Logger.Warning("RiskManager: Equity below minimum");
         return false;
      }
      
      // Check free margin (at least 50% must be free)
      double freeMarginPct = AccountInfoDouble(ACCOUNT_MARGIN_FREE) / 
                             AccountInfoDouble(ACCOUNT_EQUITY) * 100.0;
      if(freeMarginPct < 50.0) {
         if(g_Logger != NULL) g_Logger.Warning(StringFormat("RiskManager: Free margin too low (%.1f%%)", freeMarginPct));
         return false;
      }
      
      return true;
   }
   
   int CountOpenPositions() {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if(IS_PHOENIX_MAGIC(magic)) count++;
         }
      }
      return count;
   }
   
   bool HasPositionForSymbolStrategy(string symbol, ENUM_STRATEGY_TYPE strategy) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) {
            long magic = PositionGetInteger(POSITION_MAGIC);
            if(IS_PHOENIX_MAGIC(magic)) {
               ENUM_STRATEGY_TYPE posStrategy = DECODE_STRATEGY(magic);
               string posSymbol = PositionGetString(POSITION_SYMBOL);
               if(posStrategy == strategy && posSymbol == symbol) return true;
            }
         }
      }
      return false;
   }
   
   void SetCircuitBreaker(CCircuitBreaker *cb)  { m_circuitBreaker = cb; }
   void SetDrawdownGuard(CDrawdownGuard *ddg)    { m_drawdownGuard = ddg; }
   double GetRiskPercent()                        { return m_riskPercent; }
   int    GetMaxPositions()                       { return m_maxPositions; }
   
   void UpdateAccountMode() {
      g_AccountMode = DetectAccountMode();
      m_riskPercent = GetRiskForMode(g_AccountMode);
      m_maxPositions = GetMaxPositionsForMode(g_AccountMode);
   }

private:
   //+------------------------------------------------------------------+
   //| Quarter-Kelly position sizing from trade history                  |
   //+------------------------------------------------------------------+
   double ApplyKelly(double baseLots) {
      if(g_State.totalTrades < 20) return baseLots; // Not enough data
      
      double winRate = (g_State.totalTrades > 0) ? 
                       (double)(g_State.totalTrades - g_State.consecutiveLosses) / g_State.totalTrades : 0.5;
      // Simplified Kelly: f = W - (1-W)/R where R = avg win / avg loss
      double kellyFull = MathMax(0.0, winRate - (1.0 - winRate) / 1.5);
      double kellyScaled = kellyFull * m_kellyFraction;
      
      if(kellyScaled > 0 && kellyScaled < 1.0)
         baseLots *= kellyScaled / 0.25; // Normalize around expected 25%
      
      return baseLots;
   }
   
   bool ValidateMargin(string symbol, double lots) {
      double margin = 0;
      ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY;
      double price = SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      if(!OrderCalcMargin(orderType, symbol, lots, price, margin))
         return false;
      
      return (margin < AccountInfoDouble(ACCOUNT_MARGIN_FREE) * 0.8);
   }
};

#endif // __PHOENIX_RISK_MANAGER_MQH__
