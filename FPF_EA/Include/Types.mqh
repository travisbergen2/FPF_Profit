//+------------------------------------------------------------------+
//| Types.mqh                                                          |
//| Shared data structures for Intuitive Flow EA                       |
//| Bar-level memory, predictions, and outcomes                        |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| BarSummary: Nervous system fingerprint for one bar                |
//| Captures how the bar "felt" across all tick sensations            |
//+------------------------------------------------------------------+
struct BarSummary
{
   datetime time;                // open time of the bar
   double   open;
   double   high;
   double   low;
   double   close;
   long     tick_volume;

   // BigMove signal statistics over the bar (0..1 scaled)
   double   compression_mean;    // average compression sensation
   double   compression_max;     // peak compression spike
   double   sweep_mean;          // average sweep activity
   double   sweep_max;           // strongest sweep detected
   double   spread_mean;         // average spread narrowing
   double   spread_max;          // tightest spread moment
   double   stophunt_mean;       // average stop-hunt intensity
   double   stophunt_max;        // peak stop-hunt spike
   double   wicktest_mean;       // average wick-test activity
   double   wicktest_max;        // strongest wick-test
   double   tfalign_mean;        // average timeframe alignment
   double   tfalign_max;         // strongest alignment
   double   freeze_mean;         // average momentum freeze
   double   freeze_max;          // deepest freeze

   // Nervous system dynamics (how signals evolved)
   double   compression_slope;   // did compression build up?
   double   sweep_slope;         // did sweeps intensify?
   double   freeze_slope;        // did freeze deepen near end?

   // Context awareness
   ENUM_TIMEFRAMES tf;
   double          atr_value;    // ATR on this TF
   double          regime_vol;   // volatility regime (ATR vs its MA)
};

//+------------------------------------------------------------------+
//| PredictionResult: Bar-level intuition for next bar                |
//| What the meta-learner expects based on pattern memory             |
//+------------------------------------------------------------------+
struct PredictionResult
{
   double prob_up;               // 0..1, likelihood next bar goes up
   double prob_down;             // 0..1, likelihood next bar goes down
   double prob_big_move;         // 0..1, likelihood of significant range
   double expected_R_long;       // expected R-multiple if going long
   double expected_R_short;      // expected R-multiple if going short
   double confidence;            // 0..1, based on sample size & consistency
};

//+------------------------------------------------------------------+
//| TradeOutcome: Realized result after trade closes                  |
//| Used to update meta-learner's pattern memory                      |
//+------------------------------------------------------------------+
struct TradeOutcome
{
   datetime   entry_time;
   datetime   exit_time;
   double     R_multiple;        // (exit - entry) / SL, signed
   int        direction;         // +1 long, -1 short, 0 none
   BarSummary entry_bar;         // snapshot of bar fingerprint at decision
};
