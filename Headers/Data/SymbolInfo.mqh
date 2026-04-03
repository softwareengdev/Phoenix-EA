//+------------------------------------------------------------------+
//|                                                   SymbolInfo.mqh |
//|                                       Phoenix EA - Symbol Cache  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SYMBOLINFO_MQH__
#define __PHOENIX_SYMBOLINFO_MQH__

#include "..\Core\Defines.mqh"

class CSymbolData {
private:
   string m_symbol;
   double m_point;
   int    m_digits;
   double m_tickSize;
   double m_tickValue;
   double m_minLot;
   double m_maxLot;
   double m_lotStep;
   double m_contractSize;
   double m_spreadAvg;
   int    m_spreadSamples;
   double m_spreadSum;
   double m_marginRequired;
   bool   m_isValid;
   
public:
   CSymbolData() : m_isValid(false), m_spreadSamples(0), m_spreadSum(0.0) {}
   
   bool Init(string symbol) {
      m_symbol = symbol;
      if(!SymbolSelect(symbol, true)) return false;
      Refresh();
      m_isValid = (m_point > 0);
      return m_isValid;
   }
   
   void Refresh() {
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      
      // Update running spread average
      double spread = SymbolInfoDouble(m_symbol, SYMBOL_ASK) - SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_spreadSum += spread;
      m_spreadSamples++;
      m_spreadAvg = m_spreadSum / m_spreadSamples;
      
      // Limit samples to avoid overflow
      if(m_spreadSamples > 10000) {
         m_spreadSum = m_spreadAvg * 5000;
         m_spreadSamples = 5000;
      }
   }
   
   double NormalizeLots(double lots) {
      if(m_lotStep <= 0) return m_minLot;
      lots = MathMax(lots, m_minLot);
      lots = MathMin(lots, m_maxLot);
      lots = MathFloor(lots / m_lotStep) * m_lotStep;
      return NormalizeDouble(lots, 2);
   }
   
   double NormalizePrice(double price) {
      if(m_tickSize <= 0) return NormalizeDouble(price, m_digits);
      return NormalizeDouble(MathRound(price / m_tickSize) * m_tickSize, m_digits);
   }
   
   double GetAsk()           { return SymbolInfoDouble(m_symbol, SYMBOL_ASK); }
   double GetBid()           { return SymbolInfoDouble(m_symbol, SYMBOL_BID); }
   double GetSpread()        { return GetAsk() - GetBid(); }
   double GetSpreadPoints()  { return GetSpread() / m_point; }
   double GetAvgSpread()     { return m_spreadAvg; }
   bool   IsSpreadOK(double maxMultiplier) {
      if(m_spreadAvg <= 0) return true;
      return GetSpread() <= m_spreadAvg * maxMultiplier;
   }
   
   string Symbol()           { return m_symbol; }
   double Point()            { return m_point; }
   int    Digits()           { return m_digits; }
   double TickSize()         { return m_tickSize; }
   double TickValue()        { return m_tickValue; }
   double MinLot()           { return m_minLot; }
   double MaxLot()           { return m_maxLot; }
   double LotStep()          { return m_lotStep; }
   double ContractSize()     { return m_contractSize; }
   bool   IsValid()          { return m_isValid; }
   
   // Calculate margin for given lots
   double CalculateMargin(double lots, ENUM_ORDER_TYPE orderType = ORDER_TYPE_BUY) {
      double margin = 0;
      if(!OrderCalcMargin(orderType, m_symbol, lots, GetAsk(), margin))
         margin = lots * m_contractSize * GetAsk() / 100.0; // Fallback estimate
      return margin;
   }
   
   // Calculate profit for given lots and price movement
   double CalculateProfit(ENUM_ORDER_TYPE orderType, double lots, double openPrice, double closePrice) {
      double profit = 0;
      if(!OrderCalcProfit(orderType, m_symbol, lots, openPrice, closePrice, profit)) {
         // Fallback
         double diff = (orderType == ORDER_TYPE_BUY) ? closePrice - openPrice : openPrice - closePrice;
         profit = diff / m_tickSize * m_tickValue * lots;
      }
      return profit;
   }
};

#endif // __PHOENIX_SYMBOLINFO_MQH__
