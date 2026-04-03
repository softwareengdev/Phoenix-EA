//+------------------------------------------------------------------+
//|                                               SignalBreakout.mqh |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_BREAKOUT_MQH__
#define __PHOENIX_SIGNAL_BREAKOUT_MQH__

#include "SignalBase.mqh"
#include "..\Core\Globals.mqh"

class CDataEngine;

//+------------------------------------------------------------------+
//| Breakout Strategy                                                  |
//| Entry: Donchian channel breakout + volume spike confirmation     |
//| Best in: Transition from ranging to trending                     |
//+------------------------------------------------------------------+
class CSignalBreakout : public CSignalBase {
private:
   int    m_donchianPeriod;
   int    m_volumePeriod;
   double m_volumeMulti;
   double m_atrSL;
   double m_atrTP;
   
public:
   CSignalBreakout() : m_donchianPeriod(20), m_volumePeriod(20), 
                        m_volumeMulti(1.5), m_atrSL(2.0), m_atrTP(3.0) {}
   
   bool Init(ENUM_STRATEGY_TYPE type, string name) override {
      CSignalBase::Init(type, name);
      m_donchianPeriod = InpBO_DonchianPeriod;
      m_volumePeriod = InpBO_VolumePeriod;
      m_volumeMulti = InpBO_VolumeMulti;
      m_atrSL = InpBO_ATR_SL;
      m_atrTP = InpBO_ATR_TP;
      return true;
   }
   
   STradeSignal Evaluate(int symIdx, CDataEngine *data) override;
   
   double GetRegimeSuitability(ENUM_MARKET_REGIME regime) override {
      switch(regime) {
         case REGIME_RANGING_TIGHT:   return 0.9; // Squeeze = pending breakout
         case REGIME_RANGING_WIDE:    return 0.5;
         case REGIME_QUIET:           return 0.7; // Compression
         case REGIME_TRENDING_WEAK:   return 0.4;
         case REGIME_TRENDING_STRONG: return 0.3;
         case REGIME_VOLATILE:        return 0.6;
         default:                     return 0.4;
      }
   }
   
   bool ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) override;
};

//+------------------------------------------------------------------+
//| Breakout strategy implementation                                   |
//+------------------------------------------------------------------+
#include "..\Data\DataEngine.mqh"

STradeSignal CSignalBreakout::Evaluate(int symIdx, CDataEngine *data) {
   STradeSignal signal;
   ZeroMemory(signal);
   signal.direction = SIGNAL_NONE;
   signal.strategy = STRATEGY_BREAKOUT;
   signal.symbolIndex = symIdx;
   signal.symbol = g_Symbols[symIdx].name;
   signal.timestamp = TimeCurrent();
   
   double close = data.GetClose(symIdx, 0);
   double donchianHigh = data.GetDonchianHigh(symIdx, m_donchianPeriod);
   double donchianLow = data.GetDonchianLow(symIdx, m_donchianPeriod);
   double atr = data.GetATR(symIdx, 1);
   double volume = data.GetCurrentVolume(symIdx);
   double volumeAvg = data.GetVolumeSMA(symIdx, m_volumePeriod);
   
   if(atr <= 0 || donchianHigh <= 0 || donchianLow <= 0) return signal;
   
   signal.atrValue = atr;
   signal.regime = data.GetRegime(symIdx);
   
   // Volume confirmation
   bool volumeSpike = (volumeAvg > 0 && volume >= volumeAvg * m_volumeMulti);
   
   // Channel width (squeeze detection)
   double channelWidth = donchianHigh - donchianLow;
   double bbWidth = data.GetBBWidth(symIdx);
   bool isSqueeze = (bbWidth < 0.015); // Tight Bollinger = pending breakout
   
   double confidenceBonus = isSqueeze ? 0.15 : 0.0;
   
   // BUY Breakout: Close above Donchian high + volume
   if(close > donchianHigh && volumeSpike) {
      signal.direction = SIGNAL_BUY;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_ASK);
      signal.stopLoss = signal.entryPrice - atr * m_atrSL;
      signal.takeProfit = signal.entryPrice + channelWidth * 1.5;
      if(signal.takeProfit < signal.entryPrice + atr * m_atrTP)
         signal.takeProfit = signal.entryPrice + atr * m_atrTP;
      double risk = signal.entryPrice - signal.stopLoss;
      double reward = signal.takeProfit - signal.entryPrice;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = MathMin(1.0, 0.5 + confidenceBonus + (volume / volumeAvg - 1.0) * 0.2);
      signal.comment = StringFormat("BO BUY Vol=%.0f/%.0f Squeeze=%s", volume, volumeAvg, isSqueeze ? "Y" : "N");
   }
   // SELL Breakout
   else if(close < donchianLow && volumeSpike) {
      signal.direction = SIGNAL_SELL;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      signal.stopLoss = signal.entryPrice + atr * m_atrSL;
      signal.takeProfit = signal.entryPrice - channelWidth * 1.5;
      if(signal.takeProfit > signal.entryPrice - atr * m_atrTP)
         signal.takeProfit = signal.entryPrice - atr * m_atrTP;
      double risk = signal.stopLoss - signal.entryPrice;
      double reward = signal.entryPrice - signal.takeProfit;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = MathMin(1.0, 0.5 + confidenceBonus + (volume / volumeAvg - 1.0) * 0.2);
      signal.comment = StringFormat("BO SELL Vol=%.0f/%.0f Squeeze=%s", volume, volumeAvg, isSqueeze ? "Y" : "N");
   }
   
   return signal;
}

//+------------------------------------------------------------------+
bool CSignalBreakout::ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) {
   double close = data.GetClose(symIdx, 0);
   double maFast = data.GetMAFast(symIdx, 0);
   double maSlow = data.GetMASlow(symIdx, 0);
   // Exit if price retreats back into channel (trend reversal)
   if(posDir == SIGNAL_BUY && close < maSlow) return true;
   if(posDir == SIGNAL_SELL && close > maSlow) return true;
   return false;
}

#endif // __PHOENIX_SIGNAL_BREAKOUT_MQH__
