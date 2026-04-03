#ifndef __PHOENIX_GENETIC_ALLOCATOR_MQH__
#define __PHOENIX_GENETIC_ALLOCATOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Genetic Allocator — Evolves strategy allocation weights           |
//+------------------------------------------------------------------+
class CGeneticAllocator {
private:
   struct SChromosome {
      double weights[];
      double fitness;
   };
   
   SChromosome m_population[];
   int         m_popSize;
   int         m_generations;
   double      m_mutationRate;
   int         m_geneCount;      // Number of strategies
   double      m_bestWeights[];
   double      m_bestFitness;
   bool        m_hasRun;
   
public:
   CGeneticAllocator() : m_popSize(50), m_generations(30), m_mutationRate(0.15),
                          m_geneCount(0), m_bestFitness(-999), m_hasRun(false) {}
   
   void Init(int strategyCount) {
      m_geneCount = strategyCount;
      m_popSize = InpGAPopulation;
      m_generations = InpGAGenerations;
      m_mutationRate = InpGAMutation;
      ArrayResize(m_bestWeights, m_geneCount);
      
      // Start with equal weights
      for(int i = 0; i < m_geneCount; i++)
         m_bestWeights[i] = 1.0 / m_geneCount;
      
      if(g_Logger != NULL)
         g_Logger.Info(StringFormat("GeneticAllocator: Pop=%d Gen=%d Mut=%.2f Genes=%d",
            m_popSize, m_generations, m_mutationRate, m_geneCount));
   }
   
   // Run optimization using strategy metrics
   bool Optimize(SStrategyMetrics &metrics[]) {
      int metricCount = ArraySize(metrics);
      if(metricCount <= 0 || m_geneCount <= 0) return false;
      
      // Need minimum trades across strategies
      int totalTrades = 0;
      for(int i = 0; i < metricCount; i++) totalTrades += metrics[i].totalTrades;
      if(totalTrades < InpMinTradesOpt) return false;
      
      // Initialize population
      ArrayResize(m_population, m_popSize);
      for(int i = 0; i < m_popSize; i++) {
         ArrayResize(m_population[i].weights, m_geneCount);
         if(i == 0) {
            // First chromosome = current best
            for(int g = 0; g < m_geneCount; g++)
               m_population[i].weights[g] = m_bestWeights[g];
         } else {
            // Random initialization
            RandomWeights(m_population[i].weights);
         }
         m_population[i].fitness = EvaluateFitness(m_population[i].weights, metrics, metricCount);
      }
      
      // Evolution loop
      for(int gen = 0; gen < m_generations; gen++) {
         // Sort by fitness (descending)
         SortPopulation();
         
         // Create next generation
         SChromosome newPop[];
         ArrayResize(newPop, m_popSize);
         
         // Elitism: keep top 10%
         int eliteCount = MathMax(1, m_popSize / 10);
         for(int i = 0; i < eliteCount; i++) {
            ArrayResize(newPop[i].weights, m_geneCount);
            ArrayCopy(newPop[i].weights, m_population[i].weights);
            newPop[i].fitness = m_population[i].fitness;
         }
         
         // Crossover + Mutation for rest
         for(int i = eliteCount; i < m_popSize; i++) {
            ArrayResize(newPop[i].weights, m_geneCount);
            
            int parent1 = TournamentSelect(3);
            int parent2 = TournamentSelect(3);
            
            Crossover(m_population[parent1].weights, m_population[parent2].weights, newPop[i].weights);
            Mutate(newPop[i].weights);
            NormalizeWeights(newPop[i].weights);
            
            newPop[i].fitness = EvaluateFitness(newPop[i].weights, metrics, metricCount);
         }
         
         // Replace population
         ArrayResize(m_population, m_popSize);
         for(int i = 0; i < m_popSize; i++) {
            ArrayResize(m_population[i].weights, m_geneCount);
            ArrayCopy(m_population[i].weights, newPop[i].weights);
            m_population[i].fitness = newPop[i].fitness;
         }
      }
      
      // Get best
      SortPopulation();
      if(m_population[0].fitness > m_bestFitness) {
         m_bestFitness = m_population[0].fitness;
         ArrayCopy(m_bestWeights, m_population[0].weights);
         m_hasRun = true;
         
         if(g_Logger != NULL) {
            string weightStr = "";
            for(int i = 0; i < m_geneCount; i++)
               weightStr += StringFormat("%.3f ", m_bestWeights[i]);
            g_Logger.Info(StringFormat("GA Optimized: Fitness=%.4f Weights=[%s]", m_bestFitness, weightStr));
         }
      }
      
      return true;
   }
   
   void GetBestWeights(double &weights[]) {
      ArrayResize(weights, m_geneCount);
      ArrayCopy(weights, m_bestWeights);
   }
   
   double GetBestFitness() { return m_bestFitness; }
   bool   HasRun()         { return m_hasRun; }

private:
   double EvaluateFitness(double &weights[], SStrategyMetrics &metrics[], int count) {
      double weightedReturn = 0;
      double weightedRisk = 0;
      double entropy = 0;
      double weightedSharpe = 0;
      
      for(int i = 0; i < m_geneCount && i < count; i++) {
         double w = weights[i];
         if(w <= 0) continue;
         
         weightedReturn += w * metrics[i].expectancy;
         weightedRisk += w * metrics[i].maxDrawdownPct;
         weightedSharpe += w * metrics[i].sharpeRatio;
         
         if(w > 0.01)
            entropy -= w * MathLog(w);
      }
      
      // Fitness = risk-adjusted return + diversification bonus
      double riskAdjusted = (weightedRisk > 0) ? weightedReturn / weightedRisk : 0;
      double diversification = entropy / MathLog(MathMax(2, m_geneCount)); // Normalize to 0-1
      
      return riskAdjusted + diversification * 0.3 + weightedSharpe * 0.2;
   }
   
   void RandomWeights(double &weights[]) {
      double sum = 0;
      for(int i = 0; i < m_geneCount; i++) {
         weights[i] = MathRand() / 32767.0;
         sum += weights[i];
      }
      if(sum > 0) {
         for(int i = 0; i < m_geneCount; i++)
            weights[i] /= sum;
      }
   }
   
   void NormalizeWeights(double &weights[]) {
      double sum = 0;
      for(int i = 0; i < m_geneCount; i++) {
         weights[i] = MathMax(0.01, weights[i]); // Minimum 1%
         sum += weights[i];
      }
      if(sum > 0) {
         for(int i = 0; i < m_geneCount; i++)
            weights[i] /= sum;
      }
   }
   
   void Crossover(double &parent1[], double &parent2[], double &child[]) {
      // Blend crossover
      double alpha = MathRand() / 32767.0;
      for(int i = 0; i < m_geneCount; i++)
         child[i] = alpha * parent1[i] + (1.0 - alpha) * parent2[i];
   }
   
   void Mutate(double &weights[]) {
      for(int i = 0; i < m_geneCount; i++) {
         if(MathRand() / 32767.0 < m_mutationRate) {
            weights[i] += (MathRand() / 32767.0 - 0.5) * 0.3;
            weights[i] = MathMax(0, weights[i]);
         }
      }
   }
   
   int TournamentSelect(int tournSize) {
      int best = MathRand() % m_popSize;
      for(int i = 1; i < tournSize; i++) {
         int candidate = MathRand() % m_popSize;
         if(m_population[candidate].fitness > m_population[best].fitness)
            best = candidate;
      }
      return best;
   }
   
   void SortPopulation() {
      // Simple bubble sort by fitness descending
      for(int i = 0; i < m_popSize - 1; i++) {
         for(int j = 0; j < m_popSize - i - 1; j++) {
            if(m_population[j].fitness < m_population[j+1].fitness) {
               SChromosome temp;
               ArrayResize(temp.weights, m_geneCount);
               ArrayCopy(temp.weights, m_population[j].weights);
               temp.fitness = m_population[j].fitness;
               
               ArrayCopy(m_population[j].weights, m_population[j+1].weights);
               m_population[j].fitness = m_population[j+1].fitness;
               
               ArrayCopy(m_population[j+1].weights, temp.weights);
               m_population[j+1].fitness = temp.fitness;
            }
         }
      }
   }
};

#endif // __PHOENIX_GENETIC_ALLOCATOR_MQH__
