//+------------------------------------------------------------------+
//|                                              CalendarFilter.mqh  |
//|                                  Phoenix EA - Calendar Filter    |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_CALENDAR_FILTER_MQH__
#define __PHOENIX_CALENDAR_FILTER_MQH__

#include "..\Core\Defines.mqh"

class CCalendarFilter {
private:
   bool     m_enabled;
   int      m_preNewsPause;   // minutes
   int      m_postNewsWait;   // minutes
   datetime m_nextHighImpact;
   datetime m_lastCheck;
   string   m_nextEventName;
   string   m_nextEventCurrency;
   bool     m_isBlocked;
   
   struct SNewsEvent {
      datetime time;
      string   name;
      string   currency;
      int      importance;  // CALENDAR_IMPORTANCE_HIGH = 3
   };
   SNewsEvent m_upcomingEvents[];
   int        m_eventCount;

public:
   CCalendarFilter() : m_enabled(false), m_preNewsPause(30), m_postNewsWait(15),
                        m_nextHighImpact(0), m_lastCheck(0), m_isBlocked(false), m_eventCount(0) {}
   
   void Init(bool enabled, int preNewsPause, int postNewsWait) {
      m_enabled = enabled;
      m_preNewsPause = preNewsPause;
      m_postNewsWait = postNewsWait;
      if(m_enabled) Update();
   }
   
   void Update() {
      if(!m_enabled) return;
      datetime now = TimeCurrent();
      // Only refresh every 5 minutes
      if(now - m_lastCheck < 300) return;
      m_lastCheck = now;
      
      m_eventCount = 0;
      ArrayResize(m_upcomingEvents, 0);
      
      // Look ahead 24 hours
      datetime from = now - m_postNewsWait * 60;
      datetime to = now + 86400;
      
      MqlCalendarValue values[];
      int total = CalendarValueHistory(values, from, to);
      
      if(total <= 0) return;
      
      for(int i = 0; i < total; i++) {
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event)) continue;
         
         // Only high-impact events
         if(event.importance != CALENDAR_IMPORTANCE_HIGH) continue;
         
         MqlCalendarCountry country;
         if(!CalendarCountryById(event.country_id, country)) continue;
         
         ArrayResize(m_upcomingEvents, m_eventCount + 1);
         m_upcomingEvents[m_eventCount].time = values[i].time;
         m_upcomingEvents[m_eventCount].name = event.name;
         m_upcomingEvents[m_eventCount].currency = country.currency;
         m_upcomingEvents[m_eventCount].importance = (int)event.importance;
         m_eventCount++;
      }
      
      // Find next high-impact event
      m_nextHighImpact = 0;
      m_nextEventName = "";
      m_nextEventCurrency = "";
      for(int i = 0; i < m_eventCount; i++) {
         if(m_upcomingEvents[i].time > now) {
            if(m_nextHighImpact == 0 || m_upcomingEvents[i].time < m_nextHighImpact) {
               m_nextHighImpact = m_upcomingEvents[i].time;
               m_nextEventName = m_upcomingEvents[i].name;
               m_nextEventCurrency = m_upcomingEvents[i].currency;
            }
         }
      }
   }
   
   bool IsTradingBlocked(string symbol = "") {
      if(!m_enabled) return false;
      datetime now = TimeCurrent();
      
      for(int i = 0; i < m_eventCount; i++) {
         datetime eventTime = m_upcomingEvents[i].time;
         datetime blockStart = eventTime - m_preNewsPause * 60;
         datetime blockEnd = eventTime + m_postNewsWait * 60;
         
         if(now >= blockStart && now <= blockEnd) {
            // If symbol specified, check if event currency matches
            if(StringLen(symbol) > 0) {
               string currency = m_upcomingEvents[i].currency;
               if(StringFind(symbol, currency) >= 0 ||
                  StringFind(symbol, StringSubstr(currency, 0, 3)) >= 0) {
                  m_isBlocked = true;
                  return true;
               }
            } else {
               m_isBlocked = true;
               return true;
            }
         }
      }
      m_isBlocked = false;
      return false;
   }
   
   datetime GetNextHighImpactTime() { return m_nextHighImpact; }
   string   GetNextEventName()      { return m_nextEventName; }
   string   GetNextEventCurrency()  { return m_nextEventCurrency; }
   bool     IsBlocked()             { return m_isBlocked; }
   int      GetUpcomingCount()      { return m_eventCount; }
   
   int MinutesToNextEvent() {
      if(m_nextHighImpact == 0) return 9999;
      return (int)((m_nextHighImpact - TimeCurrent()) / 60);
   }
};

#endif // __PHOENIX_CALENDAR_FILTER_MQH__
