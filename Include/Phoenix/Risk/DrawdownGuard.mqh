//+------------------------------------------------------------------+
//|                                             DrawdownGuard.mqh    |
//|                          PHOENIX EA — Drawdown Protection Guard   |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_DRAWDOWN_GUARD_MQH__
#define __PHOENIX_DRAWDOWN_GUARD_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CDrawdownGuard — Monitor de drawdown con escala de riesgo         |
//|                                                                   |
//| Implementa una curva de reduccion de riesgo progresiva:           |
//| DD < 5%:  riesgo normal (100%)                                   |
//| DD 5-10%: riesgo reducido (75%)                                  |
//| DD 10-15%: riesgo reducido (50%)                                 |
//| DD 15-20%: riesgo minimo (25%)                                   |
//| DD > 20%: solo cierre de posiciones                              |
//| DD > 30%: stop total                                             |
//+------------------------------------------------------------------+
class CDrawdownGuard
{
private:
   bool              m_initialized;
   double            m_peakEquity;
   double            m_currentDD;
   double            m_riskMultiplier;
   bool              m_shouldStop;
   bool              m_closeOnlyMode;
   
   double            m_tier1;    // 5%
   double            m_tier2;    // 10%
   double            m_tier3;    // 15%
   double            m_tier4;    // 20%
   double            m_tierStop; // 30%
   
public:
   CDrawdownGuard() : m_initialized(false), m_peakEquity(0),
                       m_currentDD(0), m_riskMultiplier(1.0),
                       m_shouldStop(false), m_closeOnlyMode(false),
                       m_tier1(0.05), m_tier2(0.10), m_tier3(0.15),
                       m_tier4(0.20), m_tierStop(0.30) {}
   
   bool Init()
   {
      m_peakEquity     = AccountInfoDouble(ACCOUNT_EQUITY);
      m_riskMultiplier = 1.0;
      m_shouldStop     = false;
      m_closeOnlyMode  = false;
      m_initialized    = true;
      
      g_logger.Info(StringFormat("DrawdownGuard: Init [peak=%.2f]", m_peakEquity));
      return true;
   }
   
   void Update()
   {
      if(!m_initialized) return;
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      if(equity > m_peakEquity)
         m_peakEquity = equity;
      
      if(m_peakEquity > 0)
         m_currentDD = (m_peakEquity - equity) / m_peakEquity;
      else
         m_currentDD = 0;
      
      double oldMultiplier = m_riskMultiplier;
      
      if(m_currentDD >= m_tierStop)
      {
         m_riskMultiplier = 0.0;
         m_shouldStop     = true;
         m_closeOnlyMode  = true;
      }
      else if(m_currentDD >= m_tier4)
      {
         m_riskMultiplier = 0.0;
         m_shouldStop     = false;
         m_closeOnlyMode  = true;
      }
      else if(m_currentDD >= m_tier3)
      {
         m_riskMultiplier = 0.25;
         m_closeOnlyMode  = false;
      }
      else if(m_currentDD >= m_tier2)
      {
         m_riskMultiplier = 0.50;
         m_closeOnlyMode  = false;
      }
      else if(m_currentDD >= m_tier1)
      {
         m_riskMultiplier = 0.75;
         m_closeOnlyMode  = false;
      }
      else
      {
         m_riskMultiplier = 1.0;
         m_closeOnlyMode  = false;
         m_shouldStop     = false;
      }
      
      if(MathAbs(oldMultiplier - m_riskMultiplier) > 0.01)
      {
         g_logger.Warning(StringFormat(
            "DrawdownGuard: DD=%.2f%% riskMult=%.0f%% closeOnly=%s",
            m_currentDD * 100, m_riskMultiplier * 100,
            m_closeOnlyMode ? "YES" : "NO"));
      }
   }
   
   void OnTradeResult(bool isWin, double pnl)
   {
      // Tracking handled by Update() via equity
   }
   
   // Getters
   bool   ShouldStop()         const { return m_shouldStop; }
   bool   IsCloseOnlyMode()    const { return m_closeOnlyMode; }
   double GetRiskMultiplier()  const { return m_riskMultiplier; }
   double GetCurrentDrawdown() const { return m_currentDD; }
   double GetPeakEquity()      const { return m_peakEquity; }
};

#endif // __PHOENIX_DRAWDOWN_GUARD_MQH__
//+------------------------------------------------------------------+
