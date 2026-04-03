//+------------------------------------------------------------------+
//|                                                      Phoenix.mq5 |
//|                     Copyright 2025, Phoenix Trading Systems       |
//|                        https://github.com/softwareengdev         |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2025, Phoenix Trading Systems"
#property link        "https://github.com/softwareengdev/Phoenix-EA"
#property version     "3.00"
#property description "Phoenix EA v3.0 — Multi-strategy, Self-optimizing, Institutional-grade risk"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include "Headers\Core\Defines.mqh"
#include "Headers\Core\Logger.mqh"
#include "Headers\Core\Globals.mqh"
#include "Headers\Data\SymbolInfo.mqh"
#include "Headers\Data\SessionDetector.mqh"
#include "Headers\Data\CalendarFilter.mqh"
#include "Headers\Data\DataEngine.mqh"
#include "Headers\Signal\SignalBase.mqh"
#include "Headers\Signal\SignalTrend.mqh"
#include "Headers\Signal\SignalMeanRevert.mqh"
#include "Headers\Signal\SignalBreakout.mqh"
#include "Headers\Signal\SignalScalper.mqh"
#include "Headers\Signal\SignalAggregator.mqh"
#include "Headers\Risk\RiskManager.mqh"
#include "Headers\Risk\CircuitBreaker.mqh"
#include "Headers\Risk\DrawdownGuard.mqh"
#include "Headers\Risk\CorrelationMatrix.mqh"
#include "Headers\Execution\TradeExecutor.mqh"
#include "Headers\Optimization\PerformanceTracker.mqh"
#include "Headers\Optimization\GeneticAllocator.mqh"
#include "Headers\Persistence\StateManager.mqh"
#include "Headers\Monitor\TelegramBot.mqh"
#include "Headers\Backtest\FitnessFunction.mqh"
#include "Headers\Backtest\BacktestEngine.mqh"
#include "Headers\Backtest\MonteCarloSim.mqh"
#include "Headers\Backtest\WalkForward.mqh"
#include "Headers\Backtest\ReportGenerator.mqh"

//+------------------------------------------------------------------+
//| Component instances                                               |
//+------------------------------------------------------------------+
CDataEngine          g_DataEngine;
CSignalAggregator    g_SignalAggregator;
CRiskManager         g_RiskManager;
CCircuitBreaker      g_CircuitBreaker;
CDrawdownGuard       g_DrawdownGuard;
CCorrelationMatrix   g_Correlation;
CTradeExecutor       g_Executor;
CPerformanceTracker  g_PerfTracker;
CGeneticAllocator    g_GeneticAlloc;
CStateManager        g_StateManager;
CTelegramBot         g_Telegram;
CBacktestEngine      g_BacktestEngine;
CMonteCarloSim       g_MonteCarlo;
CWalkForward         g_WalkForward;
CReportGenerator     g_ReportGen;

//--- Timing control
datetime g_LastBarTime[];
datetime g_LastDailyReset = 0;
int      g_TickCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Initialize logger first
   g_Logger = new CLogger();
   if(!g_Logger.Init("PHX", InpLogLevel, !MQLInfoInteger(MQL_TESTER)))
   {
      Print("FATAL: Logger initialization failed");
      return INIT_FAILED;
   }
   g_Logger.Info(StringFormat("Phoenix EA v%s initializing...", PHOENIX_VERSION));

   //--- Detect environment
   g_IsTesting = (bool)MQLInfoInteger(MQL_TESTER);
   g_IsOptimizing = (bool)MQLInfoInteger(MQL_OPTIMIZATION);

   //--- Parse symbols
   g_SymbolCount = ParseSymbols(InpSymbols, g_Symbols);
   if(g_SymbolCount <= 0)
   {
      g_Logger.Fatal("No valid symbols configured");
      return INIT_PARAMETERS_INCORRECT;
   }
   g_Logger.Info(StringFormat("Symbols: %d configured", g_SymbolCount));

   //--- Initialize global state
   InitGlobalState();
   g_AccountMode = DetectAccountMode();
   g_Logger.Info(StringFormat("Account mode: %s | Equity: %.2f %s",
      EnumToString(g_AccountMode),
      AccountInfoDouble(ACCOUNT_EQUITY),
      AccountInfoString(ACCOUNT_CURRENCY)));

   //--- Initialize components in dependency order
   // 1. Data Engine (indicators, sessions, calendar)
   if(!g_DataEngine.Init(InpPrimaryTF, InpEntryTF, InpFilterTF))
   {
      g_Logger.Fatal("DataEngine initialization failed");
      return INIT_FAILED;
   }

   // 2. Risk components
   g_CircuitBreaker.Init(InpMaxDailyDD, InpMaxTotalDD, InpMaxConsecLosses, InpMaxSpreadMultiplier);
   g_DrawdownGuard.Init(InpMaxTotalDD);
   if(!g_RiskManager.Init(GetPointer(g_CircuitBreaker), GetPointer(g_DrawdownGuard)))
   {
      g_Logger.Fatal("RiskManager initialization failed");
      return INIT_FAILED;
   }

   // 3. Correlation matrix
   g_Correlation.Init(g_SymbolCount, 100, 0.7);

   // 4. Signal aggregator (all strategies)
   if(!g_SignalAggregator.Init())
   {
      g_Logger.Fatal("SignalAggregator initialization failed");
      return INIT_FAILED;
   }

   // 5. Execution
   if(!g_Executor.Init())
   {
      g_Logger.Fatal("TradeExecutor initialization failed");
      return INIT_FAILED;
   }

   // 6. Performance tracking & optimization
   g_PerfTracker.Init(1000);
   g_GeneticAlloc.Init(g_SignalAggregator.GetStrategyCount());

   // 7. State persistence (try to restore)
   g_StateManager.Init();

   // 8. Telegram
   g_Telegram.Init(InpTelegramEnabled, InpTelegramToken, InpTelegramChatID);

   // 9. Backtesting components
   if(g_IsTesting)
   {
      g_BacktestEngine.Init();
      if(InpMonteCarlo)
         g_MonteCarlo.Init(InpMCSimulations, AccountInfoDouble(ACCOUNT_EQUITY));
      if(InpWalkForward)
         g_WalkForward.Init(InpWFWindows, InpWFOOSRatio);
   }

   //--- Initialize bar time tracking (now handled by DataEngine internally)

   //--- Start timer
   EventSetTimer(TIMER_INTERVAL_SEC);

   //--- Dashboard comment (skip during backtesting)
   if(!g_IsTesting) UpdateDashboard();

   g_Logger.Info("Phoenix EA initialized successfully ✓");
   if(g_Telegram.IsEnabled())
      g_Telegram.SendMessage("🔥 Phoenix EA started | " + EnumToString(g_AccountMode));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   //--- Save state
   g_StateManager.ForceSave();

   //--- Generate report if backtesting
   if(g_IsTesting && !g_IsOptimizing && InpHTMLReport)
      GenerateBacktestReport();

   //--- Shutdown components
   g_DataEngine.Shutdown();

   if(g_Telegram.IsEnabled())
      g_Telegram.SendMessage("⏹ Phoenix EA stopped | Reason: " + IntegerToString(reason));

   //--- Clean up logger
   if(g_Logger != NULL)
   {
      g_Logger.Info(StringFormat("Phoenix EA shutdown. Reason: %d | Total trades: %d | P/L: %.2f",
         reason, g_State.totalTrades, g_State.totalPnL));
      g_Logger.Shutdown();
      delete g_Logger;
      g_Logger = NULL;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   g_TickCount++;

   //--- Update data engine
   if(!g_DataEngine.Update()) return;

   //--- Check for new day
   CheckNewDay();

   //--- Update risk components
   g_CircuitBreaker.Update();
   g_DrawdownGuard.Update();

   //--- Manage existing positions (trailing, breakeven, partial close)
   g_Executor.ManageTrailingStops();

   //--- Check for strategy exit signals
   CheckExitSignals();

   //--- Check if trading is allowed
   if(!g_CircuitBreaker.IsTradingAllowed()) return;

   //--- Check calendar filter
   CCalendarFilter *calendar = g_DataEngine.GetCalendarFilter();
   if(calendar != NULL && calendar.IsTradingBlocked()) return;

   //--- Only process signals on new bars (primary TF) to avoid overtrading
   //--- In backtesting, DataEngine already tracks new bars internally
   bool hasNewBar = g_DataEngine.HasAnyNewBar();

   if(!hasNewBar) return;

   //--- Generate signals
   int signalCount = g_SignalAggregator.GenerateSignals(GetPointer(g_DataEngine));
   if(signalCount <= 0) return;

   //--- Process each signal
   for(int i = 0; i < signalCount; i++)
   {
      STradeSignal signal = g_SignalAggregator.GetSignal(i);

      //--- Log signal
      if(g_Logger != NULL) g_Logger.LogSignal(signal);

      //--- Check spread
      CSymbolData *symData = g_DataEngine.GetSymbolData(signal.symbolIndex);
      if(symData != NULL && !symData.IsSpreadOK(InpMaxSpreadMultiplier)) continue;

      //--- Correlation filter
      if(!g_Correlation.IsCorrelationSafe(signal.symbolIndex, signal.direction)) continue;

      //--- Risk validation
      if(!g_RiskManager.CanOpenTrade(signal)) continue;

      //--- Calculate lot size
      double lots = g_RiskManager.CalculateLotSize(signal.symbol, signal.entryPrice, signal.stopLoss);
      if(lots <= 0) continue;

      //--- Execute trade
      if(g_Executor.ExecuteSignal(signal, lots))
      {
         g_State.totalTrades++;
         g_State.todayTrades++;
         g_State.lastTradeTime = TimeCurrent();

         if(g_Telegram.IsEnabled())
            g_Telegram.NotifyTradeOpen(signal.symbol,
               signal.direction == SIGNAL_BUY ? "BUY" : "SELL",
               signal.entryPrice, lots, signal.stopLoss, signal.takeProfit);
      }
   }

   //--- Update dashboard (skip during backtesting for performance)
   if(!g_IsTesting && g_TickCount % 10 == 0) UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer function                                                    |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- State persistence (skip during backtesting — no crash recovery needed)
   if(!g_IsTesting)
      g_StateManager.OnTimer();

   //--- Update correlation matrix periodically
   //--- In backtesting, reduce frequency (every 24h instead of every hour)
   static datetime lastCorrelationUpdate = 0;
   int corrInterval = g_IsTesting ? 86400 : CORRELATION_UPDATE_SEC;
   if(TimeCurrent() - lastCorrelationUpdate >= corrInterval)
   {
      g_Correlation.Update();
      lastCorrelationUpdate = TimeCurrent();
   }

   //--- Auto-optimization (genetic allocator) — skip during backtesting
   if(InpAutoOptimize && !g_IsTesting)
   {
      static datetime lastOptimize = 0;
      if(TimeCurrent() - lastOptimize >= GA_OPTIMIZE_SEC)
      {
         RunOptimization();
         lastOptimize = TimeCurrent();
      }
   }

   //--- Daily report (skip during backtesting)
   static datetime lastReport = 0;
   if(!g_IsTesting && TimeCurrent() - lastReport >= REPORT_INTERVAL_SEC)
   {
      SendDailyReport();
      lastReport = TimeCurrent();
   }

   //--- Update account mode (skip during backtesting)
   static datetime lastModeCheck = 0;
   if(!g_IsTesting && TimeCurrent() - lastModeCheck >= 3600)
   {
      g_RiskManager.UpdateAccountMode();
      lastModeCheck = TimeCurrent();
   }

   //--- Track daily returns for performance
   RecordDailyReturn();
}

//+------------------------------------------------------------------+
//| Trade event handler                                               |
//+------------------------------------------------------------------+
void OnTrade()
{
   //--- Check for closed positions and update metrics
   if(!HistorySelect(g_State.lastTradeTime > 0 ? g_State.lastTradeTime - 3600 : 0, TimeCurrent()))
      return;

   int deals = HistoryDealsTotal();
   for(int i = deals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket <= 0) continue;

      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT) continue;

      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;

      //--- Check if already processed (simple time check)
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime <= g_State.lastTradeTime - 60) continue;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                      HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                      HistoryDealGetDouble(ticket, DEAL_SWAP);

      ENUM_STRATEGY_TYPE strategy = DECODE_STRATEGY(magic);
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double profitPct = (equity > 0) ? profit / equity * 100.0 : 0;

      //--- Update strategy metrics
      g_SignalAggregator.NotifyTradeResult(strategy, profit, profitPct);

      //--- Update global state
      g_State.totalPnL += profit;
      if(profit > 0)
      {
         g_State.consecutiveWins++;
         g_State.consecutiveLosses = 0;
      }
      else
      {
         g_State.consecutiveLosses++;
         g_State.consecutiveWins = 0;
      }

      //--- Record for backtesting
      if(g_IsTesting)
      {
         g_BacktestEngine.OnTradeEvent();
      }

      //--- Record in performance tracker
      SBacktestTrade btTrade;
      ZeroMemory(btTrade);
      btTrade.ticket = (int)ticket;
      btTrade.strategy = strategy;
      btTrade.symbol = symbol;
      btTrade.profit = profit;
      btTrade.profitPct = profitPct;
      btTrade.closeTime = dealTime;
      btTrade.volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      btTrade.closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
      btTrade.equityAtOpen = equity - profit;
      g_PerfTracker.RecordTrade(btTrade);

      //--- Telegram notification
      if(g_Telegram.IsEnabled())
      {
         string reason = StringFormat("Strategy: %s", EnumToString(strategy));
         g_Telegram.NotifyTradeClose(symbol, profit, profitPct, reason);
      }

      //--- Log
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("CLOSED| %s %s | P/L=%.2f (%.2f%%) | Consec W/L=%d/%d",
            symbol, EnumToString(strategy), profit, profitPct,
            g_State.consecutiveWins, g_State.consecutiveLosses));
   }

   //--- Update peak equity
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_State.peakEquity) g_State.peakEquity = eq;
}

//+------------------------------------------------------------------+
//| Custom optimization criterion (OnTester)                          |
//+------------------------------------------------------------------+
double OnTester()
{
   //--- Collect full trade history
   g_BacktestEngine.CollectFullHistory();

   //--- Get custom fitness
   double fitness = g_BacktestEngine.GetCustomFitness();

   //--- Run Monte Carlo if enabled
   if(InpMonteCarlo && g_BacktestEngine.GetTradeCount() >= 20)
   {
      SBacktestTrade trades[];
      g_BacktestEngine.GetTrades(trades);
      SMonteCarloResult mcResult = g_MonteCarlo.Run(trades, ArraySize(trades), InpMaxTotalDD);

      //--- Penalize fitness if risk of ruin is too high
      if(mcResult.riskOfRuin > 20.0)
         fitness *= 0.5;
      else if(mcResult.riskOfRuin > 10.0)
         fitness *= 0.8;

      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("MonteCarlo: %d sims | Median=%.1f%% RoR=%.1f%% AvgDD=%.1f%%",
            mcResult.simulations, mcResult.medianReturn, mcResult.riskOfRuin, mcResult.avgMaxDD));
   }

   //--- Walk-Forward analysis if enabled
   if(InpWalkForward && g_BacktestEngine.GetTradeCount() >= 30)
   {
      SBacktestTrade trades[];
      g_BacktestEngine.GetTrades(trades);
      int tradeCount = ArraySize(trades);

      if(g_WalkForward.Analyze(trades, tradeCount,
         g_BacktestEngine.GetStartTime(), g_BacktestEngine.GetEndTime()))
      {
         if(!g_WalkForward.Passed())
            fitness *= 0.6; // Penalize non-robust parameters

         if(g_Logger != NULL)
            g_Logger.Info(StringFormat("WalkForward: %s | Efficiency=%.1f%%",
               g_WalkForward.Passed() ? "PASSED" : "FAILED",
               g_WalkForward.GetAvgEfficiency() * 100.0));
      }
   }

   //--- Log results
   if(g_Logger != NULL)
      g_Logger.Info(StringFormat("OnTester: Fitness=%.4f | Trades=%d | Profit=%.2f | WR=%.1f%% | PF=%.2f | MaxDD=%.1f%%",
         fitness, g_BacktestEngine.GetTradeCount(),
         g_BacktestEngine.GetTotalProfit(),
         g_BacktestEngine.GetWinRate() * 100.0,
         g_BacktestEngine.GetProfitFactor(),
         g_BacktestEngine.GetMaxDrawdownPct()));

   return fitness;
}

//+------------------------------------------------------------------+
//| Optimization pass event (frame collection)                        |
//+------------------------------------------------------------------+
void OnTesterPass()
{
   // Collect optimization frames for analysis
   ulong  pass;
   string name;
   long   id;
   double value;
   double data[];

   while(FrameNext(pass, name, id, value, data))
   {
      // Process each optimization pass result
      if(g_Logger != NULL)
         g_Logger.Debug(StringFormat("OptPass #%d: %s = %.4f", pass, name, value));
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   // Handle dashboard clicks, manual controls, etc.
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "btn_CloseAll")
      {
         int closed = g_Executor.CloseAllPositions("Manual Close All");
         if(g_Logger != NULL) g_Logger.Info(StringFormat("Manual close: %d positions", closed));
      }
      else if(sparam == "btn_CircuitReset")
      {
         g_CircuitBreaker.ForceClose();
         if(g_Logger != NULL) g_Logger.Info("Manual circuit breaker reset");
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Check for exit signals on open positions                  |
//+------------------------------------------------------------------+
void CheckExitSignals()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;

      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;

      ENUM_STRATEGY_TYPE strategy = DECODE_STRATEGY(magic);
      int symIdx = (int)DECODE_SYMBOL(magic);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_SIGNAL_TYPE posDir = (posType == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;

      if(g_SignalAggregator.ShouldExitPosition(symIdx, posDir, strategy, GetPointer(g_DataEngine)))
      {
         string sym = PositionGetString(POSITION_SYMBOL);
         g_Executor.ClosePosition(ticket, StringFormat("Signal Exit %s", EnumToString(strategy)));
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Check for new trading day                                 |
//+------------------------------------------------------------------+
void CheckNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d 00:00", dt.year, dt.mon, dt.day));

   if(today != g_LastDailyReset)
   {
      g_LastDailyReset = today;
      g_State.dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_State.dailyPnL = 0;
      g_State.todayTrades = 0;
      g_State.isNewDay = true;

      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("New day: %s | Start equity: %.2f",
            TimeToString(today, TIME_DATE), g_State.dayStartEquity));
   }
   else
   {
      g_State.isNewDay = false;
   }
}

//+------------------------------------------------------------------+
//| Helper: Run genetic optimization of strategy weights              |
//+------------------------------------------------------------------+
void RunOptimization()
{
   int stratCount = g_SignalAggregator.GetStrategyCount();
   if(stratCount <= 0) return;

   SStrategyMetrics metrics[];
   ArrayResize(metrics, stratCount);

   for(int i = 0; i < stratCount; i++)
   {
      CSignalBase *strat = g_SignalAggregator.GetStrategy(i);
      if(strat != NULL)
         metrics[i] = g_PerfTracker.CalculateStrategyMetrics(strat.GetType());
   }

   if(g_GeneticAlloc.Optimize(metrics))
   {
      double weights[];
      g_GeneticAlloc.GetBestWeights(weights);
      g_SignalAggregator.UpdateWeights(weights);

      g_State.lastOptimizeTime = TimeCurrent();

      if(g_Logger != NULL)
      {
         string wStr = "";
         for(int i = 0; i < ArraySize(weights); i++)
            wStr += StringFormat("%.2f ", weights[i]);
         g_Logger.Info(StringFormat("GA Optimization complete. Weights: [%s] Fitness: %.4f",
            wStr, g_GeneticAlloc.GetBestFitness()));
      }

      //--- Log each strategy's metrics
      for(int i = 0; i < stratCount; i++)
      {
         if(g_Logger != NULL) g_Logger.LogMetrics(metrics[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| Helper: Send daily report via Telegram                            |
//+------------------------------------------------------------------+
void SendDailyReport()
{
   if(!g_Telegram.IsEnabled()) return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dailyPnL = equity - g_State.dayStartEquity;
   double dailyPct = (g_State.dayStartEquity > 0) ?
                     dailyPnL / g_State.dayStartEquity * 100.0 : 0;

   int wins = 0;
   for(int i = 0; i < g_SignalAggregator.GetStrategyCount(); i++)
   {
      CSignalBase *s = g_SignalAggregator.GetStrategy(i);
      if(s != NULL) wins += s.GetMetricsCopy().winTrades;
   }

   g_Telegram.NotifyDailyReport(equity, dailyPnL, dailyPct,
      g_State.todayTrades, wins, g_State.maxDrawdownPct * 100.0);

   g_State.lastReportTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Helper: Record daily return for Sharpe calculation                |
//+------------------------------------------------------------------+
void RecordDailyReturn()
{
   static datetime lastRecordDay = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != lastRecordDay && g_State.dayStartEquity > 0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyReturn = (equity - g_State.dayStartEquity) / g_State.dayStartEquity;
      g_PerfTracker.RecordDailyReturn(dailyReturn);
      lastRecordDay = today;
   }
}

//+------------------------------------------------------------------+
//| Helper: Generate full backtest report                             |
//+------------------------------------------------------------------+
void GenerateBacktestReport()
{
   g_BacktestEngine.CollectFullHistory();

   SBacktestTrade trades[];
   g_BacktestEngine.GetTrades(trades);
   int tradeCount = ArraySize(trades);

   if(tradeCount <= 0) return;

   //--- Equity curve
   SEquityCurvePoint equityCurve[];
   g_BacktestEngine.GetEquityCurve(equityCurve);
   int equityPoints = ArraySize(equityCurve);

   //--- Monte Carlo
   SMonteCarloResult mcResult;
   ZeroMemory(mcResult);
   if(InpMonteCarlo && tradeCount >= 20)
   {
      mcResult = g_MonteCarlo.Run(trades, tradeCount, InpMaxTotalDD);
   }

   //--- Walk-Forward
   SWalkForwardResult wfResults[];
   int wfWindows = 0;
   if(InpWalkForward && tradeCount >= 30)
   {
      g_WalkForward.Analyze(trades, tradeCount,
         g_BacktestEngine.GetStartTime(), g_BacktestEngine.GetEndTime());
      g_WalkForward.GetAllResults(wfResults);
      wfWindows = g_WalkForward.GetWindowCount();
   }

   //--- Strategy metrics
   int stratCount = g_SignalAggregator.GetStrategyCount();
   SStrategyMetrics stratMetrics[];
   ArrayResize(stratMetrics, stratCount);
   for(int i = 0; i < stratCount; i++)
   {
      CSignalBase *strat = g_SignalAggregator.GetStrategy(i);
      if(strat != NULL)
         stratMetrics[i] = g_PerfTracker.CalculateStrategyMetrics(strat.GetType());
   }

   //--- Generate HTML report
   g_ReportGen.GenerateReport(trades, tradeCount,
      equityCurve, equityPoints,
      mcResult, wfResults, wfWindows,
      stratMetrics, stratCount);
}

//+------------------------------------------------------------------+
//| Helper: Update chart dashboard comment                            |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double dailyPnL = equity - g_State.dayStartEquity;
   double ddPct = (g_State.peakEquity > 0) ?
                  (g_State.peakEquity - equity) / g_State.peakEquity * 100.0 : 0;

   CSessionDetector *session = g_DataEngine.GetSessionDetector();
   string sessionName = (session != NULL) ?
      session.GetSessionName(session.GetCurrentSession()) : "Unknown";

   string dashboard = StringFormat(
      "══════════════ PHOENIX EA v%s ══════════════\n"
      "Mode: %s | Session: %s\n"
      "───────────────────────────────────\n"
      "Equity: %.2f | Balance: %.2f\n"
      "Daily P/L: %.2f | Peak: %.2f\n"
      "Drawdown: %.1f%% | Max DD: %.1f%%\n"
      "───────────────────────────────────\n"
      "Open: %d/%d | Today: %d trades\n"
      "Circuit: %s | Consec L: %d\n"
      "───────────────────────────────────\n"
      "Total Trades: %d | Total P/L: %.2f\n"
      "══════════════════════════════════\n",
      PHOENIX_VERSION,
      EnumToString(g_AccountMode), sessionName,
      equity, balance,
      dailyPnL, g_State.peakEquity,
      ddPct, g_State.maxDrawdownPct * 100.0,
      g_RiskManager.CountOpenPositions(), g_RiskManager.GetMaxPositions(),
      g_State.todayTrades,
      EnumToString(g_State.circuitState), g_State.consecutiveLosses,
      g_State.totalTrades, g_State.totalPnL
   );

   Comment(dashboard);
}
//+------------------------------------------------------------------+
