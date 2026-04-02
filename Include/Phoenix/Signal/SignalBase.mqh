//+------------------------------------------------------------------+
//|                                                   SignalBase.mqh |
//|                            PHOENIX EA — Abstract Signal Base      |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_SIGNAL_BASE_MQH__
#define __PHOENIX_SIGNAL_BASE_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CSignalBase — Clase abstracta para todas las estrategias          |
//|                                                                   |
//| Cada sub-estrategia hereda de esta clase e implementa:            |
//| - Init(): Inicialización de indicadores y buffers                 |
//| - Evaluate(): Evaluación de señal con confianza                   |
//| - GetSignal(): Retorna STradeSignal con toda la información       |
//| - Deinit(): Limpieza de recursos                                  |
//+------------------------------------------------------------------+
class CSignalBase
{
protected:
   //--- Identificación
   string               m_name;              // Nombre de la estrategia
   ENUM_STRATEGY_TYPE   m_type;              // Tipo de estrategia
   string               m_symbol;            // Símbolo asignado
   ENUM_TIMEFRAMES      m_primaryTF;         // Timeframe principal
   ENUM_TIMEFRAMES      m_entryTF;           // Timeframe de entrada
   ENUM_TIMEFRAMES      m_confirmTF;         // Timeframe de confirmación
   
   //--- Estado
   bool                 m_initialized;       // Está inicializada
   bool                 m_active;            // Está activa (puede generar señales)
   datetime             m_lastEvalTime;      // Última evaluación
   int                  m_warmupBars;        // Barras necesarias de calentamiento
   
   //--- Señal actual
   STradeSignal         m_currentSignal;     // Última señal generada
   
   //--- Performance local (para auto-evaluación rápida)
   int                  m_signalsGenerated;  // Señales totales generadas
   int                  m_signalsTaken;      // Señales que resultaron en trades
   double               m_recentWinRate;     // Win rate reciente (últimos 20 trades)
   
   //--- Handles de indicadores (para que las subclases los gestionen)
   int                  m_handles[];         // Array de handles de indicadores
   
   //--- Métodos protegidos de utilidad
   
   // Valida que hay suficientes barras disponibles
   bool HasEnoughBars(const string symbol, ENUM_TIMEFRAMES tf, int required)
   {
      int available = Bars(symbol, tf);
      if(available < required)
      {
         g_logger.Debug(StringFormat("[%s] Barras insuficientes en %s %s: %d/%d",
                        m_name, symbol, EnumToString(tf), available, required));
         return false;
      }
      return true;
   }
   
   // Obtiene spread actual normalizado
   double GetSpreadInPips(const string symbol)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
      
      // Normalizar a pips (5 digits = dividir por 10)
      if(digits == 3 || digits == 5)
         spread *= 10.0;
      
      return spread;
   }
   
   // Calcula ATR para stop loss dinámico
   double CalculateATR(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 0)
   {
      double atr[];
      int handle = iATR(symbol, tf, period);
      if(handle == INVALID_HANDLE)
         return 0.0;
      
      if(CopyBuffer(handle, 0, shift, 1, atr) != 1)
      {
         IndicatorRelease(handle);
         return 0.0;
      }
      
      IndicatorRelease(handle);
      return atr[0];
   }
   
   // Liberar handles de indicadores
   void ReleaseHandles()
   {
      for(int i = 0; i < ArraySize(m_handles); i++)
      {
         if(m_handles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_handles[i]);
            m_handles[i] = INVALID_HANDLE;
         }
      }
      ArrayFree(m_handles);
   }
   
   // Añadir un handle al array de tracking
   int AddHandle(int handle)
   {
      int size = ArraySize(m_handles);
      ArrayResize(m_handles, size + 1);
      m_handles[size] = handle;
      return handle;
   }

public:
   //--- Constructor
   CSignalBase()
   {
      m_name             = "BaseSignal";
      m_type             = STRATEGY_TREND;
      m_symbol           = "";
      m_primaryTF        = PERIOD_H1;
      m_entryTF          = PERIOD_M15;
      m_confirmTF        = PERIOD_H4;
      m_initialized      = false;
      m_active           = false;
      m_lastEvalTime     = 0;
      m_warmupBars       = WARMUP_BARS;
      m_signalsGenerated = 0;
      m_signalsTaken     = 0;
      m_recentWinRate    = 0.5;
      m_currentSignal.Reset();
   }
   
   //--- Destructor virtual
   virtual ~CSignalBase()
   {
      ReleaseHandles();
   }
   
   //=================================================================
   // MÉTODOS VIRTUALES PUROS — Cada estrategia DEBE implementar estos
   //=================================================================
   
   // Inicialización: crear indicadores, validar parámetros
   virtual bool Init(const string symbol, ENUM_TIMEFRAMES primaryTF,
                     ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES confirmTF) = 0;
   
   // Evaluación principal: analiza el mercado y genera señal
   virtual STradeSignal Evaluate() = 0;
   
   // Limpieza de recursos
   virtual void Deinit() = 0;
   
   // Nombre descriptivo de la estrategia
   virtual string GetDescription() const = 0;
   
   //=================================================================
   // MÉTODOS VIRTUALES CON IMPLEMENTACIÓN POR DEFECTO
   //=================================================================
   
   // ¿Es buen momento para esta estrategia dado el régimen de mercado?
   virtual bool IsRegimeSuitable(ENUM_MARKET_REGIME regime)
   {
      // Por defecto, todas las estrategias operan en todos los regímenes
      // Las subclases deben override esto
      return (regime != REGIME_UNKNOWN && regime != REGIME_THIN);
   }
   
   // ¿La señal sigue siendo válida? (para trailing de señal)
   virtual bool IsSignalStillValid()
   {
      if(m_currentSignal.direction == SIGNAL_NONE)
         return false;
      if(m_currentSignal.expiryTime > 0 && TimeCurrent() > m_currentSignal.expiryTime)
         return false;
      return true;
   }
   
   // Ajustar parámetros (llamado por el optimizador genético)
   virtual void AdjustParameters(const double &params[])
   {
      // Override en subclases para parámetros específicos
   }
   
   //=================================================================
   // MÉTODOS COMUNES (no override)
   //=================================================================
   
   // Getters
   string              GetName()       const { return m_name; }
   ENUM_STRATEGY_TYPE  GetType()       const { return m_type; }
   string              GetSymbol()     const { return m_symbol; }
   bool                IsInitialized() const { return m_initialized; }
   bool                IsActive()      const { return m_active; }
   STradeSignal        GetLastSignal() const { return m_currentSignal; }
   
   // Setters
   void SetActive(bool active)
   {
      if(m_active != active)
      {
         g_logger.Info(StringFormat("[%s] %s → %s", 
                       m_name, m_active ? "ACTIVE" : "INACTIVE",
                       active ? "ACTIVE" : "INACTIVE"));
         m_active = active;
      }
   }
   
   // Registrar que una señal resultó en trade
   void RecordSignalTaken()  { m_signalsTaken++; }
   
   // Actualizar win rate reciente (llamado por PerformanceTracker)
   void UpdateRecentWinRate(double winRate) { m_recentWinRate = winRate; }
   
   // Confianza ajustada por performance reciente
   double GetAdjustedConfidence()
   {
      // Ajustar confianza base por win rate reciente
      double baseConf = m_currentSignal.confidence;
      double adjustment = (m_recentWinRate - 0.5) * 0.5; // ±25% máximo
      return MathMax(0.0, MathMin(1.0, baseConf + adjustment));
   }
};

#endif // __PHOENIX_SIGNAL_BASE_MQH__
//+------------------------------------------------------------------+
