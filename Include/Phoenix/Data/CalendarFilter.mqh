//+------------------------------------------------------------------+
//|                                            CalendarFilter.mqh    |
//|                          PHOENIX EA — Economic Calendar Filter    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_CALENDAR_FILTER_MQH__
#define __PHOENIX_CALENDAR_FILTER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Estructura de evento de calendario cacheado                       |
//+------------------------------------------------------------------+
struct SCalendarEvent
{
   datetime time;           // Hora del evento
   string   currency;       // Moneda afectada
   string   name;           // Nombre del evento
   int      importance;     // 0=baja, 1=media, 2=alta
   bool     passed;         // Ya pasó
};

//+------------------------------------------------------------------+
//| CCalendarFilter — Filtra operaciones antes de noticias            |
//|                                                                   |
//| Usa CalendarValueHistory() de MQL5 nativo                         |
//| Bloquea nuevas operaciones N minutos antes/después de noticias    |
//| de alto impacto para evitar slippage y spreads elevados           |
//+------------------------------------------------------------------+
class CCalendarFilter
{
private:
   SCalendarEvent    m_events[];         // Eventos cacheados
   int               m_eventCount;       // Número de eventos
   datetime          m_lastUpdate;       // Última actualización del cache
   int               m_preNewsMinutes;   // Minutos antes de noticia para bloquear
   int               m_postNewsMinutes;  // Minutos después de noticia para bloquear
   bool              m_initialized;
   bool              m_available;        // Si el calendario está disponible
   
   // Monedas que nos importan (basado en símbolos configurados)
   string            m_watchCurrencies[];
   int               m_watchCount;
   
   // Extraer monedas de los símbolos configurados
   void BuildWatchList()
   {
      m_watchCount = 0;
      ArrayResize(m_watchCurrencies, MAX_SYMBOLS * 2);
      
      for(int i = 0; i < g_activeSymbolCount; i++)
      {
         string sym = g_symbolConfigs[i].symbol;
         string baseCurrency = SymbolInfoString(sym, SYMBOL_CURRENCY_BASE);
         string quoteCurrency = SymbolInfoString(sym, SYMBOL_CURRENCY_PROFIT);
         
         // Añadir si no está ya en la lista
         if(baseCurrency != "" && !IsInWatchList(baseCurrency))
            m_watchCurrencies[m_watchCount++] = baseCurrency;
         if(quoteCurrency != "" && !IsInWatchList(quoteCurrency))
            m_watchCurrencies[m_watchCount++] = quoteCurrency;
      }
      
      ArrayResize(m_watchCurrencies, m_watchCount);
   }
   
   bool IsInWatchList(const string &currency)
   {
      for(int i = 0; i < m_watchCount; i++)
         if(m_watchCurrencies[i] == currency)
            return true;
      return false;
   }
   
   // Cargar eventos del calendario MQL5 nativo
   void LoadEvents()
   {
      datetime from = TimeCurrent() - 3600;         // 1 hora atrás
      datetime to   = TimeCurrent() + 86400;         // 24 horas adelante
      
      ArrayResize(m_events, 0);
      m_eventCount = 0;
      
      // Usar CalendarValueHistory para obtener eventos próximos
      MqlCalendarValue values[];
      int total = CalendarValueHistory(values, from, to);
      
      if(total <= 0)
      {
         // Calendario no disponible (común en backtesting)
         m_available = false;
         return;
      }
      
      m_available = true;
      
      for(int i = 0; i < total && m_eventCount < 100; i++)
      {
         MqlCalendarEvent event;
         MqlCalendarCountry country;
         
         if(!CalendarEventById(values[i].event_id, event))
            continue;
         if(!CalendarCountryById(event.country_id, country))
            continue;
         
         // Solo eventos de importacnia media-alta de monedas que nos importan
         if(event.importance < CALENDAR_IMPORTANCE_MODERATE)
            continue;
         if(!IsInWatchList(country.currency))
            continue;
         
         int idx = m_eventCount;
         ArrayResize(m_events, idx + 1);
         m_events[idx].time       = values[i].time;
         m_events[idx].currency   = country.currency;
         m_events[idx].name       = event.name;
         m_events[idx].importance = (event.importance == CALENDAR_IMPORTANCE_HIGH) ? 2 : 1;
         m_events[idx].passed     = (values[i].time < TimeCurrent());
         m_eventCount++;
      }
      
      m_lastUpdate = TimeCurrent();
   }
   
public:
   CCalendarFilter() : m_eventCount(0), m_lastUpdate(0),
                        m_preNewsMinutes(30), m_postNewsMinutes(15),
                        m_initialized(false), m_available(false), m_watchCount(0) {}
   
   bool Init(int preMinutes = 30, int postMinutes = 15)
   {
      m_preNewsMinutes  = preMinutes;
      m_postNewsMinutes = postMinutes;
      
      BuildWatchList();
      LoadEvents();
      
      m_initialized = true;
      g_logger.Info(StringFormat("CalendarFilter: Inicializado, vigilando %d monedas, %d eventos cargados",
                    m_watchCount, m_eventCount));
      return true;
   }
   
   void Update()
   {
      if(!m_initialized) return;
      
      // Refrescar cada 15 minutos
      if(TimeCurrent() - m_lastUpdate > 900)
         LoadEvents();
   }
   
   void Deinit()
   {
      ArrayFree(m_events);
      ArrayFree(m_watchCurrencies);
      m_initialized = false;
   }
   
   // ¿Hay una noticia de alto impacto próxima?
   bool IsHighImpactSoon(const string currency = "")
   {
      if(!m_initialized || !m_available)
         return false;
      
      datetime now = TimeCurrent();
      
      for(int i = 0; i < m_eventCount; i++)
      {
         if(m_events[i].importance < 2) // Solo alto impacto
            continue;
         
         // Filtrar por moneda si se especifica
         if(currency != "" && m_events[i].currency != currency)
            continue;
         
         datetime preWindow  = m_events[i].time - m_preNewsMinutes * 60;
         datetime postWindow = m_events[i].time + m_postNewsMinutes * 60;
         
         if(now >= preWindow && now <= postWindow)
            return true;
      }
      
      return false;
   }
   
   // Minutos hasta el próximo evento de alto impacto
   int MinutesToNextHighImpact(const string currency = "")
   {
      if(!m_initialized || !m_available)
         return 9999;
      
      datetime now = TimeCurrent();
      int minMinutes = 9999;
      
      for(int i = 0; i < m_eventCount; i++)
      {
         if(m_events[i].importance < 2) continue;
         if(m_events[i].time <= now)     continue;
         if(currency != "" && m_events[i].currency != currency) continue;
         
         int mins = (int)((m_events[i].time - now) / 60);
         if(mins < minMinutes)
            minMinutes = mins;
      }
      
      return minMinutes;
   }
   
   // ¿Es seguro operar una moneda específica?
   bool IsSafeToTrade(const string &symbol)
   {
      string baseCurrency  = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
      string quoteCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
      
      return !IsHighImpactSoon(baseCurrency) && !IsHighImpactSoon(quoteCurrency);
   }
   
   int GetEventCount()  const { return m_eventCount; }
   bool IsAvailable()   const { return m_available; }
};

#endif // __PHOENIX_CALENDAR_FILTER_MQH__
//+------------------------------------------------------------------+
