//+------------------------------------------------------------------+
//|                                              TelegramBot.mqh     |
//|                       PHOENIX EA — Telegram Notifications         |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_TELEGRAM_BOT_MQH__
#define __PHOENIX_TELEGRAM_BOT_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CTelegramBot — Envio de notificaciones via Telegram WebRequest    |
//|                                                                   |
//| Requiere:                                                        |
//| 1. Bot token de @BotFather                                       |
//| 2. Chat ID del usuario/grupo                                     |
//| 3. URL https://api.telegram.org en Tools > Options > Expert      |
//|    Advisors > Allow WebRequest for listed URL                    |
//+------------------------------------------------------------------+
class CTelegramBot
{
private:
   string   m_botToken;
   string   m_chatId;
   string   m_baseUrl;
   bool     m_initialized;
   bool     m_enabled;
   int      m_messagesSent;
   datetime m_lastMessageTime;
   int      m_minIntervalSec;    // Anti-flood: minimo entre mensajes
   
   // Enviar request HTTP via WebRequest
   bool SendRequest(const string &url, const string &data)
   {
      if(g_isBacktesting || g_isOptimizing)
         return false; // No enviar en backtesting
      
      char post[];
      char result[];
      string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
      string resultHeaders;
      
      StringToCharArray(data, post, 0, StringLen(data));
      
      int timeout = 5000; // 5 segundos timeout
      int res = WebRequest("POST", url, headers, timeout, post, result, resultHeaders);
      
      if(res == -1)
      {
         int error = GetLastError();
         if(error == 4014)
            g_logger.Warning("TelegramBot: WebRequest no permitido. Agregar URL en Tools > Options");
         else
            g_logger.Error(StringFormat("TelegramBot: WebRequest error %d", error));
         return false;
      }
      
      return (res == 200);
   }
   
public:
   CTelegramBot() : m_initialized(false), m_enabled(false),
                     m_messagesSent(0), m_lastMessageTime(0),
                     m_minIntervalSec(5) {}
   
   bool Init(const string &botToken, const string &chatId)
   {
      if(botToken == "" || chatId == "")
      {
         g_logger.Info("TelegramBot: Token o ChatID vacios, deshabilitado");
         m_enabled = false;
         m_initialized = true;
         return true;
      }
      
      m_botToken = botToken;
      m_chatId   = chatId;
      m_baseUrl  = "https://api.telegram.org/bot" + m_botToken;
      m_enabled  = true;
      m_initialized = true;
      
      // Test de conexion
      SendMessage("PHOENIX EA iniciado en " + AccountInfoString(ACCOUNT_SERVER));
      
      g_logger.Info("TelegramBot: Inicializado y habilitado");
      return true;
   }
   
   // Enviar mensaje de texto
   bool SendMessage(const string &text)
   {
      if(!m_enabled || !m_initialized) return false;
      
      // Anti-flood
      if(TimeCurrent() - m_lastMessageTime < m_minIntervalSec)
         return false;
      
      string url  = m_baseUrl + "/sendMessage";
      string data = "chat_id=" + m_chatId + "&text=" + text + "&parse_mode=HTML";
      
      bool result = SendRequest(url, data);
      if(result)
      {
         m_messagesSent++;
         m_lastMessageTime = TimeCurrent();
      }
      return result;
   }
   
   // Notificaciones formateadas
   void NotifyTradeOpen(const string &symbol, const string &direction,
                        double lots, double price, double sl, double tp)
   {
      string msg = StringFormat(
         "<b>PHOENIX TRADE</b>\n"
         "Symbol: %s %s\n"
         "Lots: %.2f\n"
         "Entry: %.5f\n"
         "SL: %.5f | TP: %.5f",
         symbol, direction, lots, price, sl, tp);
      SendMessage(msg);
   }
   
   void NotifyTradeClose(const string &symbol, double profit, double balance)
   {
      string emoji = profit >= 0 ? "+" : "";
      string msg = StringFormat(
         "<b>PHOENIX CLOSE</b>\n"
         "Symbol: %s\n"
         "P&L: %s%.2f\n"
         "Balance: %.2f",
         symbol, emoji, profit, balance);
      SendMessage(msg);
   }
   
   void NotifyAlert(const string &alertType, const string &details)
   {
      string msg = StringFormat("<b>PHOENIX ALERT: %s</b>\n%s", alertType, details);
      SendMessage(msg);
   }
   
   void NotifyDailyReport(double balance, double equity, double dailyPnl,
                          int trades, double drawdown)
   {
      string msg = StringFormat(
         "<b>PHOENIX DAILY REPORT</b>\n"
         "Balance: %.2f\n"
         "Equity: %.2f\n"
         "Daily P&L: %.2f\n"
         "Trades: %d\n"
         "Drawdown: %.2f%%",
         balance, equity, dailyPnl, trades, drawdown * 100);
      SendMessage(msg);
   }
   
   int  GetMessagesSent() const { return m_messagesSent; }
   bool IsEnabled()       const { return m_enabled; }
};

#endif // __PHOENIX_TELEGRAM_BOT_MQH__
//+------------------------------------------------------------------+
