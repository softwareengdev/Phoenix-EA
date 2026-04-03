#ifndef __PHOENIX_TELEGRAM_BOT_MQH__
#define __PHOENIX_TELEGRAM_BOT_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Telegram Bot — WebRequest-based notifications                     |
//+------------------------------------------------------------------+
class CTelegramBot {
private:
   bool   m_enabled;
   string m_token;
   string m_chatID;
   string m_baseURL;
   int    m_timeout;
   datetime m_lastSend;
   int    m_minInterval;  // Min seconds between messages
   
public:
   CTelegramBot() : m_enabled(false), m_timeout(5000), m_lastSend(0), m_minInterval(2) {}
   
   bool Init(bool enabled, string token, string chatID) {
      m_enabled = enabled;
      m_token = token;
      m_chatID = chatID;
      if(m_enabled && StringLen(m_token) > 0)
         m_baseURL = "https://api.telegram.org/bot" + m_token;
      else
         m_enabled = false;
      return true;
   }
   
   bool SendMessage(string text, bool silent = false) {
      if(!m_enabled) return false;
      
      // No network I/O during backtesting (WebRequest fails in tester anyway)
      if(MQLInfoInteger(MQL_TESTER)) return false;
      
      // Rate limiting
      if(TimeCurrent() - m_lastSend < m_minInterval) return false;
      
      string url = m_baseURL + "/sendMessage";
      
      // Escape special characters for HTML
      StringReplace(text, "&", "&amp;");
      StringReplace(text, "<", "&lt;");
      StringReplace(text, ">", "&gt;");
      
      string postData = "chat_id=" + m_chatID + 
                        "&text=" + text + 
                        "&parse_mode=HTML" +
                        (silent ? "&disable_notification=true" : "");
      
      char data[];
      char result[];
      string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
      string resultHeaders;
      
      StringToCharArray(postData, data, 0, WHOLE_ARRAY, CP_UTF8);
      
      int res = WebRequest("POST", url, headers, m_timeout, data, result, resultHeaders);
      m_lastSend = TimeCurrent();
      
      if(res != 200) {
         if(g_Logger != NULL && res != -1)
            g_Logger.Debug(StringFormat("Telegram: HTTP %d", res));
         return false;
      }
      return true;
   }
   
   // Formatted notifications
   void NotifyTradeOpen(string symbol, string action, double price, double lots, double sl, double tp) {
      string msg = StringFormat(
         "🔥 *PHOENIX TRADE*\n"
         "📊 %s %s\n"
         "💰 Price: %.5f\n"
         "📦 Lots: %.2f\n"
         "🛑 SL: %.5f\n"
         "🎯 TP: %.5f",
         symbol, action, price, lots, sl, tp);
      SendMessage(msg);
   }
   
   void NotifyTradeClose(string symbol, double profit, double profitPct, string reason) {
      string emoji = (profit >= 0) ? "✅" : "❌";
      string msg = StringFormat(
         "%s *TRADE CLOSED*\n"
         "📊 %s\n"
         "💰 P/L: %.2f (%.2f%%)\n"
         "📝 Reason: %s",
         emoji, symbol, profit, profitPct, reason);
      SendMessage(msg);
   }
   
   void NotifyDailyReport(double equity, double dailyPnL, double dailyPct, 
                           int trades, int wins, double maxDD) {
      string msg = StringFormat(
         "📈 *DAILY REPORT*\n"
         "💼 Equity: %.2f\n"
         "📊 Daily P/L: %.2f (%.2f%%)\n"
         "🔢 Trades: %d (Wins: %d)\n"
         "📉 Max DD: %.2f%%",
         equity, dailyPnL, dailyPct, trades, wins, maxDD);
      SendMessage(msg, true);
   }
   
   void NotifyCircuitBreaker(string reason) {
      string msg = StringFormat(
         "🚨 *CIRCUIT BREAKER*\n"
         "⚠️ Trading halted!\n"
         "📝 Reason: %s",
         reason);
      SendMessage(msg);
   }
   
   void NotifyError(string error) {
      string msg = StringFormat("❗ *ERROR*\n%s", error);
      SendMessage(msg);
   }
   
   bool IsEnabled() { return m_enabled; }
};

#endif // __PHOENIX_TELEGRAM_BOT_MQH__
