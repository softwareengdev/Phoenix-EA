//+------------------------------------------------------------------+
//|                                                       Logger.mqh |
//|                                   PHOENIX EA — Logging System     |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_LOGGER_MQH__
#define __PHOENIX_LOGGER_MQH__

#include "Defines.mqh"

//+------------------------------------------------------------------+
//| CLogger — Sistema de logging con niveles, rotación y archivo      |
//+------------------------------------------------------------------+
class CLogger
{
private:
   ENUM_LOG_LEVEL    m_minLevel;          // Nivel mínimo para mostrar
   ENUM_LOG_LEVEL    m_fileLevel;         // Nivel mínimo para archivo
   string            m_logPath;           // Ruta del archivo de log
   string            m_prefix;            // Prefijo del componente
   int               m_fileHandle;        // Handle del archivo actual
   datetime          m_fileDate;          // Fecha del archivo actual
   bool              m_consoleEnabled;    // Output a Experts tab
   bool              m_fileEnabled;       // Output a archivo
   bool              m_alertEnabled;      // Alerts para errores
   ulong             m_totalMessages;     // Contador total
   ulong             m_errorCount;        // Contador de errores
   
   // Convierte nivel a string
   string LevelToString(ENUM_LOG_LEVEL level)
   {
      switch(level)
      {
         case LOG_LEVEL_TRACE:   return "TRACE";
         case LOG_LEVEL_DEBUG:   return "DEBUG";
         case LOG_LEVEL_INFO:    return "INFO ";
         case LOG_LEVEL_WARNING: return "WARN ";
         case LOG_LEVEL_ERROR:   return "ERROR";
         case LOG_LEVEL_FATAL:   return "FATAL";
         default:                return "?????";
      }
   }
   
   // Formato de timestamp
   string FormatTimestamp()
   {
      datetime now = TimeCurrent();
      MqlDateTime dt;
      TimeToStruct(now, dt);
      return StringFormat("%04d.%02d.%02d %02d:%02d:%02d",
                          dt.year, dt.mon, dt.day,
                          dt.hour, dt.min, dt.sec);
   }
   
   // Abre o rota el archivo de log
   bool EnsureFileOpen()
   {
      if(!m_fileEnabled)
         return false;
         
      datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
      
      // Si cambió el día, rotamos el archivo
      if(m_fileHandle != INVALID_HANDLE && today != m_fileDate)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
      
      if(m_fileHandle == INVALID_HANDLE)
      {
         m_fileDate = today;
         MqlDateTime dt;
         TimeToStruct(today, dt);
         string filename = StringFormat("%s%s_%04d%02d%02d.log",
                                        m_logPath, m_prefix,
                                        dt.year, dt.mon, dt.day);
         m_fileHandle = FileOpen(filename, FILE_WRITE | FILE_READ | FILE_TXT | 
                                 FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_ANSI);
         if(m_fileHandle != INVALID_HANDLE)
            FileSeek(m_fileHandle, 0, SEEK_END);
      }
      
      return (m_fileHandle != INVALID_HANDLE);
   }
   
   // Escribe una línea al archivo
   void WriteToFile(const string &line)
   {
      if(EnsureFileOpen())
      {
         FileWriteString(m_fileHandle, line + "\n");
         FileFlush(m_fileHandle);
      }
   }

public:
   //--- Constructor
   CLogger()
   {
      m_minLevel       = LOG_LEVEL_INFO;
      m_fileLevel      = LOG_LEVEL_DEBUG;
      m_logPath        = LOG_PATH;
      m_prefix         = PHOENIX_NAME;
      m_fileHandle     = INVALID_HANDLE;
      m_fileDate       = 0;
      m_consoleEnabled = true;
      m_fileEnabled    = true;
      m_alertEnabled   = true;
      m_totalMessages  = 0;
      m_errorCount     = 0;
   }
   
   //--- Destructor
   ~CLogger()
   {
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }
   
   //--- Inicialización
   bool Init(const string prefix, ENUM_LOG_LEVEL consoleLevel, 
             ENUM_LOG_LEVEL fileLevel, bool enableFile = true)
   {
      m_prefix         = prefix;
      m_minLevel       = consoleLevel;
      m_fileLevel      = fileLevel;
      m_fileEnabled    = enableFile;
      m_totalMessages  = 0;
      m_errorCount     = 0;
      
      // Crear directorio si no existe
      if(m_fileEnabled)
         FolderCreate(m_logPath);
      
      Info(StringFormat("Logger inicializado [%s] console=%s file=%s",
                        prefix, LevelToString(consoleLevel), 
                        LevelToString(fileLevel)));
      return true;
   }
   
   //--- Método principal de logging
   void Log(ENUM_LOG_LEVEL level, const string &message)
   {
      m_totalMessages++;
      
      if(level >= LOG_LEVEL_ERROR)
         m_errorCount++;
      
      string formattedMsg = StringFormat("[%s] [%s] [%s] %s",
                                          FormatTimestamp(),
                                          LevelToString(level),
                                          m_prefix,
                                          message);
      
      // Console output (Experts tab)
      if(m_consoleEnabled && level >= m_minLevel)
         Print(formattedMsg);
      
      // File output
      if(m_fileEnabled && level >= m_fileLevel)
         WriteToFile(formattedMsg);
      
      // Alert para errores graves
      if(m_alertEnabled && level >= LOG_LEVEL_FATAL)
         Alert("PHOENIX FATAL: ", message);
   }
   
   //--- Métodos de conveniencia por nivel
   void Trace(const string &msg)   { Log(LOG_LEVEL_TRACE, msg);   }
   void Debug(const string &msg)   { Log(LOG_LEVEL_DEBUG, msg);   }
   void Info(const string &msg)    { Log(LOG_LEVEL_INFO, msg);    }
   void Warning(const string &msg) { Log(LOG_LEVEL_WARNING, msg); }
   void Error(const string &msg)   { Log(LOG_LEVEL_ERROR, msg);   }
   void Fatal(const string &msg)   { Log(LOG_LEVEL_FATAL, msg);   }
   
   //--- Logging con formato (hasta 4 parámetros tipados)
   void InfoF(const string &fmt, const string &a1)
   { Info(StringFormat(fmt, a1)); }
   
   void InfoF(const string &fmt, const string &a1, const double a2)
   { Info(StringFormat(fmt, a1, a2)); }
   
   void ErrorF(const string &fmt, const string &a1, const int a2)
   { Error(StringFormat(fmt, a1, a2)); }
   
   //--- Getters
   ulong  GetTotalMessages() const { return m_totalMessages; }
   ulong  GetErrorCount()    const { return m_errorCount; }
   
   //--- Configuración en runtime
   void SetConsoleLevel(ENUM_LOG_LEVEL level) { m_minLevel = level; }
   void SetFileLevel(ENUM_LOG_LEVEL level)    { m_fileLevel = level; }
   void SetAlertEnabled(bool enabled)         { m_alertEnabled = enabled; }
};

#endif // __PHOENIX_LOGGER_MQH__
//+------------------------------------------------------------------+
