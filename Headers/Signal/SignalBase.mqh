//+------------------------------------------------------------------+
//|                                                   SignalBase.mqh |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_BASE_MQH__
#define __PHOENIX_SIGNAL_BASE_MQH__

#include "..\Core\Defines.mqh"

// Forward declaration
class CDataEngine;

//+------------------------------------------------------------------+
//| Base class for trading signal generators                          |
//+------------------------------------------------------------------+
class CSignalBase {
protected:
   ENUM_STRATEGY_TYPE m_strategyType;
   string             m_name;
   bool               m_enabled;
   double             m_allocationWeight;
   double             m_confidenceThreshold;
   SStrategyMetrics   m_metrics;
   
public:
   CSignalBase() : m_enabled(true), m_allocationWeight(0.25), m_confidenceThreshold(0.5) {
      ZeroMemory(m_metrics);
      m_metrics.enabled = true;
      m_metrics.allocationWeight = 0.25;
   }
   
   virtual ~CSignalBase() {}
   
   // Initialize the strategy
   virtual bool Init(ENUM_STRATEGY_TYPE type, string name) {
      m_strategyType = type;
      m_name = name;
      m_metrics.strategy = type;
      return true;
   }
   
   // Evaluate and generate signal for a specific symbol
   virtual STradeSignal Evaluate(int symbolIndex, CDataEngine *data) {
      STradeSignal signal;
      ZeroMemory(signal);
      signal.direction = SIGNAL_NONE;
      signal.strategy = m_strategyType;
      signal.symbolIndex = symbolIndex;
      return signal;
   }
   
   // How suitable is this strategy for the given regime? (0.0 - 1.0)
   virtual double GetRegimeSuitability(ENUM_MARKET_REGIME regime) { return 0.5; }
   
   // Strategy-specific exit signal (true = close position)
   virtual bool ShouldExit(int symbolIndex, ENUM_SIGNAL_TYPE posDirection, CDataEngine *data) {
      return false;
   }
   
   // Getters/Setters
   ENUM_STRATEGY_TYPE GetType()              { return m_strategyType; }
   string             GetName()              { return m_name; }
   bool               IsEnabled()            { return m_enabled; }
   void               SetEnabled(bool v)     { m_enabled = v; m_metrics.enabled = v; }
   double             GetWeight()            { return m_allocationWeight; }
   void               SetWeight(double w)    { m_allocationWeight = w; m_metrics.allocationWeight = w; }
   SStrategyMetrics*  GetMetrics()           { return GetPointer(m_metrics); }
   
   void UpdateMetrics(double profit, double profitPct) {
      m_metrics.totalTrades++;
      if(profit > 0) {
         m_metrics.winTrades++;
         m_metrics.totalProfit += profit;
         m_metrics.avgWin = m_metrics.totalProfit / m_metrics.winTrades;
         m_metrics.consecutiveWins++;
         m_metrics.consecutiveLosses = 0;
         if(m_metrics.consecutiveWins > m_metrics.maxConsecWins)
            m_metrics.maxConsecWins = m_metrics.consecutiveWins;
      } else {
         m_metrics.lossTrades++;
         m_metrics.totalLoss += MathAbs(profit);
         m_metrics.avgLoss = m_metrics.totalLoss / m_metrics.lossTrades;
         m_metrics.consecutiveLosses++;
         m_metrics.consecutiveWins = 0;
         if(m_metrics.consecutiveLosses > m_metrics.maxConsecLosses)
            m_metrics.maxConsecLosses = m_metrics.consecutiveLosses;
      }
      
      m_metrics.netProfit = m_metrics.totalProfit - m_metrics.totalLoss;
      m_metrics.winRate = (m_metrics.totalTrades > 0) ? 
                          (double)m_metrics.winTrades / m_metrics.totalTrades : 0;
      m_metrics.profitFactor = (m_metrics.totalLoss > 0) ? 
                               m_metrics.totalProfit / m_metrics.totalLoss : 
                               (m_metrics.totalProfit > 0 ? 99.9 : 0);
      m_metrics.expectancy = (m_metrics.winRate * m_metrics.avgWin) - 
                             ((1.0 - m_metrics.winRate) * m_metrics.avgLoss);
      m_metrics.lastTradeTime = TimeCurrent();
      
      // Track drawdown  
      if(profitPct < 0 && MathAbs(profitPct) > m_metrics.maxDrawdownPct)
         m_metrics.maxDrawdownPct = MathAbs(profitPct);
   }
};

#endif // __PHOENIX_SIGNAL_BASE_MQH__
