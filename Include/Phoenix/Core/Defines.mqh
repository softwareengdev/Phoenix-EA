//+------------------------------------------------------------------+
//|                                                      Defines.mqh |
//|                                     PHOENIX EA — Core Definitions |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_DEFINES_MQH__
#define __PHOENIX_DEFINES_MQH__

//+------------------------------------------------------------------+
//| Versión del EA                                                    |
//+------------------------------------------------------------------+
#define PHOENIX_VERSION          "1.0.0"
#define PHOENIX_BUILD            1
#define PHOENIX_NAME             "PHOENIX"
#define PHOENIX_MAGIC_BASE       770000    // Base para números mágicos

//+------------------------------------------------------------------+
//| Constantes de configuración                                       |
//+------------------------------------------------------------------+
#define MAX_SYMBOLS              10        // Máximo de símbolos simultáneos
#define MAX_STRATEGIES           6         // Máximo de sub-estrategias
#define MAX_TIMEFRAMES           5         // Máximo de timeframes por símbolo
#define MAX_POSITIONS            10        // Máximo de posiciones abiertas
#define MAX_PENDING_ORDERS       20        // Máximo de órdenes pendientes
#define MAX_RETRIES              3         // Reintentos de ejecución
#define RETRY_DELAY_MS           500       // Delay entre reintentos (ms)

//+------------------------------------------------------------------+
//| Constantes de riesgo                                              |
//+------------------------------------------------------------------+
#define MIN_LOT_SIZE             0.01      // Lote mínimo
#define MAX_RISK_PER_TRADE       0.05      // 5% máximo por operación
#define MIN_RISK_PER_TRADE       0.01      // 1% mínimo por operación
#define DEFAULT_RISK_PER_TRADE   0.03      // 3% por defecto
#define MAX_DAILY_DRAWDOWN       0.05      // 5% drawdown diario máximo
#define MAX_TOTAL_DRAWDOWN       0.30      // 30% drawdown total máximo
#define KELLY_FRACTION           0.25      // Quarter-Kelly
#define MIN_EQUITY_USD           10.0      // Equity mínimo para operar

//+------------------------------------------------------------------+
//| Constantes de micro-cuenta                                        |
//+------------------------------------------------------------------+
#define MICRO_ACCOUNT_THRESHOLD  500.0     // Debajo de esto: modo micro
#define SMALL_ACCOUNT_THRESHOLD  2000.0    // Debajo de esto: modo conservador
#define MEDIUM_ACCOUNT_THRESHOLD 10000.0   // Debajo de esto: modo normal

//+------------------------------------------------------------------+
//| Constantes de archivos y logs                                     |
//+------------------------------------------------------------------+
#define LOG_PATH                 "Phoenix\\logs\\"
#define STATE_PATH               "Phoenix\\state\\"
#define JOURNAL_PATH             "Phoenix\\journal\\"
#define MAX_LOG_SIZE_MB          10        // Rotación de log a 10 MB
#define STATE_SAVE_INTERVAL      60        // Guardar estado cada 60 seg

//+------------------------------------------------------------------+
//| Constantes de tiempo                                              |
//+------------------------------------------------------------------+
#define HEARTBEAT_INTERVAL       30        // Heartbeat cada 30 seg
#define OPTIMIZATION_INTERVAL    86400     // Auto-optimización cada 24h
#define PERFORMANCE_WINDOW       720       // Ventana de performance: 720 horas (30 días)
#define WARMUP_BARS              200       // Barras de calentamiento

//+------------------------------------------------------------------+
//| Enums — Niveles de Log                                            |
//+------------------------------------------------------------------+
enum ENUM_LOG_LEVEL
{
   LOG_LEVEL_TRACE   = 0,    // Trace — máximo detalle
   LOG_LEVEL_DEBUG   = 1,    // Debug — desarrollo
   LOG_LEVEL_INFO    = 2,    // Info — operación normal
   LOG_LEVEL_WARNING = 3,    // Warning — situación inusual
   LOG_LEVEL_ERROR   = 4,    // Error — fallo recuperable
   LOG_LEVEL_FATAL   = 5,    // Fatal — fallo crítico
   LOG_LEVEL_NONE    = 6     // Desactivar logging
};

//+------------------------------------------------------------------+
//| Enums — Estados del EA                                            |
//+------------------------------------------------------------------+
enum ENUM_EA_STATE
{
   EA_STATE_INITIALIZING = 0,  // Inicializando
   EA_STATE_WARMING_UP   = 1,  // Calentamiento (cargando datos)
   EA_STATE_ACTIVE       = 2,  // Operando normalmente
   EA_STATE_DEGRADED     = 3,  // Modo degradado (algún componente falló)
   EA_STATE_PAUSED       = 4,  // Pausado por circuit breaker
   EA_STATE_EMERGENCY    = 5,  // Emergencia — cerrando todo
   EA_STATE_SHUTDOWN     = 6   // Apagándose
};

//+------------------------------------------------------------------+
//| Enums — Tipos de Estrategia                                       |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TYPE
{
   STRATEGY_TREND       = 0,   // Trend Following
   STRATEGY_MEANREV     = 1,   // Mean Reversion
   STRATEGY_BREAKOUT    = 2,   // Breakout
   STRATEGY_SCALPER     = 3,   // Scalper
   STRATEGY_HYBRID      = 4    // Híbrida
};

//+------------------------------------------------------------------+
//| Enums — Régimen de Mercado                                        |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
   REGIME_UNKNOWN       = 0,   // No determinado
   REGIME_TRENDING_UP   = 1,   // Tendencia alcista
   REGIME_TRENDING_DOWN = 2,   // Tendencia bajista
   REGIME_RANGING       = 3,   // Lateral / Rango
   REGIME_VOLATILE      = 4,   // Alta volatilidad
   REGIME_THIN          = 5    // Baja liquidez
};

//+------------------------------------------------------------------+
//| Enums — Sesiones de Trading                                       |
//+------------------------------------------------------------------+
enum ENUM_TRADING_SESSION
{
   SESSION_NONE         = 0,   // Fuera de sesión
   SESSION_SYDNEY       = 1,   // Sesión de Sídney
   SESSION_TOKYO        = 2,   // Sesión de Tokio
   SESSION_LONDON       = 3,   // Sesión de Londres
   SESSION_NEWYORK      = 4,   // Sesión de Nueva York
   SESSION_OVERLAP_LN   = 5,   // Overlap Londres-NY (mejor liquidez)
   SESSION_OVERLAP_TL   = 6    // Overlap Tokio-Londres
};

//+------------------------------------------------------------------+
//| Enums — Dirección de Señal                                        |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_DIRECTION
{
   SIGNAL_NONE          = 0,   // Sin señal
   SIGNAL_BUY           = 1,   // Compra
   SIGNAL_SELL          = -1,  // Venta
   SIGNAL_CLOSE_BUY     = 2,   // Cerrar compra
   SIGNAL_CLOSE_SELL    = -2,  // Cerrar venta
   SIGNAL_CLOSE_ALL     = 99   // Cerrar todo
};

//+------------------------------------------------------------------+
//| Enums — Motivo de Circuit Breaker                                 |
//+------------------------------------------------------------------+
enum ENUM_BREAKER_REASON
{
   BREAKER_NONE              = 0,   // Sin activación
   BREAKER_DAILY_LOSS        = 1,   // Pérdida diaria excedida
   BREAKER_TOTAL_DRAWDOWN    = 2,   // Drawdown total excedido
   BREAKER_CONSECUTIVE_LOSS  = 3,   // Pérdidas consecutivas
   BREAKER_SPREAD_SPIKE      = 4,   // Spread anormalmente alto
   BREAKER_NEWS_EVENT        = 5,   // Evento de noticias de alto impacto
   BREAKER_CORRELATION       = 6,   // Correlación excesiva
   BREAKER_MANUAL            = 7,   // Pausa manual
   BREAKER_EQUITY_MINIMUM    = 8,   // Equity debajo del mínimo
   BREAKER_CONNECTION_LOSS   = 9    // Pérdida de conexión
};

//+------------------------------------------------------------------+
//| Enums — Modo de Cuenta                                            |
//+------------------------------------------------------------------+
enum ENUM_ACCOUNT_MODE
{
   ACCOUNT_MICRO        = 0,   // €50-€500: ultra conservador en tamaño
   ACCOUNT_SMALL        = 1,   // €500-€2000: conservador
   ACCOUNT_MEDIUM       = 2,   // €2000-€10000: normal
   ACCOUNT_LARGE        = 3    // €10000+: completo
};

//+------------------------------------------------------------------+
//| Estructuras — Señal de Trading                                    |
//+------------------------------------------------------------------+
struct STradeSignal
{
   ENUM_SIGNAL_DIRECTION direction;      // Dirección
   ENUM_STRATEGY_TYPE    strategy;       // Estrategia que generó
   string                symbol;         // Símbolo
   ENUM_TIMEFRAMES       timeframe;      // Timeframe principal
   double                confidence;     // Confianza 0.0 - 1.0
   double                entryPrice;     // Precio de entrada sugerido
   double                stopLoss;       // Stop loss sugerido
   double                takeProfit;     // Take profit sugerido
   double                riskReward;     // Ratio risk:reward
   datetime              signalTime;     // Hora de generación
   datetime              expiryTime;     // Hora de expiración
   string                reason;         // Razón textual
   
   void Reset()
   {
      direction   = SIGNAL_NONE;
      strategy    = STRATEGY_TREND;
      symbol      = "";
      timeframe   = PERIOD_H1;
      confidence  = 0.0;
      entryPrice  = 0.0;
      stopLoss    = 0.0;
      takeProfit  = 0.0;
      riskReward  = 0.0;
      signalTime  = 0;
      expiryTime  = 0;
      reason      = "";
   }
};

//+------------------------------------------------------------------+
//| Estructuras — Métricas de Performance por Estrategia              |
//+------------------------------------------------------------------+
struct SStrategyMetrics
{
   ENUM_STRATEGY_TYPE    type;           // Tipo de estrategia
   int                   totalTrades;    // Total de operaciones
   int                   winTrades;      // Operaciones ganadoras
   int                   lossTrades;     // Operaciones perdedoras
   double                totalProfit;    // Beneficio total
   double                totalLoss;      // Pérdida total
   double                maxDrawdown;    // Máximo drawdown
   double                sharpeRatio;    // Sharpe ratio (30 días)
   double                profitFactor;   // Factor de beneficio
   double                winRate;        // Tasa de acierto
   double                avgWin;         // Media de ganancia
   double                avgLoss;        // Media de pérdida
   double                expectancy;     // Expectancia por operación
   double                allocationWeight; // Peso de capital asignado (0-1)
   bool                  isActive;       // Está activa
   datetime              lastTradeTime;  // Última operación
   datetime              lastUpdateTime; // Última actualización
   
   void Reset()
   {
      type             = STRATEGY_TREND;
      totalTrades      = 0;
      winTrades        = 0;
      lossTrades       = 0;
      totalProfit      = 0.0;
      totalLoss        = 0.0;
      maxDrawdown      = 0.0;
      sharpeRatio      = 0.0;
      profitFactor     = 0.0;
      winRate          = 0.0;
      avgWin           = 0.0;
      avgLoss          = 0.0;
      expectancy       = 0.0;
      allocationWeight = 0.2; // 20% por defecto
      isActive         = true;
      lastTradeTime    = 0;
      lastUpdateTime   = 0;
   }
   
   // Calcula métricas derivadas
   void Calculate()
   {
      if(totalTrades > 0)
      {
         winRate = (double)winTrades / (double)totalTrades;
         if(totalLoss != 0.0)
            profitFactor = MathAbs(totalProfit / totalLoss);
         if(winTrades > 0)
            avgWin = totalProfit / winTrades;
         if(lossTrades > 0)
            avgLoss = MathAbs(totalLoss / lossTrades);
         expectancy = (winRate * avgWin) - ((1.0 - winRate) * avgLoss);
      }
      lastUpdateTime = TimeCurrent();
   }
};

//+------------------------------------------------------------------+
//| Estructuras — Estado del EA para persistencia                     |
//+------------------------------------------------------------------+
struct SEAState
{
   ENUM_EA_STATE         state;              // Estado actual
   ENUM_ACCOUNT_MODE     accountMode;        // Modo de cuenta
   double                startEquity;        // Equity al inicio
   double                peakEquity;         // Máximo equity alcanzado
   double                dailyStartEquity;   // Equity al inicio del día
   double                currentDrawdown;    // Drawdown actual
   double                maxDrawdownHit;     // Máximo drawdown alcanzado
   int                   totalTradesSession; // Trades esta sesión
   int                   consecutiveLosses;  // Pérdidas consecutivas
   int                   consecutiveWins;    // Ganancias consecutivas
   ENUM_BREAKER_REASON   breakerReason;      // Razón del circuit breaker
   datetime              breakerActivatedAt; // Cuándo se activó
   datetime              lastOptimization;   // Última auto-optimización
   datetime              lastHeartbeat;      // Último heartbeat
   datetime              sessionStart;       // Inicio de esta sesión
   uint                  tickCount;          // Contador de ticks
   
   void Reset()
   {
      state              = EA_STATE_INITIALIZING;
      accountMode        = ACCOUNT_MICRO;
      startEquity        = 0.0;
      peakEquity         = 0.0;
      dailyStartEquity   = 0.0;
      currentDrawdown    = 0.0;
      maxDrawdownHit     = 0.0;
      totalTradesSession = 0;
      consecutiveLosses  = 0;
      consecutiveWins    = 0;
      breakerReason      = BREAKER_NONE;
      breakerActivatedAt = 0;
      lastOptimization   = 0;
      lastHeartbeat      = 0;
      sessionStart       = TimeCurrent();
      tickCount          = 0;
   }
};

//+------------------------------------------------------------------+
//| Estructuras — Configuración por Símbolo                           |
//+------------------------------------------------------------------+
struct SSymbolConfig
{
   string   symbol;              // Nombre del símbolo
   bool     enabled;             // Habilitado para trading
   double   maxSpreadPoints;     // Spread máximo permitido (puntos)
   double   minLotSize;          // Lote mínimo para este símbolo
   double   maxLotSize;          // Lote máximo para este símbolo
   double   riskMultiplier;      // Multiplicador de riesgo (0.5 = mitad)
   ENUM_TIMEFRAMES primaryTF;   // Timeframe principal
   ENUM_TIMEFRAMES entryTF;     // Timeframe de entrada
   ENUM_TIMEFRAMES confirmTF;   // Timeframe de confirmación
   
   void Reset()
   {
      symbol           = "";
      enabled          = false;
      maxSpreadPoints  = 30.0;
      minLotSize       = 0.01;
      maxLotSize       = 1.0;
      riskMultiplier   = 1.0;
      primaryTF        = PERIOD_H1;
      entryTF          = PERIOD_M15;
      confirmTF        = PERIOD_H4;
   }
};

//+------------------------------------------------------------------+
//| Macro helpers                                                      |
//+------------------------------------------------------------------+
#define PHOENIX_MAGIC(strategy, symbolIndex)  (PHOENIX_MAGIC_BASE + (strategy * 100) + symbolIndex)
#define IS_PHOENIX_MAGIC(magic)               (magic >= PHOENIX_MAGIC_BASE && magic < PHOENIX_MAGIC_BASE + 10000)
#define GET_STRATEGY_FROM_MAGIC(magic)        ((ENUM_STRATEGY_TYPE)((magic - PHOENIX_MAGIC_BASE) / 100))
#define GET_SYMBOL_INDEX_FROM_MAGIC(magic)    ((magic - PHOENIX_MAGIC_BASE) % 100)

#endif // __PHOENIX_DEFINES_MQH__
//+------------------------------------------------------------------+
