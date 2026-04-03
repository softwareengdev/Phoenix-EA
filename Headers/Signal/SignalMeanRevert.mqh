//+------------------------------------------------------------------+
//|                                             SignalMeanRevert.mqh |
//|                                       Phoenix EA — Signal Layer  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SIGNAL_MEAN_REVERT_MQH__
#define __PHOENIX_SIGNAL_MEAN_REVERT_MQH__

#include "SignalBase.mqh"
#include "..\Core\Globals.mqh"

class CDataEngine;

//+------------------------------------------------------------------+
//| Mean Reversion Strategy                                           |
//| Entry: Price touches BB band + RSI extreme                       |
//| Target: BB middle line | SL: Beyond BB band + ATR buffer        |
//+------------------------------------------------------------------+
class CSignalMeanRevert : public CSignalBase {
private:
   double m_rsiOverbought;
   double m_rsiOversold;
   double m_atrSL;
   double m_atrTP;
   
public:
   CSignalMeanRevert() : m_rsiOverbought(70), m_rsiOversold(30), m_atrSL(0.8), m_atrTP(1.5) {}
   
   bool Init(ENUM_STRATEGY_TYPE type, string name) override {
      CSignalBase::Init(type, name);
      m_rsiOverbought = InpMR_RSIOverbought;
      m_rsiOversold = InpMR_RSIOversold;
      m_atrSL = InpMR_ATR_SL;
      m_atrTP = InpMR_ATR_TP;
      return true;
   }
   
   STradeSignal Evaluate(int symIdx, CDataEngine *data) override;
   
   double GetRegimeSuitability(ENUM_MARKET_REGIME regime) override {
      switch(regime) {
         case REGIME_RANGING_TIGHT:   return 1.0;
         case REGIME_RANGING_WIDE:    return 0.8;
         case REGIME_QUIET:           return 0.6;
         case REGIME_TRENDING_WEAK:   return 0.3;
         case REGIME_TRENDING_STRONG: return 0.1;
         case REGIME_VOLATILE:        return 0.2;
         default:                     return 0.3;
      }
   }
   
   bool ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) override;
};

//+------------------------------------------------------------------+
//| Mean Reversion strategy implementation                            |
//+------------------------------------------------------------------+
#include "..\Data\DataEngine.mqh"

STradeSignal CSignalMeanRevert::Evaluate(int symIdx, CDataEngine *data) {
   STradeSignal signal;
   ZeroMemory(signal);
   signal.direction = SIGNAL_NONE;
   signal.strategy = STRATEGY_MEAN_REVERT;
   signal.symbolIndex = symIdx;
   signal.symbol = g_Symbols[symIdx].name;
   signal.timestamp = TimeCurrent();
   
   double close = data.GetClose(symIdx, 0);
   double bbUpper = data.GetBBUpper(symIdx, 1);
   double bbMiddle = data.GetBBMiddle(symIdx, 1);
   double bbLower = data.GetBBLower(symIdx, 1);
   double rsi = data.GetRSI(symIdx, 1);
   double rsiPrev = data.GetRSI(symIdx, 2);
   double atr = data.GetATR(symIdx, 1);
   
   if(atr <= 0 || bbMiddle <= 0) return signal;
   
   signal.atrValue = atr;
   signal.regime = data.GetRegime(symIdx);
   
   // BUY: Price at/below lower BB + RSI oversold with reversal
   bool priceAtLower = (close <= bbLower + atr * 0.2);
   bool rsiOversold = (rsi < m_rsiOversold && rsi > rsiPrev); // RSI bouncing up
   
   // SELL: Price at/above upper BB + RSI overbought with reversal
   bool priceAtUpper = (close >= bbUpper - atr * 0.2);
   bool rsiOverbought = (rsi > m_rsiOverbought && rsi < rsiPrev); // RSI turning down
   
   if(priceAtLower && rsiOversold) {
      signal.direction = SIGNAL_BUY;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_ASK);
      signal.stopLoss = signal.entryPrice - atr * m_atrSL;
      signal.takeProfit = bbMiddle;
      double risk = signal.entryPrice - signal.stopLoss;
      double reward = signal.takeProfit - signal.entryPrice;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = MathMin(1.0, (m_rsiOversold - rsi) / 20.0 + 0.4);
      signal.comment = StringFormat("MR BUY RSI=%.1f BB_dist=%.5f", rsi, bbLower - close);
   }
   else if(priceAtUpper && rsiOverbought) {
      signal.direction = SIGNAL_SELL;
      signal.entryPrice = SymbolInfoDouble(signal.symbol, SYMBOL_BID);
      signal.stopLoss = signal.entryPrice + atr * m_atrSL;
      signal.takeProfit = bbMiddle;
      double risk = signal.stopLoss - signal.entryPrice;
      double reward = signal.entryPrice - signal.takeProfit;
      signal.riskReward = (risk > 0) ? reward / risk : 0;
      signal.confidence = MathMin(1.0, (rsi - m_rsiOverbought) / 20.0 + 0.4);
      signal.comment = StringFormat("MR SELL RSI=%.1f BB_dist=%.5f", rsi, close - bbUpper);
   }
   
   return signal;
}

//+------------------------------------------------------------------+
bool CSignalMeanRevert::ShouldExit(int symIdx, ENUM_SIGNAL_TYPE posDir, CDataEngine *data) {
   double close = data.GetClose(symIdx, 0);
   double bbMiddle = data.GetBBMiddle(symIdx, 0);
   // Exit when price reaches BB middle (mean)
   if(posDir == SIGNAL_BUY && close >= bbMiddle) return true;
   if(posDir == SIGNAL_SELL && close <= bbMiddle) return true;
   return false;
}

#endif // __PHOENIX_SIGNAL_MEAN_REVERT_MQH__
