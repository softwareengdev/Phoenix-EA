//+------------------------------------------------------------------+
//|                                               CircuitBreaker.mqh |
//|                         Phoenix EA — Risk Management Layer        |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_CIRCUIT_BREAKER_MQH__
#define __PHOENIX_CIRCUIT_BREAKER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Circuit Breaker — Emergency trading halt system                   |
//| Triggers: daily DD, total DD, consecutive losses, spread spike   |
//+------------------------------------------------------------------+
class CCircuitBreaker {
private:
   double          m_maxDailyDD;       // Max daily drawdown %
   double          m_maxTotalDD;       // Max total drawdown %
   int             m_maxConsecLosses;  // Max consecutive losing trades
   double          m_maxSpreadMulti;   // Max spread multiplier vs average
   int             m_cooldownMinutes;  // Cooldown period after trigger
   ENUM_CIRCUIT_STATE m_state;
   datetime        m_triggerTime;
   string          m_triggerReason;
   int             m_triggerCount;     // Total times triggered
   
public:
   CCircuitBreaker() : m_maxDailyDD(5.0), m_maxTotalDD(30.0), m_maxConsecLosses(5),
                         m_maxSpreadMulti(3.0), m_cooldownMinutes(60),
                         m_state(CIRCUIT_CLOSED), m_triggerTime(0), m_triggerCount(0) {}
   
   void Init(double maxDailyDD, double maxTotalDD, int maxConsecLosses, double maxSpreadMulti) {
      m_maxDailyDD = maxDailyDD;
      m_maxTotalDD = maxTotalDD;
      m_maxConsecLosses = maxConsecLosses;
      m_maxSpreadMulti = maxSpreadMulti;
      m_state = CIRCUIT_CLOSED;
   }
   
   //+------------------------------------------------------------------+
   //| Check all circuit breaker conditions                              |
   //+------------------------------------------------------------------+
   void Update() {
      if(m_state == CIRCUIT_OPEN) {
         // Check if cooldown has elapsed
         if(TimeCurrent() - m_triggerTime >= m_cooldownMinutes * 60) {
            m_state = CIRCUIT_HALF_OPEN;
            if(g_Logger != NULL)
               g_Logger.Info("CircuitBreaker: Entering HALF-OPEN state (testing recovery)");
         }
         return;
      }
      
      // Check daily drawdown
      if(CheckDailyDrawdown()) return;
      
      // Check total drawdown
      if(CheckTotalDrawdown()) return;
      
      // Check consecutive losses
      if(CheckConsecutiveLosses()) return;
      
      // If in HALF-OPEN and no triggers, restore to CLOSED
      if(m_state == CIRCUIT_HALF_OPEN) {
         m_state = CIRCUIT_CLOSED;
         if(g_Logger != NULL)
            g_Logger.Info("CircuitBreaker: Restored to CLOSED state");
      }
   }
   
   bool CheckSpreadForSymbol(string symbol, double avgSpread) {
      if(avgSpread <= 0) return true; // Allow if no data
      double currentSpread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
      return (currentSpread <= avgSpread * m_maxSpreadMulti);
   }
   
   bool IsTradingAllowed() {
      return (m_state == CIRCUIT_CLOSED || m_state == CIRCUIT_HALF_OPEN);
   }
   
   bool IsFullyOpen()       { return m_state == CIRCUIT_OPEN; }
   bool IsHalfOpen()        { return m_state == CIRCUIT_HALF_OPEN; }
   string GetTriggerReason() { return m_triggerReason; }
   int GetTriggerCount()     { return m_triggerCount; }
   ENUM_CIRCUIT_STATE GetState() { return m_state; }
   
   void ForceClose() {
      m_state = CIRCUIT_CLOSED;
      if(g_Logger != NULL) g_Logger.Info("CircuitBreaker: Force-closed by user/system");
   }
   
   void ForceOpen(string reason) {
      TripCircuit(reason);
   }

private:
   bool CheckDailyDrawdown() {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyDD = 0;
      if(g_State.dayStartEquity > 0) {
         dailyDD = (g_State.dayStartEquity - equity) / g_State.dayStartEquity * 100.0;
      }
      g_State.dailyPnL = equity - g_State.dayStartEquity;
      
      if(dailyDD >= m_maxDailyDD) {
         TripCircuit(StringFormat("Daily DD %.2f%% exceeds limit %.2f%%", dailyDD, m_maxDailyDD));
         return true;
      }
      return false;
   }
   
   bool CheckTotalDrawdown() {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > g_State.peakEquity) {
         g_State.peakEquity = equity;
      }
      
      double dd = 0;
      if(g_State.peakEquity > 0) {
         dd = (g_State.peakEquity - equity) / g_State.peakEquity * 100.0;
      }
      g_State.maxDrawdownPct = MathMax(g_State.maxDrawdownPct, dd / 100.0);
      g_State.maxDrawdown = g_State.peakEquity - equity;
      
      if(dd >= m_maxTotalDD) {
         TripCircuit(StringFormat("Total DD %.2f%% exceeds limit %.2f%%", dd, m_maxTotalDD));
         return true;
      }
      return false;
   }
   
   bool CheckConsecutiveLosses() {
      if(g_State.consecutiveLosses >= m_maxConsecLosses) {
         TripCircuit(StringFormat("Consecutive losses %d exceeds limit %d", 
                     g_State.consecutiveLosses, m_maxConsecLosses));
         return true;
      }
      return false;
   }
   
   void TripCircuit(string reason) {
      m_state = CIRCUIT_OPEN;
      m_triggerTime = TimeCurrent();
      m_triggerReason = reason;
      m_triggerCount++;
      g_State.circuitState = CIRCUIT_OPEN;
      g_State.circuitOpenTime = m_triggerTime;
      
      if(g_Logger != NULL)
         g_Logger.Warning(StringFormat("CircuitBreaker: TRIPPED — %s (count: %d)", reason, m_triggerCount));
   }
};

#endif // __PHOENIX_CIRCUIT_BREAKER_MQH__
