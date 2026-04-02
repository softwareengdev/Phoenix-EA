//+------------------------------------------------------------------+
//|                                                  DataEngine.mqh  |
//|                          PHOENIX EA — Multi-Symbol Data Engine    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_DATA_ENGINE_MQH__
#define __PHOENIX_DATA_ENGINE_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"
#include "SymbolInfo.mqh"
#include "SessionDetector.mqh"
#include "CalendarFilter.mqh"

//+------------------------------------------------------------------+
//| CDataEngine — Agregación de datos multi-símbolo y multi-TF       |
//|                                                                   |
//| Responsabilidades:                                                |
//| - Suscribir y mantener datos de todos los símbolos configurados   |
//| - Detectar régimen de mercado por símbolo                         |
//| - Calcular volatilidad y spread promedio                          |
//| - Proveer acceso unificado a datos OHLCV                         |
//| - Filtrar por sesión de trading y calendario económico            |
//+------------------------------------------------------------------+
class CDataEngine
{
private:
   CSymbolInfo       m_symbols[MAX_SYMBOLS];      // Info por símbolo
   CSessionDetector  m_sessionDetector;            // Detector de sesión
   CCalendarFilter   m_calendarFilter;             // Filtro de calendario
   int               m_symbolCount;                // Símbolos activos
   bool              m_initialized;                // Estado
   
   // Cache de régimen de mercado por símbolo
   ENUM_MARKET_REGIME m_regimes[MAX_SYMBOLS];
   datetime           m_lastRegimeUpdate[MAX_SYMBOLS];
   
   // Handles de indicadores para detección de régimen
   int               m_atrHandles[MAX_SYMBOLS];   // ATR para volatilidad
   int               m_adxHandles[MAX_SYMBOLS];   // ADX para tendencia
   int               m_bbHandles[MAX_SYMBOLS];     // Bollinger para rango
   
   // Detecta régimen de mercado usando ADX + ATR + Bollinger BW
   ENUM_MARKET_REGIME DetectRegime(int symbolIndex)
   {
      if(symbolIndex < 0 || symbolIndex >= m_symbolCount)
         return REGIME_UNKNOWN;
      
      string symbol = g_symbolConfigs[symbolIndex].symbol;
      ENUM_TIMEFRAMES tf = g_symbolConfigs[symbolIndex].primaryTF;
      
      // Leer ADX
      double adx[];
      if(CopyBuffer(m_adxHandles[symbolIndex], 0, 0, 3, adx) != 3)
         return REGIME_UNKNOWN;
      
      // Leer ATR normalizado (ATR / precio) para comparabilidad
      double atr[];
      if(CopyBuffer(m_atrHandles[symbolIndex], 0, 0, 3, atr) != 3)
         return REGIME_UNKNOWN;
      
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      if(price <= 0) return REGIME_UNKNOWN;
      double atrPct = (atr[0] / price) * 100.0; // ATR como % del precio
      
      // Leer Bollinger Bandwidth
      double bbUpper[], bbLower[];
      if(CopyBuffer(m_bbHandles[symbolIndex], 1, 0, 3, bbUpper) != 3) return REGIME_UNKNOWN;
      if(CopyBuffer(m_bbHandles[symbolIndex], 2, 0, 3, bbLower) != 3) return REGIME_UNKNOWN;
      double bbWidth = (bbUpper[0] - bbLower[0]) / price * 100.0;
      
      // Lógica de clasificación
      double adxCurrent = adx[0];
      
      // Alta volatilidad: ATR% > percentil histórico alto
      if(atrPct > 1.5) // Muy volátil
         return REGIME_VOLATILE;
      
      // Baja liquidez: spread extremadamente ancho (detectado externamente)
      double spreadPct = m_symbols[symbolIndex].GetSpreadPercent();
      if(spreadPct > 0.1) // Spread > 0.1% = thin market
         return REGIME_THIN;
      
      // Tendencia: ADX > 25
      if(adxCurrent > 25.0)
      {
         // Determinar dirección con +DI/-DI
         double plusDI[], minusDI[];
         CopyBuffer(m_adxHandles[symbolIndex], 1, 0, 1, plusDI);
         CopyBuffer(m_adxHandles[symbolIndex], 2, 0, 1, minusDI);
         
         if(ArraySize(plusDI) > 0 && ArraySize(minusDI) > 0)
            return (plusDI[0] > minusDI[0]) ? REGIME_TRENDING_UP : REGIME_TRENDING_DOWN;
         return REGIME_TRENDING_UP; // fallback
      }
      
      // Rango: ADX < 20 y Bollinger estrecho
      if(adxCurrent < 20.0 && bbWidth < 2.0)
         return REGIME_RANGING;
      
      // Default: ranging si ADX medio
      return REGIME_RANGING;
   }
   
public:
   CDataEngine() : m_symbolCount(0), m_initialized(false)
   {
      ArrayInitialize(m_atrHandles, INVALID_HANDLE);
      ArrayInitialize(m_adxHandles, INVALID_HANDLE);
      ArrayInitialize(m_bbHandles, INVALID_HANDLE);
      ArrayInitialize(m_regimes, REGIME_UNKNOWN);
      ArrayInitialize(m_lastRegimeUpdate, 0);
   }
   
   ~CDataEngine()
   {
      Deinit();
   }
   
   //--- Inicialización completa
   bool Init()
   {
      g_logger.Info("DataEngine: Inicializando...");
      
      // Inicializar detector de sesión
      if(!m_sessionDetector.Init())
      {
         g_logger.Error("DataEngine: Fallo al inicializar SessionDetector");
         return false;
      }
      
      // Inicializar filtro de calendario
      if(!m_calendarFilter.Init())
         g_logger.Warning("DataEngine: CalendarFilter no disponible (no crítico)");
      
      // Inicializar cada símbolo configurado
      m_symbolCount = g_activeSymbolCount;
      for(int i = 0; i < m_symbolCount; i++)
      {
         string sym = g_symbolConfigs[i].symbol;
         
         // Verificar que el símbolo existe
         if(!SymbolInfoInteger(sym, SYMBOL_EXIST))
         {
            g_logger.Warning(StringFormat("DataEngine: Símbolo %s no existe, deshabilitando", sym));
            g_symbolConfigs[i].enabled = false;
            continue;
         }
         
         // Activar símbolo en Market Watch
         SymbolSelect(sym, true);
         
         // Inicializar wrapper de símbolo
         if(!m_symbols[i].Init(sym))
         {
            g_logger.Error(StringFormat("DataEngine: Fallo al inicializar %s", sym));
            g_symbolConfigs[i].enabled = false;
            continue;
         }
         
         // Crear indicadores de régimen
         ENUM_TIMEFRAMES tf = g_symbolConfigs[i].primaryTF;
         m_atrHandles[i] = iATR(sym, tf, 14);
         m_adxHandles[i] = iADX(sym, tf, 14);
         m_bbHandles[i]  = iBands(sym, tf, 20, 0, 2.0, PRICE_CLOSE);
         
         if(m_atrHandles[i] == INVALID_HANDLE || 
            m_adxHandles[i] == INVALID_HANDLE ||
            m_bbHandles[i] == INVALID_HANDLE)
         {
            g_logger.Error(StringFormat("DataEngine: Fallo indicadores régimen para %s", sym));
            g_symbolConfigs[i].enabled = false;
            continue;
         }
         
         g_logger.Info(StringFormat("DataEngine: %s inicializado [TF=%s spread=%.1f pts]",
                       sym, EnumToString(tf), 
                       (double)SymbolInfoInteger(sym, SYMBOL_SPREAD)));
      }
      
      m_initialized = true;
      g_logger.Info(StringFormat("DataEngine: Inicializado con %d símbolos", m_symbolCount));
      return true;
   }
   
   //--- Actualización por tick
   void OnTick(const string &currentSymbol)
   {
      if(!m_initialized) return;
      
      // Actualizar info del símbolo que generó el tick
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(g_symbolConfigs[i].symbol == currentSymbol && g_symbolConfigs[i].enabled)
         {
            m_symbols[i].Refresh();
            break;
         }
      }
   }
   
   //--- Actualización periódica (llamar desde OnTimer)
   void OnTimer()
   {
      if(!m_initialized) return;
      
      // Actualizar sesión
      m_sessionDetector.Update();
      
      // Actualizar calendario
      m_calendarFilter.Update();
      
      // Actualizar régimen de cada símbolo (cada 5 minutos)
      datetime now = TimeCurrent();
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(!g_symbolConfigs[i].enabled) continue;
         
         if(now - m_lastRegimeUpdate[i] >= 300) // 5 minutos
         {
            ENUM_MARKET_REGIME newRegime = DetectRegime(i);
            if(newRegime != m_regimes[i] && newRegime != REGIME_UNKNOWN)
            {
               g_logger.Debug(StringFormat("DataEngine: %s régimen %s → %s",
                              g_symbolConfigs[i].symbol,
                              EnumToString(m_regimes[i]),
                              EnumToString(newRegime)));
               m_regimes[i] = newRegime;
            }
            m_lastRegimeUpdate[i] = now;
         }
      }
   }
   
   //--- Limpieza
   void Deinit()
   {
      for(int i = 0; i < MAX_SYMBOLS; i++)
      {
         if(m_atrHandles[i] != INVALID_HANDLE) { IndicatorRelease(m_atrHandles[i]); m_atrHandles[i] = INVALID_HANDLE; }
         if(m_adxHandles[i] != INVALID_HANDLE) { IndicatorRelease(m_adxHandles[i]); m_adxHandles[i] = INVALID_HANDLE; }
         if(m_bbHandles[i]  != INVALID_HANDLE) { IndicatorRelease(m_bbHandles[i]);  m_bbHandles[i]  = INVALID_HANDLE; }
      }
      m_calendarFilter.Deinit();
      m_initialized = false;
      g_logger.Info("DataEngine: Desinicializado");
   }
   
   //--- Getters
   ENUM_MARKET_REGIME    GetRegime(int symbolIndex) const { return (symbolIndex >= 0 && symbolIndex < m_symbolCount) ? m_regimes[symbolIndex] : REGIME_UNKNOWN; }
   CSessionDetector*     GetSessionDetector()              { return &m_sessionDetector; }
   CCalendarFilter*      GetCalendarFilter()               { return &m_calendarFilter; }
   CSymbolInfo*          GetSymbolInfo(int index)          { return (index >= 0 && index < m_symbolCount) ? &m_symbols[index] : NULL; }
   ENUM_TRADING_SESSION  GetCurrentSession() const         { return m_sessionDetector.GetCurrentSession(); }
   bool                  IsNewsTime() const                { return m_calendarFilter.IsHighImpactSoon(); }
   bool                  IsInitialized() const             { return m_initialized; }
   
   // ¿Es seguro operar este símbolo ahora?
   bool IsTradingSafe(int symbolIndex)
   {
      if(symbolIndex < 0 || symbolIndex >= m_symbolCount)   return false;
      if(!g_symbolConfigs[symbolIndex].enabled)              return false;
      if(m_regimes[symbolIndex] == REGIME_THIN)              return false;
      if(m_calendarFilter.IsHighImpactSoon())                return false;
      if(m_sessionDetector.GetCurrentSession() == SESSION_NONE) return false;
      
      // Verificar spread
      double currentSpread = (double)SymbolInfoInteger(g_symbolConfigs[symbolIndex].symbol, SYMBOL_SPREAD);
      if(currentSpread > g_symbolConfigs[symbolIndex].maxSpreadPoints)
      {
         g_logger.Debug(StringFormat("DataEngine: %s spread demasiado alto: %.0f > %.0f",
                        g_symbolConfigs[symbolIndex].symbol, currentSpread,
                        g_symbolConfigs[symbolIndex].maxSpreadPoints));
         return false;
      }
      
      return true;
   }
};

#endif // __PHOENIX_DATA_ENGINE_MQH__
//+------------------------------------------------------------------+
