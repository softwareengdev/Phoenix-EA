#ifndef __PHOENIX_BACKTEST_ENGINE_MQH__
#define __PHOENIX_BACKTEST_ENGINE_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "..\Optimization\PerformanceTracker.mqh"
#include "FitnessFunction.mqh"

//+------------------------------------------------------------------+
//| Backtest Engine — Trade collection, statistics, OnTester support  |
//+------------------------------------------------------------------+
class CBacktestEngine {
private:
   SBacktestTrade    m_trades[];
   int               m_tradeCount;
   SEquityCurvePoint m_equityCurve[];
   int               m_equityPoints;
   CFitnessFunction  m_fitness;
   double            m_startEquity;
   double            m_peakEquity;
   double            m_maxDrawdown;
   double            m_maxDrawdownPct;
   datetime          m_startTime;
   datetime          m_endTime;
   
public:
   CBacktestEngine() : m_tradeCount(0), m_equityPoints(0), m_startEquity(0),
                         m_peakEquity(0), m_maxDrawdown(0), m_maxDrawdownPct(0) {}
   
   void Init() {
      m_fitness.Init(InpCustomFitness);
      m_startEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_peakEquity = m_startEquity;
      m_startTime = TimeCurrent();
      ArrayResize(m_trades, 0);
      ArrayResize(m_equityCurve, 0);
      m_tradeCount = 0;
      m_equityPoints = 0;
   }
   
   // Called from OnTrade() to record completed trades
   void OnTradeEvent() {
      if(!HistorySelect(m_startTime, TimeCurrent())) return;
      
      int total = HistoryDealsTotal();
      for(int i = total - 1; i >= 0; i--) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket <= 0) continue;
         
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         // Check if already recorded
         if(IsTradeRecorded(ticket)) continue;
         
         SBacktestTrade trade;
         ZeroMemory(trade);
         trade.ticket = (int)ticket;
         trade.strategy = DECODE_STRATEGY(magic);
         trade.symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         trade.closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
         trade.volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         trade.profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP);
         trade.commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         trade.swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
         trade.closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
         trade.direction = (dealType == DEAL_TYPE_SELL) ? SIGNAL_BUY : SIGNAL_SELL;
         
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         trade.equityAtOpen = (equity > 0) ? equity - trade.profit : m_startEquity;
         trade.profitPct = (trade.equityAtOpen > 0) ? trade.profit / trade.equityAtOpen * 100.0 : 0;
         
         ArrayResize(m_trades, m_tradeCount + 1);
         m_trades[m_tradeCount] = trade;
         m_tradeCount++;
         
         // Update equity curve
         UpdateEquityCurve(equity, trade.closeTime);
      }
   }
   
   // Called from OnTester() — returns custom fitness
   double GetCustomFitness() {
      return m_fitness.Calculate();
   }
   
   // Collect all trade history for analysis
   void CollectFullHistory() {
      if(!HistorySelect(0, TimeCurrent())) return;
      
      m_tradeCount = 0;
      ArrayResize(m_trades, 0);
      
      int total = HistoryDealsTotal();
      double runningEquity = m_startEquity;
      
      for(int i = 0; i < total; i++) {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket <= 0) continue;
         
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT) continue;
         
         long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         SBacktestTrade trade;
         ZeroMemory(trade);
         trade.ticket = (int)ticket;
         trade.strategy = DECODE_STRATEGY(magic);
         trade.symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
         trade.closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
         trade.volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
         trade.profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                        HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                        HistoryDealGetDouble(ticket, DEAL_SWAP);
         trade.commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         trade.swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
         trade.closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         
         long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
         trade.direction = (dealType == DEAL_TYPE_SELL) ? SIGNAL_BUY : SIGNAL_SELL;
         trade.equityAtOpen = runningEquity;
         trade.profitPct = (runningEquity > 0) ? trade.profit / runningEquity * 100.0 : 0;
         
         runningEquity += trade.profit;
         
         ArrayResize(m_trades, m_tradeCount + 1);
         m_trades[m_tradeCount] = trade;
         m_tradeCount++;
         
         UpdateEquityCurve(runningEquity, trade.closeTime);
      }
      
      m_endTime = TimeCurrent();
   }
   
   // Statistics
   double GetTotalProfit() {
      double sum = 0;
      for(int i = 0; i < m_tradeCount; i++) sum += m_trades[i].profit;
      return sum;
   }
   
   double GetWinRate() {
      if(m_tradeCount == 0) return 0;
      int wins = 0;
      for(int i = 0; i < m_tradeCount; i++)
         if(m_trades[i].profit > 0) wins++;
      return (double)wins / m_tradeCount;
   }
   
   double GetProfitFactor() {
      double gross = 0, loss = 0;
      for(int i = 0; i < m_tradeCount; i++) {
         if(m_trades[i].profit > 0) gross += m_trades[i].profit;
         else loss += MathAbs(m_trades[i].profit);
      }
      return (loss > 0) ? gross / loss : (gross > 0 ? 99.9 : 0);
   }
   
   double GetMaxDrawdownPct() { return m_maxDrawdownPct; }
   int    GetTradeCount()      { return m_tradeCount; }
   
   void GetTrades(SBacktestTrade &trades[]) {
      ArrayResize(trades, m_tradeCount);
      for(int i = 0; i < m_tradeCount; i++)
         trades[i] = m_trades[i];
   }
   
   void GetEquityCurve(SEquityCurvePoint &curve[]) {
      ArrayResize(curve, m_equityPoints);
      for(int i = 0; i < m_equityPoints; i++)
         curve[i] = m_equityCurve[i];
   }
   
   datetime GetStartTime() { return m_startTime; }
   datetime GetEndTime()   { return m_endTime; }

private:
   bool IsTradeRecorded(ulong ticket) {
      for(int i = m_tradeCount - 1; i >= MathMax(0, m_tradeCount - 20); i--)
         if(m_trades[i].ticket == (int)ticket) return true;
      return false;
   }
   
   void UpdateEquityCurve(double equity, datetime time) {
      if(equity > m_peakEquity) m_peakEquity = equity;
      double dd = m_peakEquity - equity;
      double ddPct = (m_peakEquity > 0) ? dd / m_peakEquity * 100.0 : 0;
      if(ddPct > m_maxDrawdownPct) {
         m_maxDrawdownPct = ddPct;
         m_maxDrawdown = dd;
      }
      
      ArrayResize(m_equityCurve, m_equityPoints + 1);
      m_equityCurve[m_equityPoints].time = time;
      m_equityCurve[m_equityPoints].equity = equity;
      m_equityCurve[m_equityPoints].balance = equity;
      m_equityCurve[m_equityPoints].drawdown = dd;
      m_equityCurve[m_equityPoints].drawdownPct = ddPct / 100.0;
      m_equityPoints++;
   }
};

#endif // __PHOENIX_BACKTEST_ENGINE_MQH__
