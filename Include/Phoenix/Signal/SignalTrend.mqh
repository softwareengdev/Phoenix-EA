//+------------------------------------------------------------------+
//|                                            SignalTrend.mqh       |
//|                    PHOENIX EA — Trend Following Strategy           |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_TREND_MQH__
#define __PHOENIX_SIGNAL_TREND_MQH__

#include "SignalBase.mqh"

//+------------------------------------------------------------------+
//| CSignalTrend — Trend Following con EMA crossover + ADX + ATR     |
//|                                                                   |
//| Lógica:                                                          |
//| 1. Confirmación TF superior (H4): EMA50 > EMA200 = tendencia up  |
//| 2. Señal TF principal (H1): EMA8 cruza EMA21 en dirección trend  |
//| 3. Filtro: ADX > 20 (existe tendencia)                           |
//| 4. SL: 1.5x ATR(14) desde entrada                                |
//| 5. TP: 2.5x ATR(14) desde entrada (R:R ~1.67)                   |
//| 6. Trailing: ATR trailing a 1.2x ATR detrás del precio           |
//|                                                                   |
//| Edge esperado: captura movimientos tendenciales mayores           |
//| Win rate estimado: 38-45% con R:R > 1.5                          |
//+------------------------------------------------------------------+
class CSignalTrend : public CSignalBase
{
private:
   //--- Handles de indicadores
   int   m_emaFastHandle;       // EMA rápida (8) — TF principal
   int   m_emaSlowHandle;       // EMA lenta (21) — TF principal
   int   m_ema50ConfHandle;     // EMA 50 — TF confirmación
   int   m_ema200ConfHandle;    // EMA 200 — TF confirmación
   int   m_adxHandle;           // ADX — TF principal
   int   m_atrHandle;           // ATR — TF principal
   
   //--- Parámetros de la estrategia
   int   m_emaFastPeriod;       // Período EMA rápida
   int   m_emaSlowPeriod;       // Período EMA lenta
   int   m_emaConfFast;         // Período EMA confirmación rápida
   int   m_emaConfSlow;         // Período EMA confirmación lenta
   int   m_adxPeriod;           // Período ADX
   double m_adxMinLevel;        // Nivel mínimo de ADX para operar
   int   m_atrPeriod;           // Período ATR
   double m_slATRMultiplier;    // Multiplicador ATR para SL
   double m_tpATRMultiplier;    // Multiplicador ATR para TP
   double m_trailATRMultiplier; // Multiplicador ATR para trailing
   double m_minConfidence;      // Confianza mínima para señal
   
   //--- Estado interno
   double m_prevEmaFast;        // EMA rápida barra anterior
   double m_prevEmaSlow;        // EMA lenta barra anterior
   datetime m_lastBarTime;      // Para detectar nueva barra
   
   // Detectar si hay nueva barra en el TF principal
   bool IsNewBar()
   {
      datetime barTime = iTime(m_symbol, m_primaryTF, 0);
      if(barTime != m_lastBarTime)
      {
         m_lastBarTime = barTime;
         return true;
      }
      return false;
   }
   
public:
   CSignalTrend()
   {
      m_name              = "TrendFollower";
      m_type              = STRATEGY_TREND;
      m_warmupBars        = 250;
      
      // Parámetros por defecto (optimizables)
      m_emaFastPeriod     = 8;
      m_emaSlowPeriod     = 21;
      m_emaConfFast       = 50;
      m_emaConfSlow       = 200;
      m_adxPeriod         = 14;
      m_adxMinLevel       = 20.0;
      m_atrPeriod         = 14;
      m_slATRMultiplier   = 1.5;
      m_tpATRMultiplier   = 2.5;
      m_trailATRMultiplier= 1.2;
      m_minConfidence     = 0.4;
      
      m_emaFastHandle     = INVALID_HANDLE;
      m_emaSlowHandle     = INVALID_HANDLE;
      m_ema50ConfHandle   = INVALID_HANDLE;
      m_ema200ConfHandle  = INVALID_HANDLE;
      m_adxHandle         = INVALID_HANDLE;
      m_atrHandle         = INVALID_HANDLE;
      m_prevEmaFast       = 0;
      m_prevEmaSlow       = 0;
      m_lastBarTime       = 0;
   }
   
   //--- Inicialización
   virtual bool Init(const string symbol, ENUM_TIMEFRAMES primaryTF,
                     ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES confirmTF) override
   {
      m_symbol    = symbol;
      m_primaryTF = primaryTF;
      m_entryTF   = entryTF;
      m_confirmTF = confirmTF;
      
      // Verificar barras disponibles
      if(!HasEnoughBars(symbol, primaryTF, m_warmupBars))
         return false;
      if(!HasEnoughBars(symbol, confirmTF, m_emaConfSlow + 10))
         return false;
      
      // Crear indicadores en TF principal
      m_emaFastHandle  = iMA(symbol, primaryTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_emaSlowHandle  = iMA(symbol, primaryTF, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_adxHandle      = iADX(symbol, primaryTF, m_adxPeriod);
      m_atrHandle      = iATR(symbol, primaryTF, m_atrPeriod);
      
      // Crear indicadores en TF de confirmación
      m_ema50ConfHandle  = iMA(symbol, confirmTF, m_emaConfFast, 0, MODE_EMA, PRICE_CLOSE);
      m_ema200ConfHandle = iMA(symbol, confirmTF, m_emaConfSlow, 0, MODE_EMA, PRICE_CLOSE);
      
      // Validar handles
      if(m_emaFastHandle == INVALID_HANDLE || m_emaSlowHandle == INVALID_HANDLE ||
         m_adxHandle == INVALID_HANDLE || m_atrHandle == INVALID_HANDLE ||
         m_ema50ConfHandle == INVALID_HANDLE || m_ema200ConfHandle == INVALID_HANDLE)
      {
         g_logger.Error(StringFormat("[%s] Fallo al crear indicadores para %s", m_name, symbol));
         Deinit();
         return false;
      }
      
      // Registrar handles para limpieza automática
      AddHandle(m_emaFastHandle);
      AddHandle(m_emaSlowHandle);
      AddHandle(m_adxHandle);
      AddHandle(m_atrHandle);
      AddHandle(m_ema50ConfHandle);
      AddHandle(m_ema200ConfHandle);
      
      m_initialized = true;
      m_active = true;
      
      g_logger.Info(StringFormat("[%s] Inicializado en %s [primary=%s confirm=%s]",
                    m_name, symbol, EnumToString(primaryTF), EnumToString(confirmTF)));
      return true;
   }
   
   //--- Evaluación principal
   virtual STradeSignal Evaluate() override
   {
      m_currentSignal.Reset();
      
      if(!m_initialized || !m_active)
         return m_currentSignal;
      
      // Solo evaluar en nuevas barras del TF principal
      if(!IsNewBar())
         return m_currentSignal;
      
      //--- Leer indicadores del TF principal (barra 1 = cerrada, barra 2 = anterior)
      double emaFast[3], emaSlow[3], adx[2], adxPlus[2], adxMinus[2], atr[2];
      
      if(CopyBuffer(m_emaFastHandle, 0, 1, 3, emaFast)  != 3) return m_currentSignal;
      if(CopyBuffer(m_emaSlowHandle, 0, 1, 3, emaSlow)  != 3) return m_currentSignal;
      if(CopyBuffer(m_adxHandle, 0, 1, 2, adx)          != 2) return m_currentSignal;
      if(CopyBuffer(m_adxHandle, 1, 1, 2, adxPlus)      != 2) return m_currentSignal;
      if(CopyBuffer(m_adxHandle, 2, 1, 2, adxMinus)     != 2) return m_currentSignal;
      if(CopyBuffer(m_atrHandle, 0, 1, 2, atr)          != 2) return m_currentSignal;
      
      //--- Leer indicadores del TF de confirmación
      double ema50Conf[2], ema200Conf[2];
      if(CopyBuffer(m_ema50ConfHandle, 0, 0, 2, ema50Conf)   != 2) return m_currentSignal;
      if(CopyBuffer(m_ema200ConfHandle, 0, 0, 2, ema200Conf) != 2) return m_currentSignal;
      
      //--- Determinar tendencia del TF superior
      bool confirmBullish = (ema50Conf[0] > ema200Conf[0]);
      bool confirmBearish = (ema50Conf[0] < ema200Conf[0]);
      
      //--- Detectar crossover EMA en TF principal (barra cerrada)
      // emaFast[0] = barra 1 (más reciente cerrada), emaFast[1] = barra 2
      bool bullCross = (emaFast[0] > emaSlow[0]) && (emaFast[1] <= emaSlow[1]);
      bool bearCross = (emaFast[0] < emaSlow[0]) && (emaFast[1] >= emaSlow[1]);
      
      //--- Filtro ADX
      bool adxStrong = (adx[0] > m_adxMinLevel);
      
      //--- Generar señal
      ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE;
      double confidence = 0.0;
      
      if(bullCross && confirmBullish && adxStrong && adxPlus[0] > adxMinus[0])
      {
         direction = SIGNAL_BUY;
         
         // Calcular confianza basada en fortaleza de la señal
         confidence = 0.4; // Base
         confidence += MathMin(0.2, (adx[0] - m_adxMinLevel) / 100.0); // Más ADX = más confianza
         confidence += (ema50Conf[0] - ema200Conf[0]) > 0 ? 0.1 : 0;  // Tendencia clara
         confidence += (adx[0] > adx[1]) ? 0.1 : 0;  // ADX creciente
      }
      else if(bearCross && confirmBearish && adxStrong && adxMinus[0] > adxPlus[0])
      {
         direction = SIGNAL_SELL;
         
         confidence = 0.4;
         confidence += MathMin(0.2, (adx[0] - m_adxMinLevel) / 100.0);
         confidence += (ema200Conf[0] - ema50Conf[0]) > 0 ? 0.1 : 0;
         confidence += (adx[0] > adx[1]) ? 0.1 : 0;
      }
      
      if(direction == SIGNAL_NONE || confidence < m_minConfidence)
         return m_currentSignal;
      
      //--- Calcular SL y TP basados en ATR
      double currentATR = atr[0];
      if(currentATR <= 0) return m_currentSignal;
      
      double price = SymbolInfoDouble(m_symbol, (direction == SIGNAL_BUY) ? SYMBOL_ASK : SYMBOL_BID);
      double sl, tp;
      
      if(direction == SIGNAL_BUY)
      {
         sl = price - currentATR * m_slATRMultiplier;
         tp = price + currentATR * m_tpATRMultiplier;
      }
      else
      {
         sl = price + currentATR * m_slATRMultiplier;
         tp = price - currentATR * m_tpATRMultiplier;
      }
      
      // Normalizar precios
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      //--- Construir señal
      m_currentSignal.direction  = direction;
      m_currentSignal.strategy   = m_type;
      m_currentSignal.symbol     = m_symbol;
      m_currentSignal.timeframe  = m_primaryTF;
      m_currentSignal.confidence = MathMin(1.0, confidence);
      m_currentSignal.entryPrice = price;
      m_currentSignal.stopLoss   = sl;
      m_currentSignal.takeProfit = tp;
      m_currentSignal.riskReward = (currentATR * m_tpATRMultiplier) / (currentATR * m_slATRMultiplier);
      m_currentSignal.signalTime = TimeCurrent();
      m_currentSignal.expiryTime = TimeCurrent() + PeriodSeconds(m_primaryTF) * 3;
      m_currentSignal.reason     = StringFormat("EMA%d/%d cross + ADX=%.1f + %s trend",
                                    m_emaFastPeriod, m_emaSlowPeriod, adx[0],
                                    direction == SIGNAL_BUY ? "BULL" : "BEAR");
      
      m_signalsGenerated++;
      
      g_logger.Debug(StringFormat("[%s] Señal %s %s conf=%.2f R:R=%.2f ATR=%.5f reason=%s",
                     m_name, m_symbol,
                     direction == SIGNAL_BUY ? "BUY" : "SELL",
                     confidence, m_currentSignal.riskReward, currentATR,
                     m_currentSignal.reason));
      
      return m_currentSignal;
   }
   
   //--- Régimen adecuado para esta estrategia
   virtual bool IsRegimeSuitable(ENUM_MARKET_REGIME regime) override
   {
      return (regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN);
   }
   
   //--- Ajustar parámetros (desde el optimizador genético)
   virtual void AdjustParameters(const double &params[]) override
   {
      if(ArraySize(params) >= 4)
      {
         m_adxMinLevel      = params[0]; // 15.0 - 30.0
         m_slATRMultiplier  = params[1]; // 1.0 - 2.5
         m_tpATRMultiplier  = params[2]; // 1.5 - 4.0
         m_minConfidence    = params[3]; // 0.3 - 0.6
      }
   }
   
   virtual void Deinit() override
   {
      ReleaseHandles();
      m_initialized = false;
      m_active = false;
   }
   
   virtual string GetDescription() const override
   {
      return StringFormat("Trend EMA%d/%d + ADX(%d)>%.0f + ATR SL/TP",
                          m_emaFastPeriod, m_emaSlowPeriod, m_adxPeriod, m_adxMinLevel);
   }
};

#endif // __PHOENIX_SIGNAL_TREND_MQH__
//+------------------------------------------------------------------+
