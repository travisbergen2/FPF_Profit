//+------------------------------------------------------------------+
//| BarMetaLearner.mqh                                                 |
//| The Intuition Layer: Learns which bar fingerprints predict profit |
//| Builds pattern memory and predicts bar-level outcomes             |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"

//+------------------------------------------------------------------+
//| ContextStats: Per-context learning memory                         |
//| Tracks outcomes for each bar fingerprint pattern                  |
//+------------------------------------------------------------------+
struct ContextStats
{
   double totalR;          // cumulative R-multiple
   int    trades;          // number of samples
   double ewmaR;           // exponential moving average R
   double sumR2;           // sum of squared R (for variance)
};

//+------------------------------------------------------------------+
//| BarMetaLearner: Pattern memory and intuition                      |
//| "When I felt this kind of bar before, what happened next?"        |
//+------------------------------------------------------------------+
class BarMetaLearner
{
private:
   // Simple context mapping: key -> stats
   // Using parallel arrays for MQL5 compatibility
   long               m_keys[];          // encoded context keys
   ContextStats       m_stats[];         // stats for each context
   int                m_numContexts;     // number of learned contexts

   // Learning parameters
   int                m_minSamples;      // min trades before trusting context
   double             m_emaAlpha;        // smoothing for EWMA

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   BarMetaLearner(int minSamples = 30, double emaAlpha = 0.1)
   {
      m_minSamples = minSamples;
      m_emaAlpha = emaAlpha;
      m_numContexts = 0;

      ArrayResize(m_keys, 0);
      ArrayResize(m_stats, 0);
   }

   //+------------------------------------------------------------------+
   //| Update: Learn from a realized trade outcome                      |
   //| Feeds the meta-learner's pattern memory                          |
   //+------------------------------------------------------------------+
   void Update(const TradeOutcome &outcome)
   {
      // Encode the entry bar into a context key
      long key = EncodeContext(outcome.entry_bar);

      // Find or create context
      int idx = FindContext(key);
      if(idx < 0)
      {
         idx = CreateContext(key);
      }

      // Update statistics
      m_stats[idx].totalR += outcome.R_multiple;
      m_stats[idx].trades++;
      m_stats[idx].sumR2 += outcome.R_multiple * outcome.R_multiple;

      // Update EWMA
      if(m_stats[idx].trades == 1)
      {
         m_stats[idx].ewmaR = outcome.R_multiple;
      }
      else
      {
         m_stats[idx].ewmaR = m_emaAlpha * outcome.R_multiple +
                              (1.0 - m_emaAlpha) * m_stats[idx].ewmaR;
      }
   }

   //+------------------------------------------------------------------+
   //| Predict: Generate bar-level prediction for next bar              |
   //| Given last bar's fingerprint, what is likely to happen?          |
   //+------------------------------------------------------------------+
   PredictionResult Predict(const BarSummary &bar) const
   {
      PredictionResult pred;
      pred.prob_up = 0.5;
      pred.prob_down = 0.5;
      pred.prob_big_move = 0.3;
      pred.expected_R_long = 0.0;
      pred.expected_R_short = 0.0;
      pred.confidence = 0.0;

      // Encode bar into context
      long key = EncodeContext(bar);

      // Find matching context
      int idx = FindContext(key);
      if(idx < 0)
      {
         // No experience with this pattern - return neutral
         return pred;
      }

      // Check if we have enough samples
      if(m_stats[idx].trades < m_minSamples)
      {
         pred.confidence = (double)m_stats[idx].trades / m_minSamples;
         return pred;
      }

      // We have learned this pattern - use EWMA R
      double ewma = m_stats[idx].ewmaR;
      int trades = m_stats[idx].trades;

      // Map EWMA to directional probabilities
      // Simple sigmoid-like mapping
      if(ewma > 0.0)
      {
         pred.expected_R_long = ewma;
         pred.expected_R_short = -ewma * 0.5;
         pred.prob_up = MathMin(0.5 + ewma * 0.2, 0.9);
         pred.prob_down = 1.0 - pred.prob_up;
      }
      else
      {
         pred.expected_R_short = -ewma;
         pred.expected_R_long = ewma * 0.5;
         pred.prob_down = MathMin(0.5 - ewma * 0.2, 0.9);
         pred.prob_up = 1.0 - pred.prob_down;
      }

      // Big move probability based on variance
      double variance = 0.0;
      if(trades > 1)
      {
         double meanR = m_stats[idx].totalR / trades;
         variance = (m_stats[idx].sumR2 / trades) - (meanR * meanR);
      }
      pred.prob_big_move = MathMin(MathSqrt(MathAbs(variance)) / 2.0, 0.9);

      // Confidence based on sample size and consistency
      double sample_confidence = MathMin((double)trades / (m_minSamples * 3), 1.0);
      double consistency = 1.0 / (1.0 + MathSqrt(MathAbs(variance)));
      pred.confidence = sample_confidence * consistency;

      return pred;
   }

   //+------------------------------------------------------------------+
   //| GetContextCount: Number of learned patterns                      |
   //+------------------------------------------------------------------+
   int GetContextCount() const { return m_numContexts; }

private:
   //+------------------------------------------------------------------+
   //| EncodeContext: Simple bar fingerprint encoding                   |
   //| Discretizes key features into buckets -> single integer key      |
   //| START SIMPLE: You can iterate on this encoding after backtests   |
   //+------------------------------------------------------------------+
   long EncodeContext(const BarSummary &bar) const
   {
      // Simple encoding: discretize 5 key features

      // 1) Compression mean: 0=low (<0.3), 1=medium (0.3-0.6), 2=high (>0.6)
      int comp_bucket = 0;
      if(bar.compression_mean >= 0.6) comp_bucket = 2;
      else if(bar.compression_mean >= 0.3) comp_bucket = 1;

      // 2) Sweep mean: 0=absent (<0.3), 1=present (>=0.3)
      int sweep_bucket = (bar.sweep_mean >= 0.3) ? 1 : 0;

      // 3) Freeze slope: 0=falling (<0), 1=rising (>=0)
      int freeze_bucket = (bar.freeze_slope >= 0.0) ? 1 : 0;

      // 4) TF alignment mean: 0=weak (<0.5), 1=strong (>=0.5)
      int align_bucket = (bar.tfalign_mean >= 0.5) ? 1 : 0;

      // 5) Regime volatility: 0=low (<0.8), 1=normal (0.8-1.2), 2=high (>1.2)
      int regime_bucket = 1;
      if(bar.regime_vol < 0.8) regime_bucket = 0;
      else if(bar.regime_vol > 1.2) regime_bucket = 2;

      // Combine into single key
      // key = comp + 3*sweep + 6*freeze + 12*align + 24*regime
      long key = comp_bucket +
                 3 * sweep_bucket +
                 6 * freeze_bucket +
                 12 * align_bucket +
                 24 * regime_bucket;

      return key;
   }

   //+------------------------------------------------------------------+
   //| FindContext: Locate existing context by key                      |
   //+------------------------------------------------------------------+
   int FindContext(long key) const
   {
      for(int i = 0; i < m_numContexts; i++)
      {
         if(m_keys[i] == key)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| CreateContext: Add new context to memory                         |
   //+------------------------------------------------------------------+
   int CreateContext(long key)
   {
      int newSize = m_numContexts + 1;
      ArrayResize(m_keys, newSize);
      ArrayResize(m_stats, newSize);

      m_keys[m_numContexts] = key;
      m_stats[m_numContexts].totalR = 0.0;
      m_stats[m_numContexts].trades = 0;
      m_stats[m_numContexts].ewmaR = 0.0;
      m_stats[m_numContexts].sumR2 = 0.0;

      m_numContexts++;
      return m_numContexts - 1;
   }
};
