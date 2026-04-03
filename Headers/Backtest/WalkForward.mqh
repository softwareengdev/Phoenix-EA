#ifndef __PHOENIX_WALK_FORWARD_MQH__
#define __PHOENIX_WALK_FORWARD_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Walk-Forward Analysis — In-sample/Out-of-sample validation       |
//| Divides backtest period into windows for robustness testing      |
//+------------------------------------------------------------------+
class CWalkForward {
private:
   SWalkForwardResult m_results[];
   int                m_windowCount;
   double             m_oosRatio;
   double             m_efficiencyThreshold;
   bool               m_passed;
   double             m_avgEfficiency;
   
public:
   CWalkForward() : m_windowCount(0), m_oosRatio(0.25), m_efficiencyThreshold(0.5),
                     m_passed(false), m_avgEfficiency(0) {}
   
   void Init(int windows, double oosRatio) {
      m_windowCount = MathMin(windows, MAX_WF_WINDOWS);
      m_oosRatio = MathMax(0.1, MathMin(0.5, oosRatio));
      ArrayResize(m_results, m_windowCount);
   }
   
   // Analyze trades by splitting into walk-forward windows
   bool Analyze(SBacktestTrade &trades[], int tradeCount, datetime startTime, datetime endTime) {
      if(tradeCount < m_windowCount * 10) return false; // Need enough trades
      
      long totalDuration = (long)(endTime - startTime);
      if(totalDuration <= 0) return false;
      
      long windowDuration = totalDuration / m_windowCount;
      long oosDuration = (long)(windowDuration * m_oosRatio);
      long isDuration = windowDuration - oosDuration;
      
      double sumEfficiency = 0;
      int validWindows = 0;
      
      for(int w = 0; w < m_windowCount; w++) {
         ZeroMemory(m_results[w]);
         m_results[w].windowIndex = w;
         
         // Define IS and OOS periods
         datetime windowStart = startTime + (datetime)(w * windowDuration);
         m_results[w].isStart = windowStart;
         m_results[w].isEnd = windowStart + (datetime)isDuration;
         m_results[w].oosStart = m_results[w].isEnd;
         m_results[w].oosEnd = windowStart + (datetime)windowDuration;
         
         // Collect IS trades
         double isProfit = 0, isLoss = 0;
         double isReturns[];
         int isRetCount = 0;
         double isPeakEq = 10000, isEquity = 10000, isMaxDD = 0;
         
         for(int i = 0; i < tradeCount; i++) {
            if(trades[i].closeTime >= m_results[w].isStart && trades[i].closeTime < m_results[w].isEnd) {
               isEquity += trades[i].profit;
               if(isEquity > isPeakEq) isPeakEq = isEquity;
               double dd = (isPeakEq - isEquity) / isPeakEq * 100.0;
               if(dd > isMaxDD) isMaxDD = dd;
               
               ArrayResize(isReturns, isRetCount + 1);
               isReturns[isRetCount] = trades[i].profit;
               isRetCount++;
               
               if(trades[i].profit > 0) isProfit += trades[i].profit;
               else isLoss += MathAbs(trades[i].profit);
            }
         }
         
         m_results[w].isProfit = isProfit - isLoss;
         m_results[w].isMaxDD = isMaxDD;
         m_results[w].isSharpe = CalculateSharpe(isReturns, isRetCount);
         
         // Collect OOS trades
         double oosProfit = 0, oosLoss = 0;
         double oosReturns[];
         int oosRetCount = 0;
         double oosPeakEq = 10000, oosEquity = 10000, oosMaxDD = 0;
         
         for(int i = 0; i < tradeCount; i++) {
            if(trades[i].closeTime >= m_results[w].oosStart && trades[i].closeTime < m_results[w].oosEnd) {
               oosEquity += trades[i].profit;
               if(oosEquity > oosPeakEq) oosPeakEq = oosEquity;
               double dd = (oosPeakEq - oosEquity) / oosPeakEq * 100.0;
               if(dd > oosMaxDD) oosMaxDD = dd;
               
               ArrayResize(oosReturns, oosRetCount + 1);
               oosReturns[oosRetCount] = trades[i].profit;
               oosRetCount++;
               
               if(trades[i].profit > 0) oosProfit += trades[i].profit;
               else oosLoss += MathAbs(trades[i].profit);
            }
         }
         
         m_results[w].oosProfit = oosProfit - oosLoss;
         m_results[w].oosMaxDD = oosMaxDD;
         m_results[w].oosSharpe = CalculateSharpe(oosReturns, oosRetCount);
         
         // Calculate efficiency (OOS/IS ratio)
         if(m_results[w].isSharpe > 0) {
            m_results[w].efficiency = m_results[w].oosSharpe / m_results[w].isSharpe;
         } else {
            m_results[w].efficiency = (m_results[w].oosSharpe > 0) ? 1.0 : 0;
         }
         
         m_results[w].passed = (m_results[w].efficiency >= m_efficiencyThreshold && 
                                m_results[w].oosProfit > 0);
         
         if(isRetCount > 0 || oosRetCount > 0) {
            sumEfficiency += m_results[w].efficiency;
            validWindows++;
         }
      }
      
      m_avgEfficiency = (validWindows > 0) ? sumEfficiency / validWindows : 0;
      
      // Overall pass: majority of windows must pass
      int passCount = 0;
      for(int w = 0; w < m_windowCount; w++)
         if(m_results[w].passed) passCount++;
      
      m_passed = (passCount > m_windowCount / 2);
      return true;
   }
   
   bool     Passed()            { return m_passed; }
   double   GetAvgEfficiency()  { return m_avgEfficiency; }
   int      GetWindowCount()    { return m_windowCount; }
   
   SWalkForwardResult GetWindowResult(int idx) {
      if(idx >= 0 && idx < m_windowCount) return m_results[idx];
      SWalkForwardResult empty;
      ZeroMemory(empty);
      return empty;
   }
   
   void GetAllResults(SWalkForwardResult &results[]) {
      ArrayResize(results, m_windowCount);
      for(int i = 0; i < m_windowCount; i++)
         results[i] = m_results[i];
   }

private:
   double CalculateSharpe(double &returns[], int count) {
      if(count < 3) return 0;
      double mean = 0;
      for(int i = 0; i < count; i++) mean += returns[i];
      mean /= count;
      
      double variance = 0;
      for(int i = 0; i < count; i++) variance += MathPow(returns[i] - mean, 2);
      variance /= (count - 1);
      
      double stdDev = MathSqrt(variance);
      if(stdDev <= 0) return (mean > 0) ? 5.0 : 0;
      return mean / stdDev * MathSqrt(MathMin(252.0, (double)count));
   }
};

#endif // __PHOENIX_WALK_FORWARD_MQH__
