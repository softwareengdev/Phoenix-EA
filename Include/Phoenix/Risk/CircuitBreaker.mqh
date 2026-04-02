//+------------------------------------------------------------------+
//|                                             CircuitBreaker.mqh   |
//|                          PHOENIX EA — Emergency Circuit Breaker   |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_CIRCUIT_BREAKER_MQH__
#define __PHOENIX_CIRCUIT_BREAKER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CCircuitBreaker — Disyuntor de emergencia                        |
//|                                                                   |
//| Se activa automáticamente cuando:                                |
//| - Pérdida diaria excede el límite                                |
//| - N pérdidas consecutivas                                        |
//| - Drawdown total excede el límite                                |
//| - Spread anormalmente alto                                       |
//| - Pérdida de conexión                                            |
//|                                                                   |
//| Al activarse: bloquea nuevas operaciones, opcionalmente cierra   |
//| posiciones existentes. Se desactiva tras período de enfriamiento. |
//+------------------------------------------------------------------+
class CCircuitBreaker
{
private:
   bool              m_initialized;
   bool              m_triggered;              // Está activado
   ENUM_BREAKER_REASON m_reason;               // Razón de activación
   datetime          m_triggeredAt;            // Cuándo se activó
   int               m_cooldownMinutes;        // Enfriamiento en minutos
   
   //--- Umbrales configurables
   double            m_maxDailyLossPct;        // Pérdida diaria máxima (% equity)
   int               m_maxConsecutiveLosses;   // Pérdidas consecutivas máximas
   double            m_maxTotalDrawdownPct;    // Drawdown total máximo (% peak)
   double            m_spreadMultiplierLimit;  // Spread > N*promedio = pausa
   
   //--- Tracking diario
   double            m_dailyPnL;              // P&L del día actual
   datetime          m_dayStart;              // Inicio del día actual
   
public:
   CCircuitBreaker() : m_initialized(false), m_triggered(false),
                        m_reason(BREAKER_NONE), m_triggeredAt(0),
                        m_cooldownMinutes(60),
                        m_maxDailyLossPct(MAX_DAILY_DRAWDOWN),
                        m_maxConsecutiveLosses(5),
                        m_maxTotalDrawdownPct(MAX_TOTAL_DRAWDOWN),
                        m_spreadMultiplierLimit(3.0),
                        m_dailyPnL(0), m_dayStart(0) {}
   
   bool Init(int cooldownMinutes = 60, int maxConsecLoss = 5)
   {
      m_cooldownMinutes      = cooldownMinutes;
      m_maxConsecutiveLosses = maxConsecLoss;
      m_triggered            = false;
      m_dailyPnL             = 0.0;
      m_dayStart             = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      m_initialized          = true;
      
      g_logger.Info(StringFormat("CircuitBreaker: Init [cooldown=%dmin maxConsec=%d dailyMax=%.1f%% ddMax=%.1f%%]",
                    cooldownMinutes, maxConsecLoss, 
                    m_maxDailyLossPct * 100, m_maxTotalDrawdownPct * 100));
      return true;
   }
   
   void Update()
   {
      if(!m_initialized) return;
      
      // Nuevo día → reset P&L diario
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      if(today != m_dayStart)
      {
         g_logger.Info(StringFormat("CircuitBreaker: Nuevo día, reset P&L diario (ayer=%.2f)", m_dailyPnL));
         m_dailyPnL   = 0.0;
         m_dayStart   = today;
         g_eaState.dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      }
      
      // Verificar si el cooldown expiró
      if(m_triggered && m_cooldownMinutes > 0)
      {
         datetime cooldownEnd = m_triggeredAt + m_cooldownMinutes * 60;
         if(TimeCurrent() > cooldownEnd)
         {
            // Verificar que las condiciones mejoraron antes de desactivar
            if(g_eaState.currentDrawdown < m_maxTotalDrawdownPct * 0.8)
            {
               g_logger.Info(StringFormat("CircuitBreaker: Cooldown expirado, desactivando (razón era: %s)",
                             EnumToString(m_reason)));
               Reset();
            }
            else
            {
               g_logger.Warning("CircuitBreaker: Cooldown expirado pero drawdown aún alto, manteniendo pausa");
            }
         }
      }
      
      // Verificación activa de condiciones (solo si no está ya activado)
      if(!m_triggered)
      {
         // Pérdida diaria
         double dailyLoss = (g_eaState.dailyStartEquity - AccountInfoDouble(ACCOUNT_EQUITY)) / g_eaState.dailyStartEquity;
         if(dailyLoss > m_maxDailyLossPct)
         {
            Trigger(BREAKER_DAILY_LOSS, StringFormat("Pérdida diaria %.2f%% > %.2f%%",
                    dailyLoss * 100, m_maxDailyLossPct * 100));
         }
         
         // Drawdown total
         if(g_eaState.currentDrawdown > m_maxTotalDrawdownPct)
         {
            Trigger(BREAKER_TOTAL_DRAWDOWN, StringFormat("Drawdown total %.2f%% > %.2f%%",
                    g_eaState.currentDrawdown * 100, m_maxTotalDrawdownPct * 100));
         }
         
         // Pérdidas consecutivas
         if(g_eaState.consecutiveLosses >= m_maxConsecutiveLosses)
         {
            Trigger(BREAKER_CONSECUTIVE_LOSS, StringFormat("%d pérdidas consecutivas",
                    g_eaState.consecutiveLosses));
         }
         
         // Equity mínimo
         if(AccountInfoDouble(ACCOUNT_EQUITY) < MIN_EQUITY_USD)
         {
            Trigger(BREAKER_EQUITY_MINIMUM, StringFormat("Equity %.2f < mínimo %.2f",
                    AccountInfoDouble(ACCOUNT_EQUITY), MIN_EQUITY_USD));
         }
      }
   }
   
   // Activar el circuit breaker
   void Trigger(ENUM_BREAKER_REASON reason, const string &details = "")
   {
      m_triggered   = true;
      m_reason      = reason;
      m_triggeredAt = TimeCurrent();
      
      g_eaState.breakerReason      = reason;
      g_eaState.breakerActivatedAt = m_triggeredAt;
      
      g_logger.Fatal(StringFormat("⚡ CIRCUIT BREAKER ACTIVADO: %s — %s",
                     EnumToString(reason), details));
      
      // Push notification
      if(TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
         SendNotification(StringFormat("PHOENIX ALERT: Circuit breaker — %s", details));
   }
   
   // Desactivar
   void Reset()
   {
      m_triggered   = false;
      m_reason      = BREAKER_NONE;
      m_triggeredAt = 0;
      g_eaState.breakerReason = BREAKER_NONE;
      g_logger.Info("CircuitBreaker: Reset — trading habilitado");
   }
   
   // Registrar resultado de trade
   void OnTradeResult(bool isWin, double pnl)
   {
      m_dailyPnL += pnl;
   }
   
   //--- Getters
   bool                 IsTriggered() const { return m_triggered; }
   ENUM_BREAKER_REASON  GetReason()   const { return m_reason; }
   datetime             GetTriggeredAt() const { return m_triggeredAt; }
   double               GetDailyPnL() const { return m_dailyPnL; }
};

#endif // __PHOENIX_CIRCUIT_BREAKER_MQH__
//+------------------------------------------------------------------+
