//+------------------------------------------------------------------+
//|                                          GeneticAllocator.mqh    |
//|                    PHOENIX EA — Genetic Strategy Allocator         |
//|                          Copyright 2026, Phoenix Trading Systems  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Trading Systems"
#property link      "https://github.com/phoenix-ea"
#property version   "1.00"
#property strict

#ifndef __PHOENIX_GENETIC_ALLOCATOR_MQH__
#define __PHOENIX_GENETIC_ALLOCATOR_MQH__

#include "..\Core\Defines.mqh"
#include "..\Core\Globals.mqh"

//+------------------------------------------------------------------+
//| Cromosoma: pesos de asignacion de capital por estrategia          |
//+------------------------------------------------------------------+
struct SChromosome
{
   double weights[MAX_STRATEGIES];  // Pesos normalizados (suman 1.0)
   double fitness;                  // Fitness score
   
   void Randomize()
   {
      double sum = 0;
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         weights[i] = MathRand() / 32767.0;
         sum += weights[i];
      }
      // Normalizar
      if(sum > 0)
         for(int i = 0; i < MAX_STRATEGIES; i++)
            weights[i] /= sum;
      fitness = 0;
   }
   
   void Normalize()
   {
      double sum = 0;
      for(int i = 0; i < MAX_STRATEGIES; i++)
         sum += weights[i];
      if(sum > 0)
         for(int i = 0; i < MAX_STRATEGIES; i++)
            weights[i] /= sum;
   }
};

//+------------------------------------------------------------------+
//| CGeneticAllocator — Optimizador genetico de asignacion de capital  |
//|                                                                   |
//| Evoluciona los pesos de capital asignados a cada sub-estrategia   |
//| usando un algoritmo genetico simple pero efectivo:                |
//| - Fitness = Sharpe ratio ponderado por expectancia                |
//| - Seleccion por torneo                                           |
//| - Crossover uniforme                                             |
//| - Mutacion gaussiana                                             |
//| - Elitismo (top 10% pasa directo)                                |
//+------------------------------------------------------------------+
class CGeneticAllocator
{
private:
   bool           m_initialized;
   int            m_populationSize;
   int            m_generations;
   double         m_mutationRate;
   double         m_crossoverRate;
   SChromosome    m_population[];
   SChromosome    m_bestEver;
   int            m_currentGeneration;
   datetime       m_lastOptimization;
   
   // Evaluar fitness de un cromosoma
   double EvaluateFitness(SChromosome &chrom)
   {
      double totalReturn = 0;
      double totalRisk   = 0;
      double weightedSharpe = 0;
      
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(chrom.weights[i] < 0.05) continue; // Ignorar pesos tiny
         if(!g_strategyMetrics[i].isActive) continue;
         if(g_strategyMetrics[i].totalTrades < 5) continue;
         
         double w = chrom.weights[i];
         
         // Penalizar estrategias con poco historial
         double dataPenalty = MathMin(1.0, g_strategyMetrics[i].totalTrades / 30.0);
         
         // Componentes de fitness
         totalReturn    += w * g_strategyMetrics[i].expectancy * dataPenalty;
         totalRisk      += w * g_strategyMetrics[i].maxDrawdown;
         weightedSharpe += w * g_strategyMetrics[i].sharpeRatio * dataPenalty;
      }
      
      // Fitness: maximizar retorno ajustado por riesgo
      double fitness = 0;
      if(totalRisk > 0)
         fitness = totalReturn / totalRisk; // Sortino-like ratio
      
      // Bonus por diversificacion (entropia de Shannon de los pesos)
      double entropy = 0;
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(chrom.weights[i] > 0.01)
            entropy -= chrom.weights[i] * MathLog(chrom.weights[i]);
      }
      fitness += entropy * 0.1; // 10% bonus por diversificacion
      
      // Bonus por Sharpe alto
      fitness += weightedSharpe * 0.3;
      
      chrom.fitness = fitness;
      return fitness;
   }
   
   // Seleccion por torneo
   int TournamentSelect(int tournamentSize = 3)
   {
      int best = MathRand() % m_populationSize;
      
      for(int i = 1; i < tournamentSize; i++)
      {
         int candidate = MathRand() % m_populationSize;
         if(m_population[candidate].fitness > m_population[best].fitness)
            best = candidate;
      }
      return best;
   }
   
   // Crossover uniforme
   SChromosome Crossover(SChromosome &parent1, SChromosome &parent2)
   {
      SChromosome child;
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(MathRand() / 32767.0 < 0.5)
            child.weights[i] = parent1.weights[i];
         else
            child.weights[i] = parent2.weights[i];
      }
      child.Normalize();
      child.fitness = 0;
      return child;
   }
   
   // Mutacion gaussiana
   void Mutate(SChromosome &chrom)
   {
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(MathRand() / 32767.0 < m_mutationRate)
         {
            // Perturbacion gaussiana
            double noise = (MathRand() / 32767.0 - 0.5) * 0.2;
            chrom.weights[i] = MathMax(0.0, chrom.weights[i] + noise);
         }
      }
      chrom.Normalize();
   }
   
public:
   CGeneticAllocator() : m_initialized(false), m_populationSize(50),
                          m_generations(30), m_mutationRate(0.15),
                          m_crossoverRate(0.7), m_currentGeneration(0),
                          m_lastOptimization(0) {}
   
   bool Init(int popSize = 50, int generations = 30)
   {
      m_populationSize = popSize;
      m_generations    = generations;
      
      ArrayResize(m_population, m_populationSize);
      
      // Inicializar poblacion aleatoria
      for(int i = 0; i < m_populationSize; i++)
         m_population[i].Randomize();
      
      // Primer individuo = pesos iguales (benchmark)
      for(int j = 0; j < MAX_STRATEGIES; j++)
         m_population[0].weights[j] = 1.0 / MAX_STRATEGIES;
      
      m_bestEver.Randomize();
      m_bestEver.fitness = -999999;
      
      m_initialized = true;
      g_logger.Info(StringFormat("GeneticAllocator: Init [pop=%d gen=%d mut=%.2f]",
                    popSize, generations, m_mutationRate));
      return true;
   }
   
   // Ejecutar optimizacion completa
   void Optimize()
   {
      if(!m_initialized) return;
      
      g_logger.Info("GeneticAllocator: Iniciando optimizacion...");
      
      // Evaluar poblacion inicial
      for(int i = 0; i < m_populationSize; i++)
         EvaluateFitness(m_population[i]);
      
      for(int gen = 0; gen < m_generations; gen++)
      {
         SChromosome newPop[];
         ArrayResize(newPop, m_populationSize);
         
         // Ordenar por fitness (descendente)
         for(int i = 0; i < m_populationSize - 1; i++)
            for(int j = i + 1; j < m_populationSize; j++)
               if(m_population[j].fitness > m_population[i].fitness)
               {
                  SChromosome temp = m_population[i];
                  m_population[i]  = m_population[j];
                  m_population[j]  = temp;
               }
         
         // Elitismo: top 10%
         int eliteCount = m_populationSize / 10;
         for(int i = 0; i < eliteCount; i++)
            newPop[i] = m_population[i];
         
         // Generar resto por crossover + mutacion
         for(int i = eliteCount; i < m_populationSize; i++)
         {
            if(MathRand() / 32767.0 < m_crossoverRate)
            {
               int p1 = TournamentSelect();
               int p2 = TournamentSelect();
               newPop[i] = Crossover(m_population[p1], m_population[p2]);
            }
            else
            {
               newPop[i] = m_population[TournamentSelect()];
            }
            Mutate(newPop[i]);
            EvaluateFitness(newPop[i]);
         }
         
         // Reemplazar poblacion
         ArrayCopy(m_population, newPop);
         m_currentGeneration = gen;
      }
      
      // Mejor individuo
      int bestIdx = 0;
      for(int i = 1; i < m_populationSize; i++)
         if(m_population[i].fitness > m_population[bestIdx].fitness)
            bestIdx = i;
      
      // Actualizar mejor historico
      if(m_population[bestIdx].fitness > m_bestEver.fitness)
         m_bestEver = m_population[bestIdx];
      
      // Aplicar pesos a las estrategias
      ApplyWeights(m_bestEver);
      
      m_lastOptimization = TimeCurrent();
      g_logger.Info(StringFormat("GeneticAllocator: Optimizacion completa fitness=%.4f", m_bestEver.fitness));
      
      // Log pesos
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         if(m_bestEver.weights[i] > 0.01)
            g_logger.Info(StringFormat("  Strategy %d: weight=%.1f%%", i, m_bestEver.weights[i] * 100));
      }
   }
   
   // Aplicar pesos optimizados a las metricas globales
   void ApplyWeights(const SChromosome &chrom)
   {
      for(int i = 0; i < MAX_STRATEGIES; i++)
      {
         g_strategyMetrics[i].allocationWeight = chrom.weights[i];
         // Desactivar estrategias con peso < 5%
         if(chrom.weights[i] < 0.05)
            g_strategyMetrics[i].isActive = false;
         else
            g_strategyMetrics[i].isActive = true;
      }
   }
   
   // Getters
   double   GetBestFitness()     const { return m_bestEver.fitness; }
   datetime GetLastOptimization() const { return m_lastOptimization; }
   bool     IsInitialized()      const { return m_initialized; }
   
   double GetWeight(int stratIndex) const
   {
      if(stratIndex >= 0 && stratIndex < MAX_STRATEGIES)
         return m_bestEver.weights[stratIndex];
      return 0.0;
   }
};

#endif // __PHOENIX_GENETIC_ALLOCATOR_MQH__
//+------------------------------------------------------------------+
