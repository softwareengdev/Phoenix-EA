//+------------------------------------------------------------------+
//|                                              StateManager.mqh    |
//|                       PHOENIX EA — State Persistence Manager      |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_STATE_MANAGER_MQH__
#define __PHOENIX_STATE_MANAGER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CStateManager — Persistencia de estado del EA                     |
//|                                                                   |
//| Guarda y restaura el estado completo del EA en archivos binarios  |
//| para sobrevivir reinicios de MT5, VPS reboots, etc.              |
//| Se guarda periodicamente y en cada evento importante.             |
//+------------------------------------------------------------------+
class CStateManager
{
private:
   string   m_stateFile;          // Ruta del archivo de estado
   string   m_metricsFile;        // Ruta del archivo de metricas
   bool     m_initialized;
   datetime m_lastSave;
   int      m_saveIntervalSec;
   
public:
   CStateManager() : m_initialized(false), m_lastSave(0),
                      m_saveIntervalSec(STATE_SAVE_INTERVAL) {}
   
   bool Init(const string &prefix = PHOENIX_NAME)
   {
      FolderCreate(STATE_PATH);
      m_stateFile   = STATE_PATH + prefix + "_state.bin";
      m_metricsFile = STATE_PATH + prefix + "_metrics.bin";
      m_initialized = true;
      
      g_logger.Info(StringFormat("StateManager: Init [file=%s interval=%ds]",
                    m_stateFile, m_saveIntervalSec));
      return true;
   }
   
   // Guardar estado completo
   bool SaveState()
   {
      if(!m_initialized) return false;
      
      int handle = FileOpen(m_stateFile, FILE_WRITE | FILE_BIN);
      if(handle == INVALID_HANDLE)
      {
         g_logger.Error(StringFormat("StateManager: No se pudo abrir %s para escritura", m_stateFile));
         return false;
      }
      
      // Escribir version para compatibilidad
      int version = PHOENIX_BUILD;
      FileWriteInteger(handle, version);
      
      // Escribir estado del EA
      FileWriteStruct(handle, g_eaState);
      
      // Escribir metricas de estrategias
      FileWriteInteger(handle, MAX_STRATEGIES);
      for(int i = 0; i < MAX_STRATEGIES; i++)
         FileWriteStruct(handle, g_strategyMetrics[i]);
      
      // Escribir flags globales
      FileWriteInteger(handle, g_tradingEnabled ? 1 : 0);
      FileWriteInteger(handle, g_activeSymbolCount);
      
      FileClose(handle);
      m_lastSave = TimeCurrent();
      
      g_logger.Debug("StateManager: Estado guardado");
      return true;
   }
   
   // Restaurar estado
   bool LoadState()
   {
      if(!m_initialized) return false;
      
      if(!FileIsExist(m_stateFile))
      {
         g_logger.Info("StateManager: No hay estado previo, inicio limpio");
         return false;
      }
      
      int handle = FileOpen(m_stateFile, FILE_READ | FILE_BIN);
      if(handle == INVALID_HANDLE)
      {
         g_logger.Error("StateManager: No se pudo abrir archivo de estado");
         return false;
      }
      
      // Leer version
      int version = FileReadInteger(handle);
      if(version > PHOENIX_BUILD)
      {
         g_logger.Warning(StringFormat("StateManager: Version de estado (%d) > version EA (%d)",
                          version, PHOENIX_BUILD));
      }
      
      // Leer estado
      SEAState savedState;
      if(FileReadStruct(handle, savedState) > 0)
      {
         // Restaurar campos criticos (no todos — algunos deben reiniciar)
         g_eaState.peakEquity       = savedState.peakEquity;
         g_eaState.maxDrawdownHit   = savedState.maxDrawdownHit;
         g_eaState.totalTradesSession = savedState.totalTradesSession;
         g_eaState.consecutiveLosses = savedState.consecutiveLosses;
         g_eaState.consecutiveWins   = savedState.consecutiveWins;
         g_eaState.lastOptimization  = savedState.lastOptimization;
      }
      
      // Leer metricas
      int stratCount = FileReadInteger(handle);
      int toRead = MathMin(stratCount, MAX_STRATEGIES);
      for(int i = 0; i < toRead; i++)
      {
         SStrategyMetrics metrics;
         if(FileReadStruct(handle, metrics) > 0)
            g_strategyMetrics[i] = metrics;
      }
      
      // Leer flags
      g_tradingEnabled    = (FileReadInteger(handle) == 1);
      g_activeSymbolCount = FileReadInteger(handle);
      
      FileClose(handle);
      g_logger.Info(StringFormat("StateManager: Estado restaurado [peak=%.2f trades=%d]",
                    g_eaState.peakEquity, g_eaState.totalTradesSession));
      return true;
   }
   
   // Verificar si toca guardar
   void CheckAutoSave()
   {
      if(!m_initialized) return;
      if(TimeCurrent() - m_lastSave >= m_saveIntervalSec)
         SaveState();
   }
   
   // Forzar guardado (llamar en eventos importantes)
   void ForceSave()
   {
      SaveState();
   }
   
   datetime GetLastSaveTime() const { return m_lastSave; }
};

#endif // __PHOENIX_STATE_MANAGER_MQH__
//+------------------------------------------------------------------+
