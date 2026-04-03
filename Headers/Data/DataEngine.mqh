//+------------------------------------------------------------------+
//|                                                  DataEngine.mqh  |
//|                           Phoenix EA - Multi-Symbol Data Engine  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_DATA_ENGINE_MQH__
#define __PHOENIX_DATA_ENGINE_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "SymbolInfo.mqh"
#include "SessionDetector.mqh"
#include "CalendarFilter.mqh"

class CDataEngine {
private:
   CSymbolData       m_symbolData[];
   CSessionDetector  m_sessionDetector;
   CCalendarFilter   m_calendarFilter;
   int               m_symbolCount;
   ENUM_TIMEFRAMES   m_primaryTF;
   ENUM_TIMEFRAMES   m_entryTF;
   ENUM_TIMEFRAMES   m_filterTF;
   bool              m_initialized;
   
   // Indicator buffers (cached per-symbol)
   double m_maFast[][2];
   double m_maSlow[][2];
   double m_maFilter[][2];
   double m_rsi[][3];
   double m_atr[][3];
   double m_adx[][3];
   double m_adxPlus[][3];
   double m_adxMinus[][3];
   double m_bbUpper[][3];
   double m_bbMiddle[][3];
   double m_bbLower[][3];
   double m_macdMain[][3];
   double m_macdSignal[][3];
   double m_stochK[][3];
   double m_stochD[][3];
   double m_cci[][3];
   double m_donchianHigh[][3];
   double m_donchianLow[][3];
   
   ENUM_MARKET_REGIME m_regimes[];

public:
   CDataEngine() : m_symbolCount(0), m_primaryTF(PERIOD_H1), m_entryTF(PERIOD_M15),
                    m_filterTF(PERIOD_H4), m_initialized(false) {}
   
   ~CDataEngine() { Shutdown(); }
   
   bool Init(ENUM_TIMEFRAMES primaryTF, ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES filterTF) {
      m_primaryTF = primaryTF;
      m_entryTF = entryTF;
      m_filterTF = filterTF;
      m_symbolCount = g_SymbolCount;
      
      if(m_symbolCount <= 0) {
         if(g_Logger != NULL) g_Logger.Error("DataEngine: No symbols configured");
         return false;
      }
      
      // Initialize symbol data objects
      ArrayResize(m_symbolData, m_symbolCount);
      ArrayResize(m_regimes, m_symbolCount);
      
      // Initialize indicator buffer arrays
      ArrayResize(m_maFast, m_symbolCount);
      ArrayResize(m_maSlow, m_symbolCount);
      ArrayResize(m_maFilter, m_symbolCount);
      ArrayResize(m_rsi, m_symbolCount);
      ArrayResize(m_atr, m_symbolCount);
      ArrayResize(m_adx, m_symbolCount);
      ArrayResize(m_adxPlus, m_symbolCount);
      ArrayResize(m_adxMinus, m_symbolCount);
      ArrayResize(m_bbUpper, m_symbolCount);
      ArrayResize(m_bbMiddle, m_symbolCount);
      ArrayResize(m_bbLower, m_symbolCount);
      ArrayResize(m_macdMain, m_symbolCount);
      ArrayResize(m_macdSignal, m_symbolCount);
      ArrayResize(m_stochK, m_symbolCount);
      ArrayResize(m_stochD, m_symbolCount);
      ArrayResize(m_cci, m_symbolCount);
      ArrayResize(m_donchianHigh, m_symbolCount);
      ArrayResize(m_donchianLow, m_symbolCount);
      
      for(int i = 0; i < m_symbolCount; i++) {
         m_symbolData[i].Init(g_Symbols[i].name);
         m_regimes[i] = REGIME_UNKNOWN;
         
         // Create indicator handles for this symbol on primary TF
         string sym = g_Symbols[i].name;
         
         g_Symbols[i].handleMA_Fast = iMA(sym, m_primaryTF, InpTrend_FastMA, 0, MODE_EMA, PRICE_CLOSE);
         g_Symbols[i].handleMA_Slow = iMA(sym, m_primaryTF, InpTrend_SlowMA, 0, MODE_EMA, PRICE_CLOSE);
         g_Symbols[i].handleMA_Filter = iMA(sym, m_filterTF, InpTrend_FilterMA, 0, MODE_SMA, PRICE_CLOSE);
         g_Symbols[i].handleRSI = iRSI(sym, m_primaryTF, InpMR_RSIPeriod, PRICE_CLOSE);
         g_Symbols[i].handleATR = iATR(sym, m_primaryTF, 14);
         g_Symbols[i].handleADX = iADX(sym, m_primaryTF, InpTrend_ADXPeriod);
         g_Symbols[i].handleBands = iBands(sym, m_primaryTF, InpMR_BBPeriod, 0, InpMR_BBDeviation, PRICE_CLOSE);
         g_Symbols[i].handleMACD = iMACD(sym, m_entryTF, InpSC_MACDFast, InpSC_MACDSlow, InpSC_MACDSignal, PRICE_CLOSE);
         g_Symbols[i].handleStoch = iStochastic(sym, m_primaryTF, InpMOM_StochK, InpMOM_StochD, InpMOM_StochSlowing, MODE_SMA, STO_LOWHIGH);
         g_Symbols[i].handleCCI = iCCI(sym, m_primaryTF, InpMOM_CCIPeriod, PRICE_TYPICAL);
         
         // Donchian channels via custom iCustom or manual via iHighest/iLowest
         // We'll use iMA on high/low as proxy; actual Donchian computed in CopyBuffer
         g_Symbols[i].handleDonchian_High = iMA(sym, m_primaryTF, 1, 0, MODE_SMA, PRICE_HIGH);
         g_Symbols[i].handleDonchian_Low = iMA(sym, m_primaryTF, 1, 0, MODE_SMA, PRICE_LOW);
         
         // Validate all handles
         if(g_Symbols[i].handleMA_Fast == INVALID_HANDLE || g_Symbols[i].handleATR == INVALID_HANDLE) {
            if(g_Logger != NULL) 
               g_Logger.Error(StringFormat("DataEngine: Failed to create indicators for %s", sym));
            g_Symbols[i].enabled = false;
         }
      }
      
      // Initialize session detector
      m_sessionDetector.Init(InpLondonStart, InpLondonEnd, InpNewYorkStart, InpNewYorkEnd,
                             InpTokyoStart, InpTokyoEnd);
      
      // Initialize calendar filter
      m_calendarFilter.Init(InpCalendarFilter, InpPreNewsPause, InpPostNewsWait);
      
      m_initialized = true;
      if(g_Logger != NULL) g_Logger.Info(StringFormat("DataEngine: Initialized with %d symbols", m_symbolCount));
      return true;
   }
   
   void Shutdown() {
      for(int i = 0; i < g_SymbolCount; i++) {
         if(g_Symbols[i].handleMA_Fast != INVALID_HANDLE)  IndicatorRelease(g_Symbols[i].handleMA_Fast);
         if(g_Symbols[i].handleMA_Slow != INVALID_HANDLE)  IndicatorRelease(g_Symbols[i].handleMA_Slow);
         if(g_Symbols[i].handleMA_Filter != INVALID_HANDLE) IndicatorRelease(g_Symbols[i].handleMA_Filter);
         if(g_Symbols[i].handleRSI != INVALID_HANDLE)      IndicatorRelease(g_Symbols[i].handleRSI);
         if(g_Symbols[i].handleATR != INVALID_HANDLE)      IndicatorRelease(g_Symbols[i].handleATR);
         if(g_Symbols[i].handleADX != INVALID_HANDLE)      IndicatorRelease(g_Symbols[i].handleADX);
         if(g_Symbols[i].handleBands != INVALID_HANDLE)    IndicatorRelease(g_Symbols[i].handleBands);
         if(g_Symbols[i].handleMACD != INVALID_HANDLE)     IndicatorRelease(g_Symbols[i].handleMACD);
         if(g_Symbols[i].handleStoch != INVALID_HANDLE)    IndicatorRelease(g_Symbols[i].handleStoch);
         if(g_Symbols[i].handleCCI != INVALID_HANDLE)      IndicatorRelease(g_Symbols[i].handleCCI);
         if(g_Symbols[i].handleDonchian_High != INVALID_HANDLE) IndicatorRelease(g_Symbols[i].handleDonchian_High);
         if(g_Symbols[i].handleDonchian_Low != INVALID_HANDLE)  IndicatorRelease(g_Symbols[i].handleDonchian_Low);
      }
      m_initialized = false;
   }
   
   // Update all data for all symbols
   bool Update() {
      if(!m_initialized) return false;
      
      for(int i = 0; i < m_symbolCount; i++) {
         if(!g_Symbols[i].enabled) continue;
         m_symbolData[i].Refresh();
         UpdateIndicators(i);
         UpdateRegime(i);
      }
      
      m_calendarFilter.Update();
      return true;
   }
   
   // Getters for indicator values (index 0 = current bar, 1 = previous bar)
   double GetMAFast(int symIdx, int shift = 0)     { return (symIdx < m_symbolCount) ? m_maFast[symIdx][shift] : 0; }
   double GetMASlow(int symIdx, int shift = 0)     { return (symIdx < m_symbolCount) ? m_maSlow[symIdx][shift] : 0; }
   double GetMAFilter(int symIdx, int shift = 0)   { return (symIdx < m_symbolCount) ? m_maFilter[symIdx][shift] : 0; }
   double GetRSI(int symIdx, int shift = 0)        { return (symIdx < m_symbolCount) ? m_rsi[symIdx][shift] : 50; }
   double GetATR(int symIdx, int shift = 0)        { return (symIdx < m_symbolCount) ? m_atr[symIdx][shift] : 0; }
   double GetADX(int symIdx, int shift = 0)        { return (symIdx < m_symbolCount) ? m_adx[symIdx][shift] : 0; }
   double GetADXPlus(int symIdx, int shift = 0)    { return (symIdx < m_symbolCount) ? m_adxPlus[symIdx][shift] : 0; }
   double GetADXMinus(int symIdx, int shift = 0)   { return (symIdx < m_symbolCount) ? m_adxMinus[symIdx][shift] : 0; }
   double GetBBUpper(int symIdx, int shift = 0)    { return (symIdx < m_symbolCount) ? m_bbUpper[symIdx][shift] : 0; }
   double GetBBMiddle(int symIdx, int shift = 0)   { return (symIdx < m_symbolCount) ? m_bbMiddle[symIdx][shift] : 0; }
   double GetBBLower(int symIdx, int shift = 0)    { return (symIdx < m_symbolCount) ? m_bbLower[symIdx][shift] : 0; }
   double GetMACDMain(int symIdx, int shift = 0)   { return (symIdx < m_symbolCount) ? m_macdMain[symIdx][shift] : 0; }
   double GetMACDSignal(int symIdx, int shift = 0) { return (symIdx < m_symbolCount) ? m_macdSignal[symIdx][shift] : 0; }
   double GetStochK(int symIdx, int shift = 0)     { return (symIdx < m_symbolCount) ? m_stochK[symIdx][shift] : 50; }
   double GetStochD(int symIdx, int shift = 0)     { return (symIdx < m_symbolCount) ? m_stochD[symIdx][shift] : 50; }
   double GetCCI(int symIdx, int shift = 0)        { return (symIdx < m_symbolCount) ? m_cci[symIdx][shift] : 0; }
   
   double GetDonchianHigh(int symIdx, int period) {
      if(symIdx >= m_symbolCount) return 0;
      double high[];
      ArraySetAsSeries(high, true);
      if(CopyHigh(g_Symbols[symIdx].name, m_primaryTF, 1, period, high) < period) return 0;
      int maxIdx = ArrayMaximum(high);
      return (maxIdx >= 0) ? high[maxIdx] : 0;
   }
   
   double GetDonchianLow(int symIdx, int period) {
      if(symIdx >= m_symbolCount) return 0;
      double low[];
      ArraySetAsSeries(low, true);
      if(CopyLow(g_Symbols[symIdx].name, m_primaryTF, 1, period, low) < period) return 0;
      int minIdx = ArrayMinimum(low);
      return (minIdx >= 0) ? low[minIdx] : 0;
   }
   
   double GetVolumeSMA(int symIdx, int period) {
      if(symIdx >= m_symbolCount) return 0;
      long vol[];
      ArraySetAsSeries(vol, true);
      if(CopyTickVolume(g_Symbols[symIdx].name, m_primaryTF, 0, period, vol) < period) return 0;
      double sum = 0;
      for(int i = 0; i < period; i++) sum += (double)vol[i];
      return sum / period;
   }
   
   double GetCurrentVolume(int symIdx) {
      if(symIdx >= m_symbolCount) return 0;
      long vol[];
      ArraySetAsSeries(vol, true);
      if(CopyTickVolume(g_Symbols[symIdx].name, m_primaryTF, 0, 1, vol) < 1) return 0;
      return (double)vol[0];
   }
   
   // Get current close price
   double GetClose(int symIdx, int shift = 0) {
      if(symIdx >= m_symbolCount) return 0;
      double close[];
      ArraySetAsSeries(close, true);
      if(CopyClose(g_Symbols[symIdx].name, m_primaryTF, shift, 1, close) < 1) return 0;
      return close[0];
   }
   
   // Market regime detection
   ENUM_MARKET_REGIME GetRegime(int symIdx) {
      if(symIdx >= m_symbolCount) return REGIME_UNKNOWN;
      return m_regimes[symIdx];
   }
   
   // Session & Calendar access
   CSessionDetector*  GetSessionDetector()  { return GetPointer(m_sessionDetector); }
   CCalendarFilter*   GetCalendarFilter()   { return GetPointer(m_calendarFilter); }
   CSymbolData*       GetSymbolData(int idx) { return (idx < m_symbolCount) ? GetPointer(m_symbolData[idx]) : NULL; }
   int                GetSymbolCount()       { return m_symbolCount; }
   
   double GetBBWidth(int symIdx) {
      double upper = GetBBUpper(symIdx, 1);
      double lower = GetBBLower(symIdx, 1);
      double middle = GetBBMiddle(symIdx, 1);
      if(middle <= 0) return 0;
      return (upper - lower) / middle;
   }

private:
   void UpdateIndicators(int idx) {
      string sym = g_Symbols[idx].name;
      double buf[];
      ArraySetAsSeries(buf, true);
      
      // MA Fast
      if(CopyBuffer(g_Symbols[idx].handleMA_Fast, 0, 0, 2, buf) >= 2)
         { m_maFast[idx][0] = buf[0]; m_maFast[idx][1] = buf[1]; }
      
      // MA Slow
      if(CopyBuffer(g_Symbols[idx].handleMA_Slow, 0, 0, 2, buf) >= 2)
         { m_maSlow[idx][0] = buf[0]; m_maSlow[idx][1] = buf[1]; }
      
      // MA Filter
      if(CopyBuffer(g_Symbols[idx].handleMA_Filter, 0, 0, 2, buf) >= 2)
         { m_maFilter[idx][0] = buf[0]; m_maFilter[idx][1] = buf[1]; }
      
      // RSI
      if(CopyBuffer(g_Symbols[idx].handleRSI, 0, 0, 3, buf) >= 3)
         { m_rsi[idx][0] = buf[0]; m_rsi[idx][1] = buf[1]; m_rsi[idx][2] = buf[2]; }
      
      // ATR
      if(CopyBuffer(g_Symbols[idx].handleATR, 0, 0, 3, buf) >= 3)
         { m_atr[idx][0] = buf[0]; m_atr[idx][1] = buf[1]; m_atr[idx][2] = buf[2]; }
      
      // ADX (3 buffers: main=0, +DI=1, -DI=2)
      if(CopyBuffer(g_Symbols[idx].handleADX, 0, 0, 3, buf) >= 3)
         { m_adx[idx][0] = buf[0]; m_adx[idx][1] = buf[1]; m_adx[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleADX, 1, 0, 3, buf) >= 3)
         { m_adxPlus[idx][0] = buf[0]; m_adxPlus[idx][1] = buf[1]; m_adxPlus[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleADX, 2, 0, 3, buf) >= 3)
         { m_adxMinus[idx][0] = buf[0]; m_adxMinus[idx][1] = buf[1]; m_adxMinus[idx][2] = buf[2]; }
      
      // Bollinger Bands (0=base, 1=upper, 2=lower)
      if(CopyBuffer(g_Symbols[idx].handleBands, 0, 0, 3, buf) >= 3)
         { m_bbMiddle[idx][0] = buf[0]; m_bbMiddle[idx][1] = buf[1]; m_bbMiddle[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleBands, 1, 0, 3, buf) >= 3)
         { m_bbUpper[idx][0] = buf[0]; m_bbUpper[idx][1] = buf[1]; m_bbUpper[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleBands, 2, 0, 3, buf) >= 3)
         { m_bbLower[idx][0] = buf[0]; m_bbLower[idx][1] = buf[1]; m_bbLower[idx][2] = buf[2]; }
      
      // MACD (0=main, 1=signal)
      if(CopyBuffer(g_Symbols[idx].handleMACD, 0, 0, 3, buf) >= 3)
         { m_macdMain[idx][0] = buf[0]; m_macdMain[idx][1] = buf[1]; m_macdMain[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleMACD, 1, 0, 3, buf) >= 3)
         { m_macdSignal[idx][0] = buf[0]; m_macdSignal[idx][1] = buf[1]; m_macdSignal[idx][2] = buf[2]; }
      
      // Stochastic (0=%K, 1=%D)
      if(CopyBuffer(g_Symbols[idx].handleStoch, 0, 0, 3, buf) >= 3)
         { m_stochK[idx][0] = buf[0]; m_stochK[idx][1] = buf[1]; m_stochK[idx][2] = buf[2]; }
      if(CopyBuffer(g_Symbols[idx].handleStoch, 1, 0, 3, buf) >= 3)
         { m_stochD[idx][0] = buf[0]; m_stochD[idx][1] = buf[1]; m_stochD[idx][2] = buf[2]; }
      
      // CCI
      if(CopyBuffer(g_Symbols[idx].handleCCI, 0, 0, 3, buf) >= 3)
         { m_cci[idx][0] = buf[0]; m_cci[idx][1] = buf[1]; m_cci[idx][2] = buf[2]; }
   }
   
   void UpdateRegime(int idx) {
      double adx = m_adx[idx][1];
      double atr = m_atr[idx][1];
      double bbWidth = GetBBWidth(idx);
      
      // ATR percentile (compare to recent average)
      double atrAvg = (m_atr[idx][0] + m_atr[idx][1] + m_atr[idx][2]) / 3.0;
      double atrRatio = (atrAvg > 0) ? atr / atrAvg : 1.0;
      
      if(adx > 30 && atrRatio > 1.2) {
         m_regimes[idx] = REGIME_TRENDING_STRONG;
      } else if(adx > 20) {
         m_regimes[idx] = REGIME_TRENDING_WEAK;
      } else if(adx < 15 && bbWidth < 0.02) {
         m_regimes[idx] = REGIME_RANGING_TIGHT;
      } else if(adx < 20 && bbWidth < 0.04) {
         m_regimes[idx] = REGIME_RANGING_WIDE;
      } else if(atrRatio > 1.5) {
         m_regimes[idx] = REGIME_VOLATILE;
      } else if(atrRatio < 0.7) {
         m_regimes[idx] = REGIME_QUIET;
      } else {
         m_regimes[idx] = REGIME_UNKNOWN;
      }
   }
};

#endif // __PHOENIX_DATA_ENGINE_MQH__
