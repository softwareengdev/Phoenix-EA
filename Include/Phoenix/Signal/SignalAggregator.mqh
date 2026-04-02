//+------------------------------------------------------------------+
//|                                         SignalAggregator.mqh     |
//|                   PHOENIX EA — Multi-Strategy Signal Aggregator    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_AGGREGATOR_MQH__
#define __PHOENIX_SIGNAL_AGGREGATOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "SignalBase.mqh"
#include "SignalTrend.mqh"
#include "SignalMeanRevert.mqh"
#include "SignalBreakout.mqh"
#include "SignalScalper.mqh"

//+------------------------------------------------------------------+
//| CSignalAggregator — Orquestador de múltiples estrategias          |
//|                                                                   |
//| - Inicializa y gestiona las 4 sub-estrategias                    |
//| - Evalúa todas en cada tick/barra                                |
//| - Filtra señales por régimen de mercado y sesión                 |
//| - Pesa señales por confianza y allocation del genético           |
//| - Retorna la mejor señal candidata                               |
//| - Maneja conflictos (señales opuestas simultáneas)               |
//+------------------------------------------------------------------+
class CSignalAggregator
{
private:
   CSignalTrend      m_trendStrats[MAX_SYMBOLS];
   CSignalMeanRevert m_meanRevStrats[MAX_SYMBOLS];
   CSignalBreakout   m_breakoutStrats[MAX_SYMBOLS];
   CSignalScalper    m_scalperStrats[MAX_SYMBOLS];
   
   int               m_symbolCount;
   bool              m_initialized;
   
   // Buffer de señales pendientes
   STradeSignal      m_pendingSignals[];
   int               m_pendingCount;
   
   // Verificar si ya hay posición abierta para esta combinación estrategia+símbolo
   bool HasOpenPosition(ENUM_STRATEGY_TYPE strategy, const string &symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         if(GET_STRATEGY_FROM_MAGIC(magic) != strategy) continue;
         if(PositionGetString(POSITION_SYMBOL) == symbol)
            return true;
      }
      return false;
   }
   
public:
   CSignalAggregator() : m_symbolCount(0), m_initialized(false), m_pendingCount(0) {}
   
   ~CSignalAggregator()
   {
      Deinit();
   }
   
   bool Init()
   {
      g_logger.Info("SignalAggregator: Inicializando estrategias...");
      
      m_symbolCount = g_activeSymbolCount;
      int initCount = 0;
      
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(!g_symbolConfigs[i].enabled) continue;
         
         string sym = g_symbolConfigs[i].symbol;
         ENUM_TIMEFRAMES primaryTF = g_symbolConfigs[i].primaryTF;
         ENUM_TIMEFRAMES entryTF   = g_symbolConfigs[i].entryTF;
         ENUM_TIMEFRAMES confirmTF = g_symbolConfigs[i].confirmTF;
         
         // Inicializar las 4 estrategias para cada símbolo
         if(m_trendStrats[i].Init(sym, primaryTF, entryTF, confirmTF))
            initCount++;
         else
            g_logger.Warning(StringFormat("SignalAggregator: Trend falló para %s", sym));
         
         if(m_meanRevStrats[i].Init(sym, primaryTF, entryTF, confirmTF))
            initCount++;
         else
            g_logger.Warning(StringFormat("SignalAggregator: MeanRev falló para %s", sym));
         
         if(m_breakoutStrats[i].Init(sym, primaryTF, entryTF, confirmTF))
            initCount++;
         else
            g_logger.Warning(StringFormat("SignalAggregator: Breakout falló para %s", sym));
         
         if(m_scalperStrats[i].Init(sym, entryTF, entryTF, primaryTF))
            initCount++;
         else
            g_logger.Warning(StringFormat("SignalAggregator: Scalper falló para %s", sym));
      }
      
      ArrayResize(m_pendingSignals, 0);
      m_pendingCount = 0;
      m_initialized = true;
      
      g_logger.Info(StringFormat("SignalAggregator: %d estrategias inicializadas en %d símbolos",
                    initCount, m_symbolCount));
      return (initCount > 0);
   }
   
   // Evaluar todas las estrategias y recopilar señales
   int Evaluate(ENUM_MARKET_REGIME regimes[], ENUM_TRADING_SESSION session)
   {
      if(!m_initialized) return 0;
      
      ArrayResize(m_pendingSignals, 0);
      m_pendingCount = 0;
      
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(!g_symbolConfigs[i].enabled) continue;
         
         ENUM_MARKET_REGIME regime = (i < ArraySize(regimes)) ? regimes[i] : REGIME_UNKNOWN;
         
         // Evaluar cada estrategia si el régimen es adecuado y está activa
         // Trend Following
         if(m_trendStrats[i].IsActive() && 
            m_trendStrats[i].IsRegimeSuitable(regime) &&
            g_strategyMetrics[STRATEGY_TREND].isActive)
         {
            STradeSignal sig = m_trendStrats[i].Evaluate();
            if(sig.direction != SIGNAL_NONE && !HasOpenPosition(STRATEGY_TREND, sig.symbol))
               AddSignal(sig);
         }
         
         // Mean Reversion
         if(m_meanRevStrats[i].IsActive() && 
            m_meanRevStrats[i].IsRegimeSuitable(regime) &&
            g_strategyMetrics[STRATEGY_MEANREV].isActive)
         {
            STradeSignal sig = m_meanRevStrats[i].Evaluate();
            if(sig.direction != SIGNAL_NONE && !HasOpenPosition(STRATEGY_MEANREV, sig.symbol))
               AddSignal(sig);
         }
         
         // Breakout
         if(m_breakoutStrats[i].IsActive() && 
            m_breakoutStrats[i].IsRegimeSuitable(regime) &&
            g_strategyMetrics[STRATEGY_BREAKOUT].isActive)
         {
            STradeSignal sig = m_breakoutStrats[i].Evaluate();
            if(sig.direction != SIGNAL_NONE && !HasOpenPosition(STRATEGY_BREAKOUT, sig.symbol))
               AddSignal(sig);
         }
         
         // Scalper — solo en sesiones activas
         if(m_scalperStrats[i].IsActive() && 
            m_scalperStrats[i].IsRegimeSuitable(regime) &&
            g_strategyMetrics[STRATEGY_SCALPER].isActive &&
            (session == SESSION_LONDON || session == SESSION_OVERLAP_LN || session == SESSION_NEWYORK))
         {
            STradeSignal sig = m_scalperStrats[i].Evaluate();
            if(sig.direction != SIGNAL_NONE && !HasOpenPosition(STRATEGY_SCALPER, sig.symbol))
               AddSignal(sig);
         }
      }
      
      return m_pendingCount;
   }
   
   // Añadir señal al buffer (ajustada por peso genético)
   void AddSignal(STradeSignal &signal)
   {
      // Ajustar confianza por allocation weight del genético
      int stratIdx = (int)signal.strategy;
      if(stratIdx >= 0 && stratIdx < MAX_STRATEGIES)
      {
         double allocWeight = g_strategyMetrics[stratIdx].allocationWeight;
         signal.confidence *= allocWeight * MAX_STRATEGIES; // Normalizar: si weight = 1/N, factor = 1
      }
      
      ArrayResize(m_pendingSignals, m_pendingCount + 1);
      m_pendingSignals[m_pendingCount] = signal;
      m_pendingCount++;
   }
   
   // Obtener la mejor señal (mayor confianza ajustada)
   bool GetBestSignal(STradeSignal &outSignal)
   {
      if(m_pendingCount == 0) return false;
      
      int bestIdx = 0;
      double bestScore = -1;
      
      for(int i = 0; i < m_pendingCount; i++)
      {
         // Score = confianza * R:R (prioriza mejor calidad)
         double score = m_pendingSignals[i].confidence * 
                       MathMin(3.0, m_pendingSignals[i].riskReward);
         if(score > bestScore)
         {
            bestScore = score;
            bestIdx = i;
         }
      }
      
      outSignal = m_pendingSignals[bestIdx];
      return true;
   }
   
   // Obtener todas las señales pendientes (para multi-posición)
   int GetAllSignals(STradeSignal &outSignals[])
   {
      ArrayResize(outSignals, m_pendingCount);
      for(int i = 0; i < m_pendingCount; i++)
         outSignals[i] = m_pendingSignals[i];
      return m_pendingCount;
   }
   
   void Deinit()
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         m_trendStrats[i].Deinit();
         m_meanRevStrats[i].Deinit();
         m_breakoutStrats[i].Deinit();
         m_scalperStrats[i].Deinit();
      }
      m_initialized = false;
   }
   
   // Getters
   int GetPendingCount() const { return m_pendingCount; }
   bool IsInitialized()  const { return m_initialized; }
   
   // Acceso a estrategias individuales (para ajustar parámetros)
   CSignalTrend*      GetTrendStrategy(int symbolIdx)     { return (symbolIdx >= 0 && symbolIdx < m_symbolCount) ? &m_trendStrats[symbolIdx] : NULL; }
   CSignalMeanRevert* GetMeanRevStrategy(int symbolIdx)   { return (symbolIdx >= 0 && symbolIdx < m_symbolCount) ? &m_meanRevStrats[symbolIdx] : NULL; }
   CSignalBreakout*   GetBreakoutStrategy(int symbolIdx)  { return (symbolIdx >= 0 && symbolIdx < m_symbolCount) ? &m_breakoutStrats[symbolIdx] : NULL; }
   CSignalScalper*    GetScalperStrategy(int symbolIdx)   { return (symbolIdx >= 0 && symbolIdx < m_symbolCount) ? &m_scalperStrats[symbolIdx] : NULL; }
};

#endif // __PHOENIX_SIGNAL_AGGREGATOR_MQH__
//+------------------------------------------------------------------+
