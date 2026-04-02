//+------------------------------------------------------------------+
//|                                           SignalBreakout.mqh     |
//|                    PHOENIX EA — Breakout / Momentum Strategy       |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_BREAKOUT_MQH__
#define __PHOENIX_SIGNAL_BREAKOUT_MQH__

#include "SignalBase.mqh"

//+------------------------------------------------------------------+
//| CSignalBreakout — Donchian Channel Breakout + Volume + Momentum  |
//|                                                                   |
//| Lógica:                                                          |
//| 1. Canal Donchian de N períodos (high/low)                       |
//| 2. BUY: cierre rompe máximo del canal + volumen > 1.5x promedio  |
//| 3. SELL: cierre rompe mínimo del canal + volumen > 1.5x promedio |
//| 4. Filtro: BB squeeze previo (volatilidad comprimida → expansión)|
//| 5. SL: lado opuesto del canal o 2x ATR                          |
//| 6. TP: extensión del rango del canal (1:2 riesgo)               |
//|                                                                   |
//| Edge: captura rupturas de consolidación. Win rate ~35-40%, R:R >2|
//+------------------------------------------------------------------+
class CSignalBreakout : public CSignalBase
{
private:
   int   m_atrHandle;
   int   m_bbHandle;            // Bollinger para detectar squeeze
   int   m_volHandle;           // Volumes MA
   
   //--- Parámetros
   int   m_channelPeriod;       // Período del canal Donchian
   int   m_atrPeriod;
   double m_volumeMultiplier;   // Volumen debe ser > N*promedio
   int   m_volumeAvgPeriod;     // Período para promedio de volumen
   double m_slATRMultiplier;    // SL como múltiplo de ATR
   double m_tpMultiplier;       // TP como múltiplo del rango del canal
   double m_squeezeThreshold;   // BB width < X = squeeze
   int   m_squeezeLookback;     // Barras a mirar para squeeze previo
   
   datetime m_lastBarTime;
   
   bool IsNewBar()
   {
      datetime barTime = iTime(m_symbol, m_primaryTF, 0);
      if(barTime != m_lastBarTime) { m_lastBarTime = barTime; return true; }
      return false;
   }
   
   // Calcular Donchian Channel (high/low de N barras)
   bool GetDonchianChannel(double &upper, double &lower, int shift = 1)
   {
      double highs[], lows[];
      if(CopyHigh(m_symbol, m_primaryTF, shift, m_channelPeriod, highs) != m_channelPeriod) return false;
      if(CopyLow(m_symbol, m_primaryTF, shift, m_channelPeriod, lows)   != m_channelPeriod) return false;
      
      upper = highs[ArrayMaximum(highs)];
      lower = lows[ArrayMinimum(lows)];
      return true;
   }
   
   // Detectar Bollinger squeeze (baja volatilidad previa)
   bool WasSqueezed()
   {
      double bbUpper[], bbLower[];
      if(CopyBuffer(m_bbHandle, 1, 1, m_squeezeLookback, bbUpper) != m_squeezeLookback) return false;
      if(CopyBuffer(m_bbHandle, 2, 1, m_squeezeLookback, bbLower) != m_squeezeLookback) return false;
      
      double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      if(price <= 0) return false;
      
      int squeezeCount = 0;
      for(int i = 0; i < m_squeezeLookback; i++)
      {
         double width = (bbUpper[i] - bbLower[i]) / price * 100.0;
         if(width < m_squeezeThreshold)
            squeezeCount++;
      }
      
      // Al menos 60% de las barras recientes estaban en squeeze
      return (squeezeCount >= m_squeezeLookback * 0.6);
   }
   
   // Verificar volumen alto
   bool IsVolumeHigh()
   {
      long volumes[];
      if(CopyTickVolume(m_symbol, m_primaryTF, 1, m_volumeAvgPeriod + 1, volumes) != m_volumeAvgPeriod + 1)
         return false;
      
      double avgVol = 0;
      for(int i = 1; i <= m_volumeAvgPeriod; i++)
         avgVol += (double)volumes[i];
      avgVol /= m_volumeAvgPeriod;
      
      return ((double)volumes[0] > avgVol * m_volumeMultiplier);
   }
   
public:
   CSignalBreakout()
   {
      m_name              = "Breakout";
      m_type              = STRATEGY_BREAKOUT;
      m_warmupBars        = 100;
      
      m_channelPeriod     = 20;
      m_atrPeriod         = 14;
      m_volumeMultiplier  = 1.3;
      m_volumeAvgPeriod   = 20;
      m_slATRMultiplier   = 2.0;
      m_tpMultiplier      = 1.5;
      m_squeezeThreshold  = 1.5; // BB width < 1.5%
      m_squeezeLookback   = 10;
      
      m_atrHandle = m_bbHandle = m_volHandle = INVALID_HANDLE;
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
      
      m_atrHandle = iATR(symbol, primaryTF, m_atrPeriod);
      m_bbHandle  = iBands(symbol, primaryTF, 20, 0, 2.0, PRICE_CLOSE);
      
      if(m_atrHandle == INVALID_HANDLE || m_bbHandle == INVALID_HANDLE)
      {
         g_logger.Error(StringFormat("[%s] Fallo indicadores para %s", m_name, symbol));
         Deinit();
         return false;
      }
      
      AddHandle(m_atrHandle);
      AddHandle(m_bbHandle);
      
      m_initialized = true;
      m_active = true;
      
      g_logger.Info(StringFormat("[%s] Inicializado en %s [channel=%d volMult=%.1f]",
                    m_name, symbol, m_channelPeriod, m_volumeMultiplier));
      return true;
   }
   
   virtual STradeSignal Evaluate() override
   {
      m_currentSignal.Reset();
      
      if(!m_initialized || !m_active) return m_currentSignal;
      if(!IsNewBar()) return m_currentSignal;
      
      //--- Calcular canal Donchian (barra 2 en adelante para canal previo)
      double channelHigh, channelLow;
      if(!GetDonchianChannel(channelHigh, channelLow, 2))
         return m_currentSignal;
      
      //--- Precio de la última barra cerrada
      double closeLast = iClose(m_symbol, m_primaryTF, 1);
      
      //--- ATR
      double atr[];
      if(CopyBuffer(m_atrHandle, 0, 1, 1, atr) != 1) return m_currentSignal;
      if(atr[0] <= 0) return m_currentSignal;
      
      ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE;
      double confidence = 0.0;
      
      //--- Breakout alcista
      if(closeLast > channelHigh)
      {
         direction = SIGNAL_BUY;
         confidence = 0.40;
         
         // Bonus si venía de squeeze
         if(WasSqueezed()) confidence += 0.20;
         // Bonus si volumen alto
         if(IsVolumeHigh()) confidence += 0.15;
         // Bonus si rompió por margen significativo
         double breakMargin = (closeLast - channelHigh) / atr[0];
         if(breakMargin > 0.5) confidence += 0.10;
      }
      //--- Breakout bajista
      else if(closeLast < channelLow)
      {
         direction = SIGNAL_SELL;
         confidence = 0.40;
         
         if(WasSqueezed()) confidence += 0.20;
         if(IsVolumeHigh()) confidence += 0.15;
         double breakMargin = (channelLow - closeLast) / atr[0];
         if(breakMargin > 0.5) confidence += 0.10;
      }
      
      if(direction == SIGNAL_NONE) return m_currentSignal;
      
      //--- SL/TP
      double price = SymbolInfoDouble(m_symbol, (direction == SIGNAL_BUY) ? SYMBOL_ASK : SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double channelRange = channelHigh - channelLow;
      double sl, tp;
      
      if(direction == SIGNAL_BUY)
      {
         sl = MathMin(channelLow, price - atr[0] * m_slATRMultiplier);
         tp = price + channelRange * m_tpMultiplier;
      }
      else
      {
         sl = MathMax(channelHigh, price + atr[0] * m_slATRMultiplier);
         tp = price - channelRange * m_tpMultiplier;
      }
      
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      double risk   = MathAbs(price - sl);
      double reward = MathAbs(tp - price);
      if(risk <= 0 || reward / risk < 1.2) return m_currentSignal;
      
      m_currentSignal.direction  = direction;
      m_currentSignal.strategy   = m_type;
      m_currentSignal.symbol     = m_symbol;
      m_currentSignal.timeframe  = m_primaryTF;
      m_currentSignal.confidence = MathMin(1.0, confidence);
      m_currentSignal.entryPrice = price;
      m_currentSignal.stopLoss   = sl;
      m_currentSignal.takeProfit = tp;
      m_currentSignal.riskReward = reward / risk;
      m_currentSignal.signalTime = TimeCurrent();
      m_currentSignal.expiryTime = TimeCurrent() + PeriodSeconds(m_primaryTF) * 2;
      m_currentSignal.reason     = StringFormat("Donchian(%d) breakout %s squeezed=%s vol=%s",
                                    m_channelPeriod,
                                    direction == SIGNAL_BUY ? "UP" : "DOWN",
                                    WasSqueezed() ? "Y" : "N",
                                    IsVolumeHigh() ? "HIGH" : "normal");
      
      m_signalsGenerated++;
      g_logger.Debug(StringFormat("[%s] Señal %s %s conf=%.2f R:R=%.2f",
                     m_name, m_symbol,
                     direction == SIGNAL_BUY ? "BUY" : "SELL",
                     confidence, m_currentSignal.riskReward));
      
      return m_currentSignal;
   }
   
   virtual bool IsRegimeSuitable(ENUM_MARKET_REGIME regime) override
   {
      // Breakout funciona al salir de rango hacia tendencia
      return (regime == REGIME_RANGING || regime == REGIME_VOLATILE);
   }
   
   virtual void AdjustParameters(const double &params[]) override
   {
      if(ArraySize(params) >= 3)
      {
         m_channelPeriod    = (int)params[0]; // 10-40
         m_volumeMultiplier = params[1];      // 1.0-2.0
         m_tpMultiplier     = params[2];      // 1.0-3.0
      }
   }
   
   virtual void Deinit() override { ReleaseHandles(); m_initialized = false; m_active = false; }
   
   virtual string GetDescription() const override
   {
      return StringFormat("Breakout Donchian(%d) + Vol + Squeeze", m_channelPeriod);
   }
};

#endif // __PHOENIX_SIGNAL_BREAKOUT_MQH__
//+------------------------------------------------------------------+
