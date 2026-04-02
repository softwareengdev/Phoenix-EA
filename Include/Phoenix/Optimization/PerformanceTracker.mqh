//+------------------------------------------------------------------+
//|                                        PerformanceTracker.mqh    |
//|                  PHOENIX EA — Strategy Performance Tracking       |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_PERFORMANCE_TRACKER_MQH__
#define __PHOENIX_PERFORMANCE_TRACKER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CPerformanceTracker — Seguimiento de rendimiento por estrategia   |
//|                                                                   |
//| Analiza el historial de operaciones cerradas para calcular        |
//| metricas de cada estrategia: win rate, profit factor, Sharpe,     |
//| expectancia, drawdown. Alimenta al GeneticAllocator.              |
//+------------------------------------------------------------------+
class CPerformanceTracker
{
private:
   bool     m_initialized;
   datetime m_lastUpdate;
   int      m_windowHours;     // Ventana de analisis en horas
   
   // Historial de retornos por estrategia (para Sharpe)
   double   m_dailyReturns[][MAX_STRATEGIES];
   int      m_returnCount;
   
public:
   CPerformanceTracker() : m_initialized(false), m_lastUpdate(0),
                            m_windowHours(PERFORMANCE_WINDOW), m_returnCount(0) {}
   
   bool Init(int windowHours = PERFORMANCE_WINDOW)
   {
      m_windowHours = windowHours;
      m_returnCount = 0;
      ArrayResize(m_dailyReturns, 365); // Max 1 year of daily returns
      m_initialized = true;
      
      // Calcular metricas iniciales desde historial existente
      RecalculateAll();
      
      g_logger.Info(StringFormat("PerformanceTracker: Init [window=%dh]", m_windowHours));
      return true;
   }
   
   // Recalcular todas las metricas desde el historial de operaciones
   void RecalculateAll()
   {
      if(!m_initialized) return;
      
      datetime from = TimeCurrent() - m_windowHours * 3600;
      
      // Reset metricas
      for(int s = 0; s < MAX_STRATEGIES; s++)
      {
         g_strategyMetrics[s].totalTrades = 0;
         g_strategyMetrics[s].winTrades   = 0;
         g_strategyMetrics[s].lossTrades  = 0;
         g_strategyMetrics[s].totalProfit = 0;
         g_strategyMetrics[s].totalLoss   = 0;
      }
      
      // Iterar historial de deals
      HistorySelect(from, TimeCurrent());
      int totalDeals = HistoryDealsTotal();
      
      for(int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         // Solo deals de salida (con P&L)
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) 
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         ENUM_STRATEGY_TYPE strat = GET_STRATEGY_FROM_MAGIC(magic);
         if(strat < 0 || strat >= MAX_STRATEGIES) continue;
         
         g_strategyMetrics[strat].totalTrades++;
         
         if(profit >= 0)
         {
            g_strategyMetrics[strat].winTrades++;
            g_strategyMetrics[strat].totalProfit += profit;
         }
         else
         {
            g_strategyMetrics[strat].lossTrades++;
            g_strategyMetrics[strat].totalLoss += profit; // Negativo
         }
         
         g_strategyMetrics[strat].lastTradeTime = 
            (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      }
      
      // Calcular metricas derivadas
      for(int s = 0; s < MAX_STRATEGIES; s++)
      {
         g_strategyMetrics[s].Calculate();
         CalculateSharpe(s);
      }
      
      m_lastUpdate = TimeCurrent();
   }
   
   // Calcular Sharpe ratio simplificado para una estrategia
   void CalculateSharpe(int stratIndex)
   {
      if(stratIndex < 0 || stratIndex >= MAX_STRATEGIES) return;
      if(g_strategyMetrics[stratIndex].totalTrades < 10)
      {
         g_strategyMetrics[stratIndex].sharpeRatio = 0.0;
         return;
      }
      
      // Recopilar P&L por trade
      datetime from = TimeCurrent() - m_windowHours * 3600;
      HistorySelect(from, TimeCurrent());
      
      double profits[];
      ArrayResize(profits, 0);
      int count = 0;
      
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         if(GET_STRATEGY_FROM_MAGIC(magic) != stratIndex) continue;
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
         
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                       + HistoryDealGetDouble(ticket, DEAL_SWAP)
                       + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         ArrayResize(profits, count + 1);
         profits[count++] = profit;
      }
      
      if(count < 5)
      {
         g_strategyMetrics[stratIndex].sharpeRatio = 0.0;
         return;
      }
      
      // Media y desviacion estandar
      double sum = 0;
      for(int i = 0; i < count; i++)
         sum += profits[i];
      double mean = sum / count;
      
      double sumSq = 0;
      for(int i = 0; i < count; i++)
         sumSq += (profits[i] - mean) * (profits[i] - mean);
      double stdDev = MathSqrt(sumSq / (count - 1));
      
      if(stdDev > 0)
         g_strategyMetrics[stratIndex].sharpeRatio = (mean / stdDev) * MathSqrt(252.0); // Annualizado
      else
         g_strategyMetrics[stratIndex].sharpeRatio = 0.0;
   }
   
   // Registrar nuevo trade cerrado
   void OnTradeClosed(ENUM_STRATEGY_TYPE strategy, double profit)
   {
      RecalculateAll(); // Recalcular todo por simplicidad y precision
   }
   
   // Actualizar periodicamente (cada hora)
   void Update()
   {
      if(!m_initialized) return;
      if(TimeCurrent() - m_lastUpdate > 3600)
         RecalculateAll();
   }
   
   // Obtener la mejor estrategia activa
   int GetBestStrategy() const
   {
      int best = -1;
      double bestExpectancy = -999999;
      
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(!g_strategyMetrics[i].isActive) continue;
         if(g_strategyMetrics[i].totalTrades < 10) continue;
         if(g_strategyMetrics[i].expectancy > bestExpectancy)
         {
            bestExpectancy = g_strategyMetrics[i].expectancy;
            best = i;
         }
      }
      return best;
   }
   
   datetime GetLastUpdate() const { return m_lastUpdate; }
};

#endif // __PHOENIX_PERFORMANCE_TRACKER_MQH__
//+------------------------------------------------------------------+
