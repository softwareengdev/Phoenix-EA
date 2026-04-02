//+------------------------------------------------------------------+
//|                                                 RiskManager.mqh  |
//|                          PHOENIX EA — Risk Management Engine      |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_RISK_MANAGER_MQH__
#define __PHOENIX_RISK_MANAGER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "..\Data\SymbolInfo.mqh"
#include "CircuitBreaker.mqh"
#include "DrawdownGuard.mqh"

//+------------------------------------------------------------------+
//| CRiskManager — Motor de gestión de riesgo                        |
//|                                                                   |
//| Responsabilidades:                                                |
//| - Calcular tamaño de posición (Kelly fraccionado + ATR)           |
//| - Verificar exposición total antes de abrir posiciones            |
//| - Validar SL/TP y Risk:Reward                                    |
//| - Integrar Circuit Breaker y Drawdown Guard                      |
//| - Adaptar riesgo según rendimiento y régimen                     |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   CCircuitBreaker   m_circuitBreaker;       // Circuit breaker
   CDrawdownGuard    m_drawdownGuard;        // Drawdown guard
   bool              m_initialized;
   
   //--- Parámetros de riesgo adaptativos
   double            m_baseRiskPct;          // Riesgo base (% equity)
   double            m_currentRiskPct;       // Riesgo actual (adaptado)
   double            m_kellyFraction;        // Fracción de Kelly a usar
   double            m_maxExposurePct;       // Exposición máxima total
   int               m_maxOpenPositions;     // Posiciones máximas
   double            m_minRiskReward;        // R:R mínimo aceptable
   
   //--- Tracking de exposición
   double            m_totalExposure;        // Exposición total actual ($)
   int               m_openPositionCount;    // Posiciones abiertas PHOENIX
   
   // Calcular tamaño Kelly óptimo basado en métricas de estrategia
   double CalculateKellySize(const SStrategyMetrics &metrics)
   {
      if(metrics.totalTrades < 20) // Insuficientes datos
         return m_baseRiskPct;
      
      double winRate = metrics.winRate;
      double avgWin  = metrics.avgWin;
      double avgLoss = metrics.avgLoss;
      
      if(avgLoss == 0.0 || avgWin == 0.0)
         return m_baseRiskPct;
      
      double winLossRatio = avgWin / avgLoss;
      
      // Fórmula Kelly: f* = (p * b - q) / b
      // donde p = winRate, q = 1-p, b = winLossRatio
      double kelly = (winRate * winLossRatio - (1.0 - winRate)) / winLossRatio;
      
      // Aplicar fracción (quarter-Kelly por seguridad)
      kelly *= m_kellyFraction;
      
      // Limitar
      kelly = MathMax(MIN_RISK_PER_TRADE, kelly);
      kelly = MathMin(MAX_RISK_PER_TRADE, kelly);
      
      return kelly;
   }
   
   // Contar posiciones abiertas de PHOENIX
   int CountPhoenixPositions()
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(IS_PHOENIX_MAGIC(magic))
            count++;
      }
      return count;
   }
   
   // Calcular exposición total de PHOENIX
   double CalculateTotalExposure()
   {
      double exposure = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         double volume = PositionGetDouble(POSITION_VOLUME);
         string symbol = PositionGetString(POSITION_SYMBOL);
         double price  = PositionGetDouble(POSITION_PRICE_CURRENT);
         double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
         
         exposure += volume * price * contractSize;
      }
      return exposure;
   }
   
public:
   CRiskManager() : m_initialized(false), m_baseRiskPct(DEFAULT_RISK_PER_TRADE),
                     m_currentRiskPct(DEFAULT_RISK_PER_TRADE), m_kellyFraction(KELLY_FRACTION),
                     m_maxExposurePct(0.5), m_maxOpenPositions(MAX_POSITIONS),
                     m_minRiskReward(1.0), m_totalExposure(0), m_openPositionCount(0) {}
   
   bool Init()
   {
      g_logger.Info("RiskManager: Inicializando...");
      
      // Configurar según modo de cuenta
      m_baseRiskPct      = GetRiskPerTrade();
      m_currentRiskPct   = m_baseRiskPct;
      m_maxOpenPositions = GetMaxPositions();
      
      // Inicializar sub-componentes
      if(!m_circuitBreaker.Init())
      {
         g_logger.Error("RiskManager: Fallo al inicializar CircuitBreaker");
         return false;
      }
      
      if(!m_drawdownGuard.Init())
      {
         g_logger.Error("RiskManager: Fallo al inicializar DrawdownGuard");
         return false;
      }
      
      // Contar posiciones existentes
      m_openPositionCount = CountPhoenixPositions();
      m_totalExposure     = CalculateTotalExposure();
      
      m_initialized = true;
      g_logger.Info(StringFormat("RiskManager: Inicializado [risk=%.1f%% maxPos=%d kelly=%.2f]",
                    m_currentRiskPct * 100, m_maxOpenPositions, m_kellyFraction));
      return true;
   }
   
   //--- Actualización periódica
   void Update()
   {
      if(!m_initialized) return;
      
      m_openPositionCount = CountPhoenixPositions();
      m_totalExposure     = CalculateTotalExposure();
      
      m_circuitBreaker.Update();
      m_drawdownGuard.Update();
      
      // Adaptar riesgo según drawdown actual
      double dd = g_eaState.currentDrawdown;
      if(dd > 0.15) // DD > 15%: reducir riesgo al 50%
         m_currentRiskPct = m_baseRiskPct * 0.5;
      else if(dd > 0.10) // DD > 10%: reducir al 75%
         m_currentRiskPct = m_baseRiskPct * 0.75;
      else
         m_currentRiskPct = m_baseRiskPct;
      
      // Actualizar parámetros según modo de cuenta (crece con equity)
      m_baseRiskPct      = GetRiskPerTrade();
      m_maxOpenPositions = GetMaxPositions();
   }
   
   //=================================================================
   // CÁLCULO DE TAMAÑO DE POSICIÓN
   //=================================================================
   
   // Calcular lotes basado en riesgo fijo + ATR para SL dinámico
   double CalculateLotSize(const string &symbol, double slDistance, 
                           ENUM_STRATEGY_TYPE strategy = STRATEGY_TREND)
   {
      if(slDistance <= 0)
      {
         g_logger.Warning("RiskManager: slDistance <= 0, retornando lote mínimo");
         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      }
      
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity < MIN_EQUITY_USD)
      {
         g_logger.Warning(StringFormat("RiskManager: Equity %.2f < mínimo %.2f", equity, MIN_EQUITY_USD));
         return 0.0;
      }
      
      // Obtener riesgo ajustado por Kelly si hay suficientes datos
      double riskPct = m_currentRiskPct;
      if(strategy >= 0 && strategy < MAX_STRATEGIES)
      {
         double kellyRisk = CalculateKellySize(g_strategyMetrics[strategy]);
         // Promedio entre riesgo fijo y Kelly (suaviza la transición)
         riskPct = (m_currentRiskPct + kellyRisk) / 2.0;
      }
      
      double riskAmount = equity * riskPct;
      
      // Calcular lotes: riskAmount = lots * slDistance * tickValue / tickSize
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(tickValue <= 0 || tickSize <= 0)
      {
         g_logger.Error(StringFormat("RiskManager: tickValue o tickSize inválido para %s", symbol));
         return SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      }
      
      double lots = riskAmount / (slDistance / tickSize * tickValue);
      
      // Normalizar
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      lots = MathMax(minLot, lots);
      lots = MathMin(maxLot, lots);
      if(lotStep > 0)
         lots = MathFloor(lots / lotStep) * lotStep;
      
      lots = NormalizeDouble(lots, 2);
      
      g_logger.Debug(StringFormat("RiskManager: %s lots=%.2f [equity=%.2f risk=%.2f%% sl=%.5f]",
                     symbol, lots, equity, riskPct * 100, slDistance));
      
      return lots;
   }
   
   //=================================================================
   // VALIDACIÓN DE OPERACIONES
   //=================================================================
   
   // ¿Se puede abrir una nueva posición?
   bool CanOpenPosition(const string &symbol, double lots)
   {
      // Circuit breaker activo?
      if(m_circuitBreaker.IsTriggered())
      {
         g_logger.Debug(StringFormat("RiskManager: Bloqueado por circuit breaker (%s)",
                        EnumToString(m_circuitBreaker.GetReason())));
         return false;
      }
      
      // Drawdown guard
      if(m_drawdownGuard.ShouldStop())
      {
         g_logger.Debug("RiskManager: Bloqueado por drawdown guard");
         return false;
      }
      
      // Máximo de posiciones
      if(m_openPositionCount >= m_maxOpenPositions)
      {
         g_logger.Debug(StringFormat("RiskManager: Máximo posiciones alcanzado (%d/%d)",
                        m_openPositionCount, m_maxOpenPositions));
         return false;
      }
      
      // Verificar margen libre
      double margin;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lots, 
                          SymbolInfoDouble(symbol, SYMBOL_ASK), margin))
      {
         g_logger.Error("RiskManager: No se pudo calcular margen");
         return false;
      }
      
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin > freeMargin * 0.8) // No usar más del 80% del margen libre
      {
         g_logger.Warning(StringFormat("RiskManager: Margen insuficiente (needed=%.2f free=%.2f)",
                          margin, freeMargin));
         return false;
      }
      
      // Equity mínimo
      if(AccountInfoDouble(ACCOUNT_EQUITY) < MIN_EQUITY_USD)
      {
         g_logger.Warning("RiskManager: Equity debajo del mínimo");
         return false;
      }
      
      return true;
   }
   
   // Validar SL/TP
   bool ValidateStopLevels(const string &symbol, ENUM_ORDER_TYPE type,
                           double entryPrice, double sl, double tp)
   {
      if(sl <= 0 || tp <= 0)
         return false;
      
      // Calcular R:R
      double risk   = MathAbs(entryPrice - sl);
      double reward = MathAbs(tp - entryPrice);
      
      if(risk <= 0) return false;
      
      double rr = reward / risk;
      if(rr < m_minRiskReward)
      {
         g_logger.Debug(StringFormat("RiskManager: R:R insuficiente %.2f < %.2f", rr, m_minRiskReward));
         return false;
      }
      
      // Verificar distancia mínima de stops
      int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double minDist = stopsLevel * point;
      
      if(MathAbs(entryPrice - sl) < minDist || MathAbs(entryPrice - tp) < minDist)
      {
         g_logger.Debug(StringFormat("RiskManager: SL/TP demasiado cerca del precio (min=%.5f)", minDist));
         return false;
      }
      
      return true;
   }
   
   //--- Registrar resultado de trade (para adaptar riesgo)
   void OnTradeResult(ENUM_STRATEGY_TYPE strategy, bool isWin, double pnl)
   {
      m_circuitBreaker.OnTradeResult(isWin, pnl);
      m_drawdownGuard.OnTradeResult(isWin, pnl);
      
      if(!isWin)
      {
         g_eaState.consecutiveLosses++;
         g_eaState.consecutiveWins = 0;
      }
      else
      {
         g_eaState.consecutiveWins++;
         g_eaState.consecutiveLosses = 0;
      }
   }
   
   //--- Getters
   CCircuitBreaker*  GetCircuitBreaker()    { return &m_circuitBreaker; }
   CDrawdownGuard*   GetDrawdownGuard()     { return &m_drawdownGuard; }
   double            GetCurrentRiskPct()  const { return m_currentRiskPct; }
   int               GetOpenPositions()   const { return m_openPositionCount; }
   double            GetTotalExposure()   const { return m_totalExposure; }
   bool              IsInitialized()      const { return m_initialized; }
};

#endif // __PHOENIX_RISK_MANAGER_MQH__
//+------------------------------------------------------------------+
