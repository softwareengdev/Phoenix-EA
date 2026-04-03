#ifndef __PHOENIX_STATE_MANAGER_MQH__
#define __PHOENIX_STATE_MANAGER_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| State Manager — Binary save/restore for crash recovery            |
//+------------------------------------------------------------------+
class CStateManager {
private:
   string m_stateFile;
   string m_backupFile;
   int    m_saveInterval;  // seconds
   datetime m_lastSave;
   bool   m_initialized;
   
public:
   CStateManager() : m_saveInterval(60), m_lastSave(0), m_initialized(false) {}
   
   bool Init() {
      string dir = "Phoenix\\state";
      FolderCreate(dir);
      m_stateFile = dir + "\\phoenix_state.bin";
      m_backupFile = dir + "\\phoenix_state.bak";
      m_saveInterval = SAVE_STATE_SEC;
      m_initialized = true;
      
      // Try to restore previous state
      if(FileIsExist(m_stateFile)) {
         if(LoadState()) {
            if(g_Logger != NULL) g_Logger.Info("StateManager: Restored state from disk");
            return true;
         }
      }
      
      if(g_Logger != NULL) g_Logger.Info("StateManager: Fresh state initialized");
      return true;
   }
   
   void OnTimer() {
      if(!m_initialized) return;
      if(TimeCurrent() - m_lastSave >= m_saveInterval) {
         SaveState();
      }
   }
   
   bool SaveState() {
      // Backup current file first
      if(FileIsExist(m_stateFile)) {
         if(FileIsExist(m_backupFile)) FileDelete(m_backupFile);
         FileCopy(m_stateFile, 0, m_backupFile, 0);
      }
      
      int handle = FileOpen(m_stateFile, FILE_WRITE|FILE_BIN);
      if(handle == INVALID_HANDLE) {
         if(g_Logger != NULL) g_Logger.Error("StateManager: Cannot open state file for writing");
         return false;
      }
      
      // Write header
      int version = 300;
      FileWriteInteger(handle, version);
      FileWriteInteger(handle, (int)TimeCurrent());
      
      // Write EA state
      FileWriteDouble(handle, g_State.peakEquity);
      FileWriteDouble(handle, g_State.maxDrawdown);
      FileWriteDouble(handle, g_State.maxDrawdownPct);
      FileWriteDouble(handle, g_State.dailyPnL);
      FileWriteDouble(handle, g_State.weeklyPnL);
      FileWriteDouble(handle, g_State.monthlyPnL);
      FileWriteDouble(handle, g_State.totalPnL);
      FileWriteInteger(handle, g_State.totalTrades);
      FileWriteInteger(handle, g_State.todayTrades);
      FileWriteInteger(handle, g_State.consecutiveWins);
      FileWriteInteger(handle, g_State.consecutiveLosses);
      FileWriteInteger(handle, (int)g_State.lastTradeTime);
      FileWriteInteger(handle, (int)g_State.lastOptimizeTime);
      FileWriteInteger(handle, (int)g_State.lastReportTime);
      FileWriteDouble(handle, g_State.dayStartEquity);
      FileWriteInteger(handle, (int)g_State.circuitState);
      
      // Checksum
      double checksum = g_State.peakEquity + g_State.totalPnL + g_State.totalTrades;
      FileWriteDouble(handle, checksum);
      
      FileClose(handle);
      m_lastSave = TimeCurrent();
      return true;
   }
   
   bool LoadState() {
      int handle = FileOpen(m_stateFile, FILE_READ|FILE_BIN);
      if(handle == INVALID_HANDLE) return false;
      
      int version = FileReadInteger(handle);
      if(version < 100) {
         FileClose(handle);
         return false;
      }
      
      int savedTime = FileReadInteger(handle);
      
      g_State.peakEquity = FileReadDouble(handle);
      g_State.maxDrawdown = FileReadDouble(handle);
      g_State.maxDrawdownPct = FileReadDouble(handle);
      g_State.dailyPnL = FileReadDouble(handle);
      g_State.weeklyPnL = FileReadDouble(handle);
      g_State.monthlyPnL = FileReadDouble(handle);
      g_State.totalPnL = FileReadDouble(handle);
      g_State.totalTrades = FileReadInteger(handle);
      g_State.todayTrades = FileReadInteger(handle);
      g_State.consecutiveWins = FileReadInteger(handle);
      g_State.consecutiveLosses = FileReadInteger(handle);
      g_State.lastTradeTime = (datetime)FileReadInteger(handle);
      g_State.lastOptimizeTime = (datetime)FileReadInteger(handle);
      g_State.lastReportTime = (datetime)FileReadInteger(handle);
      g_State.dayStartEquity = FileReadDouble(handle);
      g_State.circuitState = (ENUM_CIRCUIT_STATE)FileReadInteger(handle);
      
      double checksum = FileReadDouble(handle);
      double expectedChecksum = g_State.peakEquity + g_State.totalPnL + g_State.totalTrades;
      
      FileClose(handle);
      
      if(MathAbs(checksum - expectedChecksum) > 0.001) {
         if(g_Logger != NULL) g_Logger.Warning("StateManager: Checksum mismatch, using fresh state");
         ZeroMemory(g_State);
         return false;
      }
      
      g_State.isInitialized = true;
      return true;
   }
   
   void ForceSave() { SaveState(); }
   
   void Cleanup() {
      SaveState();
   }
};

#endif // __PHOENIX_STATE_MANAGER_MQH__
