#ifndef __PHOENIX_MONTE_CARLO_SIM_MQH__
#define __PHOENIX_MONTE_CARLO_SIM_MQH__

#include "..\Core\Defines.mqh"

//+------------------------------------------------------------------+
//| Monte Carlo Simulator — Trade order randomization                 |
//| Generates confidence intervals for equity curves                 |
//+------------------------------------------------------------------+
class CMonteCarloSim {
private:
   int    m_simulations;
   double m_startEquity;
   SMonteCarloResult m_result;
   
public:
   CMonteCarloSim() : m_simulations(1000), m_startEquity(10000) {}
   
   void Init(int simulations, double startEquity) {
      m_simulations = MathMin(simulations, MAX_MONTE_CARLO_RUNS);
      m_startEquity = startEquity;
      MathSrand(GetTickCount());
   }
   
   // Run Monte Carlo simulation on trade results
   SMonteCarloResult Run(SBacktestTrade &trades[], int tradeCount, double maxDDThreshold = 30.0) {
      ZeroMemory(m_result);
      if(tradeCount <= 0) return m_result;
      
      double finalEquities[];
      double maxDDs[];
      ArrayResize(finalEquities, m_simulations);
      ArrayResize(maxDDs, m_simulations);
      
      int ruinCount = 0;
      
      for(int sim = 0; sim < m_simulations; sim++) {
         // Create shuffled trade order
         int order[];
         ArrayResize(order, tradeCount);
         for(int i = 0; i < tradeCount; i++) order[i] = i;
         ShuffleArray(order, tradeCount);
         
         // Simulate equity curve with shuffled order
         double equity = m_startEquity;
         double peak = equity;
         double maxDD = 0;
         
         for(int i = 0; i < tradeCount; i++) {
            int idx = order[i];
            // Scale profit to equity-relative (use profitPct)
            double profitPct = trades[idx].profitPct;
            equity += equity * profitPct / 100.0;
            
            if(equity > peak) peak = equity;
            double dd = (peak - equity) / peak * 100.0;
            if(dd > maxDD) maxDD = dd;
            
            // Check ruin
            if(equity <= 0) {
               equity = 0;
               maxDD = 100;
               break;
            }
         }
         
         finalEquities[sim] = equity;
         maxDDs[sim] = maxDD;
         
         if(maxDD >= maxDDThreshold) ruinCount++;
      }
      
      // Sort results
      ArraySort(finalEquities);
      ArraySort(maxDDs);
      
      // Calculate statistics
      double sumEquity = 0;
      for(int i = 0; i < m_simulations; i++) sumEquity += finalEquities[i];
      
      m_result.simulations = m_simulations;
      m_result.meanReturn = (sumEquity / m_simulations - m_startEquity) / m_startEquity * 100.0;
      m_result.medianReturn = (finalEquities[m_simulations / 2] - m_startEquity) / m_startEquity * 100.0;
      
      // Percentiles
      m_result.percentile5 = (finalEquities[(int)(m_simulations * 0.05)] - m_startEquity) / m_startEquity * 100.0;
      m_result.percentile25 = (finalEquities[(int)(m_simulations * 0.25)] - m_startEquity) / m_startEquity * 100.0;
      m_result.percentile75 = (finalEquities[(int)(m_simulations * 0.75)] - m_startEquity) / m_startEquity * 100.0;
      m_result.percentile95 = (finalEquities[(int)(m_simulations * 0.95)] - m_startEquity) / m_startEquity * 100.0;
      
      // Drawdown stats
      double sumDD = 0;
      for(int i = 0; i < m_simulations; i++) sumDD += maxDDs[i];
      m_result.avgMaxDD = sumDD / m_simulations;
      m_result.worstMaxDD = maxDDs[m_simulations - 1];
      m_result.bestMaxDD = maxDDs[0];
      
      // Risk of ruin
      m_result.riskOfRuin = (double)ruinCount / m_simulations * 100.0;
      
      // Standard deviation of returns
      double sumSq = 0;
      for(int i = 0; i < m_simulations; i++) {
         double ret = (finalEquities[i] - m_startEquity) / m_startEquity * 100.0;
         sumSq += MathPow(ret - m_result.meanReturn, 2);
      }
      m_result.stdDevReturn = MathSqrt(sumSq / m_simulations);
      
      return m_result;
   }
   
   SMonteCarloResult GetResult() { return m_result; }

private:
   void ShuffleArray(int &arr[], int size) {
      for(int i = size - 1; i > 0; i--) {
         int j = MathRand() % (i + 1);
         int temp = arr[i];
         arr[i] = arr[j];
         arr[j] = temp;
      }
   }
};

#endif // __PHOENIX_MONTE_CARLO_SIM_MQH__
