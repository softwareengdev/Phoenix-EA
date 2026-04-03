//+------------------------------------------------------------------+
//|                                              SessionDetector.mqh |
//|                                  Phoenix EA - Session Detection  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_SESSION_DETECTOR_MQH__
#define __PHOENIX_SESSION_DETECTOR_MQH__

#include "..\Core\Defines.mqh"

class CSessionDetector {
private:
   int m_londonStart, m_londonEnd;
   int m_newYorkStart, m_newYorkEnd;
   int m_tokyoStart, m_tokyoEnd;
   int m_sydneyStart, m_sydneyEnd;
   int m_gmtOffset;
   
public:
   CSessionDetector() : m_gmtOffset(0) {}
   
   void Init(int londonStart, int londonEnd, int nyStart, int nyEnd,
             int tokyoStart, int tokyoEnd) {
      m_londonStart = londonStart;
      m_londonEnd = londonEnd;
      m_newYorkStart = nyStart;
      m_newYorkEnd = nyEnd;
      m_tokyoStart = tokyoStart;
      m_tokyoEnd = tokyoEnd;
      m_sydneyStart = 22; // UTC
      m_sydneyEnd = 7;    // UTC
      
      // Calculate broker GMT offset
      datetime serverTime = TimeCurrent();
      datetime gmtTime = TimeGMT();
      m_gmtOffset = (int)((serverTime - gmtTime) / 3600);
   }
   
   ENUM_TRADING_SESSION GetCurrentSession() {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int hour = dt.hour;
      
      bool isLondon = (hour >= m_londonStart && hour < m_londonEnd);
      bool isNewYork = (hour >= m_newYorkStart && hour < m_newYorkEnd);
      bool isTokyo = IsInSession(hour, m_tokyoStart, m_tokyoEnd);
      bool isSydney = IsInSession(hour, m_sydneyStart, m_sydneyEnd);
      
      // Check overlaps first (highest priority)
      if(isLondon && isNewYork) return SESSION_LONDON_NY_OVERLAP;
      if(isTokyo && isLondon)   return SESSION_TOKYO_LONDON_OVERLAP;
      
      // Individual sessions
      if(isLondon)   return SESSION_LONDON;
      if(isNewYork)  return SESSION_NEWYORK;
      if(isTokyo)    return SESSION_TOKYO;
      if(isSydney)   return SESSION_SYDNEY;
      
      return SESSION_OFF_HOURS;
   }
   
   double GetSessionAggressiveness(ENUM_TRADING_SESSION session) {
      switch(session) {
         case SESSION_LONDON_NY_OVERLAP:    return 1.2;
         case SESSION_LONDON:              return 1.1;
         case SESSION_NEWYORK:             return 1.0;
         case SESSION_TOKYO_LONDON_OVERLAP: return 1.0;
         case SESSION_TOKYO:               return 0.8;
         case SESSION_SYDNEY:              return 0.6;
         case SESSION_OFF_HOURS:           return 0.3;
         default:                          return 0.5;
      }
   }
   
   string GetSessionName(ENUM_TRADING_SESSION session) {
      switch(session) {
         case SESSION_LONDON_NY_OVERLAP:    return "London-NY Overlap";
         case SESSION_LONDON:              return "London";
         case SESSION_NEWYORK:             return "New York";
         case SESSION_TOKYO_LONDON_OVERLAP: return "Tokyo-London Overlap";
         case SESSION_TOKYO:               return "Tokyo";
         case SESSION_SYDNEY:              return "Sydney";
         case SESSION_OFF_HOURS:           return "Off Hours";
         default:                          return "Unknown";
      }
   }
   
   bool IsHighLiquiditySession() {
      ENUM_TRADING_SESSION s = GetCurrentSession();
      return (s == SESSION_LONDON || s == SESSION_NEWYORK || s == SESSION_LONDON_NY_OVERLAP);
   }
   
   bool IsTradingAllowed(ENUM_STRATEGY_TYPE strategy) {
      ENUM_TRADING_SESSION session = GetCurrentSession();
      // Scalper only during high-liquidity sessions
      if(strategy == STRATEGY_SCALPER)
         return (session == SESSION_LONDON || session == SESSION_NEWYORK || session == SESSION_LONDON_NY_OVERLAP);
      // Other strategies: avoid off-hours completely
      return (session != SESSION_OFF_HOURS);
   }

private:
   bool IsInSession(int hour, int start, int end) {
      if(start < end)
         return (hour >= start && hour < end);
      else // wraps midnight
         return (hour >= start || hour < end);
   }
};

#endif // __PHOENIX_SESSION_DETECTOR_MQH__
