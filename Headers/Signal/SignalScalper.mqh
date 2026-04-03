//+------------------------------------------------------------------+
//|                                                SignalScalper.mqh |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_SCALPER_MQH__
#define __PHOENIX_SIGNAL_SCALPER_MQH__

#include "SignalBase.mqh"
#include "..\Core\Globals.mqh"

class CDataEngine;

//+------------------------------------------------------------------+
//| Scalper Strategy                                                   |
//| Entry: Fast EMA cross + RSI pullback + MACD confirmation         |
//| Works on M15, tight stops, session-filtered (London/NY only)     |
//+------------------------------------------------------------------+
class CSignalScalper : public CSignalBase {
private:
   double m_atrSL;
   double m_atrTP;
   
public:
   CSignalScalper() : m_atrSL(1.0), m_atrTP(1.5) {}
   
   bool Init(ENUM_STRATEGY_TYPE type, string name) override {
      CSignalBase::Init(type, name);
      m_atrSL = InpSC_ATR_SL;
      m_atrTP = InpSC_ATR_TP;
      return true;
   }
   
   STradeSignal Evaluate(int symIdx, CDataEngine *data) override;
   
   double GetRegimeSuitability(ENUM_MARKET_REGIME regime) override {
      switch(regime) {
         case REGIME_TRENDING_WEAK:   return 0.8;
         case REGIME_RANGING_WIDE:    return 0.7;
         case REGIME_TRENDING_STRONG: return 0.6;
         case REGIME_VOLATILE:        return 0.3;
         case REGIME_RANGING_TIGHT:   return 0.5;
         case REGIME_QUIET:           return 0.2;
         default:                     return 0.5;
      }
   }
   
   bool ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) override;
};

//+------------------------------------------------------------------+
//| Scalper strategy implementation                                    |
//+------------------------------------------------------------------+
#include "..\Data\DataEngine.mqh"

STradeSignal CSignalScalper::Evaluate(int symIdx, CDataEngine *data) {
   STradeSignal signal;
   ZeroMemory(signal);
   signal.direction = SIGNAL_NONE;
   signal.strategy = STRATEGY_SCALPER;
   signal.symbolIndex = symIdx;
   signal.symbol = g_Symbols[symIdx].name;
   signal.timestamp = TimeCurrent();
   
   // Scalper only during high-liquidity sessions
   CSessionDetector *session = data.GetSessionDetector();
   if(session != NULL && !session.IsTradingAllowed(STRATEGY_SCALPER)) return signal;
   
   double close = data.GetClose(symIdx, 0);
   double maFast = data.GetMAFast(symIdx, 0);
   double maSlow = data.GetMASlow(symIdx, 0);
   double rsi = data.GetRSI(symIdx, 1);
   double macdMain = data.GetMACDMain(symIdx, 1);
   double macdSignal = data.GetMACDSignal(symIdx, 1);
   double macdMainPrev = data.GetMACDMain(symIdx, 2);
   double macdSignalPrev = data.GetMACDSignal(symIdx, 2);
   double atr = data.GetATR(symIdx, 1);
   
   if(atr <= 0) return signal;
   
   signal.atrValue = atr;
   signal.regime = data.GetRegime(symIdx);
   signal.session = session.GetCurrentSession();
   
   // BUY: Fast > Slow + RSI pullback from 50 + MACD cross up
   bool fastAboveSlow = (maFast > maSlow);
   bool rsiPullback = (rsi > 40 && rsi < 60);
   bool macdCrossUp = (macdMainPrev <= macdSignalPrev && macdMain > macdSignal);
   
   // SELL: Fast < Slow + RSI pullback from 50 + MACD cross down
   bool fastBelowSlow = (maFast < maSlow);
   bool macdCrossDown = (macdMainPrev >= macdSignalPrev && macdMain < macdSignal);
   
   if(fastAboveSlow && rsiPullback && macdCrossUp) {
      signal.direction = SIGNAL_BUY;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_ASK);
      signal.stopLoss = signal.entryPrice - atr * m_atrSL;
      signal.takeProfit = signal.entryPrice + atr * m_atrTP;
      double risk = signal.entryPrice - signal.stopLoss;
      double reward = signal.takeProfit - signal.entryPrice;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = 0.55;
      signal.comment = StringFormat("SC BUY RSI=%.1f MACD=%.5f", rsi, macdMain);
   }
   else if(fastBelowSlow && rsiPullback && macdCrossDown) {
      signal.direction = SIGNAL_SELL;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      signal.stopLoss = signal.entryPrice + atr * m_atrSL;
      signal.takeProfit = signal.entryPrice - atr * m_atrTP;
      double risk = signal.stopLoss - signal.entryPrice;
      double reward = signal.entryPrice - signal.takeProfit;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = 0.55;
      signal.comment = StringFormat("SC SELL RSI=%.1f MACD=%.5f", rsi, macdMain);
   }
   
   return signal;
}

//+------------------------------------------------------------------+
bool CSignalScalper::ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) {
   double rsi = data.GetRSI(symIdx, 0);
   // Quick exit on RSI extremes
   if(posDir == SIGNAL_BUY && rsi > 75) return true;
   if(posDir == SIGNAL_SELL && rsi < 25) return true;
   return false;
}

#endif // __PHOENIX_SIGNAL_SCALPER_MQH__
