//+------------------------------------------------------------------+
//|                                            SignalAggregator.mqh  |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_AGGREGATOR_MQH__
#define __PHOENIX_SIGNAL_AGGREGATOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "SignalBase.mqh"
#include "SignalTrend.mqh"
#include "SignalMeanRevert.mqh"
#include "SignalBreakout.mqh"
#include "SignalScalper.mqh"

class CDataEngine;

//+------------------------------------------------------------------+
//| Signal Aggregator — Multi-strategy orchestrator                   |
//| Evaluates all strategies per symbol, filters, and ranks signals  |
//+------------------------------------------------------------------+
class CSignalAggregator {
private:
   CSignalTrend      m_trend;
   CSignalMeanRevert m_meanRevert;
   CSignalBreakout   m_breakout;
   CSignalScalper    m_scalper;
   CSignalBase*      m_strategies[];
   int               m_strategyCount;
   STradeSignal      m_pendingSignals[];
   int               m_pendingCount;
   int               m_maxSignalsPerTick;
   
public:
   CSignalAggregator() : m_strategyCount(0), m_pendingCount(0), m_maxSignalsPerTick(3) {}
   
   ~CSignalAggregator() {
      ArrayFree(m_strategies);
   }
   
   bool Init() {
      m_strategyCount = 0;
      ArrayResize(m_strategies, STRATEGY_COUNT);
      
      if(InpEnableTrend) {
         m_trend.Init(STRATEGY_TREND, "TrendFollower");
         m_strategies[m_strategyCount++] = GetPointer(m_trend);
      }
      if(InpEnableMeanRev) {
         m_meanRevert.Init(STRATEGY_MEAN_REVERT, "MeanReversion");
         m_strategies[m_strategyCount++] = GetPointer(m_meanRevert);
      }
      if(InpEnableBreakout) {
         m_breakout.Init(STRATEGY_BREAKOUT, "Breakout");
         m_strategies[m_strategyCount++] = GetPointer(m_breakout);
      }
      if(InpEnableScalper) {
         m_scalper.Init(STRATEGY_SCALPER, "Scalper");
         m_strategies[m_strategyCount++] = GetPointer(m_scalper);
      }
      
      ArrayResize(m_strategies, m_strategyCount);
      ArrayResize(m_pendingSignals, 0);
      
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("SignalAggregator: Initialized %d strategies", m_strategyCount));
      return (m_strategyCount > 0);
   }
   
   // Evaluate all strategies for all symbols
   int GenerateSignals(CDataEngine *data) {
      m_pendingCount = 0;
      ArrayResize(m_pendingSignals, 0);
      
      for(int sym = 0; sym < g_SymbolCount; sym++) {
         if(!g_Symbols[sym].enabled) continue;
         
         ENUM_MARKET_REGIME regime = data.GetRegime(sym);
         
         for(int s = 0; s < m_strategyCount; s++) {
            if(!m_strategies[s].IsEnabled()) continue;
            
            // Check regime suitability
            double suitability = m_strategies[s].GetRegimeSuitability(regime);
            if(suitability < 0.2) continue;
            
            // Generate signal
            STradeSignal signal = m_strategies[s].Evaluate(sym, data);
            if(signal.direction == SIGNAL_NONE) continue;
            
            // Apply regime suitability to confidence
            signal.confidence *= suitability;
            
            // Apply allocation weight
            signal.confidence *= m_strategies[s].GetWeight();
            
            // Filter by minimum confidence
            if(signal.confidence < 0.15) continue;
            
            // Filter by minimum R:R
            if(signal.riskReward < InpMinRiskReward) continue;
            
            // Add to pending signals
            int newSize = m_pendingCount + 1;
            ArrayResize(m_pendingSignals, newSize);
            m_pendingSignals[m_pendingCount] = signal;
            m_pendingCount++;
         }
      }
      
      // Sort by confidence (descending) using simple bubble sort
      for(int i = 0; i < m_pendingCount - 1; i++) {
         for(int j = 0; j < m_pendingCount - i - 1; j++) {
            if(m_pendingSignals[j].confidence < m_pendingSignals[j+1].confidence) {
               STradeSignal temp = m_pendingSignals[j];
               m_pendingSignals[j] = m_pendingSignals[j+1];
               m_pendingSignals[j+1] = temp;
            }
         }
      }
      
      // Limit signals per tick
      if(m_pendingCount > m_maxSignalsPerTick)
         m_pendingCount = m_maxSignalsPerTick;
      
      return m_pendingCount;
   }
   
   // Check if any strategy wants to exit a position
   bool ShouldExitPosition(int symIdx, ENUM_SIGNAL_TYPE posDir, ENUM_STRATEGY_TYPE strategy, CDataEngine *data) {
      for(int s = 0; s < m_strategyCount; s++) {
         if(m_strategies[s].GetType() == strategy) {
            return m_strategies[s].ShouldExit(symIdx, posDir, data);
         }
      }
      return false;
   }
   
   // Get pending signals
   int GetPendingCount()                    { return m_pendingCount; }
   STradeSignal GetSignal(int idx)          { return m_pendingSignals[idx]; }
   
   // Strategy access
   int GetStrategyCount()                   { return m_strategyCount; }
   CSignalBase* GetStrategy(int idx)        { return (idx < m_strategyCount) ? m_strategies[idx] : NULL; }
   
   CSignalBase* GetStrategyByType(ENUM_STRATEGY_TYPE type) {
      for(int i = 0; i < m_strategyCount; i++) {
         if(m_strategies[i].GetType() == type) return m_strategies[i];
      }
      return NULL;
   }
   
   // Update strategy weights from genetic allocator
   void UpdateWeights(double &weights[]) {
      for(int i = 0; i < m_strategyCount && i < ArraySize(weights); i++) {
         m_strategies[i].SetWeight(weights[i]);
      }
   }
   
   // Notify strategy of trade result
   void NotifyTradeResult(ENUM_STRATEGY_TYPE type, double profit, double profitPct) {
      for(int i = 0; i < m_strategyCount; i++) {
         if(m_strategies[i].GetType() == type) {
            m_strategies[i].UpdateMetrics(profit, profitPct);
            break;
         }
      }
   }
};

#endif // __PHOENIX_SIGNAL_AGGREGATOR_MQH__
