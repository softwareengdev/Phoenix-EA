//+------------------------------------------------------------------+
//|                                                DrawdownGuard.mqh |
//|                         Phoenix EA — Risk Management Layer        |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_DRAWDOWN_GUARD_MQH__
#define __PHOENIX_DRAWDOWN_GUARD_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Drawdown Guard — Progressive risk scaling                         |
//| Reduces risk as drawdown increases, speeds recovery              |
//+------------------------------------------------------------------+
class CDrawdownGuard {
private:
   double m_maxDD;        // Max acceptable DD before full stop
   double m_tier1DD;      // First reduction tier (e.g., 5%)
   double m_tier2DD;      // Second reduction tier (e.g., 15%)
   double m_tier3DD;      // Third reduction tier (e.g., 25%)
   double m_tier1Scale;   // Risk multiplier at tier 1
   double m_tier2Scale;   // Risk multiplier at tier 2
   double m_tier3Scale;   // Risk multiplier at tier 3
   double m_currentMultiplier;
   bool   m_inRecovery;
   double m_recoveryStartDD;
   
public:
   CDrawdownGuard() : m_maxDD(30.0), m_tier1DD(5.0), m_tier2DD(15.0), m_tier3DD(25.0),
                       m_tier1Scale(0.75), m_tier2Scale(0.5), m_tier3Scale(0.25),
                       m_currentMultiplier(1.0), m_inRecovery(false), m_recoveryStartDD(0) {}
   
   void Init(double maxDD) {
      m_maxDD = maxDD;
      m_tier1DD = maxDD * 0.17;  // ~5% of 30%
      m_tier2DD = maxDD * 0.50;  // ~15% of 30%
      m_tier3DD = maxDD * 0.83;  // ~25% of 30%
      m_currentMultiplier = 1.0;
   }
   
   //+------------------------------------------------------------------+
   //| Update risk multiplier based on current drawdown tier             |
   //+------------------------------------------------------------------+
   void Update() {
      double currentDD = GetCurrentDrawdownPct();
      
      if(currentDD <= 1.0) {
         m_currentMultiplier = 1.0;
         m_inRecovery = false;
      }
      else if(currentDD < m_tier1DD) {
         m_currentMultiplier = 1.0;
         if(m_inRecovery && currentDD < m_recoveryStartDD * 0.5) {
            m_inRecovery = false;
         }
      }
      else if(currentDD < m_tier2DD) {
         m_currentMultiplier = m_tier1Scale;
         if(!m_inRecovery) {
            m_inRecovery = true;
            m_recoveryStartDD = currentDD;
         }
      }
      else if(currentDD < m_tier3DD) {
         m_currentMultiplier = m_tier2Scale;
         m_inRecovery = true;
      }
      else {
         m_currentMultiplier = m_tier3Scale;
         m_inRecovery = true;
      }
   }
   
   double GetRiskMultiplier()     { return m_currentMultiplier; }
   bool   IsInRecovery()          { return m_inRecovery; }
   
   double GetCurrentDrawdownPct() {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(g_State.peakEquity <= 0) return 0;
      double dd = (g_State.peakEquity - equity) / g_State.peakEquity * 100.0;
      return MathMax(0, dd);
   }
   
   string GetStatus() {
      return StringFormat("DD=%.1f%% Mult=%.2f Recovery=%s",
             GetCurrentDrawdownPct(), m_currentMultiplier,
             m_inRecovery ? "YES" : "NO");
   }
};

#endif // __PHOENIX_DRAWDOWN_GUARD_MQH__
