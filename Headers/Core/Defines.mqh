//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                     Copyright 2025, Phoenix Trading Systems       |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_DEFINES_MQH__
#define __PHOENIX_DEFINES_MQH__

// Version
#define PHOENIX_VERSION        "3.0.0"
#define PHOENIX_NAME           "Phoenix EA"
#define PHOENIX_COPYRIGHT      "Copyright 2025, Phoenix Trading Systems"
#define PHOENIX_MAGIC_BASE     770000

// Limits
#define MAX_SYMBOLS            8
#define MAX_STRATEGIES         6
#define MAX_OPEN_POSITIONS     12
#define MAX_PENDING_ORDERS     20
#define MAX_HISTORY_BARS       5000
#define MAX_CORRELATION_PAIRS  28
#define MAX_GA_POPULATION      80
#define MAX_GA_GENERATIONS     50
#define MAX_MONTE_CARLO_RUNS   2000
#define MAX_WF_WINDOWS         20

// Timing
#define TIMER_INTERVAL_SEC     1
#define SAVE_STATE_SEC         60
#define CORRELATION_UPDATE_SEC 3600
#define GA_OPTIMIZE_SEC        86400
#define REPORT_INTERVAL_SEC    86400

// Risk defaults
#define DEFAULT_RISK_PCT       3.0
#define DEFAULT_MAX_DAILY_DD   5.0
#define DEFAULT_MAX_TOTAL_DD   30.0
#define DEFAULT_KELLY_FRACTION 0.25
#define DEFAULT_MIN_RR         1.0
#define MIN_EQUITY_USD         10.0

// Enums
enum ENUM_STRATEGY_TYPE {
   STRATEGY_TREND = 0,
   STRATEGY_MEAN_REVERT = 1,
   STRATEGY_BREAKOUT = 2,
   STRATEGY_SCALPER = 3,
   STRATEGY_MOMENTUM = 4,
   STRATEGY_COUNT = 5
};

enum ENUM_MARKET_REGIME {
   REGIME_TRENDING_STRONG = 0,
   REGIME_TRENDING_WEAK = 1,
   REGIME_RANGING_TIGHT = 2,
   REGIME_RANGING_WIDE = 3,
   REGIME_VOLATILE = 4,
   REGIME_QUIET = 5,
   REGIME_UNKNOWN = 6
};

enum ENUM_TRADING_SESSION {
   SESSION_SYDNEY = 0,
   SESSION_TOKYO = 1,
   SESSION_LONDON = 2,
   SESSION_NEWYORK = 3,
   SESSION_LONDON_NY_OVERLAP = 4,
   SESSION_TOKYO_LONDON_OVERLAP = 5,
   SESSION_OFF_HOURS = 6
};

enum ENUM_SIGNAL_TYPE {
   SIGNAL_NONE = 0,
   SIGNAL_BUY = 1,
   SIGNAL_SELL = -1
};

enum ENUM_ACCOUNT_MODE {
   ACCOUNT_MICRO = 0,    // < 500 USD
   ACCOUNT_SMALL = 1,    // 500-2000 USD
   ACCOUNT_MEDIUM = 2,   // 2000-10000 USD
   ACCOUNT_LARGE = 3     // > 10000 USD
};

enum ENUM_LOG_LEVEL {
   LOG_TRACE = 0,
   LOG_DEBUG = 1,
   LOG_INFO = 2,
   LOG_WARNING = 3,
   LOG_ERROR = 4,
   LOG_FATAL = 5
};

enum ENUM_CIRCUIT_STATE {
   CIRCUIT_CLOSED = 0,   // Normal trading
   CIRCUIT_OPEN = 1,     // Trading halted
   CIRCUIT_HALF_OPEN = 2 // Testing recovery
};

enum ENUM_TRAIL_MODE {
   TRAIL_NONE = 0,
   TRAIL_ATR = 1,
   TRAIL_CHANDELIER = 2,
   TRAIL_PARABOLIC = 3,
   TRAIL_STEPPED = 4
};

enum ENUM_EXIT_REASON {
   EXIT_SL = 0,
   EXIT_TP = 1,
   EXIT_TRAILING = 2,
   EXIT_BREAKEVEN = 3,
   EXIT_TIME = 4,
   EXIT_SIGNAL = 5,
   EXIT_CIRCUIT_BREAKER = 6,
   EXIT_MANUAL = 7,
   EXIT_CORRELATION = 8
};

// Structures
struct STradeSignal {
   ENUM_SIGNAL_TYPE   direction;
   ENUM_STRATEGY_TYPE strategy;
   string             symbol;
   int                symbolIndex;
   double             confidence;   // 0.0 - 1.0
   double             entryPrice;
   double             stopLoss;
   double             takeProfit;
   double             riskReward;
   double             atrValue;
   ENUM_MARKET_REGIME regime;
   ENUM_TRADING_SESSION session;
   datetime           timestamp;
   string             comment;
};

struct SStrategyMetrics {
   ENUM_STRATEGY_TYPE strategy;
   int                totalTrades;
   int                winTrades;
   int                lossTrades;
   double             winRate;
   double             avgWin;
   double             avgLoss;
   double             profitFactor;
   double             expectancy;
   double             sharpeRatio;
   double             sortinoRatio;
   double             calmarRatio;
   double             maxDrawdown;
   double             maxDrawdownPct;
   double             totalProfit;
   double             totalLoss;
   double             netProfit;
   double             allocationWeight;
   int                consecutiveWins;
   int                consecutiveLosses;
   int                maxConsecWins;
   int                maxConsecLosses;
   datetime           lastTradeTime;
   bool               enabled;
};

struct SSymbolConfig {
   string             name;
   bool               enabled;
   double             point;
   int                digits;
   double             tickSize;
   double             tickValue;
   double             minLot;
   double             maxLot;
   double             lotStep;
   double             contractSize;
   double             marginRequired;
   double             avgSpread;
   double             avgATR;
   int                handleMA_Fast;
   int                handleMA_Slow;
   int                handleMA_Filter;
   int                handleRSI;
   int                handleATR;
   int                handleADX;
   int                handleBands;
   int                handleMACD;
   int                handleStoch;
   int                handleCCI;
   int                handleDonchian_High;
   int                handleDonchian_Low;
   int                handleVolume;
};

struct SEAState {
   double             peakEquity;
   double             maxDrawdown;
   double             maxDrawdownPct;
   double             dailyPnL;
   double             weeklyPnL;
   double             monthlyPnL;
   double             totalPnL;
   int                totalTrades;
   int                todayTrades;
   int                consecutiveWins;
   int                consecutiveLosses;
   datetime           lastTradeTime;
   datetime           lastOptimizeTime;
   datetime           lastReportTime;
   datetime           lastSaveTime;
   datetime           dayStartTime;
   double             dayStartEquity;
   ENUM_CIRCUIT_STATE circuitState;
   datetime           circuitOpenTime;
   bool               isNewDay;
   bool               isInitialized;
};

struct SBacktestTrade {
   int                ticket;
   ENUM_STRATEGY_TYPE strategy;
   string             symbol;
   ENUM_SIGNAL_TYPE   direction;
   double             openPrice;
   double             closePrice;
   double             stopLoss;
   double             takeProfit;
   double             volume;
   double             profit;
   double             profitPct;
   double             commission;
   double             swap;
   datetime           openTime;
   datetime           closeTime;
   int                holdBars;
   double             maxFavorable;   // MAE
   double             maxAdverse;     // MFE
   ENUM_EXIT_REASON   exitReason;
   double             riskReward;
   double             equityAtOpen;
};

struct SEquityCurvePoint {
   datetime           time;
   double             equity;
   double             balance;
   double             drawdown;
   double             drawdownPct;
};

struct SMonteCarloResult {
   double             medianReturn;
   double             meanReturn;
   double             stdDevReturn;
   double             percentile5;
   double             percentile25;
   double             percentile75;
   double             percentile95;
   double             riskOfRuin;     // P(DD > maxDD)
   double             avgMaxDD;
   double             worstMaxDD;
   double             bestMaxDD;
   int                simulations;
};

struct SWalkForwardResult {
   int                windowIndex;
   datetime           isStart;
   datetime           isEnd;
   datetime           oosStart;
   datetime           oosEnd;
   double             isSharpe;
   double             oosSharpe;
   double             isProfit;
   double             oosProfit;
   double             isMaxDD;
   double             oosMaxDD;
   double             efficiency;     // OOS/IS ratio
   bool               passed;        // efficiency > threshold
};

// Utility macros
#define ENCODE_MAGIC(strategy, symbolIdx) (PHOENIX_MAGIC_BASE + (strategy) * 100 + (symbolIdx))
#define DECODE_STRATEGY(magic) ((ENUM_STRATEGY_TYPE)(((magic) - PHOENIX_MAGIC_BASE) / 100))
#define DECODE_SYMBOL(magic) (((magic) - PHOENIX_MAGIC_BASE) % 100)
#define IS_PHOENIX_MAGIC(magic) ((magic) >= PHOENIX_MAGIC_BASE && (magic) < PHOENIX_MAGIC_BASE + MAX_STRATEGIES * 100)

#define SAFE_DELETE(ptr) if(CheckPointer(ptr) == POINTER_DYNAMIC) { delete ptr; ptr = NULL; }

#endif // __PHOENIX_DEFINES_MQH__
