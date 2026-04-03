//+------------------------------------------------------------------+
//|                                            CorrelationMatrix.mqh |
//|                         Phoenix EA — Risk Management Layer        |
//+------------------------------------------------------------------+
#ifndef __PHOENIX_CORRELATION_MATRIX_MQH__
#define __PHOENIX_CORRELATION_MATRIX_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Correlation Matrix — Cross-pair correlation filter                |
//| Prevents opening highly correlated positions in same direction   |
//+------------------------------------------------------------------+
class CCorrelationMatrix {
private:
   double m_matrix[];          // Flat NxN matrix
   int    m_size;              // Number of symbols
   int    m_lookbackBars;      // Bars for correlation calculation
   double m_maxCorrelation;    // Max allowed correlation for same-direction trades
   datetime m_lastUpdate;
   
public:
   CCorrelationMatrix() : m_size(0), m_lookbackBars(100), m_maxCorrelation(0.7), m_lastUpdate(0) {}
   
   void Init(int symbolCount, int lookbackBars = 100, double maxCorrelation = 0.7) {
      m_size = symbolCount;
      // In backtesting, use shorter lookback (50 vs 100 bars) for speed
      m_lookbackBars = g_IsTesting ? MathMin(lookbackBars, 50) : lookbackBars;
      m_maxCorrelation = maxCorrelation;
      ArrayResize(m_matrix, m_size * m_size);
      ArrayInitialize(m_matrix, 0);
      // Set diagonal to 1.0
      for(int i = 0; i < m_size; i++)
         m_matrix[i * m_size + i] = 1.0;
   }
   
   //+------------------------------------------------------------------+
   //| Recalculate correlation matrix from H1 close prices              |
   //+------------------------------------------------------------------+
   void Update() {
      datetime now = TimeCurrent();
      if(now - m_lastUpdate < CORRELATION_UPDATE_SEC) return;
      m_lastUpdate = now;
      
      // Get close prices for all symbols (flat array, no 2D in MQL5)
      int totalData = m_size * m_lookbackBars;
      double allCloses[];
      ArrayResize(allCloses, totalData);
      
      for(int i = 0; i < m_size; i++) {
         double prices[];
         ArraySetAsSeries(prices, true);
         int copied = CopyClose(g_Symbols[i].name, PERIOD_H1, 0, m_lookbackBars, prices);
         if(copied < m_lookbackBars) {
            for(int k = 0; k < m_lookbackBars; k++)
               allCloses[i * m_lookbackBars + k] = 0;
            continue;
         }
         for(int k = 0; k < m_lookbackBars; k++)
            allCloses[i * m_lookbackBars + k] = prices[k];
      }
      
      // Calculate returns
      double returns[];
      int retSize = m_size * (m_lookbackBars - 1);
      ArrayResize(returns, retSize);
      
      for(int i = 0; i < m_size; i++) {
         for(int k = 0; k < m_lookbackBars - 1; k++) {
            double curr = allCloses[i * m_lookbackBars + k];
            double prev = allCloses[i * m_lookbackBars + k + 1];
            returns[i * (m_lookbackBars - 1) + k] = (prev > 0) ? (curr - prev) / prev : 0;
         }
      }
      
      // Calculate correlation matrix (upper triangle, mirror to lower)
      int n = m_lookbackBars - 1;
      for(int i = 0; i < m_size; i++) {
         for(int j = i; j < m_size; j++) {
            if(i == j) {
               m_matrix[i * m_size + j] = 1.0;
               continue;
            }
            double corr = CalculateCorrelation(returns, i, j, n);
            m_matrix[i * m_size + j] = corr;
            m_matrix[j * m_size + i] = corr; // Symmetric
         }
      }
      
      if(g_Logger != NULL)
         g_Logger.Debug("CorrelationMatrix: Updated correlation matrix");
   }
   
   double GetCorrelation(int sym1, int sym2) {
      if(sym1 < 0 || sym1 >= m_size || sym2 < 0 || sym2 >= m_size) return 0;
      return m_matrix[sym1 * m_size + sym2];
   }
   
   //+------------------------------------------------------------------+
   //| Check if opening a trade would create over-correlated exposure    |
   //+------------------------------------------------------------------+
   bool IsCorrelationSafe(int symIdx, ENUM_SIGNAL_TYPE direction) {
      for(int i = PositionsTotal() - 1; i >= 0; i--) {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(!IS_PHOENIX_MAGIC(magic)) continue;
         
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         int posSymIdx = FindSymbolIndex(posSymbol);
         if(posSymIdx < 0 || posSymIdx == symIdx) continue;
         
         // Get position direction
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_SIGNAL_TYPE posDir = (posType == POSITION_TYPE_BUY) ? SIGNAL_BUY : SIGNAL_SELL;
         
         double corr = GetCorrelation(symIdx, posSymIdx);
         
         // Same direction + high positive correlation = over-exposed
         if(direction == posDir && corr > m_maxCorrelation) {
            if(g_Logger != NULL)
               g_Logger.Debug(StringFormat("CorrelationFilter: Blocked %s (%s dir) - correlated %.2f with %s",
                   g_Symbols[symIdx].name, direction == SIGNAL_BUY ? "BUY" : "SELL",
                   corr, posSymbol));
            return false;
         }
         
         // Opposite direction + high negative correlation = same exposure
         if(direction != posDir && corr < -m_maxCorrelation) {
            if(g_Logger != NULL)
               g_Logger.Debug(StringFormat("CorrelationFilter: Blocked %s - inverse corr %.2f with %s",
                   g_Symbols[symIdx].name, corr, posSymbol));
            return false;
         }
      }
      return true;
   }

private:
   //+------------------------------------------------------------------+
   //| Pearson correlation between two return series                     |
   //+------------------------------------------------------------------+
   double CalculateCorrelation(double &rets[], int sym1, int sym2, int n) {
      if(n <= 1) return 0;
      int offset1 = sym1 * n;
      int offset2 = sym2 * n;
      
      double sum1 = 0, sum2 = 0, sum12 = 0, sumSq1 = 0, sumSq2 = 0;
      for(int k = 0; k < n; k++) {
         double r1 = rets[offset1 + k];
         double r2 = rets[offset2 + k];
         sum1 += r1;
         sum2 += r2;
         sum12 += r1 * r2;
         sumSq1 += r1 * r1;
         sumSq2 += r2 * r2;
      }
      
      double mean1 = sum1 / n;
      double mean2 = sum2 / n;
      double cov = sum12 / n - mean1 * mean2;
      double std1 = MathSqrt(MathMax(0, sumSq1 / n - mean1 * mean1));
      double std2 = MathSqrt(MathMax(0, sumSq2 / n - mean2 * mean2));
      
      if(std1 <= 0 || std2 <= 0) return 0;
      return cov / (std1 * std2);
   }
   
   int FindSymbolIndex(string symbol) {
      for(int i = 0; i < g_SymbolCount; i++) {
         if(g_Symbols[i].name == symbol) return i;
      }
      return -1;
   }
};

#endif // __PHOENIX_CORRELATION_MATRIX_MQH__
