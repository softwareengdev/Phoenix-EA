//+------------------------------------------------------------------+
//|                                                      Globals.mqh |
//|                     Copyright 2025, Phoenix Trading Systems       |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_GLOBALS_MQH__
#define __PHOENIX_GLOBALS_MQH__

#include "Defines.mqh"
#include "Logger.mqh"

//--- Input Parameters: General
input group "═══════════════ General Settings ═══════════════"
input string   InpSymbols         = "EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD"; // Symbols (comma-separated)
input ENUM_TIMEFRAMES InpPrimaryTF = PERIOD_H1;    // Primary Timeframe
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_M15;   // Entry Timeframe
input ENUM_TIMEFRAMES InpFilterTF  = PERIOD_H4;    // Filter Timeframe
input ENUM_LOG_LEVEL  InpLogLevel  = LOG_INFO;      // Log Level

//--- Input Parameters: Risk Management
input group "═══════════════ Risk Management ═══════════════"
input double   InpRiskPercent     = 3.0;    // Risk per Trade (%)
input double   InpMaxDailyDD      = 5.0;    // Max Daily Drawdown (%)
input double   InpMaxTotalDD      = 30.0;   // Max Total Drawdown (%)
input int      InpMaxPositions    = 5;      // Max Simultaneous Positions
input double   InpKellyFraction   = 0.25;   // Kelly Fraction (0.1-0.5)
input double   InpMinRiskReward   = 1.0;    // Minimum Risk:Reward
input int      InpMaxConsecLosses = 5;      // Max Consecutive Losses (circuit breaker)
input double   InpMaxSpreadMultiplier = 3.0; // Max Spread Multiplier (vs avg)

//--- Input Parameters: Strategies
input group "═══════════════ Strategy Settings ═══════════════"
input bool     InpEnableTrend     = true;   // Enable Trend Following
input bool     InpEnableMeanRev   = true;   // Enable Mean Reversion
input bool     InpEnableBreakout  = true;   // Enable Breakout
input bool     InpEnableScalper   = true;   // Enable Scalper
input bool     InpEnableMomentum  = true;   // Enable Momentum

//--- Input Parameters: Trend Strategy
input group "═══════════════ Trend Strategy ═══════════════"
input int      InpTrend_FastMA     = 8;     // Fast MA Period
input int      InpTrend_SlowMA     = 21;    // Slow MA Period
input int      InpTrend_FilterMA   = 200;   // Filter MA Period
input int      InpTrend_ADXPeriod  = 14;    // ADX Period
input double   InpTrend_ADXMin     = 20.0;  // Min ADX for Trend
input double   InpTrend_ATR_SL     = 1.5;   // ATR Multiplier for SL
input double   InpTrend_ATR_TP     = 2.5;   // ATR Multiplier for TP

//--- Input Parameters: Mean Reversion
input group "═══════════════ Mean Reversion ═══════════════"
input int      InpMR_BBPeriod      = 20;    // Bollinger Period
input double   InpMR_BBDeviation   = 2.0;   // Bollinger Deviation
input int      InpMR_RSIPeriod     = 14;    // RSI Period
input double   InpMR_RSIOverbought = 70.0;  // RSI Overbought
input double   InpMR_RSIOversold   = 30.0;  // RSI Oversold
input double   InpMR_ATR_SL       = 0.8;   // ATR Multiplier for SL
input double   InpMR_ATR_TP       = 1.5;   // ATR Multiplier for TP

//--- Input Parameters: Breakout
input group "═══════════════ Breakout Strategy ═══════════════"
input int      InpBO_DonchianPeriod = 20;   // Donchian Channel Period
input int      InpBO_VolumePeriod   = 20;   // Volume MA Period
input double   InpBO_VolumeMulti    = 1.5;  // Volume Spike Multiplier
input double   InpBO_ATR_SL        = 2.0;   // ATR Multiplier for SL
input double   InpBO_ATR_TP        = 3.0;   // ATR Multiplier for TP

//--- Input Parameters: Scalper
input group "═══════════════ Scalper Strategy ═══════════════"
input int      InpSC_FastMA        = 5;     // Fast MA Period
input int      InpSC_SlowMA        = 13;    // Slow MA Period
input int      InpSC_RSIPeriod     = 7;     // RSI Period
input int      InpSC_MACDFast      = 12;    // MACD Fast Period
input int      InpSC_MACDSlow      = 26;    // MACD Slow Period
input int      InpSC_MACDSignal    = 9;     // MACD Signal Period
input double   InpSC_ATR_SL       = 1.0;   // ATR Multiplier for SL
input double   InpSC_ATR_TP       = 1.5;   // ATR Multiplier for TP

//--- Input Parameters: Momentum
input group "═══════════════ Momentum Strategy ═══════════════"
input int      InpMOM_CCIPeriod    = 20;    // CCI Period
input double   InpMOM_CCIUpper     = 100.0; // CCI Upper Level
input double   InpMOM_CCILower     = -100.0;// CCI Lower Level
input int      InpMOM_StochK       = 14;    // Stochastic %K
input int      InpMOM_StochD       = 3;     // Stochastic %D
input int      InpMOM_StochSlowing = 3;     // Stochastic Slowing
input double   InpMOM_ATR_SL      = 1.2;   // ATR Multiplier for SL
input double   InpMOM_ATR_TP      = 2.0;   // ATR Multiplier for TP

//--- Input Parameters: Trade Execution
input group "═══════════════ Execution Settings ═══════════════"
input int      InpSlippage         = 10;    // Max Slippage (points)
input int      InpMaxRetries       = 3;     // Max Retry Attempts
input ENUM_TRAIL_MODE InpTrailMode = TRAIL_ATR; // Trailing Stop Mode
input double   InpTrailATRMulti    = 2.0;   // Trail ATR Multiplier
input double   InpBreakevenPips    = 15.0;  // Breakeven Trigger (pips)
input double   InpBreakevenOffset  = 2.0;   // Breakeven Offset (pips)
input bool     InpPartialClose     = true;  // Enable Partial Close
input double   InpPartialPct       = 50.0;  // Partial Close Percent
input double   InpPartialTrigger   = 1.0;   // Partial Trigger (x Risk)

//--- Input Parameters: Session Filter
input group "═══════════════ Session Filter ═══════════════"
input bool     InpSessionFilter    = true;  // Enable Session Filter
input int      InpLondonStart      = 7;     // London Start (UTC hour)
input int      InpLondonEnd        = 16;    // London End (UTC hour)
input int      InpNewYorkStart     = 12;    // NY Start (UTC hour)
input int      InpNewYorkEnd       = 21;    // NY End (UTC hour)
input int      InpTokyoStart       = 0;     // Tokyo Start (UTC hour)
input int      InpTokyoEnd         = 9;     // Tokyo End (UTC hour)

//--- Input Parameters: Calendar
input group "═══════════════ Calendar Filter ═══════════════"
input bool     InpCalendarFilter   = true;  // Enable News Filter
input int      InpPreNewsPause     = 30;    // Pre-News Pause (minutes)
input int      InpPostNewsWait     = 15;    // Post-News Wait (minutes)

//--- Input Parameters: Optimization
input group "═══════════════ Optimization ═══════════════"
input bool     InpAutoOptimize     = true;  // Auto-Optimize Allocations
input int      InpGAPopulation     = 50;    // GA Population Size
input int      InpGAGenerations    = 30;    // GA Generations
input double   InpGAMutation       = 0.15;  // GA Mutation Rate
input int      InpMinTradesOpt     = 30;    // Min Trades for Optimization

//--- Input Parameters: Telegram
input group "═══════════════ Telegram Alerts ═══════════════"
input bool     InpTelegramEnabled  = false; // Enable Telegram
input string   InpTelegramToken    = "";    // Bot Token
input string   InpTelegramChatID   = "";    // Chat ID

//--- Input Parameters: Backtesting
input group "═══════════════ Backtesting ═══════════════"
input bool     InpWalkForward      = false; // Enable Walk-Forward Mode
input int      InpWFWindows        = 5;     // Walk-Forward Windows
input double   InpWFOOSRatio       = 0.25;  // OOS Ratio (0.1-0.5)
input bool     InpMonteCarlo       = true;  // Enable Monte Carlo Analysis
input int      InpMCSimulations    = 1000;  // Monte Carlo Simulations
input bool     InpHTMLReport       = true;  // Generate HTML Report
input int      InpCustomFitness    = 0;     // Fitness: 0=Sharpe 1=Sortino 2=Calmar 3=PF*WR 4=Composite

//--- Global Objects (forward declarations)
class CDataEngine;
class CSignalAggregator;
class CRiskManager;
class CCircuitBreaker;
class CDrawdownGuard;
class CCorrelationMatrix;
class CTradeExecutor;
class CPerformanceTracker;
class CGeneticAllocator;
class CStateManager;
class CTelegramBot;
class CSessionDetector;
class CCalendarFilter;
class CBacktestEngine;

//--- Global Singletons
CLogger           *g_Logger = NULL;
SEAState           g_State;
SSymbolConfig      g_Symbols[];
int                g_SymbolCount = 0;
ENUM_ACCOUNT_MODE  g_AccountMode = ACCOUNT_MICRO;
bool               g_IsTesting = false;
bool               g_IsOptimizing = false;

//+------------------------------------------------------------------+
//| Account Mode Detection                                           |
//+------------------------------------------------------------------+
ENUM_ACCOUNT_MODE DetectAccountMode() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   // Convert to USD equivalent
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   double equityUSD = equity;
   if(currency == "EUR") equityUSD = equity * 1.10;
   else if(currency == "GBP") equityUSD = equity * 1.27;
   else if(currency == "JPY") equityUSD = equity / 150.0;
   
   if(equityUSD < 500.0)       return ACCOUNT_MICRO;
   else if(equityUSD < 2000.0)  return ACCOUNT_SMALL;
   else if(equityUSD < 10000.0) return ACCOUNT_MEDIUM;
   else                         return ACCOUNT_LARGE;
}

//+------------------------------------------------------------------+
//| Get max positions based on account mode                          |
//+------------------------------------------------------------------+
int GetMaxPositionsForMode(ENUM_ACCOUNT_MODE mode) {
   switch(mode) {
      case ACCOUNT_MICRO:  return MathMin(InpMaxPositions, 2);
      case ACCOUNT_SMALL:  return MathMin(InpMaxPositions, 3);
      case ACCOUNT_MEDIUM: return MathMin(InpMaxPositions, 5);
      case ACCOUNT_LARGE:  return InpMaxPositions;
      default:             return 2;
   }
}

//+------------------------------------------------------------------+
//| Get risk percentage based on account mode                        |
//+------------------------------------------------------------------+
double GetRiskForMode(ENUM_ACCOUNT_MODE mode) {
   switch(mode) {
      case ACCOUNT_MICRO:  return MathMin(InpRiskPercent, 4.0);
      case ACCOUNT_SMALL:  return MathMin(InpRiskPercent, 3.5);
      case ACCOUNT_MEDIUM: return MathMin(InpRiskPercent, 3.0);
      case ACCOUNT_LARGE:  return MathMin(InpRiskPercent, 2.0);
      default:             return 2.0;
   }
}

//+------------------------------------------------------------------+
//| Parse symbols string into array                                  |
//+------------------------------------------------------------------+
int ParseSymbols(string symbolsStr, SSymbolConfig &configs[]) {
   string symbols[];
   int count = StringSplit(symbolsStr, ',', symbols);
   if(count <= 0) return 0;
   
   ArrayResize(configs, count);
   int valid = 0;
   for(int i = 0; i < count; i++) {
      StringTrimRight(symbols[i]);
      StringTrimLeft(symbols[i]);
      if(StringLen(symbols[i]) == 0) continue;
      if(!SymbolSelect(symbols[i], true)) {
         if(g_Logger != NULL)
            g_Logger.Warning(StringFormat("Symbol %s not available, skipping", symbols[i]));
         continue;
      }
      ZeroMemory(configs[valid]);
      configs[valid].name = symbols[i];
      configs[valid].enabled = true;
      configs[valid].point = SymbolInfoDouble(symbols[i], SYMBOL_POINT);
      configs[valid].digits = (int)SymbolInfoInteger(symbols[i], SYMBOL_DIGITS);
      configs[valid].tickSize = SymbolInfoDouble(symbols[i], SYMBOL_TRADE_TICK_SIZE);
      configs[valid].tickValue = SymbolInfoDouble(symbols[i], SYMBOL_TRADE_TICK_VALUE);
      configs[valid].minLot = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MIN);
      configs[valid].maxLot = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MAX);
      configs[valid].lotStep = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_STEP);
      configs[valid].contractSize = SymbolInfoDouble(symbols[i], SYMBOL_TRADE_CONTRACT_SIZE);
      // Initialize indicator handles to INVALID_HANDLE
      configs[valid].handleMA_Fast = INVALID_HANDLE;
      configs[valid].handleMA_Slow = INVALID_HANDLE;
      configs[valid].handleMA_Filter = INVALID_HANDLE;
      configs[valid].handleRSI = INVALID_HANDLE;
      configs[valid].handleATR = INVALID_HANDLE;
      configs[valid].handleADX = INVALID_HANDLE;
      configs[valid].handleBands = INVALID_HANDLE;
      configs[valid].handleMACD = INVALID_HANDLE;
      configs[valid].handleStoch = INVALID_HANDLE;
      configs[valid].handleCCI = INVALID_HANDLE;
      configs[valid].handleDonchian_High = INVALID_HANDLE;
      configs[valid].handleDonchian_Low = INVALID_HANDLE;
      configs[valid].handleVolume = INVALID_HANDLE;
      valid++;
   }
   if(valid < count) ArrayResize(configs, valid);
   return valid;
}

//+------------------------------------------------------------------+
//| Initialize global state                                          |
//+------------------------------------------------------------------+
void InitGlobalState() {
   ZeroMemory(g_State);
   g_State.peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_State.dayStartEquity = g_State.peakEquity;
   g_State.dayStartTime = TimeCurrent();
   g_State.circuitState = CIRCUIT_CLOSED;
   g_State.isInitialized = true;
   g_IsTesting = MQLInfoInteger(MQL_TESTER);
   g_IsOptimizing = MQLInfoInteger(MQL_OPTIMIZATION);
}

#endif // __PHOENIX_GLOBALS_MQH__
