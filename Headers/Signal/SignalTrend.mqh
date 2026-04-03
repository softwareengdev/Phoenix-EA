//+------------------------------------------------------------------+
//|                                                  SignalTrend.mqh |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_TREND_MQH__
#define __PHOENIX_SIGNAL_TREND_MQH__

#include "SignalBase.mqh"
#include "..\Core\Globals.mqh"

// Forward declaration
class CDataEngine;

//+------------------------------------------------------------------+
//| Trend Following Strategy                                          |
//| Entry: EMA fast/slow crossover + ADX confirmation + MA200 filter |
//| SL: ATR-based | TP: ATR-based with higher multiplier             |
//+------------------------------------------------------------------+
class CSignalTrend : public CSignalBase {
private:
   double m_adxMin;
   double m_atrSL;
   double m_atrTP;

public:
   CSignalTrend() : m_adxMin(20.0), m_atrSL(1.5), m_atrTP(2.5) {}
   
   bool Init(ENUM_STRATEGY_TYPE type, string name) override {
      CSignalBase::Init(type, name);
      m_adxMin = InpTrend_ADXMin;
      m_atrSL = InpTrend_ATR_SL;
      m_atrTP = InpTrend_ATR_TP;
      return true;
   }
   
   STradeSignal Evaluate(int symIdx, CDataEngine *data) override;
   
   double GetRegimeSuitability(ENUM_MARKET_REGIME regime) override {
      switch(regime) {
         case REGIME_TRENDING_STRONG: return 1.0;
         case REGIME_TRENDING_WEAK:   return 0.7;
         case REGIME_VOLATILE:        return 0.4;
         case REGIME_RANGING_WIDE:    return 0.2;
         case REGIME_RANGING_TIGHT:   return 0.1;
         case REGIME_QUIET:           return 0.15;
         default:                     return 0.3;
      }
   }
   
   bool ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) override;
};

//+------------------------------------------------------------------+
//| Trend strategy implementation                                     |
//+------------------------------------------------------------------+
#include "..\Data\DataEngine.mqh"

STradeSignal CSignalTrend::Evaluate(int symIdx, CDataEngine *data) {
   STradeSignal signal;
   ZeroMemory(signal);
   signal.direction = SIGNAL_NONE;
   signal.strategy = STRATEGY_TREND;
   signal.symbolIndex = symIdx;
   signal.symbol = g_Symbols[symIdx].name;
   signal.timestamp = TimeCurrent();
   
   double maFast0 = data.GetMAFast(symIdx, 0);
   double maFast1 = data.GetMAFast(symIdx, 1);
   double maSlow0 = data.GetMASlow(symIdx, 0);
   double maSlow1 = data.GetMASlow(symIdx, 1);
   double maFilter = data.GetMAFilter(symIdx, 0);
   double adx = data.GetADX(symIdx, 1);
   double adxPlus = data.GetADXPlus(symIdx, 1);
   double adxMinus = data.GetADXMinus(symIdx, 1);
   double atr = data.GetATR(symIdx, 1);
   double close = data.GetClose(symIdx, 0);
   
   if(atr <= 0 || maFast0 <= 0 || maSlow0 <= 0) return signal;
   
   signal.atrValue = atr;
   signal.regime = data.GetRegime(symIdx);
   
   // ADX must confirm trending conditions
   if(adx < m_adxMin) return signal;
   
   // BUY: Fast MA crosses above Slow MA + Price above 200 MA
   bool bullishCross = (maFast1 <= maSlow1 && maFast0 > maSlow0);
   bool bullishTrend = (close > maFilter) && (adxPlus > adxMinus);
   
   // SELL: Fast MA crosses below Slow MA + Price below 200 MA
   bool bearishCross = (maFast1 >= maSlow1 && maFast0 < maSlow0);
   bool bearishTrend = (close < maFilter) && (adxMinus > adxPlus);
   
   if(bullishCross && bullishTrend) {
      signal.direction = SIGNAL_BUY;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_ASK);
      signal.stopLoss = signal.entryPrice - atr * m_atrSL;
      signal.takeProfit = signal.entryPrice + atr * m_atrTP;
      signal.confidence = MathMin(1.0, (adx - m_adxMin) / 30.0 + 0.5);
      signal.riskReward = (signal.takeProfit - signal.entryPrice) / 
                          (signal.entryPrice - signal.stopLoss);
      signal.comment = StringFormat("Trend BUY ADX=%.1f", adx);
   }
   else if(bearishCross && bearishTrend) {
      signal.direction = SIGNAL_SELL;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      signal.stopLoss = signal.entryPrice + atr * m_atrSL;
      signal.takeProfit = signal.entryPrice - atr * m_atrTP;
      signal.confidence = MathMin(1.0, (adx - m_adxMin) / 30.0 + 0.5);
      signal.riskReward = (signal.entryPrice - signal.takeProfit) / 
                          (signal.stopLoss - signal.entryPrice);
      signal.comment = StringFormat("Trend SELL ADX=%.1f", adx);
   }
   
   return signal;
}

//+------------------------------------------------------------------+
bool CSignalTrend::ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) {
   double maFast = data.GetMAFast(symIdx, 0);
   double maSlow = data.GetMASlow(symIdx, 0);
   if(maFast <= 0 || maSlow <= 0) return false;
   
   // Exit when MAs cross against position
   if(posDir == SIGNAL_BUY && maFast < maSlow) return true;
   if(posDir == SIGNAL_SELL && maFast > maSlow) return true;
   return false;
}

#endif // __PHOENIX_SIGNAL_TREND_MQH__
