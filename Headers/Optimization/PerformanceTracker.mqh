#ifndef __PHOENIX_PERFORMANCE_TRACKER_MQH__
#define __PHOENIX_PERFORMANCE_TRACKER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Performance Tracker — Strategy-level metrics with rolling window  |
//+------------------------------------------------------------------+
class CPerformanceTracker {
private:
   SBacktestTrade m_tradeHistory[];
   int            m_historyCount;
   int            m_maxHistory;
   double         m_dailyReturns[];
   int            m_dailyReturnCount;
   
public:
   CPerformanceTracker() : m_historyCount(0), m_maxHistory(1000), m_dailyReturnCount(0) {}
   
   void Init(int maxHistory = 1000) {
      m_maxHistory = maxHistory;
      ArrayResize(m_tradeHistory, 0);
      ArrayResize(m_dailyReturns, 0);
      m_historyCount = 0;
      m_dailyReturnCount = 0;
   }
   
   void RecordTrade(SBacktestTrade &trade) {
      if(m_historyCount >= m_maxHistory) {
         // Shift array: remove oldest
         for(int i = 0; i < m_historyCount - 1; i++)
            m_tradeHistory[i] = m_tradeHistory[i + 1];
         m_historyCount--;
      }
      ArrayResize(m_tradeHistory, m_historyCount + 1);
      m_tradeHistory[m_historyCount] = trade;
      m_historyCount++;
   }
   
   void RecordDailyReturn(double returnPct) {
      ArrayResize(m_dailyReturns, m_dailyReturnCount + 1);
      m_dailyReturns[m_dailyReturnCount] = returnPct;
      m_dailyReturnCount++;
   }
   
   // Calculate Sharpe ratio (annualized)
   double CalculateSharpe(double riskFreeRate = 0.02) {
      if(m_dailyReturnCount < 10) return 0;
      
      double mean = 0, variance = 0;
      for(int i = 0; i < m_dailyReturnCount; i++)
         mean += m_dailyReturns[i];
      mean /= m_dailyReturnCount;
      
      for(int i = 0; i < m_dailyReturnCount; i++)
         variance += MathPow(m_dailyReturns[i] - mean, 2);
      variance /= (m_dailyReturnCount - 1);
      
      double stdDev = MathSqrt(variance);
      if(stdDev <= 0) return 0;
      
      double dailyRF = riskFreeRate / 252.0;
      double sharpe = (mean - dailyRF) / stdDev * MathSqrt(252.0);
      return sharpe;
   }
   
   // Calculate Sortino ratio (penalizes only downside volatility)
   double CalculateSortino(double riskFreeRate = 0.02) {
      if(m_dailyReturnCount < 10) return 0;
      
      double mean = 0;
      for(int i = 0; i < m_dailyReturnCount; i++)
         mean += m_dailyReturns[i];
      mean /= m_dailyReturnCount;
      
      double downsideVariance = 0;
      int downsideCount = 0;
      double dailyRF = riskFreeRate / 252.0;
      for(int i = 0; i < m_dailyReturnCount; i++) {
         if(m_dailyReturns[i] < dailyRF) {
            downsideVariance += MathPow(m_dailyReturns[i] - dailyRF, 2);
            downsideCount++;
         }
      }
      
      if(downsideCount <= 0) return (mean > 0) ? 99.9 : 0;
      downsideVariance /= downsideCount;
      double downsideStd = MathSqrt(downsideVariance);
      if(downsideStd <= 0) return 0;
      
      return (mean - dailyRF) / downsideStd * MathSqrt(252.0);
   }
   
   // Calculate Calmar ratio
   double CalculateCalmar() {
      if(m_dailyReturnCount < 20) return 0;
      
      double totalReturn = 0;
      for(int i = 0; i < m_dailyReturnCount; i++)
         totalReturn += m_dailyReturns[i];
      
      double annualizedReturn = totalReturn / m_dailyReturnCount * 252.0;
      double maxDD = g_State.maxDrawdownPct;
      
      if(maxDD <= 0) return (annualizedReturn > 0) ? 99.9 : 0;
      return annualizedReturn / maxDD;
   }
   
   // Get strategy-specific metrics
   SStrategyMetrics CalculateStrategyMetrics(ENUM_STRATEGY_TYPE strategy) {
      SStrategyMetrics metrics;
      ZeroMemory(metrics);
      metrics.strategy = strategy;
      
      double profits[];
      int profitCount = 0;
      
      for(int i = 0; i < m_historyCount; i++) {
         if(m_tradeHistory[i].strategy != strategy) continue;
         
         metrics.totalTrades++;
         double p = m_tradeHistory[i].profit;
         
         ArrayResize(profits, profitCount + 1);
         profits[profitCount] = p;
         profitCount++;
         
         if(p > 0) {
            metrics.winTrades++;
            metrics.totalProfit += p;
         } else {
            metrics.lossTrades++;
            metrics.totalLoss += MathAbs(p);
         }
      }
      
      if(metrics.totalTrades > 0) {
         metrics.winRate = (double)metrics.winTrades / metrics.totalTrades;
         metrics.avgWin = (metrics.winTrades > 0) ? metrics.totalProfit / metrics.winTrades : 0;
         metrics.avgLoss = (metrics.lossTrades > 0) ? metrics.totalLoss / metrics.lossTrades : 0;
         metrics.profitFactor = (metrics.totalLoss > 0) ? metrics.totalProfit / metrics.totalLoss : 99.9;
         metrics.expectancy = (metrics.winRate * metrics.avgWin) - ((1.0 - metrics.winRate) * metrics.avgLoss);
         metrics.netProfit = metrics.totalProfit - metrics.totalLoss;
      }
      
      // Sharpe for this strategy
      if(profitCount > 5) {
         double mean = 0, variance = 0;
         for(int i = 0; i < profitCount; i++) mean += profits[i];
         mean /= profitCount;
         for(int i = 0; i < profitCount; i++) variance += MathPow(profits[i] - mean, 2);
         variance /= (profitCount - 1);
         double stdDev = MathSqrt(variance);
         metrics.sharpeRatio = (stdDev > 0) ? mean / stdDev * MathSqrt(252.0 / MathMax(1, profitCount)) : 0;
      }
      
      return metrics;
   }
   
   // Build equity curve from trade history
   int BuildEquityCurve(SEquityCurvePoint &curve[]) {
      if(m_historyCount <= 0) return 0;
      
      ArrayResize(curve, m_historyCount);
      double equity = 10000; // Starting equity for normalization
      double peak = equity;
      
      for(int i = 0; i < m_historyCount; i++) {
         equity += m_tradeHistory[i].profit;
         peak = MathMax(peak, equity);
         
         curve[i].time = m_tradeHistory[i].closeTime;
         curve[i].equity = equity;
         curve[i].balance = equity;
         curve[i].drawdown = peak - equity;
         curve[i].drawdownPct = (peak > 0) ? (peak - equity) / peak : 0;
      }
      return m_historyCount;
   }
   
   int GetTradeCount()       { return m_historyCount; }
   int GetDailyReturnCount() { return m_dailyReturnCount; }
   
   bool GetTrade(int idx, SBacktestTrade &out) {
      if(idx >= 0 && idx < m_historyCount) { out = m_tradeHistory[idx]; return true; }
      return false;
   }
   
   void GetAllTrades(SBacktestTrade &trades[]) {
      ArrayResize(trades, m_historyCount);
      for(int i = 0; i < m_historyCount; i++)
         trades[i] = m_tradeHistory[i];
   }
   
   void GetDailyReturns(double &returns[]) {
      ArrayResize(returns, m_dailyReturnCount);
      for(int i = 0; i < m_dailyReturnCount; i++)
         returns[i] = m_dailyReturns[i];
   }
};

#endif // __PHOENIX_PERFORMANCE_TRACKER_MQH__
