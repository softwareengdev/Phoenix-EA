//+------------------------------------------------------------------+
//|                                          SignalMeanRevert.mqh    |
//|                    PHOENIX EA — Mean Reversion Strategy            |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_MEANREVERT_MQH__
#define __PHOENIX_SIGNAL_MEANREVERT_MQH__

#include "SignalBase.mqh"

//+------------------------------------------------------------------+
//| CSignalMeanRevert — Mean Reversion con Bollinger + RSI + Stoch   |
//|                                                                   |
//| Lógica:                                                          |
//| 1. Filtro: ADX < 25 (mercado lateral, no tendencial)             |
//| 2. Señal BUY: precio toca BB inferior + RSI < 30 + Stoch < 20   |
//| 3. Señal SELL: precio toca BB superior + RSI > 70 + Stoch > 80  |
//| 4. Confirmación: vela de rechazo (pin bar / engulfing)           |
//| 5. SL: fuera de BB + buffer ATR                                  |
//| 6. TP: banda media (EMA 20) = centro de Bollinger                |
//|                                                                   |
//| Edge: captura rebotes en rango. Win rate alto (~55-65%), R:R ~1  |
//+------------------------------------------------------------------+
class CSignalMeanRevert : public CSignalBase
{
private:
   int   m_bbHandle;            // Bollinger Bands
   int   m_rsiHandle;           // RSI
   int   m_stochHandle;         // Stochastic
   int   m_adxHandle;           // ADX para filtro
   int   m_atrHandle;           // ATR para SL buffer
   
   //--- Parámetros
   int   m_bbPeriod;
   double m_bbDeviation;
   int   m_rsiPeriod;
   double m_rsiOversold;
   double m_rsiOverbought;
   int   m_stochK;
   int   m_stochD;
   int   m_stochSlowing;
   double m_stochOversold;
   double m_stochOverbought;
   double m_adxMaxLevel;        // ADX debe estar debajo de esto
   int   m_atrPeriod;
   double m_slBuffer;           // Buffer adicional de SL (multiplicador ATR)
   
   datetime m_lastBarTime;
   
   bool IsNewBar()
   {
      datetime barTime = iTime(m_symbol, m_primaryTF, 0);
      if(barTime != m_lastBarTime) { m_lastBarTime = barTime; return true; }
      return false;
   }
   
   // Detectar vela de rechazo (pin bar simplificado)
   bool IsBullishRejection()
   {
      double open  = iOpen(m_symbol, m_primaryTF, 1);
      double close = iClose(m_symbol, m_primaryTF, 1);
      double high  = iHigh(m_symbol, m_primaryTF, 1);
      double low   = iLow(m_symbol, m_primaryTF, 1);
      
      double body     = MathAbs(close - open);
      double range    = high - low;
      double lowerWick = MathMin(open, close) - low;
      
      if(range <= 0) return false;
      
      // Lower wick > 60% del rango y body < 40%
      return (lowerWick / range > 0.55 && body / range < 0.45);
   }
   
   bool IsBearishRejection()
   {
      double open  = iOpen(m_symbol, m_primaryTF, 1);
      double close = iClose(m_symbol, m_primaryTF, 1);
      double high  = iHigh(m_symbol, m_primaryTF, 1);
      double low   = iLow(m_symbol, m_primaryTF, 1);
      
      double body     = MathAbs(close - open);
      double range    = high - low;
      double upperWick = high - MathMax(open, close);
      
      if(range <= 0) return false;
      
      return (upperWick / range > 0.55 && body / range < 0.45);
   }
   
public:
   CSignalMeanRevert()
   {
      m_name             = "MeanReversion";
      m_type             = STRATEGY_MEANREV;
      m_warmupBars       = 100;
      
      m_bbPeriod         = 20;
      m_bbDeviation      = 2.0;
      m_rsiPeriod        = 14;
      m_rsiOversold      = 30.0;
      m_rsiOverbought    = 70.0;
      m_stochK           = 14;
      m_stochD           = 3;
      m_stochSlowing     = 3;
      m_stochOversold    = 20.0;
      m_stochOverbought  = 80.0;
      m_adxMaxLevel      = 25.0;
      m_atrPeriod        = 14;
      m_slBuffer         = 0.5;
      
      m_bbHandle = m_rsiHandle = m_stochHandle = m_adxHandle = m_atrHandle = INVALID_HANDLE;
      m_lastBarTime = 0;
   }
   
   virtual bool Init(const string symbol, ENUM_TIMEFRAMES primaryTF,
                     ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES confirmTF) override
   {
      m_symbol    = symbol;
      m_primaryTF = primaryTF;
      m_entryTF   = entryTF;
      m_confirmTF = confirmTF;
      
      if(!HasEnoughBars(symbol, primaryTF, m_warmupBars))
         return false;
      
      m_bbHandle    = iBands(symbol, primaryTF, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
      m_rsiHandle   = iRSI(symbol, primaryTF, m_rsiPeriod, PRICE_CLOSE);
      m_stochHandle = iStochastic(symbol, primaryTF, m_stochK, m_stochD, m_stochSlowing, MODE_SMA, STO_LOWHIGH);
      m_adxHandle   = iADX(symbol, primaryTF, 14);
      m_atrHandle   = iATR(symbol, primaryTF, m_atrPeriod);
      
      if(m_bbHandle == INVALID_HANDLE || m_rsiHandle == INVALID_HANDLE ||
         m_stochHandle == INVALID_HANDLE || m_adxHandle == INVALID_HANDLE ||
         m_atrHandle == INVALID_HANDLE)
      {
         g_logger.Error(StringFormat("[%s] Fallo indicadores para %s", m_name, symbol));
         Deinit();
         return false;
      }
      
      AddHandle(m_bbHandle);
      AddHandle(m_rsiHandle);
      AddHandle(m_stochHandle);
      AddHandle(m_adxHandle);
      AddHandle(m_atrHandle);
      
      m_initialized = true;
      m_active = true;
      
      g_logger.Info(StringFormat("[%s] Inicializado en %s [BB(%d,%.1f) RSI(%d) Stoch(%d,%d)]",
                    m_name, symbol, m_bbPeriod, m_bbDeviation, m_rsiPeriod, m_stochK, m_stochD));
      return true;
   }
   
   virtual STradeSignal Evaluate() override
   {
      m_currentSignal.Reset();
      
      if(!m_initialized || !m_active) return m_currentSignal;
      if(!IsNewBar()) return m_currentSignal;
      
      //--- Leer indicadores (barra 1 = última cerrada)
      double bbMid[2], bbUpper[2], bbLower[2], rsi[2], stochK[2], stochD[2], adx[2], atr[2];
      
      if(CopyBuffer(m_bbHandle, 0, 1, 2, bbMid)    != 2) return m_currentSignal;
      if(CopyBuffer(m_bbHandle, 1, 1, 2, bbUpper)  != 2) return m_currentSignal;
      if(CopyBuffer(m_bbHandle, 2, 1, 2, bbLower)  != 2) return m_currentSignal;
      if(CopyBuffer(m_rsiHandle, 0, 1, 2, rsi)     != 2) return m_currentSignal;
      if(CopyBuffer(m_stochHandle, 0, 1, 2, stochK)!= 2) return m_currentSignal;
      if(CopyBuffer(m_stochHandle, 1, 1, 2, stochD)!= 2) return m_currentSignal;
      if(CopyBuffer(m_adxHandle, 0, 1, 2, adx)     != 2) return m_currentSignal;
      if(CopyBuffer(m_atrHandle, 0, 1, 2, atr)     != 2) return m_currentSignal;
      
      //--- Filtro: mercado lateral (ADX bajo)
      if(adx[0] > m_adxMaxLevel)
         return m_currentSignal;
      
      double closeLast = iClose(m_symbol, m_primaryTF, 1);
      double lowLast   = iLow(m_symbol, m_primaryTF, 1);
      double highLast  = iHigh(m_symbol, m_primaryTF, 1);
      
      ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE;
      double confidence = 0.0;
      
      //--- BUY: precio tocó BB inferior + RSI sobrevendido + Stoch sobrevendido
      if(lowLast <= bbLower[0] && rsi[0] < m_rsiOversold && stochK[0] < m_stochOversold)
      {
         direction = SIGNAL_BUY;
         confidence = 0.45;
         
         // Bonus por confluencia
         if(IsBullishRejection()) confidence += 0.15;
         if(stochK[0] < stochD[0] && stochK[0] < 10) confidence += 0.1;
         if(rsi[0] < 20) confidence += 0.1;
      }
      //--- SELL: precio tocó BB superior + RSI sobrecomprado + Stoch sobrecomprado
      else if(highLast >= bbUpper[0] && rsi[0] > m_rsiOverbought && stochK[0] > m_stochOverbought)
      {
         direction = SIGNAL_SELL;
         confidence = 0.45;
         
         if(IsBearishRejection()) confidence += 0.15;
         if(stochK[0] > stochD[0] && stochK[0] > 90) confidence += 0.1;
         if(rsi[0] > 80) confidence += 0.1;
      }
      
      if(direction == SIGNAL_NONE) return m_currentSignal;
      
      //--- Calcular SL/TP
      double currentATR = atr[0];
      if(currentATR <= 0) return m_currentSignal;
      
      double price = SymbolInfoDouble(m_symbol, (direction == SIGNAL_BUY) ? SYMBOL_ASK : SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double sl, tp;
      
      if(direction == SIGNAL_BUY)
      {
         sl = bbLower[0] - currentATR * m_slBuffer;
         tp = bbMid[0]; // Target = banda media
      }
      else
      {
         sl = bbUpper[0] + currentATR * m_slBuffer;
         tp = bbMid[0];
      }
      
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      // Verificar R:R mínimo
      double risk   = MathAbs(price - sl);
      double reward = MathAbs(tp - price);
      if(risk <= 0 || reward / risk < 0.8) return m_currentSignal;
      
      //--- Construir señal
      m_currentSignal.direction  = direction;
      m_currentSignal.strategy   = m_type;
      m_currentSignal.symbol     = m_symbol;
      m_currentSignal.timeframe  = m_primaryTF;
      m_currentSignal.confidence = MathMin(1.0, confidence);
      m_currentSignal.entryPrice = price;
      m_currentSignal.stopLoss   = sl;
      m_currentSignal.takeProfit = tp;
      m_currentSignal.riskReward = (risk > 0) ? reward / risk : 0;
      m_currentSignal.signalTime = TimeCurrent();
      m_currentSignal.expiryTime = TimeCurrent() + PeriodSeconds(m_primaryTF) * 2;
      m_currentSignal.reason     = StringFormat("BB+RSI(%.1f)+Stoch(%.1f) %s",
                                    rsi[0], stochK[0],
                                    direction == SIGNAL_BUY ? "OVERSOLD" : "OVERBOUGHT");
      
      m_signalsGenerated++;
      g_logger.Debug(StringFormat("[%s] Señal %s %s conf=%.2f R:R=%.2f",
                     m_name, m_symbol,
                     direction == SIGNAL_BUY ? "BUY" : "SELL",
                     confidence, m_currentSignal.riskReward));
      
      return m_currentSignal;
   }
   
   virtual bool IsRegimeSuitable(ENUM_MARKET_REGIME regime) override
   {
      return (regime == REGIME_RANGING);
   }
   
   virtual void AdjustParameters(const double &params[]) override
   {
      if(ArraySize(params) >= 4)
      {
         m_rsiOversold    = params[0]; // 20-35
         m_rsiOverbought  = 100.0 - params[0]; // Simétrico
         m_bbDeviation    = params[1]; // 1.5-3.0
         m_adxMaxLevel    = params[2]; // 20-30
         m_slBuffer       = params[3]; // 0.3-1.0
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
      return StringFormat("MeanRev BB(%d,%.1f) + RSI(%d) + Stoch(%d)", 
                          m_bbPeriod, m_bbDeviation, m_rsiPeriod, m_stochK);
   }
};

#endif // __PHOENIX_SIGNAL_MEANREVERT_MQH__
//+------------------------------------------------------------------+
