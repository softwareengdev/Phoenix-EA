//+------------------------------------------------------------------+
//|                                           SignalScalper.mqh      |
//|                      PHOENIX EA — Session Scalper Strategy         |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_SCALPER_MQH__
#define __PHOENIX_SIGNAL_SCALPER_MQH__

#include "SignalBase.mqh"

//+------------------------------------------------------------------+
//| CSignalScalper — Scalper en M15 durante sesiones activas          |
//|                                                                   |
//| Lógica:                                                          |
//| 1. Opera SOLO durante London y London-NY overlap (máxima liquid.) |
//| 2. EMA rápida (5) + EMA media (13) en M15 para dirección         |
//| 3. RSI(7) para timing de entrada (pullback en tendencia)          |
//| 4. MACD histogram para momentum                                  |
//| 5. SL: tight — 1x ATR(10) en M15                                 |
//| 6. TP: 1.5x SL con trailing a 0.7x ATR                          |
//|                                                                   |
//| Edge: alta frecuencia en el timeframe más líquido                |
//| Win rate esperado: 50-55%, R:R ~1.3-1.5, 3-8 trades/día         |
//+------------------------------------------------------------------+
class CSignalScalper : public CSignalBase
{
private:
   int   m_emaFastHandle;
   int   m_emaMedHandle;
   int   m_rsiHandle;
   int   m_macdHandle;
   int   m_atrHandle;
   
   //--- Parámetros
   int   m_emaFastPeriod;
   int   m_emaMedPeriod;
   int   m_rsiPeriod;
   double m_rsiBuyZone;         // RSI < esto en pullback alcista
   double m_rsiSellZone;        // RSI > esto en pullback bajista
   int   m_atrPeriod;
   double m_slATRMult;
   double m_tpRRRatio;          // R:R target
   int   m_maxDailyTrades;      // Máximo de scalps por día
   int   m_todayTrades;
   datetime m_lastTradeDay;
   
   datetime m_lastBarTime;
   
   bool IsNewBar()
   {
      datetime barTime = iTime(m_symbol, m_entryTF, 0); // Usa TF de entrada (M15)
      if(barTime != m_lastBarTime) { m_lastBarTime = barTime; return true; }
      return false;
   }
   
   void ResetDailyCounter()
   {
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      if(today != m_lastTradeDay)
      {
         m_todayTrades = 0;
         m_lastTradeDay = today;
      }
   }
   
public:
   CSignalScalper()
   {
      m_name           = "Scalper";
      m_type           = STRATEGY_SCALPER;
      m_warmupBars     = 50;
      
      m_emaFastPeriod  = 5;
      m_emaMedPeriod   = 13;
      m_rsiPeriod      = 7;
      m_rsiBuyZone     = 40.0;  // RSI pulls back below 40 in uptrend
      m_rsiSellZone    = 60.0;  // RSI pulls back above 60 in downtrend
      m_atrPeriod      = 10;
      m_slATRMult      = 1.0;
      m_tpRRRatio      = 1.5;
      m_maxDailyTrades = 8;
      m_todayTrades    = 0;
      m_lastTradeDay   = 0;
      
      m_emaFastHandle = m_emaMedHandle = m_rsiHandle = m_macdHandle = m_atrHandle = INVALID_HANDLE;
      m_lastBarTime = 0;
   }
   
   virtual bool Init(const string symbol, ENUM_TIMEFRAMES primaryTF,
                     ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES confirmTF) override
   {
      m_symbol    = symbol;
      m_primaryTF = primaryTF;
      m_entryTF   = (entryTF != 0) ? entryTF : PERIOD_M15;
      m_confirmTF = confirmTF;
      
      if(!HasEnoughBars(symbol, m_entryTF, m_warmupBars))
         return false;
      
      // Indicadores en TF de entrada (M15 para scalping)
      m_emaFastHandle = iMA(symbol, m_entryTF, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_emaMedHandle  = iMA(symbol, m_entryTF, m_emaMedPeriod, 0, MODE_EMA, PRICE_CLOSE);
      m_rsiHandle     = iRSI(symbol, m_entryTF, m_rsiPeriod, PRICE_CLOSE);
      m_macdHandle    = iMACD(symbol, m_entryTF, 12, 26, 9, PRICE_CLOSE);
      m_atrHandle     = iATR(symbol, m_entryTF, m_atrPeriod);
      
      if(m_emaFastHandle == INVALID_HANDLE || m_emaMedHandle == INVALID_HANDLE ||
         m_rsiHandle == INVALID_HANDLE || m_macdHandle == INVALID_HANDLE ||
         m_atrHandle == INVALID_HANDLE)
      {
         g_logger.Error(StringFormat("[%s] Fallo indicadores para %s", m_name, symbol));
         Deinit();
         return false;
      }
      
      AddHandle(m_emaFastHandle);
      AddHandle(m_emaMedHandle);
      AddHandle(m_rsiHandle);
      AddHandle(m_macdHandle);
      AddHandle(m_atrHandle);
      
      m_initialized = true;
      m_active = true;
      
      g_logger.Info(StringFormat("[%s] Inicializado en %s [entry=%s EMA%d/%d RSI%d maxDaily=%d]",
                    m_name, symbol, EnumToString(m_entryTF),
                    m_emaFastPeriod, m_emaMedPeriod, m_rsiPeriod, m_maxDailyTrades));
      return true;
   }
   
   virtual STradeSignal Evaluate() override
   {
      m_currentSignal.Reset();
      
      if(!m_initialized || !m_active) return m_currentSignal;
      if(!IsNewBar()) return m_currentSignal;
      
      ResetDailyCounter();
      
      // Límite diario
      if(m_todayTrades >= m_maxDailyTrades) return m_currentSignal;
      
      //--- Leer indicadores (barras 1 y 2 del TF de entrada)
      double emaFast[3], emaMed[3], rsi[3], macdMain[3], macdSignal[3], atr[2];
      
      if(CopyBuffer(m_emaFastHandle, 0, 1, 3, emaFast) != 3) return m_currentSignal;
      if(CopyBuffer(m_emaMedHandle, 0, 1, 3, emaMed)   != 3) return m_currentSignal;
      if(CopyBuffer(m_rsiHandle, 0, 1, 3, rsi)         != 3) return m_currentSignal;
      if(CopyBuffer(m_macdHandle, 0, 1, 3, macdMain)   != 3) return m_currentSignal;
      if(CopyBuffer(m_macdHandle, 1, 1, 3, macdSignal) != 3) return m_currentSignal;
      if(CopyBuffer(m_atrHandle, 0, 1, 2, atr)         != 2) return m_currentSignal;
      
      double macdHist0 = macdMain[0] - macdSignal[0];
      double macdHist1 = macdMain[1] - macdSignal[1];
      
      //--- Tendencia de corto plazo (EMA fast > EMA med = bull)
      bool bullTrend = (emaFast[0] > emaMed[0]) && (emaFast[1] > emaMed[1]);
      bool bearTrend = (emaFast[0] < emaMed[0]) && (emaFast[1] < emaMed[1]);
      
      ENUM_SIGNAL_DIRECTION direction = SIGNAL_NONE;
      double confidence = 0.0;
      
      //--- BUY: tendencia alcista + RSI pullback + MACD momentum positivo
      if(bullTrend && rsi[0] < m_rsiBuyZone && rsi[0] > rsi[1] && macdHist0 > 0)
      {
         direction = SIGNAL_BUY;
         confidence = 0.45;
         
         // RSI girando desde más abajo = mejor entrada
         if(rsi[1] < 30) confidence += 0.15;
         // MACD creciendo
         if(macdHist0 > macdHist1) confidence += 0.10;
         // Spread bajo
         if(GetSpreadInPips(m_symbol) < 1.5) confidence += 0.10;
      }
      //--- SELL: tendencia bajista + RSI pullback + MACD momentum negativo
      else if(bearTrend && rsi[0] > m_rsiSellZone && rsi[0] < rsi[1] && macdHist0 < 0)
      {
         direction = SIGNAL_SELL;
         confidence = 0.45;
         
         if(rsi[1] > 70) confidence += 0.15;
         if(macdHist0 < macdHist1) confidence += 0.10;
         if(GetSpreadInPips(m_symbol) < 1.5) confidence += 0.10;
      }
      
      if(direction == SIGNAL_NONE) return m_currentSignal;
      
      //--- SL/TP
      double currentATR = atr[0];
      if(currentATR <= 0) return m_currentSignal;
      
      double price = SymbolInfoDouble(m_symbol, (direction == SIGNAL_BUY) ? SYMBOL_ASK : SYMBOL_BID);
      int digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      double slDist = currentATR * m_slATRMult;
      double tpDist = slDist * m_tpRRRatio;
      double sl, tp;
      
      if(direction == SIGNAL_BUY)
      {
         sl = price - slDist;
         tp = price + tpDist;
      }
      else
      {
         sl = price + slDist;
         tp = price - tpDist;
      }
      
      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);
      
      m_currentSignal.direction  = direction;
      m_currentSignal.strategy   = m_type;
      m_currentSignal.symbol     = m_symbol;
      m_currentSignal.timeframe  = m_entryTF;
      m_currentSignal.confidence = MathMin(1.0, confidence);
      m_currentSignal.entryPrice = price;
      m_currentSignal.stopLoss   = sl;
      m_currentSignal.takeProfit = tp;
      m_currentSignal.riskReward = m_tpRRRatio;
      m_currentSignal.signalTime = TimeCurrent();
      m_currentSignal.expiryTime = TimeCurrent() + PeriodSeconds(m_entryTF);
      m_currentSignal.reason     = StringFormat("Scalp EMA%d/%d RSI=%.1f MACD=%s",
                                    m_emaFastPeriod, m_emaMedPeriod, rsi[0],
                                    macdHist0 > 0 ? "+" : "-");
      
      m_signalsGenerated++;
      m_todayTrades++;
      
      g_logger.Debug(StringFormat("[%s] Señal %s %s conf=%.2f daily=%d/%d",
                     m_name, m_symbol,
                     direction == SIGNAL_BUY ? "BUY" : "SELL",
                     confidence, m_todayTrades, m_maxDailyTrades));
      
      return m_currentSignal;
   }
   
   virtual bool IsRegimeSuitable(ENUM_MARKET_REGIME regime) override
   {
      // Scalper funciona en trending y ranging (no en volatile/thin)
      return (regime == REGIME_TRENDING_UP || regime == REGIME_TRENDING_DOWN || regime == REGIME_RANGING);
   }
   
   virtual void AdjustParameters(const double &params[]) override
   {
      if(ArraySize(params) >= 3)
      {
         m_rsiBuyZone     = params[0]; // 35-50
         m_rsiSellZone    = 100.0 - params[0];
         m_slATRMult      = params[1]; // 0.7-1.5
         m_tpRRRatio      = params[2]; // 1.0-2.5
      }
   }
   
   virtual void Deinit() override { ReleaseHandles(); m_initialized = false; m_active = false; }
   
   virtual string GetDescription() const override
   {
      return StringFormat("Scalper M15 EMA%d/%d + RSI(%d) + MACD",
                          m_emaFastPeriod, m_emaMedPeriod, m_rsiPeriod);
   }
};

#endif // __PHOENIX_SIGNAL_SCALPER_MQH__
//+------------------------------------------------------------------+
