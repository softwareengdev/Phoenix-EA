//+------------------------------------------------------------------+
//|                                            CorrelationMatrix.mqh |
//|                      PHOENIX EA — Cross-Pair Correlation Filter   |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_CORRELATION_MATRIX_MQH__
#define __PHOENIX_CORRELATION_MATRIX_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| CCorrelationMatrix — Calcula y monitorea correlaciones            |
//|                                                                   |
//| Evita abrir posiciones en instrumentos altamente correlacionados  |
//| para reducir riesgo de concentracion.                             |
//| Usa retornos log de cierre H1 de las ultimas N barras.           |
//+------------------------------------------------------------------+
class CCorrelationMatrix
{
private:
   int      m_symbolCount;
   int      m_lookback;               // Barras de lookback
   double   m_maxCorrelation;         // Correlacion maxima permitida
   matrix   m_corrMatrix;             // Matriz de correlacion (MQL5 native)
   datetime m_lastUpdate;
   bool     m_initialized;
   
   // Calcular correlacion Pearson entre dos arrays
   double PearsonCorrelation(const double &x[], const double &y[], int size)
   {
      if(size < 10) return 0.0;
      
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
      for(int i = 0; i < size; i++)
      {
         sumX  += x[i];
         sumY  += y[i];
         sumXY += x[i] * y[i];
         sumX2 += x[i] * x[i];
         sumY2 += y[i] * y[i];
      }
      
      double n = (double)size;
      double denom = MathSqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
      if(denom == 0.0) return 0.0;
      
      return (n * sumXY - sumX * sumY) / denom;
   }
   
public:
   CCorrelationMatrix() : m_symbolCount(0), m_lookback(100),
                            m_maxCorrelation(0.7), m_lastUpdate(0),
                            m_initialized(false) {}
   
   bool Init(int lookback = 100, double maxCorrelation = 0.7)
   {
      m_lookback       = lookback;
      m_maxCorrelation = maxCorrelation;
      m_symbolCount    = g_activeSymbolCount;
      m_corrMatrix.Resize(m_symbolCount, m_symbolCount);
      m_corrMatrix.Fill(0.0);
      
      // Diagonal = 1.0
      for(int i = 0; i < m_symbolCount; i++)
         m_corrMatrix[i][i] = 1.0;
      
      m_initialized = true;
      RecalculateAll();
      
      g_logger.Info(StringFormat("CorrelationMatrix: Init [%dx%d lookback=%d maxCorr=%.2f]",
                    m_symbolCount, m_symbolCount, m_lookback, m_maxCorrelation));
      return true;
   }
   
   // Recalcular toda la matriz (llamar cada hora)
   void RecalculateAll()
   {
      if(!m_initialized || m_symbolCount < 2) return;
      
      // Obtener retornos de cierre H1
      double returns[][]; 
      ArrayResize(returns, m_symbolCount);
      
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(!g_symbolConfigs[i].enabled) continue;
         
         double close[];
         int copied = CopyClose(g_symbolConfigs[i].symbol, PERIOD_H1, 0, m_lookback + 1, close);
         if(copied < m_lookback + 1) continue;
         
         double ret[];
         ArrayResize(ret, m_lookback);
         for(int j = 0; j < m_lookback; j++)
         {
            if(close[j] > 0)
               ret[j] = MathLog(close[j + 1] / close[j]);
            else
               ret[j] = 0.0;
         }
         ArrayCopy(returns[i], ret);
      }
      
      // Calcular correlaciones par a par
      for(int i = 0; i < m_symbolCount; i++)
      {
         for(int j = i + 1; j < m_symbolCount; j++)
         {
            if(ArraySize(returns[i]) < m_lookback || ArraySize(returns[j]) < m_lookback)
            {
               m_corrMatrix[i][j] = 0.0;
               m_corrMatrix[j][i] = 0.0;
               continue;
            }
            
            double corr = PearsonCorrelation(returns[i], returns[j], m_lookback);
            m_corrMatrix[i][j] = corr;
            m_corrMatrix[j][i] = corr;
         }
      }
      
      m_lastUpdate = TimeCurrent();
   }
   
   // Verificar si abrir posicion en symbolIndex conflicta con posiciones abiertas
   bool HasCorrelationConflict(int symbolIndex)
   {
      if(!m_initialized) return false;
      if(symbolIndex < 0 || symbolIndex >= m_symbolCount) return false;
      
      // Verificar contra todas las posiciones abiertas de PHOENIX
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         
         // Encontrar indice del simbolo de la posicion
         for(int j = 0; j < m_symbolCount; j++)
         {
            if(g_symbolConfigs[j].symbol == posSymbol && j != symbolIndex)
            {
               double corr = MathAbs(m_corrMatrix[symbolIndex][j]);
               if(corr > m_maxCorrelation)
               {
                  g_logger.Debug(StringFormat(
                     "CorrelationMatrix: %s bloqueado — corr=%.2f con %s (max=%.2f)",
                     g_symbolConfigs[symbolIndex].symbol, corr,
                     posSymbol, m_maxCorrelation));
                  return true;
               }
            }
         }
      }
      
      return false;
   }
   
   // Obtener correlacion entre dos simbolos
   double GetCorrelation(int idx1, int idx2) const
   {
      if(idx1 < 0 || idx1 >= m_symbolCount || idx2 < 0 || idx2 >= m_symbolCount)
         return 0.0;
      return m_corrMatrix[idx1][idx2];
   }
};

#endif // __PHOENIX_CORRELATION_MATRIX_MQH__
//+------------------------------------------------------------------+
