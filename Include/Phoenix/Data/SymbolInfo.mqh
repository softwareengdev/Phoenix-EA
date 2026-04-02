//+------------------------------------------------------------------+
//|                                                  SymbolInfo.mqh  |
//|                          PHOENIX EA — Symbol Information Cache    |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SYMBOL_INFO_MQH__
#define __PHOENIX_SYMBOL_INFO_MQH__

#include "..\Core\Defines.mqh"

//+------------------------------------------------------------------+
//| CSymbolInfo — Cache de propiedades del símbolo                    |
//|                                                                   |
//| Evita llamadas repetidas a SymbolInfoDouble/Integer               |
//| Se refresca por tick o periódicamente                             |
//+------------------------------------------------------------------+
class CSymbolInfo
{
private:
   string            m_symbol;           // Nombre
   bool              m_initialized;      // Estado
   
   //--- Propiedades estáticas (no cambian)
   int               m_digits;           // Decimales del precio
   double            m_point;            // Valor de un punto
   double            m_tickSize;         // Tamaño mínimo de tick
   double            m_tickValue;        // Valor monetario de un tick
   double            m_lotStep;          // Paso mínimo de lote
   double            m_minLot;           // Lote mínimo
   double            m_maxLot;           // Lote máximo
   double            m_contractSize;     // Tamaño del contrato
   int               m_stopsLevel;       // Nivel mínimo de stops (puntos)
   int               m_freezeLevel;      // Nivel de congelación
   ENUM_SYMBOL_TRADE_EXECUTION m_execMode; // Modo de ejecución
   
   //--- Propiedades dinámicas (cambian por tick)
   double            m_bid;              // Precio bid actual
   double            m_ask;              // Precio ask actual
   double            m_spread;           // Spread en puntos
   double            m_spreadPercent;    // Spread como % del precio
   double            m_swapLong;         // Swap largo
   double            m_swapShort;        // Swap corto
   datetime          m_lastRefresh;      // Última actualización
   
   //--- Estadísticas de spread
   double            m_avgSpread;        // Spread promedio (EMA)
   double            m_maxSpreadSeen;    // Máximo spread observado

public:
   CSymbolInfo() : m_initialized(false), m_avgSpread(0), m_maxSpreadSeen(0) {}
   
   bool Init(const string symbol)
   {
      m_symbol = symbol;
      
      if(!SymbolInfoInteger(symbol, SYMBOL_EXIST))
         return false;
      
      // Cargar propiedades estáticas
      m_digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_lotStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_minLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_maxLot       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_stopsLevel   = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel  = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      m_execMode     = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(symbol, SYMBOL_TRADE_EXEMODE);
      
      Refresh();
      m_initialized = true;
      return true;
   }
   
   // Actualizar precios y spread (llamar por tick)
   void Refresh()
   {
      m_bid          = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      m_ask          = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      m_spread       = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      m_swapLong     = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG);
      m_swapShort    = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT);
      m_tickValue    = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_lastRefresh  = TimeCurrent();
      
      // Spread como porcentaje
      if(m_bid > 0)
         m_spreadPercent = (m_ask - m_bid) / m_bid * 100.0;
      
      // EMA del spread (alpha = 0.01 → suavizado lento)
      if(m_avgSpread == 0.0)
         m_avgSpread = m_spread;
      else
         m_avgSpread = m_avgSpread * 0.99 + m_spread * 0.01;
      
      // Tracking de máximo
      if(m_spread > m_maxSpreadSeen)
         m_maxSpreadSeen = m_spread;
   }
   
   // Normalizar lote al step del símbolo
   double NormalizeLot(double lot)
   {
      lot = MathMax(m_minLot, lot);
      lot = MathMin(m_maxLot, lot);
      if(m_lotStep > 0)
         lot = MathFloor(lot / m_lotStep) * m_lotStep;
      return NormalizeDouble(lot, 2);
   }
   
   // Normalizar precio al tick size
   double NormalizePrice(double price)
   {
      if(m_tickSize > 0)
         price = MathRound(price / m_tickSize) * m_tickSize;
      return NormalizeDouble(price, m_digits);
   }
   
   // Verificar que stop cumple con nivel mínimo
   bool IsStopLevelValid(double price, double stopPrice)
   {
      double minDist = m_stopsLevel * m_point;
      return (MathAbs(price - stopPrice) >= minDist);
   }
   
   // Convertir pips a precio
   double PipsToPrice(double pips)
   {
      if(m_digits == 3 || m_digits == 5)
         return pips * m_point * 10.0;
      return pips * m_point;
   }
   
   // Valor monetario de N pips para N lotes
   double PipValue(double lots, double pips = 1.0)
   {
      if(m_tickSize <= 0 || m_tickValue <= 0) return 0.0;
      double priceMove = PipsToPrice(pips);
      return (priceMove / m_tickSize) * m_tickValue * lots;
   }
   
   //--- Getters
   string   GetSymbol()         const { return m_symbol; }
   double   GetBid()            const { return m_bid; }
   double   GetAsk()            const { return m_ask; }
   double   GetSpread()         const { return m_spread; }
   double   GetSpreadPercent()  const { return m_spreadPercent; }
   double   GetAvgSpread()      const { return m_avgSpread; }
   double   GetPoint()          const { return m_point; }
   int      GetDigits()         const { return m_digits; }
   double   GetMinLot()         const { return m_minLot; }
   double   GetMaxLot()         const { return m_maxLot; }
   double   GetLotStep()        const { return m_lotStep; }
   double   GetTickValue()      const { return m_tickValue; }
   double   GetTickSize()       const { return m_tickSize; }
   double   GetContractSize()   const { return m_contractSize; }
   int      GetStopsLevel()     const { return m_stopsLevel; }
   double   GetSwapLong()       const { return m_swapLong; }
   double   GetSwapShort()      const { return m_swapShort; }
   bool     IsInitialized()     const { return m_initialized; }
   ENUM_SYMBOL_TRADE_EXECUTION GetExecMode() const { return m_execMode; }
   
   // ¿Spread está anormalmente alto? (> 2x promedio)
   bool IsSpreadAbnormal() const
   {
      return (m_avgSpread > 0 && m_spread > m_avgSpread * 2.0);
   }
};

#endif // __PHOENIX_SYMBOL_INFO_MQH__
//+------------------------------------------------------------------+
