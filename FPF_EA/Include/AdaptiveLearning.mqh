//+------------------------------------------------------------------+
//| AdaptiveLearning.mqh                                               |
//| Advanced learning system that analyzes past trades and predicts    |
//| future market behavior with recursive self-improvement             |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Pattern Record for Learning                                        |
//+------------------------------------------------------------------+
struct PatternRecord {
   // Entry conditions
   double phi;
   double decPot;
   double mlProb;
   double atr;
   double rsi;
   double compression;
   double sweeps;
   double tfAlign;
   bool isTrending;
   bool highVol;
   int direction;
   int hour;

   // Outcome
   double profit;
   bool wasWin;
   double rMultiple;
   datetime entryTime;
};

//+------------------------------------------------------------------+
//| Rejected Trade Record (Learning from Rejections)                  |
//+------------------------------------------------------------------+
struct RejectedPattern {
   // Entry conditions (what was rejected)
   double phi;
   double mlProb;
   double compression;
   double sweeps;
   double tfAlign;
   double prediction;
   int hour;
   bool isTrending;
   bool highVol;
   int direction;
   datetime rejectionTime;

   // Why rejected
   string rejectionReason;
   bool failedPhi;
   bool failedML;
   bool failedPrediction;
   bool failedSignals;
   bool failedTime;
   bool failedCompliance;

   // What would have happened (simulated outcome)
   double simPrice;
   double simSL;
   double simTP;
   bool simulated;
   double wouldBeProfitPoints;
   bool wouldBeWin;
};

//+------------------------------------------------------------------+
//| Adaptive Learning Engine                                          |
//+------------------------------------------------------------------+
class AdaptiveLearningEngine
{
private:
   PatternRecord patterns[];
   int maxPatterns;

   // REJECTION LEARNING
   RejectedPattern rejectedPatterns[];
   int maxRejectedPatterns;
   int rejectionCount;
   int missedOpportunityCount;  // Rejected trades that would have won

   // Learned optimal ranges
   double optimal_phi_min;
   double optimal_phi_max;
   double optimal_mlProb_min;
   double optimal_atr_min;
   double optimal_atr_max;
   double optimal_compression_min;

   // Performance tracking
   double bestHourWinRates[24];
   double bestConditionWinRates[10];

   // Prediction models
   double phiWeights[6];        // Weights for phi components
   double signalWeights[5];     // Weights for signal scores
   double hourMultipliers[24];  // Time-based multipliers

   // Self-optimization
   bool learningEnabled;
   int minSampleSize;
   datetime lastOptimization;
   int optimizationInterval;

   // Prediction cache
   double lastPrediction;
   datetime lastPredictionTime;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                        |
   //+------------------------------------------------------------------+
   AdaptiveLearningEngine()
   {
      maxPatterns = 500;
      ArrayResize(patterns, 0);

      // Initialize rejection tracking
      maxRejectedPatterns = 200;
      ArrayResize(rejectedPatterns, 0);
      rejectionCount = 0;
      missedOpportunityCount = 0;

      // Initialize defaults
      optimal_phi_min = 0.08;
      optimal_phi_max = 0.50;
      optimal_mlProb_min = 0.65;
      optimal_atr_min = 0.0;
      optimal_atr_max = 999999;
      optimal_compression_min = 0.20;

      // Initialize arrays
      ArrayInitialize(bestHourWinRates, 0.5);
      ArrayInitialize(bestConditionWinRates, 0.5);
      ArrayInitialize(phiWeights, 0.16667); // Equal weights initially
      ArrayInitialize(signalWeights, 0.20);  // Equal weights
      ArrayInitialize(hourMultipliers, 1.0);

      learningEnabled = true;
      minSampleSize = 20;
      optimizationInterval = 3600; // Optimize every hour
      lastOptimization = TimeCurrent();
      lastPrediction = 0.5;
      lastPredictionTime = 0;
   }

   //+------------------------------------------------------------------+
   //| Record trade pattern and outcome                                  |
   //+------------------------------------------------------------------+
   void RecordPattern(double phi, double decPot, double mlProb, double atr,
                      double rsi, double comp, double sweep, double tfAlign,
                      bool trending, bool highVol, int dir, int hour,
                      double profit, double rMult, datetime entryTime)
   {
      int size = ArraySize(patterns);

      // Maintain max size
      if(size >= maxPatterns)
      {
         // Remove oldest 10%
         int removeCount = (int)(maxPatterns * 0.10);
         for(int i = 0; i < size - removeCount; i++)
         {
            patterns[i] = patterns[i + removeCount];
         }
         size = size - removeCount;
      }

      ArrayResize(patterns, size + 1);

      patterns[size].phi = phi;
      patterns[size].decPot = decPot;
      patterns[size].mlProb = mlProb;
      patterns[size].atr = atr;
      patterns[size].rsi = rsi;
      patterns[size].compression = comp;
      patterns[size].sweeps = sweep;
      patterns[size].tfAlign = tfAlign;
      patterns[size].isTrending = trending;
      patterns[size].highVol = highVol;
      patterns[size].direction = dir;
      patterns[size].hour = hour;
      patterns[size].profit = profit;
      patterns[size].wasWin = (profit > 0);
      patterns[size].rMultiple = rMult;
      patterns[size].entryTime = entryTime;

      // Trigger learning if enough new data
      if(size >= minSampleSize && size % 10 == 0)
      {
         LearnFromPatterns();
      }
   }

   //+------------------------------------------------------------------+
   //| Record rejected trade opportunity (LEARNING FROM REJECTIONS)     |
   //+------------------------------------------------------------------+
   void RecordRejection(double phi, double mlProb, double comp, double sweep,
                        double tfAlign, double prediction, int hour,
                        bool trending, bool highVol, int direction,
                        string reason, bool failedPhi, bool failedML,
                        bool failedPrediction, bool failedSignals,
                        bool failedTime, bool failedCompliance,
                        double priceAtRejection = 0) // Add price parameter
   {
      int size = ArraySize(rejectedPatterns);

      // Maintain max size
      if(size >= maxRejectedPatterns)
      {
         // Remove oldest 10%
         int removeCount = (int)(maxRejectedPatterns * 0.10);
         for(int i = 0; i < size - removeCount; i++)
         {
            rejectedPatterns[i] = rejectedPatterns[i + removeCount];
         }
         size = size - removeCount;
      }

      ArrayResize(rejectedPatterns, size + 1);

      rejectedPatterns[size].phi = phi;
      rejectedPatterns[size].mlProb = mlProb;
      rejectedPatterns[size].compression = comp;
      rejectedPatterns[size].sweeps = sweep;
      rejectedPatterns[size].tfAlign = tfAlign;
      rejectedPatterns[size].prediction = prediction;
      rejectedPatterns[size].hour = hour;
      rejectedPatterns[size].isTrending = trending;
      rejectedPatterns[size].highVol = highVol;
      rejectedPatterns[size].direction = direction;
      rejectedPatterns[size].rejectionTime = TimeCurrent();
      rejectedPatterns[size].rejectionReason = reason;
      rejectedPatterns[size].failedPhi = failedPhi;
      rejectedPatterns[size].failedML = failedML;
      rejectedPatterns[size].failedPrediction = failedPrediction;
      rejectedPatterns[size].failedSignals = failedSignals;
      rejectedPatterns[size].failedTime = failedTime;
      rejectedPatterns[size].failedCompliance = failedCompliance;
      rejectedPatterns[size].simPrice = priceAtRejection; // Store price for simulation
      rejectedPatterns[size].simulated = false;

      rejectionCount++;

      // Debug output (if enabled externally)
      if(learningEnabled)
         Print("📊 REJECTION RECORDED: ", reason, " | Phi: ", phi, " ML: ", mlProb, " Pred: ", prediction);
   }

   //+------------------------------------------------------------------+
   //| Simulate what would have happened if rejected trade was taken    |
   //+------------------------------------------------------------------+
   void SimulateRejectedOutcome(int rejectedIndex, double currentPrice,
                                double atrValue, int barsSinceRejection)
   {
      if(rejectedIndex < 0 || rejectedIndex >= ArraySize(rejectedPatterns))
         return;

      if(rejectedPatterns[rejectedIndex].simulated)
         return; // Already simulated

      // Simulate SL/TP based on what would have been used
      double slDistance = atrValue * 2.0; // ATR_SL_Multiplier from main EA
      double tpDistance = slDistance * 3.0; // Base_TP_Multiplier

      double simPrice = rejectedPatterns[rejectedIndex].simPrice;
      if(simPrice == 0) return; // No price recorded

      int dir = rejectedPatterns[rejectedIndex].direction;

      double simSL, simTP;
      if(dir > 0) // Would have been BUY
      {
         simSL = simPrice - slDistance;
         simTP = simPrice + tpDistance;

         // Check if current price hit SL or TP
         if(currentPrice <= simSL)
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = -slDistance;
            rejectedPatterns[rejectedIndex].wouldBeWin = false;
         }
         else if(currentPrice >= simTP)
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = tpDistance;
            rejectedPatterns[rejectedIndex].wouldBeWin = true;
            missedOpportunityCount++; // We rejected a winner!
         }
         else if(barsSinceRejection > 50) // Timeout
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = currentPrice - simPrice;
            rejectedPatterns[rejectedIndex].wouldBeWin = (currentPrice > simPrice);
            if(rejectedPatterns[rejectedIndex].wouldBeWin)
               missedOpportunityCount++;
         }
         else
         {
            return; // Still open, don't mark simulated yet
         }
      }
      else // Would have been SELL
      {
         simSL = simPrice + slDistance;
         simTP = simPrice - tpDistance;

         if(currentPrice >= simSL)
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = -slDistance;
            rejectedPatterns[rejectedIndex].wouldBeWin = false;
         }
         else if(currentPrice <= simTP)
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = tpDistance;
            rejectedPatterns[rejectedIndex].wouldBeWin = true;
            missedOpportunityCount++;
         }
         else if(barsSinceRejection > 50)
         {
            rejectedPatterns[rejectedIndex].wouldBeProfitPoints = simPrice - currentPrice;
            rejectedPatterns[rejectedIndex].wouldBeWin = (currentPrice < simPrice);
            if(rejectedPatterns[rejectedIndex].wouldBeWin)
               missedOpportunityCount++;
         }
         else
         {
            return;
         }
      }

      rejectedPatterns[rejectedIndex].simulated = true;

      // Debug output for missed opportunities
      if(rejectedPatterns[rejectedIndex].wouldBeWin)
      {
         Print("⚠️ MISSED OPPORTUNITY: Rejected trade would have WON +",
               rejectedPatterns[rejectedIndex].wouldBeProfitPoints,
               " points | Reason: ", rejectedPatterns[rejectedIndex].rejectionReason);
      }
   }

   //+------------------------------------------------------------------+
   //| Analyze rejections to optimize thresholds                        |
   //+------------------------------------------------------------------+
   void AnalyzeRejections()
   {
      int rejSize = ArraySize(rejectedPatterns);
      if(rejSize < 10) return; // Need minimum rejections

      int simulatedCount = 0;
      int missedWins = 0;
      int correctRejectionsCount = 0;

      // Count simulated outcomes
      for(int i = 0; i < rejSize; i++)
      {
         if(rejectedPatterns[i].simulated)
         {
            simulatedCount++;
            if(rejectedPatterns[i].wouldBeWin)
               missedWins++;
            else
               correctRejectionsCount++;
         }
      }

      if(simulatedCount < 10) return;

      double missedWinRate = (double)missedWins / simulatedCount;

      Print("REJECTION ANALYSIS:");
      Print("  Total Rejections: ", rejectionCount);
      Print("  Simulated Outcomes: ", simulatedCount);
      Print("  Missed Winners: ", missedWins, " (", DoubleToString(missedWinRate * 100, 1), "%)");
      Print("  Correct Rejections: ", correctRejectionsCount);

      // If missing too many winning trades, relax thresholds
      if(missedWinRate > 0.40) // Missing 40%+ winners
      {
         Print("⚠️ WARNING: Too restrictive! Missing ", DoubleToString(missedWinRate * 100, 1), "% of winning opportunities");
         Print("  RELAXING THRESHOLDS...");

         // Analyze which filter is rejecting too much
         int phiRejects = 0, mlRejects = 0, predRejects = 0, signalRejects = 0;
         int timeRejects = 0, complianceRejects = 0;

         for(int i = 0; i < rejSize; i++)
         {
            if(rejectedPatterns[i].simulated && rejectedPatterns[i].wouldBeWin)
            {
               if(rejectedPatterns[i].failedPhi) phiRejects++;
               if(rejectedPatterns[i].failedML) mlRejects++;
               if(rejectedPatterns[i].failedPrediction) predRejects++;
               if(rejectedPatterns[i].failedSignals) signalRejects++;
               if(rejectedPatterns[i].failedTime) timeRejects++;
               if(rejectedPatterns[i].failedCompliance) complianceRejects++;
            }
         }

         // Relax the most problematic filter
         if(phiRejects > missedWins * 0.3)
         {
            optimal_phi_min *= 0.90; // Reduce by 10%
            Print("  ↓ Phi threshold reduced to: ", optimal_phi_min);
         }
         if(mlRejects > missedWins * 0.3)
         {
            optimal_mlProb_min *= 0.95; // Reduce by 5%
            Print("  ↓ ML Prob threshold reduced to: ", optimal_mlProb_min);
         }
         if(predRejects > missedWins * 0.3)
         {
            Print("  ⚠️ Prediction model too conservative (rejecting ", predRejects, " winners)");
         }
         if(signalRejects > missedWins * 0.3)
         {
            optimal_compression_min *= 0.90;
            Print("  ↓ Signal thresholds relaxed");
         }
         if(timeRejects > missedWins * 0.3)
         {
            Print("  ⚠️ Time filter rejecting ", timeRejects, " winners - consider expanding hours");
         }
         if(complianceRejects > missedWins * 0.3)
         {
            Print("  ⚠️ Compliance rules rejecting ", complianceRejects, " winners");
         }
      }
      else if(missedWinRate < 0.20) // Only missing <20% winners
      {
         Print("✅ GOOD: Rejection filters are working well (only ", DoubleToString(missedWinRate * 100, 1), "% missed)");
      }
   }

   //+------------------------------------------------------------------+
   //| Learn from historical patterns                                    |
   //+------------------------------------------------------------------+
   void LearnFromPatterns()
   {
      if(!learningEnabled) return;

      int size = ArraySize(patterns);
      if(size < minSampleSize)
      {
         Print("LEARNING: Insufficient data (", size, " < ", minSampleSize, ")");
         return;
      }

      Print("LEARNING: Analyzing ", size, " patterns for optimization...");

      // Learn 1: Optimal hour distribution
      LearnOptimalHours();

      // Learn 2: Optimal entry conditions
      LearnOptimalConditions();

      // Learn 3: Optimize signal weights
      OptimizeSignalWeights();

      // Learn 4: Update prediction model
      UpdatePredictionModel();

      // Learn 5: Analyze rejections (learn why not trading)
      AnalyzeRejections();

      lastOptimization = TimeCurrent();

      Print("LEARNING: Optimization complete");
      PrintLearnings();
   }

   //+------------------------------------------------------------------+
   //| Learn which hours perform best                                    |
   //+------------------------------------------------------------------+
   void LearnOptimalHours()
   {
      int hourCounts[24];
      int hourWins[24];
      ArrayInitialize(hourCounts, 0);
      ArrayInitialize(hourWins, 0);

      int size = ArraySize(patterns);
      for(int i = 0; i < size; i++)
      {
         int h = patterns[i].hour;
         if(h >= 0 && h < 24)
         {
            hourCounts[h]++;
            if(patterns[i].wasWin) hourWins[h]++;
         }
      }

      // Calculate win rates
      for(int h = 0; h < 24; h++)
      {
         if(hourCounts[h] >= 5) // Need minimum samples
         {
            bestHourWinRates[h] = (double)hourWins[h] / hourCounts[h];

            // Set multiplier based on performance
            if(bestHourWinRates[h] > 0.65)
               hourMultipliers[h] = 1.20; // Boost good hours
            else if(bestHourWinRates[h] > 0.55)
               hourMultipliers[h] = 1.10;
            else if(bestHourWinRates[h] < 0.45)
               hourMultipliers[h] = 0.80; // Penalize bad hours
            else if(bestHourWinRates[h] < 0.35)
               hourMultipliers[h] = 0.60;
            else
               hourMultipliers[h] = 1.00;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Learn optimal entry conditions                                    |
   //+------------------------------------------------------------------+
   void LearnOptimalConditions()
   {
      int size = ArraySize(patterns);

      // Find optimal phi range
      double winningPhis[];
      ArrayResize(winningPhis, 0);

      for(int i = 0; i < size; i++)
      {
         if(patterns[i].wasWin)
         {
            int idx = ArraySize(winningPhis);
            ArrayResize(winningPhis, idx + 1);
            winningPhis[idx] = patterns[i].phi;
         }
      }

      if(ArraySize(winningPhis) >= 10)
      {
         // Sort and find 25th-75th percentile
         ArraySort(winningPhis);
         int count = ArraySize(winningPhis);
         optimal_phi_min = winningPhis[(int)(count * 0.25)];
         optimal_phi_max = winningPhis[(int)(count * 0.75)];
      }

      // Find optimal ML probability minimum
      double winningMLProbs[];
      ArrayResize(winningMLProbs, 0);

      for(int i = 0; i < size; i++)
      {
         if(patterns[i].wasWin)
         {
            int idx = ArraySize(winningMLProbs);
            ArrayResize(winningMLProbs, idx + 1);
            winningMLProbs[idx] = patterns[i].mlProb;
         }
      }

      if(ArraySize(winningMLProbs) >= 10)
      {
         ArraySort(winningMLProbs);
         optimal_mlProb_min = winningMLProbs[(int)(ArraySize(winningMLProbs) * 0.20)];
      }

      // Find optimal compression minimum
      double winningCompression[];
      ArrayResize(winningCompression, 0);

      for(int i = 0; i < size; i++)
      {
         if(patterns[i].wasWin && patterns[i].compression > 0)
         {
            int idx = ArraySize(winningCompression);
            ArrayResize(winningCompression, idx + 1);
            winningCompression[idx] = patterns[i].compression;
         }
      }

      if(ArraySize(winningCompression) >= 10)
      {
         ArraySort(winningCompression);
         optimal_compression_min = winningCompression[(int)(ArraySize(winningCompression) * 0.30)];
      }
   }

   //+------------------------------------------------------------------+
   //| Optimize signal weights based on correlation with wins            |
   //+------------------------------------------------------------------+
   void OptimizeSignalWeights()
   {
      int size = ArraySize(patterns);
      if(size < minSampleSize) return;

      // Calculate correlation between each signal and winning
      double compWinAvg = 0, compLossAvg = 0;
      double sweepWinAvg = 0, sweepLossAvg = 0;
      double tfAlignWinAvg = 0, tfAlignLossAvg = 0;

      int winCount = 0, lossCount = 0;

      for(int i = 0; i < size; i++)
      {
         if(patterns[i].wasWin)
         {
            compWinAvg += patterns[i].compression;
            sweepWinAvg += patterns[i].sweeps;
            tfAlignWinAvg += patterns[i].tfAlign;
            winCount++;
         }
         else
         {
            compLossAvg += patterns[i].compression;
            sweepLossAvg += patterns[i].sweeps;
            tfAlignLossAvg += patterns[i].tfAlign;
            lossCount++;
         }
      }

      if(winCount > 0 && lossCount > 0)
      {
         compWinAvg /= winCount;
         compLossAvg /= lossCount;
         sweepWinAvg /= winCount;
         sweepLossAvg /= lossCount;
         tfAlignWinAvg /= winCount;
         tfAlignLossAvg /= lossCount;

         // Calculate differential (higher = better predictor)
         double compDiff = MathAbs(compWinAvg - compLossAvg);
         double sweepDiff = MathAbs(sweepWinAvg - sweepLossAvg);
         double tfAlignDiff = MathAbs(tfAlignWinAvg - tfAlignLossAvg);

         double totalDiff = compDiff + sweepDiff + tfAlignDiff;

         if(totalDiff > 0)
         {
            // Redistribute weights based on predictive power
            signalWeights[0] = compDiff / totalDiff * 0.6;     // Compression
            signalWeights[1] = sweepDiff / totalDiff * 0.25;   // Sweeps
            signalWeights[2] = tfAlignDiff / totalDiff * 0.15; // TF Align
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Update prediction model based on recent performance               |
   //+------------------------------------------------------------------+
   void UpdatePredictionModel()
   {
      // This would implement more sophisticated ML here
      // For now, just update based on recent win rate trends

      int size = ArraySize(patterns);
      if(size < minSampleSize) return;

      // Look at last 50 trades
      int lookback = MathMin(50, size);
      int recentWins = 0;

      for(int i = size - lookback; i < size; i++)
      {
         if(patterns[i].wasWin) recentWins++;
      }

      double recentWinRate = (double)recentWins / lookback;

      // Adjust thresholds based on recent performance
      if(recentWinRate > 0.65)
      {
         // Performing well, can relax thresholds slightly
         optimal_phi_min *= 0.98;
         optimal_mlProb_min *= 0.98;
      }
      else if(recentWinRate < 0.45)
      {
         // Performing poorly, tighten thresholds
         optimal_phi_min *= 1.05;
         optimal_mlProb_min *= 1.05;
      }

      // Keep in reasonable bounds
      if(optimal_phi_min < 0.05) optimal_phi_min = 0.05;
      if(optimal_phi_min > 0.15) optimal_phi_min = 0.15;
      if(optimal_mlProb_min < 0.60) optimal_mlProb_min = 0.60;
      if(optimal_mlProb_min > 0.75) optimal_mlProb_min = 0.75;
   }

   //+------------------------------------------------------------------+
   //| Predict success probability for current conditions                |
   //+------------------------------------------------------------------+
   double PredictSuccessProbability(double phi, double mlProb, double comp,
                                    double sweep, double tfAlign, int hour,
                                    bool trending, bool highVol)
   {
      // Cache prediction for same tick
      datetime now = TimeCurrent();
      if(now == lastPredictionTime)
         return lastPrediction;

      int size = ArraySize(patterns);
      if(size < minSampleSize)
      {
         // Not enough data, return conservative estimate
         lastPrediction = 0.55;
         lastPredictionTime = now;
         return 0.55;
      }

      double baseProbability = 0.50;

      // Factor 1: Phi similarity
      int phiMatches = 0, phiWins = 0;
      for(int i = 0; i < size; i++)
      {
         if(MathAbs(patterns[i].phi - phi) < 0.03) // Similar phi
         {
            phiMatches++;
            if(patterns[i].wasWin) phiWins++;
         }
      }
      if(phiMatches >= 5)
         baseProbability += ((double)phiWins / phiMatches - 0.5) * 0.15;

      // Factor 2: ML probability similarity
      int mlMatches = 0, mlWins = 0;
      for(int i = 0; i < size; i++)
      {
         if(MathAbs(patterns[i].mlProb - mlProb) < 0.05)
         {
            mlMatches++;
            if(patterns[i].wasWin) mlWins++;
         }
      }
      if(mlMatches >= 5)
         baseProbability += ((double)mlWins / mlMatches - 0.5) * 0.15;

      // Factor 3: Hour performance
      if(hour >= 0 && hour < 24)
         baseProbability *= hourMultipliers[hour];

      // Factor 4: Market regime
      int regimeMatches = 0, regimeWins = 0;
      for(int i = 0; i < size; i++)
      {
         if(patterns[i].isTrending == trending)
         {
            regimeMatches++;
            if(patterns[i].wasWin) regimeWins++;
         }
      }
      if(regimeMatches >= 10)
         baseProbability += ((double)regimeWins / regimeMatches - 0.5) * 0.10;

      // Factor 5: Signal strength combination
      double signalScore = comp * signalWeights[0] +
                          sweep * signalWeights[1] +
                          tfAlign * signalWeights[2];
      baseProbability += (signalScore - 0.5) * 0.10;

      // Clamp to valid range
      if(baseProbability > 0.95) baseProbability = 0.95;
      if(baseProbability < 0.20) baseProbability = 0.20;

      lastPrediction = baseProbability;
      lastPredictionTime = now;

      return baseProbability;
   }

   //+------------------------------------------------------------------+
   //| Get learned optimal parameters                                    |
   //+------------------------------------------------------------------+
   double GetOptimalPhiMin() { return optimal_phi_min; }
   double GetOptimalMLProbMin() { return optimal_mlProb_min; }
   double GetOptimalCompressionMin() { return optimal_compression_min; }
   double GetHourMultiplier(int hour)
   {
      if(hour >= 0 && hour < 24)
         return hourMultipliers[hour];
      return 1.0;
   }

   //+------------------------------------------------------------------+
   //| Check if should take trade based on learned patterns              |
   //+------------------------------------------------------------------+
   bool ShouldTakeTrade(double phi, double mlProb, double prediction)
   {
      int size = ArraySize(patterns);
      if(size < minSampleSize)
         return true; // Not enough data, use default logic

      // Use learned thresholds
      if(phi < optimal_phi_min * 0.95) return false; // Buffer
      if(mlProb < optimal_mlProb_min * 0.95) return false;
      if(prediction < 0.55) return false; // Prediction too low

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get performance statistics                                        |
   //+------------------------------------------------------------------+
   void GetStats(int &totalPatterns, double &avgWinRate, double &avgRMult)
   {
      int size = ArraySize(patterns);
      totalPatterns = size;

      if(size == 0)
      {
         avgWinRate = 0;
         avgRMult = 0;
         return;
      }

      int wins = 0;
      double totalR = 0;

      for(int i = 0; i < size; i++)
      {
         if(patterns[i].wasWin) wins++;
         totalR += patterns[i].rMultiple;
      }

      avgWinRate = (double)wins / size * 100.0;
      avgRMult = totalR / size;
   }

   //+------------------------------------------------------------------+
   //| Print learning insights                                           |
   //+------------------------------------------------------------------+
   void PrintLearnings()
   {
      Print("=== LEARNED PARAMETERS ===");
      Print("Optimal Phi Min: ", optimal_phi_min);
      Print("Optimal ML Prob Min: ", optimal_mlProb_min);
      Print("Optimal Compression Min: ", optimal_compression_min);

      Print("Best Hours: ");
      for(int h = 0; h < 24; h++)
      {
         if(hourMultipliers[h] > 1.05)
            Print("  Hour ", h, ": ", DoubleToString(bestHourWinRates[h] * 100, 1),
                  "% win rate (mult: ", DoubleToString(hourMultipliers[h], 2), ")");
      }
   }

   //+------------------------------------------------------------------+
   //| Generate learning report                                          |
   //+------------------------------------------------------------------+
   string GenerateReport()
   {
      int total;
      double winRate, avgR;
      GetStats(total, winRate, avgR);

      string report = "\n=== ADAPTIVE LEARNING REPORT ===\n";
      report += "Patterns Analyzed: " + IntegerToString(total) + "\n";
      report += "Overall Win Rate: " + DoubleToString(winRate, 2) + "%\n";
      report += "Avg R-Multiple: " + DoubleToString(avgR, 2) + "\n";
      report += "---\n";
      report += "Learned Optimal Thresholds:\n";
      report += "  Phi Min: " + DoubleToString(optimal_phi_min, 3) + "\n";
      report += "  ML Prob Min: " + DoubleToString(optimal_mlProb_min, 3) + "\n";
      report += "  Compression Min: " + DoubleToString(optimal_compression_min, 3) + "\n";
      report += "---\n";
      report += "Last Optimization: " + TimeToString(lastOptimization) + "\n";
      report += "Learning Enabled: " + (learningEnabled ? "YES" : "NO") + "\n";

      return report;
   }

   //+------------------------------------------------------------------+
   //| Get rejection statistics                                          |
   //+------------------------------------------------------------------+
   void GetRejectionStats(int &totalRej, int &missedOpp, double &missedRate)
   {
      totalRej = rejectionCount;
      missedOpp = missedOpportunityCount;

      int simulatedCount = 0;
      int rejSize = ArraySize(rejectedPatterns);
      for(int i = 0; i < rejSize; i++)
      {
         if(rejectedPatterns[i].simulated)
            simulatedCount++;
      }

      if(simulatedCount > 0)
         missedRate = (double)missedOpportunityCount / simulatedCount * 100.0;
      else
         missedRate = 0;
   }

   //+------------------------------------------------------------------+
   //| Enable/disable learning                                           |
   //+------------------------------------------------------------------+
   void SetLearningEnabled(bool enabled) { learningEnabled = enabled; }
   bool IsLearningEnabled() { return learningEnabled; }

   int GetRejectionCount() { return rejectionCount; }
   int GetMissedOpportunityCount() { return missedOpportunityCount; }
};
