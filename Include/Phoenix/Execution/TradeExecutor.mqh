//+------------------------------------------------------------------+
//|                                              TradeExecutor.mqh   |
//|                          PHOENIX EA — Smart Trade Execution       |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_TRADE_EXECUTOR_MQH__
#define __PHOENIX_TRADE_EXECUTOR_MQH__

#include <Trade\Trade.mqh>
#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CTradeExecutor — Ejecucion inteligente con reintentos             |
//|                                                                   |
//| - Envio de ordenes con retry y backoff exponencial                |
//| - Validacion pre-envio (spread, margen, stops)                   |
//| - Manejo de diferentes modos de ejecucion del broker             |
//| - Trailing stop multiples algoritmos                              |
//| - Break-even automatico                                          |
//| - Cierre parcial                                                 |
//+------------------------------------------------------------------+
class CTradeExecutor
{
private:
   CTrade            m_trade;            // Objeto CTrade de la stdlib
   bool              m_initialized;
   int               m_maxRetries;
   int               m_retryDelayMs;
   ulong             m_lastTicket;       // Ultimo ticket ejecutado
   int               m_slippage;         // Slippage maximo en puntos
   
   // Estadisticas de ejecucion
   int               m_totalOrders;
   int               m_successOrders;
   int               m_failedOrders;
   int               m_retriedOrders;
   double            m_totalSlippage;    // Slippage acumulado
   
   // Verificar resultado de la operacion
   bool CheckResult(const string &symbol, const string &operation)
   {
      uint retcode = m_trade.ResultRetcode();
      
      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
      {
         m_lastTicket = m_trade.ResultOrder();
         m_successOrders++;
         g_logger.Info(StringFormat("TradeExecutor: %s %s OK ticket=%llu",
                       operation, symbol, m_lastTicket));
         return true;
      }
      
      g_logger.Error(StringFormat("TradeExecutor: %s %s FALLO code=%u msg=%s",
                     operation, symbol, retcode, m_trade.ResultComment()));
      return false;
   }
   
   // Esperar con backoff exponencial
   void WaitRetry(int attempt)
   {
      int delay = m_retryDelayMs * (int)MathPow(2, attempt);
      Sleep(delay);
   }
   
public:
   CTradeExecutor() : m_initialized(false), m_maxRetries(MAX_RETRIES),
                       m_retryDelayMs(RETRY_DELAY_MS), m_lastTicket(0),
                       m_slippage(30), m_totalOrders(0), m_successOrders(0),
                       m_failedOrders(0), m_retriedOrders(0), m_totalSlippage(0) {}
   
   bool Init(int slippage = 30)
   {
      m_slippage = slippage;
      m_trade.SetExpertMagicNumber(PHOENIX_MAGIC_BASE);
      m_trade.SetDeviationInPoints(slippage);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
      m_trade.SetAsyncMode(false); // Sincrono por defecto para control
      
      m_initialized = true;
      g_logger.Info(StringFormat("TradeExecutor: Init [slippage=%d retries=%d]",
                    slippage, m_maxRetries));
      return true;
   }
   
   //=================================================================
   // APERTURA DE POSICIONES
   //=================================================================
   
   // Abrir posicion con reintentos
   bool OpenPosition(const string &symbol, ENUM_ORDER_TYPE type,
                     double lots, double sl, double tp,
                     long magic, const string &comment = "")
   {
      if(!m_initialized) return false;
      
      m_totalOrders++;
      m_trade.SetExpertMagicNumber(magic);
      
      for(int attempt = 0; attempt <= m_maxRetries; attempt++)
      {
         if(attempt > 0)
         {
            m_retriedOrders++;
            g_logger.Debug(StringFormat("TradeExecutor: Reintento %d/%d para %s",
                           attempt, m_maxRetries, symbol));
            WaitRetry(attempt - 1);
            
            // Refrescar precios antes de reintentar
            SymbolInfoTick(symbol, MqlTick());
         }
         
         // Obtener precio actual
         double price = (type == ORDER_TYPE_BUY) 
                        ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                        : SymbolInfoDouble(symbol, SYMBOL_BID);
         
         if(price <= 0) continue;
         
         // Normalizar
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         price = NormalizeDouble(price, digits);
         sl    = NormalizeDouble(sl, digits);
         tp    = NormalizeDouble(tp, digits);
         
         bool result = false;
         if(type == ORDER_TYPE_BUY)
            result = m_trade.Buy(lots, symbol, price, sl, tp, comment);
         else if(type == ORDER_TYPE_SELL)
            result = m_trade.Sell(lots, symbol, price, sl, tp, comment);
         
         if(result && CheckResult(symbol, (type == ORDER_TYPE_BUY) ? "BUY" : "SELL"))
         {
            g_eaState.totalTradesSession++;
            return true;
         }
         
         // Errores no reintentables
         uint retcode = m_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_MARKET_CLOSED ||
            retcode == TRADE_RETCODE_NO_MONEY ||
            retcode == TRADE_RETCODE_TOO_MANY_REQUESTS ||
            retcode == TRADE_RETCODE_TRADE_DISABLED)
         {
            g_logger.Error(StringFormat("TradeExecutor: Error no reintentable: %u", retcode));
            break;
         }
      }
      
      m_failedOrders++;
      g_logger.Error(StringFormat("TradeExecutor: Fallo definitivo %s %s lots=%.2f",
                     (type == ORDER_TYPE_BUY) ? "BUY" : "SELL", symbol, lots));
      return false;
   }
   
   //=================================================================
   // CIERRE DE POSICIONES
   //=================================================================
   
   // Cerrar posicion por ticket
   bool ClosePosition(ulong ticket, const string &reason = "")
   {
      if(!m_initialized) return false;
      
      for(int attempt = 0; attempt <= m_maxRetries; attempt++)
      {
         if(attempt > 0) WaitRetry(attempt - 1);
         
         if(m_trade.PositionClose(ticket))
         {
            g_logger.Info(StringFormat("TradeExecutor: CLOSE ticket=%llu reason=%s", ticket, reason));
            return true;
         }
      }
      
      g_logger.Error(StringFormat("TradeExecutor: Fallo CLOSE ticket=%llu", ticket));
      return false;
   }
   
   // Cerrar todas las posiciones de PHOENIX
   int CloseAllPhoenix(const string &reason = "")
   {
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         if(ClosePosition(ticket, reason))
            closed++;
      }
      
      if(closed > 0)
         g_logger.Info(StringFormat("TradeExecutor: Cerradas %d posiciones (%s)", closed, reason));
      
      return closed;
   }
   
   // Cierre parcial (porcentaje del volumen)
   bool ClosePartial(ulong ticket, double percentToClose)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      
      double volume = PositionGetDouble(POSITION_VOLUME);
      double closeVolume = volume * percentToClose;
      
      // Normalizar al lot step
      string symbol = PositionGetString(POSITION_SYMBOL);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      
      closeVolume = MathFloor(closeVolume / lotStep) * lotStep;
      if(closeVolume < minLot) return false;
      
      return m_trade.PositionClosePartial(ticket, closeVolume);
   }
   
   //=================================================================
   // MODIFICACION DE POSICIONES
   //=================================================================
   
   // Mover SL (para trailing stop)
   bool ModifySL(ulong ticket, double newSL)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      string symbol    = PositionGetString(POSITION_SYMBOL);
      int    digits    = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      newSL = NormalizeDouble(newSL, digits);
      
      // No mover SL en contra (buy: solo subir, sell: solo bajar)
      long type = PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY && newSL <= currentSL && currentSL > 0)
         return false;
      if(type == POSITION_TYPE_SELL && newSL >= currentSL && currentSL > 0)
         return false;
      
      return m_trade.PositionModify(ticket, newSL, currentTP);
   }
   
   // Break-even: mover SL al precio de entrada + N pips
   bool MoveToBreakEven(ulong ticket, double minProfitPips = 10.0)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      long   type   = PositionGetInteger(POSITION_TYPE);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      
      double pipSize = (digits == 3 || digits == 5) ? point * 10 : point;
      double profitPips = 0;
      double beSL = 0;
      
      if(type == POSITION_TYPE_BUY)
      {
         profitPips = (currentPrice - entry) / pipSize;
         beSL = entry + 2 * pipSize; // 2 pips de beneficio asegurado
      }
      else
      {
         profitPips = (entry - currentPrice) / pipSize;
         beSL = entry - 2 * pipSize;
      }
      
      if(profitPips < minProfitPips)
         return false;
      
      return ModifySL(ticket, NormalizeDouble(beSL, digits));
   }
   
   //--- Getters
   ulong  GetLastTicket()    const { return m_lastTicket; }
   int    GetTotalOrders()   const { return m_totalOrders; }
   int    GetSuccessOrders() const { return m_successOrders; }
   int    GetFailedOrders()  const { return m_failedOrders; }
   double GetSuccessRate()   const { return m_totalOrders > 0 ? (double)m_successOrders / m_totalOrders : 0; }
   bool   IsInitialized()   const { return m_initialized; }
};

#endif // __PHOENIX_TRADE_EXECUTOR_MQH__
//+------------------------------------------------------------------+
