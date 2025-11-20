//+------------------------------------------------------------------+
//| TickFieldAccumulator.mqh                                           |
//| The Nervous System: Processes every tick and accumulates signals  |
//| Feels the microstructure and builds bar-level memory fingerprints |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "BigMoveSignals.mqh"

//+------------------------------------------------------------------+
//| TickFieldAccumulator: Continuous sensory processing               |
//| Every tick is a nerve signal - compression, sweeps, hunts, etc.   |
//+------------------------------------------------------------------+
class TickFieldAccumulator
{
private:
   string                 m_symbol;
   ENUM_TIMEFRAMES        m_tf;
   datetime               m_currentBarTime;
   long                   m_tickVolume;

   // OHLC for current bar
   double                 m_open, m_high, m_low, m_close;

   // Running accumulations for each signal (0..1 scores)
   int                    m_tickCount;
   double                 m_comp_sum, m_comp_max, m_comp_last;
   double                 m_sweep_sum, m_sweep_max, m_sweep_last;
   double                 m_spread_sum, m_spread_max;
   double                 m_stophunt_sum, m_stophunt_max;
   double                 m_wicktest_sum, m_wicktest_max;
   double                 m_tfalign_sum, m_tfalign_max;
   double                 m_freeze_sum, m_freeze_max, m_freeze_last;

   // BigMove signal detector (the sensory apparatus)
   BigMoveSignalDetector  m_signals;

   // ATR handle for regime detection
   int                    m_atr_handle;
   int                    m_atr_slow_handle;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   TickFieldAccumulator(const string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_currentBarTime = 0;
      m_tickVolume = 0;
      m_tickCount = 0;

      m_open = m_high = m_low = m_close = 0.0;

      m_comp_sum = m_comp_max = m_comp_last = 0.0;
      m_sweep_sum = m_sweep_max = m_sweep_last = 0.0;
      m_spread_sum = m_spread_max = 0.0;
      m_stophunt_sum = m_stophunt_max = 0.0;
      m_wicktest_sum = m_wicktest_max = 0.0;
      m_tfalign_sum = m_tfalign_max = 0.0;
      m_freeze_sum = m_freeze_max = m_freeze_last = 0.0;

      m_atr_handle = INVALID_HANDLE;
      m_atr_slow_handle = INVALID_HANDLE;

      // Initialize BigMove detector
      m_signals.Init(14, 20, 0.3, 20, 10);
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~TickFieldAccumulator()
   {
      if(m_atr_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr_handle);
      if(m_atr_slow_handle != INVALID_HANDLE)
         IndicatorRelease(m_atr_slow_handle);
   }

   //+------------------------------------------------------------------+
   //| OnTickUpdate: Process each tick (nervous system pulse)           |
   //| Update OHLC, accumulate all 7 BigMove sensations                 |
   //+------------------------------------------------------------------+
   void OnTickUpdate(double bid, double ask)
   {
      datetime currentTime = iTime(m_symbol, m_tf, 0);

      // First tick of new bar - initialize
      if(currentTime != m_currentBarTime)
      {
         if(m_currentBarTime != 0)
         {
            // Bar just closed - accumulators will be finalized externally
         }

         m_currentBarTime = currentTime;

         // Reset bar OHLC
         MqlRates rates[];
         ArraySetAsSeries(rates, true);
         if(CopyRates(m_symbol, m_tf, 0, 1, rates) > 0)
         {
            m_open = rates[0].open;
            m_high = rates[0].high;
            m_low = rates[0].low;
            m_close = rates[0].close;
            m_tickVolume = rates[0].tick_volume;
         }

         // Reset accumulators for fresh bar
         ResetAccumulators();
      }

      // Update current bar stats
      double mid = (bid + ask) / 2.0;
      if(mid > m_high) m_high = mid;
      if(mid < m_low || m_low == 0) m_low = mid;
      m_close = mid;
      m_tickCount++;

      // Update nervous system: sense all 7 BigMove signals
      m_signals.Update(m_symbol, m_tf);

      // Accumulate sensations (scores are 0..1)
      double comp_score = m_signals.GetCompressionScore();
      double sweep_score = m_signals.GetSweepScore();
      double hunt_score = m_signals.GetStopHuntScore();
      double wick_score = m_signals.GetWickScore();
      double align_score = m_signals.GetTimeframeAlignment();

      // Spread narrowing & freeze don't have score getters, use boolean
      double spread_score = m_signals.IsSpreadNarrowing() ? 1.0 : 0.0;
      double freeze_score = m_signals.IsMomentumFreeze() ? 1.0 : 0.0;

      // Accumulate sums
      m_comp_sum += comp_score;
      m_sweep_sum += sweep_score;
      m_spread_sum += spread_score;
      m_stophunt_sum += hunt_score;
      m_wicktest_sum += wick_score;
      m_tfalign_sum += align_score;
      m_freeze_sum += freeze_score;

      // Track maxima (peak sensations)
      if(comp_score > m_comp_max) m_comp_max = comp_score;
      if(sweep_score > m_sweep_max) m_sweep_max = sweep_score;
      if(spread_score > m_spread_max) m_spread_max = spread_score;
      if(hunt_score > m_stophunt_max) m_stophunt_max = hunt_score;
      if(wick_score > m_wicktest_max) m_wicktest_max = wick_score;
      if(align_score > m_tfalign_max) m_tfalign_max = align_score;
      if(freeze_score > m_freeze_max) m_freeze_max = freeze_score;

      // Track last values for slope calculation
      m_comp_last = comp_score;
      m_sweep_last = sweep_score;
      m_freeze_last = freeze_score;
   }

   //+------------------------------------------------------------------+
   //| IsNewBar: Detect when a new bar has formed                       |
   //| Returns true exactly once when bar boundary is crossed           |
   //+------------------------------------------------------------------+
   bool IsNewBar()
   {
      datetime currentTime = iTime(m_symbol, m_tf, 0);

      if(m_currentBarTime == 0)
      {
         m_currentBarTime = currentTime;
         return false;
      }

      if(currentTime != m_currentBarTime)
      {
         return true;  // New bar detected
      }

      return false;
   }

   //+------------------------------------------------------------------+
   //| FinalizeLastBar: Compress all tick sensations into BarSummary    |
   //| This is the bar's "felt memory" - how it experienced itself      |
   //+------------------------------------------------------------------+
   bool FinalizeLastBar(BarSummary &summary)
   {
      if(m_tickCount == 0)
         return false;

      // Fill OHLC and time
      summary.time = m_currentBarTime;
      summary.open = m_open;
      summary.high = m_high;
      summary.low = m_low;
      summary.close = m_close;
      summary.tick_volume = m_tickVolume;
      summary.tf = m_tf;

      // Compute means (average sensations across the bar)
      int divisor = MathMax(1, m_tickCount);
      summary.compression_mean = m_comp_sum / divisor;
      summary.sweep_mean = m_sweep_sum / divisor;
      summary.spread_mean = m_spread_sum / divisor;
      summary.stophunt_mean = m_stophunt_sum / divisor;
      summary.wicktest_mean = m_wicktest_sum / divisor;
      summary.tfalign_mean = m_tfalign_sum / divisor;
      summary.freeze_mean = m_freeze_sum / divisor;

      // Peak sensations (maxima)
      summary.compression_max = m_comp_max;
      summary.sweep_max = m_sweep_max;
      summary.spread_max = m_spread_max;
      summary.stophunt_max = m_stophunt_max;
      summary.wicktest_max = m_wicktest_max;
      summary.tfalign_max = m_tfalign_max;
      summary.freeze_max = m_freeze_max;

      // Compute simple slopes (dynamics: did signal ramp up?)
      // slope ≈ last_value - mean
      summary.compression_slope = m_comp_last - summary.compression_mean;
      summary.sweep_slope = m_sweep_last - summary.sweep_mean;
      summary.freeze_slope = m_freeze_last - summary.freeze_mean;

      // Context: ATR and regime
      summary.atr_value = GetATR(0);
      summary.regime_vol = GetRegimeVolatility();

      return true;
   }

   //+------------------------------------------------------------------+
   //| CurrentBarTime: Get current bar timestamp                        |
   //+------------------------------------------------------------------+
   datetime CurrentBarTime() const { return m_currentBarTime; }

private:
   //+------------------------------------------------------------------+
   //| ResetAccumulators: Clear nervous system memory for new bar       |
   //+------------------------------------------------------------------+
   void ResetAccumulators()
   {
      m_tickCount = 0;

      m_comp_sum = m_comp_max = m_comp_last = 0.0;
      m_sweep_sum = m_sweep_max = m_sweep_last = 0.0;
      m_spread_sum = m_spread_max = 0.0;
      m_stophunt_sum = m_stophunt_max = 0.0;
      m_wicktest_sum = m_wicktest_max = 0.0;
      m_tfalign_sum = m_tfalign_max = 0.0;
      m_freeze_sum = m_freeze_max = m_freeze_last = 0.0;
   }

   //+------------------------------------------------------------------+
   //| GetATR: Current ATR value for context                            |
   //+------------------------------------------------------------------+
   double GetATR(int shift)
   {
      if(m_atr_handle == INVALID_HANDLE)
         m_atr_handle = iATR(m_symbol, m_tf, 14);

      if(m_atr_handle == INVALID_HANDLE)
         return 0.0;

      double buffer[];
      ArraySetAsSeries(buffer, true);

      if(CopyBuffer(m_atr_handle, 0, shift, 1, buffer) <= 0)
         return 0.0;

      return buffer[0];
   }

   //+------------------------------------------------------------------+
   //| GetRegimeVolatility: ATR vs its moving average (regime sense)    |
   //+------------------------------------------------------------------+
   double GetRegimeVolatility()
   {
      double atr_current = GetATR(0);

      if(m_atr_slow_handle == INVALID_HANDLE)
         m_atr_slow_handle = iMA(m_symbol, m_tf, 50, 0, MODE_SMA, PRICE_CLOSE);

      // Simple regime: ATR(14) / SMA(50 bars of ATR)
      // For now, use simplified: current ATR / avg of recent ATRs
      double atr_sum = 0.0;
      for(int i = 1; i <= 20; i++)
      {
         atr_sum += GetATR(i);
      }
      double atr_avg = atr_sum / 20.0;

      if(atr_avg > 0)
         return atr_current / atr_avg;

      return 1.0;
   }
};
