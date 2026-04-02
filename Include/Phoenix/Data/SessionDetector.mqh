//+------------------------------------------------------------------+
//|                                            SessionDetector.mqh   |
//|                          PHOENIX EA — Trading Session Detector    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SESSION_DETECTOR_MQH__
#define __PHOENIX_SESSION_DETECTOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CSessionDetector — Detecta la sesión de trading actual            |
//|                                                                   |
//| Sesiones (hora servidor UTC por defecto, ajustable):              |
//| Sydney:   22:00 - 07:00 UTC                                      |
//| Tokyo:    00:00 - 09:00 UTC                                      |
//| London:   07:00 - 16:00 UTC                                      |
//| New York: 12:00 - 21:00 UTC                                      |
//| Overlap Tokyo-London: 07:00 - 09:00                              |
//| Overlap London-NY:    12:00 - 16:00 (mejor liquidez)             |
//+------------------------------------------------------------------+
class CSessionDetector
{
private:
   ENUM_TRADING_SESSION  m_currentSession;     // Sesión actual
   int                   m_gmtOffset;          // Offset del servidor vs UTC (horas)
   bool                  m_initialized;
   
   // Horarios de sesiones en horas UTC
   int m_sydneyOpen, m_sydneyClose;
   int m_tokyoOpen,  m_tokyoClose;
   int m_londonOpen, m_londonClose;
   int m_nyOpen,     m_nyClose;
   
public:
   CSessionDetector() : m_currentSession(SESSION_NONE), m_gmtOffset(0), m_initialized(false)
   {
      // Horarios estándar UTC
      m_sydneyOpen  = 22; m_sydneyClose = 7;
      m_tokyoOpen   = 0;  m_tokyoClose  = 9;
      m_londonOpen  = 7;  m_londonClose = 16;
      m_nyOpen      = 12; m_nyClose     = 21;
   }
   
   bool Init(int gmtOffsetHours = 0)
   {
      m_gmtOffset = gmtOffsetHours;
      m_initialized = true;
      Update();
      g_logger.Info(StringFormat("SessionDetector: Inicializado (GMT offset=%+d)", m_gmtOffset));
      return true;
   }
   
   // Actualizar sesión actual
   void Update()
   {
      if(!m_initialized) return;
      
      MqlDateTime dt;
      TimeCurrent(dt);
      int hour = (dt.hour - m_gmtOffset + 24) % 24; // Convertir a UTC
      
      ENUM_TRADING_SESSION newSession = SESSION_NONE;
      
      // Overlap London-NY (prioridad más alta — mejor liquidez)
      if(hour >= m_nyOpen && hour < m_londonClose)
         newSession = SESSION_OVERLAP_LN;
      // Overlap Tokyo-London
      else if(hour >= m_londonOpen && hour < m_tokyoClose)
         newSession = SESSION_OVERLAP_TL;
      // London
      else if(hour >= m_londonOpen && hour < m_londonClose)
         newSession = SESSION_LONDON;
      // New York
      else if(hour >= m_nyOpen && hour < m_nyClose)
         newSession = SESSION_NEWYORK;
      // Tokyo
      else if(hour >= m_tokyoOpen && hour < m_tokyoClose)
         newSession = SESSION_TOKYO;
      // Sydney (wraps midnight)
      else if(hour >= m_sydneyOpen || hour < m_sydneyClose)
         newSession = SESSION_SYDNEY;
      
      if(newSession != m_currentSession)
      {
         g_logger.Debug(StringFormat("SessionDetector: %s → %s",
                        EnumToString(m_currentSession),
                        EnumToString(newSession)));
         m_currentSession = newSession;
      }
   }
   
   // Getters
   ENUM_TRADING_SESSION GetCurrentSession() const { return m_currentSession; }
   
   // ¿Estamos en overlap? (mejor para scalping)
   bool IsOverlap() const
   {
      return (m_currentSession == SESSION_OVERLAP_LN || 
              m_currentSession == SESSION_OVERLAP_TL);
   }
   
   // ¿Es horario principal? (London o NY o overlap)
   bool IsPrimeTime() const
   {
      return (m_currentSession == SESSION_LONDON ||
              m_currentSession == SESSION_NEWYORK ||
              m_currentSession == SESSION_OVERLAP_LN ||
              m_currentSession == SESSION_OVERLAP_TL);
   }
   
   // ¿Es fin de semana? (no hay trading)
   bool IsWeekend() const
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      return (dt.day_of_week == 0 || dt.day_of_week == 6);
   }
   
   // ¿Cierre de viernes? (últimas 2 horas)
   bool IsFridayClose() const
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      return (dt.day_of_week == 5 && dt.hour >= 20);
   }
   
   // Obtener multiplicador de agresividad por sesión
   double GetSessionMultiplier() const
   {
      switch(m_currentSession)
      {
         case SESSION_OVERLAP_LN:  return 1.2;  // Máxima liquidez, más agresivo
         case SESSION_LONDON:      return 1.0;  // Estándar
         case SESSION_NEWYORK:     return 1.0;  // Estándar
         case SESSION_OVERLAP_TL:  return 0.9;  // Buena pero menor que L-NY
         case SESSION_TOKYO:       return 0.7;  // Menor volatilidad
         case SESSION_SYDNEY:      return 0.5;  // Mínima liquidez
         case SESSION_NONE:        return 0.0;  // No operar
         default:                  return 0.5;
      }
   }
};

#endif // __PHOENIX_SESSION_DETECTOR_MQH__
//+------------------------------------------------------------------+
