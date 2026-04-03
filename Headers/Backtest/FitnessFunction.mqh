#ifndef __PHOENIX_FITNESS_FUNCTION_MQH__
#define __PHOENIX_FITNESS_FUNCTION_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Fitness Function — Custom optimization criteria                   |
//| Used by OnTester() to return custom fitness for optimizer         |
//+------------------------------------------------------------------+
class CFitnessFunction {
private:
   int m_type; // 0=Sharpe, 1=Sortino, 2=Calmar, 3=PF*WR, 4=Composite
   
public:
   CFitnessFunction() : m_type(0) {}
   
   void Init(int type) { m_type = type; }
   
   // Main fitness calculation - called from OnTester()
   double Calculate() {
      // Collect basic statistics from MQL5 tester
      double profit = TesterStatistics(STAT_PROFIT);
      double profitFactor = TesterStatistics(STAT_PROFIT_FACTOR);
      double sharpe = TesterStatistics(STAT_SHARPE_RATIO);
      double maxDD = TesterStatistics(STAT_EQUITY_DD_RELATIVE);
      double trades = TesterStatistics(STAT_TRADES);
      double winRate = 0;
      double totalWins = TesterStatistics(STAT_SHORT_TRADES) > 0 ? 
                         TesterStatistics(STAT_PROFIT_SHORT_TRADES) : 0;
      
      // Minimum trade filter - penalize low trade count
      if(trades < 20) return -999.0;
      
      // Calculate win rate from deal history
      winRate = CalculateWinRate();
      
      switch(m_type) {
         case 0: return CalculateSharpe(profit, trades, maxDD);
         case 1: return CalculateSortino(profit, trades);
         case 2: return CalculateCalmar(profit, maxDD);
         case 3: return CalculatePFxWR(profitFactor, winRate, trades);
         case 4: return CalculateComposite(profit, profitFactor, sharpe, maxDD, trades, winRate);
         default: return sharpe;
      }
   }
   
private:
   double CalculateWinRate() {
      if(!HistorySelect(0, TimeCurrent())) return 0;
      int total = HistoryDealsTotal();
      int wins = 0, count = 0;
      
      for(int i = 0; i < total; i++) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket <= 0) continue;
         
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + 
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP);
         count++;
         if(dealProfit > 0) wins++;
      }
      
      return (count > 0) ? (double)wins / count : 0;
   }
   
   double CalculateSharpe(double profit, double trades, double maxDD) {
      // Custom Sharpe with penalty for low trades and high DD
      double returns[];
      CollectTradeReturns(returns);
      int n = ArraySize(returns);
      if(n < 10) return -999;
      
      double mean = 0;
      for(int i = 0; i < n; i++) mean += returns[i];
      mean /= n;
      
      double variance = 0;
      for(int i = 0; i < n; i++) variance += MathPow(returns[i] - mean, 2);
      variance /= (n - 1);
      double stdDev = MathSqrt(variance);
      
      if(stdDev <= 0) return (mean > 0) ? 10.0 : -999;
      double sharpe = mean / stdDev * MathSqrt(252.0);
      
      // Penalty for excessive drawdown
      if(maxDD > 30) sharpe *= 0.5;
      else if(maxDD > 20) sharpe *= 0.8;
      
      return sharpe;
   }
   
   double CalculateSortino(double profit, double trades) {
      double returns[];
      CollectTradeReturns(returns);
      int n = ArraySize(returns);
      if(n < 10) return -999;
      
      double mean = 0;
      for(int i = 0; i < n; i++) mean += returns[i];
      mean /= n;
      
      double downsideVar = 0;
      int downsideCount = 0;
      for(int i = 0; i < n; i++) {
         if(returns[i] < 0) {
            downsideVar += returns[i] * returns[i];
            downsideCount++;
         }
      }
      
      if(downsideCount <= 0) return (mean > 0) ? 10.0 : 0;
      double downsideStd = MathSqrt(downsideVar / downsideCount);
      if(downsideStd <= 0) return 0;
      
      return mean / downsideStd * MathSqrt(252.0);
   }
   
   double CalculateCalmar(double profit, double maxDD) {
      if(maxDD <= 0) return (profit > 0) ? 10.0 : -999;
      return profit / maxDD;
   }
   
   double CalculatePFxWR(double profitFactor, double winRate, double trades) {
      // Profit Factor × Win Rate, with trade count bonus
      double base = profitFactor * winRate;
      double tradeBonus = MathMin(1.0, trades / 100.0); // Scale up to 100 trades
      return base * (0.5 + 0.5 * tradeBonus);
   }
   
   double CalculateComposite(double profit, double profitFactor, double sharpe,
                              double maxDD, double trades, double winRate) {
      // Comprehensive fitness combining multiple metrics
      double score = 0;
      
      // Sharpe component (30%)
      score += MathMin(3.0, MathMax(-3.0, sharpe)) / 3.0 * 30.0;
      
      // Profit Factor component (20%)
      score += MathMin(3.0, MathMax(0.0, profitFactor - 1.0)) / 2.0 * 20.0;
      
      // Win Rate component (15%)
      score += MathMin(1.0, winRate / 0.6) * 15.0;
      
      // Drawdown penalty (20%) - lower is better
      double ddScore = MathMax(0.0, 1.0 - maxDD / 30.0);
      score += ddScore * 20.0;
      
      // Trade frequency (15%) - need enough trades
      double tradeScore = MathMin(1.0, trades / 100.0);
      score += tradeScore * 15.0;
      
      // Absolute profit bonus
      if(profit > 0) score += MathMin(10.0, profit / 1000.0);
      
      return score;
   }
   
   void CollectTradeReturns(double &returns[]) {
      if(!HistorySelect(0, TimeCurrent())) return;
      int total = HistoryDealsTotal();
      int count = 0;
      
      for(int i = 0; i < total; i++) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket <= 0) continue;
         
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         double dealProfit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP);
         
         ArrayResize(returns, count + 1);
         returns[count] = dealProfit;
         count++;
      }
   }
};

#endif // __PHOENIX_FITNESS_FUNCTION_MQH__
