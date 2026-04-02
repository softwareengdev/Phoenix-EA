//+------------------------------------------------------------------+
//|                                                      Globals.mqh |
//|                                  PHOENIX EA — Global State Hub    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_GLOBALS_MQH__
#define __PHOENIX_GLOBALS_MQH__

#include "Defines.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Variables Globales del EA — Singleton pattern via includes        |
//+------------------------------------------------------------------+

// Logger global — accesible desde cualquier módulo
CLogger  g_logger;

// Estado del EA
SEAState g_eaState;

// Métricas de performance por estrategia
SStrategyMetrics g_strategyMetrics[MAX_STRATEGIES];

// Configuración de símbolos activos
SSymbolConfig g_symbolConfigs[MAX_SYMBOLS];
int           g_activeSymbolCount = 0;

// Flags de control globales
bool g_tradingEnabled    = false;   // Master switch de trading
bool g_isOptimizing      = false;   // Estamos en optimización del Strategy Tester
bool g_isBacktesting     = false;   // Estamos en backtest
bool g_isVisualMode      = false;   // Modo visual del tester
bool g_isDemoAccount     = false;   // Cuenta demo
bool g_isHedgingAccount  = false;   // Cuenta con hedging

// Contadores de rendimiento
ulong g_tickProcessTimeUs = 0;      // Tiempo de procesamiento del último tick (µs)
ulong g_maxTickTimeUs     = 0;      // Máximo tiempo de tick registrado

//+------------------------------------------------------------------+
//| Inicialización de variables globales                              |
//+------------------------------------------------------------------+
void InitGlobals()
{
   // Reset estado
   g_eaState.Reset();
   
   // Reset métricas
   for(int i = 0; i < MAX_STRATEGIES; i++)
   {
      g_strategyMetrics[i].Reset();
      g_strategyMetrics[i].type = (ENUM_STRATEGY_TYPE)i;
   }
   
   // Reset configuración de símbolos
   for(int i = 0; i < MAX_SYMBOLS; i++)
      g_symbolConfigs[i].Reset();
   
   g_activeSymbolCount = 0;
   
   // Detectar entorno
   g_isOptimizing     = (MQLInfoInteger(MQL_OPTIMIZATION) != 0);
   g_isBacktesting    = (MQLInfoInteger(MQL_TESTER) != 0);
   g_isVisualMode     = (MQLInfoInteger(MQL_VISUAL_MODE) != 0);
   g_isDemoAccount    = (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
   g_isHedgingAccount = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   
   // Determinar modo de cuenta basado en equity
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity < MICRO_ACCOUNT_THRESHOLD)
      g_eaState.accountMode = ACCOUNT_MICRO;
   else if(equity < SMALL_ACCOUNT_THRESHOLD)
      g_eaState.accountMode = ACCOUNT_SMALL;
   else if(equity < MEDIUM_ACCOUNT_THRESHOLD)
      g_eaState.accountMode = ACCOUNT_MEDIUM;
   else
      g_eaState.accountMode = ACCOUNT_LARGE;
   
   // Guardar equity inicial
   g_eaState.startEquity      = equity;
   g_eaState.peakEquity       = equity;
   g_eaState.dailyStartEquity = equity;
}

//+------------------------------------------------------------------+
//| Actualizar modo de cuenta (llamar periódicamente)                 |
//+------------------------------------------------------------------+
void UpdateAccountMode()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   ENUM_ACCOUNT_MODE newMode;
   if(equity < MICRO_ACCOUNT_THRESHOLD)
      newMode = ACCOUNT_MICRO;
   else if(equity < SMALL_ACCOUNT_THRESHOLD)
      newMode = ACCOUNT_SMALL;
   else if(equity < MEDIUM_ACCOUNT_THRESHOLD)
      newMode = ACCOUNT_MEDIUM;
   else
      newMode = ACCOUNT_LARGE;
   
   if(newMode != g_eaState.accountMode)
   {
      g_logger.Info(StringFormat("Account mode changed: %d → %d (equity=%.2f)",
                                 g_eaState.accountMode, newMode, equity));
      g_eaState.accountMode = newMode;
   }
   
   // Actualizar peak equity
   if(equity > g_eaState.peakEquity)
      g_eaState.peakEquity = equity;
   
   // Calcular drawdown actual
   if(g_eaState.peakEquity > 0)
      g_eaState.currentDrawdown = (g_eaState.peakEquity - equity) / g_eaState.peakEquity;
   
   // Track máximo drawdown
   if(g_eaState.currentDrawdown > g_eaState.maxDrawdownHit)
      g_eaState.maxDrawdownHit = g_eaState.currentDrawdown;
}

//+------------------------------------------------------------------+
//| Obtener número máximo de posiciones según modo de cuenta          |
//+------------------------------------------------------------------+
int GetMaxPositions()
{
   switch(g_eaState.accountMode)
   {
      case ACCOUNT_MICRO:  return 2;    // €50-€500: máximo 2 posiciones
      case ACCOUNT_SMALL:  return 3;    // €500-€2000: máximo 3
      case ACCOUNT_MEDIUM: return 5;    // €2000-€10000: máximo 5
      case ACCOUNT_LARGE:  return MAX_POSITIONS; // €10000+: sin límite práctico
      default:             return 2;
   }
}

//+------------------------------------------------------------------+
//| Obtener riesgo por trade según modo de cuenta                     |
//+------------------------------------------------------------------+
double GetRiskPerTrade()
{
   switch(g_eaState.accountMode)
   {
      case ACCOUNT_MICRO:  return 0.04;  // 4% (agresivo para crecer rápido)
      case ACCOUNT_SMALL:  return 0.035; // 3.5%
      case ACCOUNT_MEDIUM: return 0.03;  // 3% (estándar)
      case ACCOUNT_LARGE:  return 0.02;  // 2% (conservador)
      default:             return DEFAULT_RISK_PER_TRADE;
   }
}

#endif // __PHOENIX_GLOBALS_MQH__
//+------------------------------------------------------------------+
