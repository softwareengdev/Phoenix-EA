//+------------------------------------------------------------------+
//|                                                  Phoenix_EA.mq5  |
//|                  PHOENIX — Autonomous Multi-Strategy Trading EA    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright   "Copyright 2026, Phoenix Trading Systems"
#property link        "https://github.com/softwareengdev/Phoenix-EA"
#property version     "1.00"
#property description "PHOENIX — Autonomous Micro-Account Compounder"
#property description "Multi-strategy, self-optimizing, adaptive risk management"
#property description "Target: €50 → €10,000 in 6-12 months"
#property strict

//+------------------------------------------------------------------+
//| Includes                                                          |
//+------------------------------------------------------------------+
#include <Phoenix\Core\Defines.mqh>
#include <Phoenix\Core\Logger.mqh>
#include <Phoenix\Core\Globals.mqh>
#include <Phoenix\Data\DataEngine.mqh>
#include <Phoenix\Signal\SignalAggregator.mqh>
#include <Phoenix\Risk\RiskManager.mqh>
#include <Phoenix\Risk\CorrelationMatrix.mqh>
#include <Phoenix\Execution\TradeExecutor.mqh>
#include <Phoenix\Optimization\PerformanceTracker.mqh>
#include <Phoenix\Optimization\GeneticAllocator.mqh>
#include <Phoenix\Persistence\StateManager.mqh>
#include <Phoenix\Monitor\TelegramBot.mqh>

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
//--- Símbolos a operar (vacío = deshabilitado)
input group "═══ SÍMBOLOS ═══"
input string   InpSymbol1     = "EURUSD";    // Símbolo 1
input string   InpSymbol2     = "GBPUSD";    // Símbolo 2
input string   InpSymbol3     = "USDJPY";    // Símbolo 3
input string   InpSymbol4     = "XAUUSD";    // Símbolo 4 (Oro)
input string   InpSymbol5     = "";           // Símbolo 5
input string   InpSymbol6     = "";           // Símbolo 6

//--- Configuración de timeframes
input group "═══ TIMEFRAMES ═══"
input ENUM_TIMEFRAMES InpPrimaryTF  = PERIOD_H1;   // TF Principal
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M15;   // TF de Entrada
input ENUM_TIMEFRAMES InpConfirmTF  = PERIOD_H4;    // TF de Confirmación

//--- Gestión de riesgo
input group "═══ RIESGO ═══"
input double   InpRiskPercent    = 3.0;       // Riesgo por operación (%)
input double   InpMaxDailyDD     = 5.0;       // Drawdown diario máximo (%)
input double   InpMaxTotalDD     = 30.0;      // Drawdown total máximo (%)
input int      InpMaxPositions   = 3;         // Máximo posiciones simultáneas
input double   InpMinRiskReward  = 1.0;       // R:R mínimo
input int      InpMaxConsecLoss  = 5;         // Pérdidas consecutivas para pausa
input int      InpCooldownMin    = 60;        // Minutos de enfriamiento tras circuit breaker

//--- Spread y ejecución
input group "═══ EJECUCIÓN ═══"
input int      InpMaxSpreadPoints = 30;       // Spread máximo (puntos)
input int      InpSlippage        = 30;       // Slippage máximo (puntos)
input bool     InpEnableTrailing  = true;      // Activar trailing stop
input double   InpBreakEvenPips   = 10.0;     // Pips para break-even

//--- Sesiones de trading
input group "═══ SESIONES ═══"
input int      InpGMTOffset      = 0;         // Offset GMT del servidor
input bool     InpTradeSydney    = false;      // Operar en sesión Sydney
input bool     InpTradeTokyo     = true;       // Operar en sesión Tokyo
input bool     InpTradeLondon    = true;       // Operar en sesión London
input bool     InpTradeNY        = true;       // Operar en sesión New York

//--- Calendario económico
input group "═══ NOTICIAS ═══"
input bool     InpFilterNews     = true;       // Filtrar noticias de alto impacto
input int      InpPreNewsMin     = 30;         // Minutos antes de noticia
input int      InpPostNewsMin    = 15;         // Minutos después de noticia

//--- Auto-optimización
input group "═══ OPTIMIZACIÓN ═══"
input bool     InpEnableGenetic  = true;       // Activar optimizador genético
input int      InpOptInterval    = 24;         // Horas entre optimizaciones

//--- Telegram
input group "═══ TELEGRAM ═══"
input string   InpTelegramToken  = "";         // Bot Token (@BotFather)
input string   InpTelegramChatId = "";         // Chat ID

//--- Logging
input group "═══ LOGGING ═══"
input ENUM_LOG_LEVEL InpConsoleLogLevel = LOG_LEVEL_INFO;    // Nivel log consola
input ENUM_LOG_LEVEL InpFileLogLevel    = LOG_LEVEL_DEBUG;   // Nivel log archivo

//+------------------------------------------------------------------+
//| Componentes del sistema                                           |
//+------------------------------------------------------------------+
CDataEngine          g_dataEngine;
CSignalAggregator    g_signalAggregator;
CRiskManager         g_riskManager;
CCorrelationMatrix   g_correlationMatrix;
CTradeExecutor       g_tradeExecutor;
CPerformanceTracker  g_perfTracker;
CGeneticAllocator    g_geneticAllocator;
CStateManager        g_stateManager;
CTelegramBot         g_telegram;

//+------------------------------------------------------------------+
//| Configurar símbolos desde inputs                                  |
//+------------------------------------------------------------------+
void ConfigureSymbols()
{
   string symbols[] = {InpSymbol1, InpSymbol2, InpSymbol3, 
                       InpSymbol4, InpSymbol5, InpSymbol6};
   
   g_activeSymbolCount = 0;
   
   for(int i = 0; i < ArraySize(symbols) && g_activeSymbolCount < MAX_SYMBOLS; i++)
   {
      if(symbols[i] == "") continue;
      
      // Verificar que existe
      if(!SymbolInfoInteger(symbols[i], SYMBOL_EXIST))
      {
         g_logger.Warning(StringFormat("Símbolo %s no existe en el broker, saltando", symbols[i]));
         continue;
      }
      
      int idx = g_activeSymbolCount;
      g_symbolConfigs[idx].symbol          = symbols[i];
      g_symbolConfigs[idx].enabled         = true;
      g_symbolConfigs[idx].maxSpreadPoints = InpMaxSpreadPoints;
      g_symbolConfigs[idx].minLotSize      = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MIN);
      g_symbolConfigs[idx].maxLotSize      = SymbolInfoDouble(symbols[i], SYMBOL_VOLUME_MAX);
      g_symbolConfigs[idx].riskMultiplier  = 1.0;
      g_symbolConfigs[idx].primaryTF       = InpPrimaryTF;
      g_symbolConfigs[idx].entryTF         = InpEntryTF;
      g_symbolConfigs[idx].confirmTF       = InpConfirmTF;
      
      // Activar en Market Watch
      SymbolSelect(symbols[i], true);
      
      g_activeSymbolCount++;
   }
   
   g_logger.Info(StringFormat("Configurados %d símbolos", g_activeSymbolCount));
}

//+------------------------------------------------------------------+
//| Verificar si la sesión actual permite trading                      |
//+------------------------------------------------------------------+
bool IsSessionAllowed(ENUM_TRADING_SESSION session)
{
   switch(session)
   {
      case SESSION_SYDNEY:     return InpTradeSydney;
      case SESSION_TOKYO:      return InpTradeTokyo;
      case SESSION_LONDON:     return InpTradeLondon;
      case SESSION_NEWYORK:    return InpTradeNY;
      case SESSION_OVERLAP_LN: return (InpTradeLondon && InpTradeNY);
      case SESSION_OVERLAP_TL: return (InpTradeTokyo && InpTradeLondon);
      default:                 return false;
   }
}

//+------------------------------------------------------------------+
//| Aplicar trailing stop a posiciones abiertas                       |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpEnableTrailing) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;
      
      // Primero intentar break-even
      g_tradeExecutor.MoveToBreakEven(ticket, InpBreakEvenPips);
   }
}

//+------------------------------------------------------------------+
//| Procesar señales y ejecutar trades                                |
//+------------------------------------------------------------------+
void ProcessSignals()
{
   // Obtener régimen de cada símbolo
   ENUM_MARKET_REGIME regimes[];
   ArrayResize(regimes, g_activeSymbolCount);
   for(int i = 0; i < g_activeSymbolCount; i++)
      regimes[i] = g_dataEngine.GetRegime(i);
   
   ENUM_TRADING_SESSION session = g_dataEngine.GetCurrentSession();
   
   // Evaluar todas las estrategias
   int signalCount = g_signalAggregator.Evaluate(regimes, session);
   
   if(signalCount == 0) return;
   
   // Obtener señales ordenadas
   STradeSignal signals[];
   int totalSignals = g_signalAggregator.GetAllSignals(signals);
   
   // Ordenar por score (confidence * R:R) descendente
   for(int i = 0; i < totalSignals - 1; i++)
      for(int j = i + 1; j < totalSignals; j++)
      {
         double scoreI = signals[i].confidence * MathMin(3.0, signals[i].riskReward);
         double scoreJ = signals[j].confidence * MathMin(3.0, signals[j].riskReward);
         if(scoreJ > scoreI)
         {
            STradeSignal temp = signals[i];
            signals[i] = signals[j];
            signals[j] = temp;
         }
      }
   
   // Ejecutar las mejores señales (respetando límite de posiciones)
   for(int i = 0; i < totalSignals; i++)
   {
      STradeSignal sig = signals[i];
      
      // Verificaciones finales
      if(!g_dataEngine.IsTradingSafe(FindSymbolIndex(sig.symbol)))
         continue;
      
      // Filtro de correlación
      int symIdx = FindSymbolIndex(sig.symbol);
      if(symIdx >= 0 && g_correlationMatrix.HasCorrelationConflict(symIdx))
         continue;
      
      // Calcular lote
      double slDistance = MathAbs(sig.entryPrice - sig.stopLoss);
      double lots = g_riskManager.CalculateLotSize(sig.symbol, slDistance, sig.strategy);
      
      if(lots <= 0) continue;
      
      // Validar stops
      ENUM_ORDER_TYPE orderType = (sig.direction == SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!g_riskManager.ValidateStopLevels(sig.symbol, orderType, sig.entryPrice, sig.stopLoss, sig.takeProfit))
         continue;
      
      // Verificar si podemos abrir
      if(!g_riskManager.CanOpenPosition(sig.symbol, lots))
         continue;
      
      // Construir magic number y comentario
      long magic = PHOENIX_MAGIC((int)sig.strategy, symIdx);
      string comment = StringFormat("PHX_%s_%s", 
                        EnumToString(sig.strategy),
                        sig.symbol);
      
      // EJECUTAR
      bool success = g_tradeExecutor.OpenPosition(
         sig.symbol, orderType, lots,
         sig.stopLoss, sig.takeProfit,
         magic, comment
      );
      
      if(success)
      {
         g_logger.Info(StringFormat("TRADE ABIERTO: %s %s %.2f lots [%s] conf=%.2f R:R=%.2f",
                       sig.symbol,
                       sig.direction == SIGNAL_BUY ? "BUY" : "SELL",
                       lots, sig.reason, sig.confidence, sig.riskReward));
         
         // Notificar Telegram
         g_telegram.NotifyTradeOpen(sig.symbol,
                                     sig.direction == SIGNAL_BUY ? "BUY" : "SELL",
                                     lots, sig.entryPrice, sig.stopLoss, sig.takeProfit);
         
         // Guardar estado
         g_stateManager.ForceSave();
      }
   }
}

//+------------------------------------------------------------------+
//| Encontrar índice de símbolo en la configuración                   |
//+------------------------------------------------------------------+
int FindSymbolIndex(const string &symbol)
{
   for(int i = 0; i < g_activeSymbolCount; i++)
      if(g_symbolConfigs[i].symbol == symbol)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Inicializar Logger primero
   g_logger.Init(PHOENIX_NAME, InpConsoleLogLevel, InpFileLogLevel);
   g_logger.Info("==============================================");
   g_logger.Info(StringFormat("PHOENIX EA v%s (build %d) INICIANDO", PHOENIX_VERSION, PHOENIX_BUILD));
   g_logger.Info(StringFormat("Cuenta: %s (%s) Servidor: %s",
                 AccountInfoString(ACCOUNT_NAME),
                 AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO ? "DEMO" : "REAL",
                 AccountInfoString(ACCOUNT_SERVER)));
   g_logger.Info(StringFormat("Balance: %.2f %s Leverage: 1:%d",
                 AccountInfoDouble(ACCOUNT_BALANCE),
                 AccountInfoString(ACCOUNT_CURRENCY),
                 AccountInfoInteger(ACCOUNT_LEVERAGE)));
   g_logger.Info("==============================================");
   
   //--- Inicializar globals
   InitGlobals();
   
   //--- Configurar símbolos
   ConfigureSymbols();
   if(g_activeSymbolCount == 0)
   {
      g_logger.Fatal("No hay símbolos válidos configurados. EA no puede iniciar.");
      return INIT_FAILED;
   }
   
   //--- Inicializar componentes en orden de dependencia
   
   // 1. State Manager — restaurar estado previo
   if(!g_stateManager.Init())
      g_logger.Warning("StateManager falló (no crítico, inicio limpio)");
   else
      g_stateManager.LoadState(); // Intentar restaurar
   
   // 2. Data Engine
   if(!g_dataEngine.Init())
   {
      g_logger.Fatal("DataEngine falló. EA no puede iniciar.");
      return INIT_FAILED;
   }
   
   // 3. Signal Aggregator (todas las estrategias)
   if(!g_signalAggregator.Init())
   {
      g_logger.Fatal("SignalAggregator falló. EA no puede iniciar.");
      return INIT_FAILED;
   }
   
   // 4. Risk Manager
   if(!g_riskManager.Init())
   {
      g_logger.Fatal("RiskManager falló. EA no puede iniciar.");
      return INIT_FAILED;
   }
   
   // 5. Correlation Matrix
   if(!g_correlationMatrix.Init(100, 0.7))
      g_logger.Warning("CorrelationMatrix falló (no crítico)");
   
   // 6. Trade Executor
   if(!g_tradeExecutor.Init(InpSlippage))
   {
      g_logger.Fatal("TradeExecutor falló. EA no puede iniciar.");
      return INIT_FAILED;
   }
   
   // 7. Performance Tracker
   if(!g_perfTracker.Init())
      g_logger.Warning("PerformanceTracker falló (no crítico)");
   
   // 8. Genetic Allocator
   if(InpEnableGenetic)
   {
      if(!g_geneticAllocator.Init(50, 30))
         g_logger.Warning("GeneticAllocator falló (no crítico)");
   }
   
   // 9. Telegram
   g_telegram.Init(InpTelegramToken, InpTelegramChatId);
   
   //--- Configurar timer (30 segundos para actualizaciones periódicas)
   EventSetTimer(HEARTBEAT_INTERVAL);
   
   //--- EA está listo
   g_eaState.state = EA_STATE_WARMING_UP;
   g_tradingEnabled = true;
   
   g_logger.Info(StringFormat("PHOENIX EA inicializado correctamente. Modo: %s. %d símbolos. Estado: WARMING_UP",
                 EnumToString(g_eaState.accountMode), g_activeSymbolCount));
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_logger.Info(StringFormat("PHOENIX EA desinicializando (razón: %d)", reason));
   
   // Guardar estado final
   g_stateManager.ForceSave();
   
   // Desinicializar componentes
   g_signalAggregator.Deinit();
   g_dataEngine.Deinit();
   
   // Detener timer
   EventKillTimer();
   
   g_logger.Info("PHOENIX EA detenido.");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   ulong startTime = GetMicrosecondCount();
   
   //--- Incrementar contador
   g_eaState.tickCount++;
   
   //--- Actualizar modo de cuenta (equity cambia)
   UpdateAccountMode();
   
   //--- Actualizar data engine con el tick actual
   g_dataEngine.OnTick(_Symbol);
   
   //--- Verificar si estamos en warming up
   if(g_eaState.state == EA_STATE_WARMING_UP)
   {
      // Verificar si hay suficientes datos
      bool ready = true;
      for(int i = 0; i < g_activeSymbolCount; i++)
      {
         if(Bars(g_symbolConfigs[i].symbol, g_symbolConfigs[i].primaryTF) < WARMUP_BARS)
         {
            ready = false;
            break;
         }
      }
      if(ready)
      {
         g_eaState.state = EA_STATE_ACTIVE;
         g_logger.Info("Warmup completado. Estado: ACTIVE. Trading habilitado.");
      }
      else
      {
         return; // Esperar más datos
      }
   }
   
   //--- No operar si no estamos activos
   if(g_eaState.state != EA_STATE_ACTIVE && g_eaState.state != EA_STATE_DEGRADED)
      return;
   
   //--- No operar si trading está deshabilitado
   if(!g_tradingEnabled) return;
   
   //--- Verificar sesión
   ENUM_TRADING_SESSION session = g_dataEngine.GetCurrentSession();
   if(!IsSessionAllowed(session)) return;
   
   //--- Verificar noticias
   if(InpFilterNews && g_dataEngine.IsNewsTime()) return;
   
   //--- Gestionar posiciones abiertas (trailing, break-even)
   ManageOpenPositions();
   
   //--- Actualizar risk manager
   g_riskManager.Update();
   
   //--- Si circuit breaker activo, no abrir nuevas posiciones
   if(g_riskManager.GetCircuitBreaker()->IsTriggered())
   {
      // En emergencia, cerrar todo
      if(g_eaState.state == EA_STATE_EMERGENCY)
         g_tradeExecutor.CloseAllPhoenix("EMERGENCY_STOP");
      return;
   }
   
   //--- Procesar señales y ejecutar trades
   ProcessSignals();
   
   //--- Medir tiempo de procesamiento
   g_tickProcessTimeUs = GetMicrosecondCount() - startTime;
   if(g_tickProcessTimeUs > g_maxTickTimeUs)
      g_maxTickTimeUs = g_tickProcessTimeUs;
}

//+------------------------------------------------------------------+
//| Timer function — actualizaciones periódicas                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Heartbeat
   g_eaState.lastHeartbeat = TimeCurrent();
   
   //--- Actualizar data engine (sesiones, calendario, regímenes)
   g_dataEngine.OnTimer();
   
   //--- Auto-save estado
   g_stateManager.CheckAutoSave();
   
   //--- Actualizar métricas de performance
   g_perfTracker.Update();
   
   //--- Auto-optimización genética
   if(InpEnableGenetic && g_geneticAllocator.IsInitialized())
   {
      datetime lastOpt = g_geneticAllocator.GetLastOptimization();
      if(lastOpt == 0 || TimeCurrent() - lastOpt > InpOptInterval * 3600)
      {
         g_logger.Info("Ejecutando auto-optimización genética...");
         g_geneticAllocator.Optimize();
         g_stateManager.ForceSave();
      }
   }
   
   //--- Recalcular correlaciones (cada hora)
   static datetime lastCorrCalc = 0;
   if(TimeCurrent() - lastCorrCalc > 3600)
   {
      g_correlationMatrix.RecalculateAll();
      lastCorrCalc = TimeCurrent();
   }
   
   //--- Reporte diario a Telegram
   static datetime lastDailyReport = 0;
   datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(today != lastDailyReport && g_dataEngine.GetSessionDetector()->IsFridayClose() == false)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.hour == 21 && dt.min < 1) // Reporte a las 21:00
      {
         g_telegram.NotifyDailyReport(
            AccountInfoDouble(ACCOUNT_BALANCE),
            AccountInfoDouble(ACCOUNT_EQUITY),
            g_riskManager.GetCircuitBreaker()->GetDailyPnL(),
            g_eaState.totalTradesSession,
            g_eaState.currentDrawdown
         );
         lastDailyReport = today;
      }
   }
}

//+------------------------------------------------------------------+
//| Trade function — monitoreo de eventos de trading                  |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Verificar deals recientes para tracking de P&L
   HistorySelect(TimeCurrent() - 60, TimeCurrent());
   
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      long magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(!IS_PHOENIX_MAGIC(magic)) continue;
      
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
      
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      
      ENUM_STRATEGY_TYPE strat = GET_STRATEGY_FROM_MAGIC(magic);
      bool isWin = (profit >= 0);
      
      // Notificar al risk manager
      g_riskManager.OnTradeResult(strat, isWin, profit);
      
      // Notificar al performance tracker
      g_perfTracker.OnTradeClosed(strat, profit);
      
      // Telegram
      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      g_telegram.NotifyTradeClose(symbol, profit, AccountInfoDouble(ACCOUNT_BALANCE));
      
      g_logger.Info(StringFormat("TRADE CERRADO: %s P&L=%.2f Balance=%.2f [%s]",
                    symbol, profit, AccountInfoDouble(ACCOUNT_BALANCE),
                    isWin ? "WIN" : "LOSS"));
      
      // Guardar estado tras cada cierre
      g_stateManager.ForceSave();
   }
}

//+------------------------------------------------------------------+
//| Tester function — para optimización en Strategy Tester             |
//+------------------------------------------------------------------+
double OnTester()
{
   // Custom optimization criterion: Sharpe * sqrt(totalTrades) * profitFactor
   // Esto penaliza sistemas con pocos trades y favorece consistencia
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double initialBalance = g_eaState.startEquity;
   if(initialBalance <= 0) initialBalance = 50.0;
   
   double totalReturn = (balance - initialBalance) / initialBalance;
   double maxDD = g_eaState.maxDrawdownHit;
   if(maxDD <= 0) maxDD = 0.001;
   
   int totalTrades = g_eaState.totalTradesSession;
   if(totalTrades < 30) return -totalTrades; // Penalizar pocos trades
   
   // Calmar Ratio simplificado * sqrt(trades)
   double calmar = totalReturn / maxDD;
   double criterion = calmar * MathSqrt((double)totalTrades);
   
   // Penalizar drawdowns excesivos
   if(maxDD > 0.30) criterion *= 0.5;
   if(maxDD > 0.50) criterion *= 0.1;
   
   return criterion;
}
//+------------------------------------------------------------------+
