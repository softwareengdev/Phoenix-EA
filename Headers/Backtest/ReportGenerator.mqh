#ifndef __PHOENIX_REPORT_GENERATOR_MQH__
#define __PHOENIX_REPORT_GENERATOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "MonteCarloSim.mqh"
#include "WalkForward.mqh"

//+------------------------------------------------------------------+
//| Report Generator — HTML backtest report with detailed analysis   |
//+------------------------------------------------------------------+
class CReportGenerator {
private:
   string m_reportFile;

public:
   CReportGenerator() {}
   
   bool GenerateReport(SBacktestTrade &trades[], int tradeCount,
                        SEquityCurvePoint &equity[], int equityPoints,
                        SMonteCarloResult &mcResult,
                        SWalkForwardResult &wfResults[], int wfWindows,
                        SStrategyMetrics &stratMetrics[], int stratCount) {
      
      string dir = "Phoenix\\reports";
      FolderCreate(dir);
      m_reportFile = dir + "\\Phoenix_Report_" + 
                     TimeToString(TimeCurrent(), TIME_DATE) + ".html";
      StringReplace(m_reportFile, ".", "_");
      StringReplace(m_reportFile, ":", "_");
      m_reportFile = dir + "\\Phoenix_Report.html";
      
      int handle = FileOpen(m_reportFile, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle == INVALID_HANDLE) return false;
      
      // HTML Header
      FileWriteString(handle, "<!DOCTYPE html><html><head><meta charset='utf-8'>\n");
      FileWriteString(handle, "<title>Phoenix EA - Backtest Report</title>\n");
      FileWriteString(handle, "<style>\n");
      FileWriteString(handle, "body{font-family:'Segoe UI',Arial,sans-serif;margin:20px;background:#1a1a2e;color:#eee;}\n");
      FileWriteString(handle, "h1{color:#e94560;border-bottom:2px solid #e94560;padding-bottom:10px;}\n");
      FileWriteString(handle, "h2{color:#0f3460;background:#16213e;padding:10px;border-radius:5px;color:#e94560;}\n");
      FileWriteString(handle, "table{border-collapse:collapse;width:100%;margin:15px 0;}\n");
      FileWriteString(handle, "th{background:#0f3460;color:#fff;padding:10px;text-align:left;}\n");
      FileWriteString(handle, "td{padding:8px;border-bottom:1px solid #333;}\n");
      FileWriteString(handle, "tr:hover{background:#16213e;}\n");
      FileWriteString(handle, ".positive{color:#00ff88;font-weight:bold;}\n");
      FileWriteString(handle, ".negative{color:#ff4444;font-weight:bold;}\n");
      FileWriteString(handle, ".card{background:#16213e;border-radius:10px;padding:20px;margin:15px 0;}\n");
      FileWriteString(handle, ".metric{display:inline-block;width:200px;margin:10px;text-align:center;}\n");
      FileWriteString(handle, ".metric .value{font-size:24px;font-weight:bold;}\n");
      FileWriteString(handle, ".metric .label{font-size:12px;color:#888;}\n");
      FileWriteString(handle, ".bar{height:20px;background:#0f3460;border-radius:3px;margin:2px 0;}\n");
      FileWriteString(handle, ".bar-fill{height:100%;border-radius:3px;}\n");
      FileWriteString(handle, ".pass{color:#00ff88;} .fail{color:#ff4444;}\n");
      FileWriteString(handle, "</style></head><body>\n");
      
      // Title
      FileWriteString(handle, StringFormat("<h1>🔥 Phoenix EA — Backtest Report</h1>\n"));
      FileWriteString(handle, StringFormat("<p>Generated: %s | Period: %s to %s</p>\n",
         TimeToString(TimeCurrent()), 
         tradeCount > 0 ? TimeToString(trades[0].closeTime, TIME_DATE) : "N/A",
         tradeCount > 0 ? TimeToString(trades[tradeCount-1].closeTime, TIME_DATE) : "N/A"));
      
      // Summary Section
      WriteSummarySection(handle, trades, tradeCount);
      
      // Strategy Breakdown
      WriteStrategySection(handle, stratMetrics, stratCount);
      
      // Equity Curve (text-based chart)
      WriteEquitySection(handle, equity, equityPoints);
      
      // Monthly Breakdown
      WriteMonthlySection(handle, trades, tradeCount);
      
      // Monte Carlo Section
      WriteMonteCarloSection(handle, mcResult);
      
      // Walk-Forward Section
      WriteWalkForwardSection(handle, wfResults, wfWindows);
      
      // Trade Log
      WriteTradeLog(handle, trades, tradeCount);
      
      // Footer
      FileWriteString(handle, "<hr><p style='text-align:center;color:#666;'>Phoenix EA v" + PHOENIX_VERSION + " — Autonomous Trading System</p>\n");
      FileWriteString(handle, "</body></html>\n");
      
      FileClose(handle);
      
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("Report generated: %s", m_reportFile));
      return true;
   }

private:
   void WriteSummarySection(int handle, SBacktestTrade &trades[], int count) {
      if(count <= 0) return;
      
      double totalProfit = 0, grossProfit = 0, grossLoss = 0;
      int wins = 0;
      double maxDD = 0, peak = 10000, equity = 10000;
      
      for(int i = 0; i < count; i++) {
         totalProfit += trades[i].profit;
         if(trades[i].profit > 0) { grossProfit += trades[i].profit; wins++; }
         else grossLoss += MathAbs(trades[i].profit);
         
         equity += trades[i].profit;
         if(equity > peak) peak = equity;
         double dd = (peak - equity) / peak * 100.0;
         if(dd > maxDD) maxDD = dd;
      }
      
      double winRate = (count > 0) ? (double)wins / count * 100.0 : 0;
      double pf = (grossLoss > 0) ? grossProfit / grossLoss : 99.9;
      double avgWin = (wins > 0) ? grossProfit / wins : 0;
      double avgLoss = (count - wins > 0) ? grossLoss / (count - wins) : 0;
      double expectancy = (winRate / 100.0 * avgWin) - ((1.0 - winRate / 100.0) * avgLoss);
      
      FileWriteString(handle, "<h2>📊 Summary Statistics</h2>\n<div class='card'>\n");
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value %s'>%.2f</div><div class='label'>Net Profit</div></div>\n",
         totalProfit >= 0 ? "positive" : "negative", totalProfit));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value'>%d</div><div class='label'>Total Trades</div></div>\n", count));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value %s'>%.1f%%</div><div class='label'>Win Rate</div></div>\n",
         winRate >= 50 ? "positive" : "negative", winRate));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value %s'>%.2f</div><div class='label'>Profit Factor</div></div>\n",
         pf >= 1.5 ? "positive" : "negative", pf));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value negative'>%.1f%%</div><div class='label'>Max Drawdown</div></div>\n", maxDD));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value'>%.2f</div><div class='label'>Expectancy</div></div>\n", expectancy));
      FileWriteString(handle, "</div>\n");
   }
   
   void WriteStrategySection(int handle, SStrategyMetrics &metrics[], int count) {
      if(count <= 0) return;
      FileWriteString(handle, "<h2>🎯 Strategy Breakdown</h2>\n");
      FileWriteString(handle, "<table><tr><th>Strategy</th><th>Trades</th><th>Win Rate</th><th>PF</th><th>Sharpe</th><th>Max DD</th><th>Net P/L</th><th>Weight</th></tr>\n");
      
      for(int i = 0; i < count; i++) {
         string pnlClass = (metrics[i].netProfit >= 0) ? "positive" : "negative";
         FileWriteString(handle, StringFormat(
            "<tr><td>%s</td><td>%d</td><td>%.1f%%</td><td>%.2f</td><td>%.2f</td><td>%.1f%%</td><td class='%s'>%.2f</td><td>%.1f%%</td></tr>\n",
            EnumToString(metrics[i].strategy), metrics[i].totalTrades,
            metrics[i].winRate * 100, metrics[i].profitFactor,
            metrics[i].sharpeRatio, metrics[i].maxDrawdownPct * 100,
            pnlClass, metrics[i].netProfit,
            metrics[i].allocationWeight * 100));
      }
      FileWriteString(handle, "</table>\n");
   }
   
   void WriteEquitySection(int handle, SEquityCurvePoint &curve[], int points) {
      if(points <= 0) return;
      FileWriteString(handle, "<h2>📈 Equity Curve</h2>\n<div class='card'>\n");
      
      // Find min/max for scaling
      double minEq = curve[0].equity, maxEq = curve[0].equity;
      for(int i = 1; i < points; i++) {
         if(curve[i].equity < minEq) minEq = curve[i].equity;
         if(curve[i].equity > maxEq) maxEq = curve[i].equity;
      }
      double range = maxEq - minEq;
      if(range <= 0) range = 1;
      
      // Draw simple bar chart
      int barCount = MathMin(points, 100);
      int step = MathMax(1, points / barCount);
      
      for(int i = 0; i < points; i += step) {
         double pct = (curve[i].equity - minEq) / range * 100.0;
         string color = (curve[i].drawdownPct > 0.05) ? "#ff4444" : "#00ff88";
         FileWriteString(handle, StringFormat(
            "<div class='bar'><div class='bar-fill' style='width:%.0f%%;background:%s;'></div></div>\n",
            MathMax(1, pct), color));
      }
      FileWriteString(handle, StringFormat("<p>Min: %.2f | Max: %.2f | Final: %.2f</p>\n",
         minEq, maxEq, curve[points-1].equity));
      FileWriteString(handle, "</div>\n");
   }
   
   void WriteMonthlySection(int handle, SBacktestTrade &trades[], int count) {
      if(count <= 0) return;
      FileWriteString(handle, "<h2>📅 Monthly Performance</h2>\n");
      FileWriteString(handle, "<table><tr><th>Month</th><th>Trades</th><th>Win Rate</th><th>P/L</th></tr>\n");
      
      // Group by month
      MqlDateTime firstDt, lastDt;
      TimeToStruct(trades[0].closeTime, firstDt);
      TimeToStruct(trades[count-1].closeTime, lastDt);
      
      int curYear = firstDt.year;
      int curMonth = firstDt.mon;
      
      while(curYear < lastDt.year || (curYear == lastDt.year && curMonth <= lastDt.mon)) {
         double monthPnL = 0;
         int monthTrades = 0, monthWins = 0;
         
         for(int i = 0; i < count; i++) {
            MqlDateTime dt;
            TimeToStruct(trades[i].closeTime, dt);
            if(dt.year == curYear && dt.mon == curMonth) {
               monthPnL += trades[i].profit;
               monthTrades++;
               if(trades[i].profit > 0) monthWins++;
            }
         }
         
         if(monthTrades > 0) {
            string pnlClass = (monthPnL >= 0) ? "positive" : "negative";
            double wr = (double)monthWins / monthTrades * 100.0;
            FileWriteString(handle, StringFormat(
               "<tr><td>%04d-%02d</td><td>%d</td><td>%.1f%%</td><td class='%s'>%.2f</td></tr>\n",
               curYear, curMonth, monthTrades, wr, pnlClass, monthPnL));
         }
         
         curMonth++;
         if(curMonth > 12) { curMonth = 1; curYear++; }
      }
      FileWriteString(handle, "</table>\n");
   }
   
   void WriteMonteCarloSection(int handle, SMonteCarloResult &mc) {
      if(mc.simulations <= 0) return;
      FileWriteString(handle, "<h2>🎲 Monte Carlo Analysis</h2>\n<div class='card'>\n");
      FileWriteString(handle, StringFormat("<p>Simulations: %d</p>\n", mc.simulations));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value'>%.1f%%</div><div class='label'>Median Return</div></div>\n", mc.medianReturn));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value'>%.1f%%</div><div class='label'>Mean Return</div></div>\n", mc.meanReturn));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value negative'>%.1f%%</div><div class='label'>Risk of Ruin</div></div>\n", mc.riskOfRuin));
      FileWriteString(handle, StringFormat(
         "<div class='metric'><div class='value'>%.1f%%</div><div class='label'>Avg Max DD</div></div>\n", mc.avgMaxDD));
      
      FileWriteString(handle, "<h3>Confidence Intervals</h3>\n");
      FileWriteString(handle, "<table><tr><th>Percentile</th><th>Return</th></tr>\n");
      FileWriteString(handle, StringFormat("<tr><td>5th (Worst Case)</td><td class='%s'>%.1f%%</td></tr>\n",
         mc.percentile5 >= 0 ? "positive" : "negative", mc.percentile5));
      FileWriteString(handle, StringFormat("<tr><td>25th</td><td class='%s'>%.1f%%</td></tr>\n",
         mc.percentile25 >= 0 ? "positive" : "negative", mc.percentile25));
      FileWriteString(handle, StringFormat("<tr><td>50th (Median)</td><td class='%s'>%.1f%%</td></tr>\n",
         mc.medianReturn >= 0 ? "positive" : "negative", mc.medianReturn));
      FileWriteString(handle, StringFormat("<tr><td>75th</td><td class='%s'>%.1f%%</td></tr>\n",
         mc.percentile75 >= 0 ? "positive" : "negative", mc.percentile75));
      FileWriteString(handle, StringFormat("<tr><td>95th (Best Case)</td><td class='%s'>%.1f%%</td></tr>\n",
         mc.percentile95 >= 0 ? "positive" : "negative", mc.percentile95));
      FileWriteString(handle, "</table></div>\n");
   }
   
   void WriteWalkForwardSection(int handle, SWalkForwardResult &wf[], int windows) {
      if(windows <= 0) return;
      FileWriteString(handle, "<h2>🔄 Walk-Forward Analysis</h2>\n");
      FileWriteString(handle, "<table><tr><th>Window</th><th>IS Period</th><th>OOS Period</th><th>IS Sharpe</th><th>OOS Sharpe</th><th>Efficiency</th><th>OOS P/L</th><th>Status</th></tr>\n");
      
      int passCount = 0;
      for(int w = 0; w < windows; w++) {
         string status = wf[w].passed ? "<span class='pass'>✅ PASS</span>" : "<span class='fail'>❌ FAIL</span>";
         if(wf[w].passed) passCount++;
         FileWriteString(handle, StringFormat(
            "<tr><td>%d</td><td>%s</td><td>%s</td><td>%.2f</td><td>%.2f</td><td>%.1f%%</td><td class='%s'>%.2f</td><td>%s</td></tr>\n",
            w + 1,
            TimeToString(wf[w].isStart, TIME_DATE), TimeToString(wf[w].oosStart, TIME_DATE),
            wf[w].isSharpe, wf[w].oosSharpe, wf[w].efficiency * 100.0,
            wf[w].oosProfit >= 0 ? "positive" : "negative", wf[w].oosProfit,
            status));
      }
      FileWriteString(handle, "</table>\n");
      FileWriteString(handle, StringFormat("<p><strong>Result: %d/%d windows passed (%s)</strong></p>\n",
         passCount, windows, passCount > windows / 2 ? "OVERALL PASS" : "OVERALL FAIL"));
   }
   
   void WriteTradeLog(int handle, SBacktestTrade &trades[], int count) {
      if(count <= 0) return;
      int showCount = MathMin(count, 200); // Limit to last 200 trades
      int startIdx = MathMax(0, count - showCount);
      
      FileWriteString(handle, StringFormat("<h2>📋 Trade Log (last %d of %d)</h2>\n", showCount, count));
      FileWriteString(handle, "<table><tr><th>#</th><th>Time</th><th>Symbol</th><th>Strategy</th><th>Dir</th><th>Volume</th><th>P/L</th><th>P/L %</th></tr>\n");
      
      for(int i = startIdx; i < count; i++) {
         string pnlClass = (trades[i].profit >= 0) ? "positive" : "negative";
         string dir = (trades[i].direction == SIGNAL_BUY) ? "BUY" : "SELL";
         FileWriteString(handle, StringFormat(
            "<tr><td>%d</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%.2f</td><td class='%s'>%.2f</td><td class='%s'>%.2f%%</td></tr>\n",
            i + 1, TimeToString(trades[i].closeTime),
            trades[i].symbol, EnumToString(trades[i].strategy),
            dir, trades[i].volume,
            pnlClass, trades[i].profit,
            pnlClass, trades[i].profitPct));
      }
      FileWriteString(handle, "</table>\n");
   }
};

#endif // __PHOENIX_REPORT_GENERATOR_MQH__
