//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                     Copyright 2025, Phoenix Trading Systems       |
//|                                                                  |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_LOGGER_MQH__
#define __PHOENIX_LOGGER_MQH__

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| CLogger - Comprehensive logging with file output and rotation    |
//+------------------------------------------------------------------+
class CLogger {
private:
   ENUM_LOG_LEVEL m_minLevel;
   string         m_logFile;
   int            m_fileHandle;
   bool           m_fileEnabled;
   bool           m_printEnabled;
   int            m_maxFileSize;  // bytes
   int            m_linesWritten;
   datetime       m_lastRotation;
   string         m_prefix;
   
   string LevelToString(ENUM_LOG_LEVEL level) {
      switch(level) {
         case LOG_TRACE:   return "TRACE";
         case LOG_DEBUG:   return "DEBUG";
         case LOG_INFO:    return "INFO ";
         case LOG_WARNING: return "WARN ";
         case LOG_ERROR:   return "ERROR";
         case LOG_FATAL:   return "FATAL";
         default:          return "?????";
      }
   }
   
   void RotateFile() {
      if(m_fileHandle != INVALID_HANDLE) {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
      string backupName = m_logFile + "." + TimeToString(TimeCurrent(), TIME_DATE) + ".bak";
      // MQL5 doesn't have rename, so just start new file
      m_fileHandle = FileOpen(m_logFile, FILE_WRITE|FILE_TXT|FILE_ANSI, '\t');
      m_linesWritten = 0;
      m_lastRotation = TimeCurrent();
   }
   
   void WriteToFile(string msg) {
      if(!m_fileEnabled || m_fileHandle == INVALID_HANDLE) return;
      FileWriteString(m_fileHandle, msg + "\n");
      // Flush every 100 lines instead of every write (10x less I/O syscalls)
      m_linesWritten++;
      if(m_linesWritten % 100 == 0) FileFlush(m_fileHandle);
      if(m_linesWritten > 50000) RotateFile();
   }

public:
   CLogger() : m_minLevel(LOG_INFO), m_fileHandle(INVALID_HANDLE), 
               m_fileEnabled(false), m_printEnabled(true),
               m_maxFileSize(5*1024*1024), m_linesWritten(0),
               m_prefix("PHX") {}
   
   ~CLogger() {
      if(m_fileHandle != INVALID_HANDLE) {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }
   
   bool Init(string prefix, ENUM_LOG_LEVEL level, bool enableFile = true) {
      m_prefix = prefix;
      m_minLevel = level;
      m_printEnabled = true;
      m_fileEnabled = enableFile;
      
      // In backtesting: disable file logging entirely (massive I/O savings)
      // In optimization: also disable Print (thousands of passes)
      if(MQLInfoInteger(MQL_TESTER)) {
         m_fileEnabled = false;
         if(MQLInfoInteger(MQL_OPTIMIZATION))
            m_printEnabled = false;
         else
            m_minLevel = (ENUM_LOG_LEVEL)MathMax(m_minLevel, LOG_WARNING); // Only warnings+ in tester
      }
      
      if(m_fileEnabled) {
         string dir = "Phoenix\\logs";
         if(!FolderCreate(dir)) {
            // folder may already exist
         }
         m_logFile = dir + "\\Phoenix_" + TimeToString(TimeCurrent(), TIME_DATE) + ".log";
         StringReplace(m_logFile, ".", "_");
         StringReplace(m_logFile, ":", "_");
         m_logFile = dir + "\\Phoenix.log";
         m_fileHandle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ, '\t');
         if(m_fileHandle == INVALID_HANDLE) {
            Print("[", m_prefix, "] WARNING: Could not open log file: ", m_logFile);
            m_fileEnabled = false;
         } else {
            FileSeek(m_fileHandle, 0, SEEK_END);
         }
      }
      return true;
   }
   
   void SetLevel(ENUM_LOG_LEVEL level) { m_minLevel = level; }
   ENUM_LOG_LEVEL GetLevel() { return m_minLevel; }
   
   void Log(ENUM_LOG_LEVEL level, string message) {
      if(level < m_minLevel) return;
      string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
      string formatted = StringFormat("[%s][%s][%s] %s", timestamp, m_prefix, LevelToString(level), message);
      if(m_printEnabled) Print(formatted);
      WriteToFile(formatted);
   }
   
   void Trace(string msg)   { Log(LOG_TRACE, msg); }
   void Debug(string msg)   { Log(LOG_DEBUG, msg); }
   void Info(string msg)    { Log(LOG_INFO, msg); }
   void Warning(string msg) { Log(LOG_WARNING, msg); }
   void Error(string msg)   { Log(LOG_ERROR, msg); }
   void Fatal(string msg)   { Log(LOG_FATAL, msg); }
   
   // Performance logging
   void LogTrade(string symbol, string action, double price, double lots, double sl, double tp, string comment) {
      Log(LOG_INFO, StringFormat("TRADE| %s %s @ %.5f | Lots=%.2f SL=%.5f TP=%.5f | %s",
          symbol, action, price, lots, sl, tp, comment));
   }
   
   void LogSignal(STradeSignal &signal) {
      Log(LOG_DEBUG, StringFormat("SIGNAL| %s %s %s | Conf=%.2f R:R=%.2f ATR=%.5f | %s",
          signal.symbol,
          signal.direction == SIGNAL_BUY ? "BUY" : "SELL",
          EnumToString(signal.strategy),
          signal.confidence, signal.riskReward, signal.atrValue,
          signal.comment));
   }
   
   void LogMetrics(SStrategyMetrics &metrics) {
      Log(LOG_INFO, StringFormat("METRICS| %s | Trades=%d WR=%.1f%% PF=%.2f Sharpe=%.2f DD=%.1f%% Weight=%.2f",
          EnumToString(metrics.strategy), metrics.totalTrades,
          metrics.winRate * 100, metrics.profitFactor,
          metrics.sharpeRatio, metrics.maxDrawdownPct * 100,
          metrics.allocationWeight));
   }
   
   void LogState(SEAState &state) {
      Log(LOG_INFO, StringFormat("STATE| Peak=%.2f DD=%.2f%% DailyPnL=%.2f Trades=%d Circuit=%s",
          state.peakEquity, state.maxDrawdownPct * 100,
          state.dailyPnL, state.totalTrades,
          EnumToString(state.circuitState)));
   }
   
   void Shutdown() {
      if(m_fileHandle != INVALID_HANDLE) {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }
};

#endif // __PHOENIX_LOGGER_MQH__
