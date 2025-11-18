//+------------------------------------------------------------------+
//| BigMoveSignals.mqh                                                 |
//| Detects 7 pre-move signals with proper MQL5 indicator usage      |
//+------------------------------------------------------------------+
#property strict

class BigMoveSignalDetector
{
private:
   int atr_period;
   int compression_lookback;
   double compression_threshold;
   int volume_ma_period;
   double sweep_tolerance;
   
   int handle_atr;
   int handle_rsi;
   
   bool compression_detected;
   bool sweeps_detected;
   bool spread_narrowing;
   bool stop_hunt_detected;
   bool wick_test_detected;
   bool tf_aligned;
   bool momentum_freeze;
   
   double compression_score;
   double sweep_score;
   double stop_hunt_score;
   double wick_score;
   double tf_align_score;
   
public:
   BigMoveSignalDetector()
   {
      atr_period = 14;
      compression_lookback = 20;
      compression_threshold = 0.3;
      volume_ma_period = 20;
      sweep_tolerance = 10;
      
      handle_atr = INVALID_HANDLE;
      handle_rsi = INVALID_HANDLE;
      
      ResetSignals();
   }
   
   ~BigMoveSignalDetector()
   {
      if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);
      if(handle_rsi != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   }
   
   void Init(int atr_p, int comp_lb, double comp_th, int vol_ma, double sweep_tol)
   {
      atr_period = atr_p;
      compression_lookback = comp_lb;
      compression_threshold = comp_th;
      volume_ma_period = vol_ma;
      sweep_tolerance = sweep_tol;
      
      ResetSignals();
   }
   
   void ResetSignals()
   {
      compression_detected = false;
      sweeps_detected = false;
      spread_narrowing = false;
      stop_hunt_detected = false;
      wick_test_detected = false;
      tf_aligned = false;
      momentum_freeze = false;
      
      compression_score = 0.0;
      sweep_score = 0.0;
      stop_hunt_score = 0.0;
      wick_score = 0.0;
      tf_align_score = 0.0;
   }
   
   double GetATR(string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
   {
      double atr_buffer[];
      ArraySetAsSeries(atr_buffer, true);
      
      if(handle_atr == INVALID_HANDLE)
         handle_atr = iATR(symbol, timeframe, atr_period);
      
      if(handle_atr == INVALID_HANDLE) return 0;
      if(CopyBuffer(handle_atr, 0, shift, 1, atr_buffer) <= 0) return 0;
      
      return atr_buffer[0];
   }
   
   double GetRSI(string symbol, ENUM_TIMEFRAMES timeframe, int shift = 0)
   {
      double rsi_buffer[];
      ArraySetAsSeries(rsi_buffer, true);
      
      if(handle_rsi == INVALID_HANDLE)
         handle_rsi = iRSI(symbol, timeframe, 14, PRICE_CLOSE);
      
      if(handle_rsi == INVALID_HANDLE) return 50;
      if(CopyBuffer(handle_rsi, 0, shift, 1, rsi_buffer) <= 0) return 50;
      
      return rsi_buffer[0];
   }
   
   double GetEMA(string symbol, ENUM_TIMEFRAMES timeframe, int period, int shift = 0)
   {
      double ema_buffer[];
      ArraySetAsSeries(ema_buffer, true);
      
      int handle = iMA(symbol, timeframe, period, 0, MODE_EMA, PRICE_CLOSE);
      if(handle == INVALID_HANDLE) return 0;
      
      int copied = CopyBuffer(handle, 0, shift, 1, ema_buffer);
      IndicatorRelease(handle);
      
      if(copied <= 0) return 0;
      return ema_buffer[0];
   }
   
   void Update(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      ResetSignals();
      DetectCompression(symbol, timeframe);
      DetectSweeps(symbol, timeframe);
      DetectSpreadNarrowing(symbol, timeframe);
      DetectStopHunts(symbol, timeframe);
      DetectWickTests(symbol, timeframe);
      DetectTimeframeAlignment(symbol, timeframe);
      DetectMomentumFreeze(symbol, timeframe);
   }
   
   void DetectCompression(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      double atr_current = GetATR(symbol, timeframe, 0);
      double atr_avg = 0.0;
      
      for(int i = 1; i <= compression_lookback; i++)
      {
         atr_avg += GetATR(symbol, timeframe, i);
      }
      atr_avg /= compression_lookback;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, timeframe, 0, 11, rates) < 11) return;
      
      double avg_body = 0.0;
      for(int i = 1; i <= 10; i++)
      {
         avg_body += MathAbs(rates[i].close - rates[i].open);
      }
      avg_body /= 10.0;
      
      double current_body = MathAbs(rates[0].close - rates[0].open);
      double atr_ratio = (atr_avg > 0) ? (atr_current / atr_avg) : 1.0;
      double body_ratio = (avg_body > 0) ? (current_body / avg_body) : 1.0;
      
      if(atr_ratio < compression_threshold || body_ratio < 0.5)
      {
         compression_detected = true;
         compression_score = 1.0 - MathMin(atr_ratio, 1.0);
      }
      else
      {
         compression_score = 0.0;
      }
   }
   
   void DetectSweeps(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, timeframe, 0, 21, rates) < 21) return;
      
      int sweep_count = 0;
      double tolerance = sweep_tolerance * SymbolInfoDouble(symbol, SYMBOL_POINT);
      
      double swing_high = rates[1].high;
      for(int i = 2; i <= 10; i++)
      {
         if(rates[i].high > swing_high) swing_high = rates[i].high;
      }
      
      for(int i = 1; i <= 20; i++)
      {
         if(MathAbs(rates[i].high - swing_high) < tolerance && rates[i].close < swing_high)
         {
            sweep_count++;
         }
      }
      
      double swing_low = rates[1].low;
      for(int i = 2; i <= 10; i++)
      {
         if(rates[i].low < swing_low) swing_low = rates[i].low;
      }
      
      for(int i = 1; i <= 20; i++)
      {
         if(MathAbs(rates[i].low - swing_low) < tolerance && rates[i].close > swing_low)
         {
            sweep_count++;
         }
      }
      
      if(sweep_count >= 3)
      {
         sweeps_detected = true;
         sweep_score = MathMin((double)sweep_count / 5.0, 1.0);
      }
      else
      {
         sweep_score = (double)sweep_count / 5.0;
      }
   }
   
   void DetectSpreadNarrowing(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      long volumes[];
      ArraySetAsSeries(volumes, true);
      if(CopyTickVolume(symbol, timeframe, 0, volume_ma_period + 1, volumes) < volume_ma_period + 1)
         return;
      
      long vol_sum = 0;
      for(int i = 1; i <= volume_ma_period; i++)
      {
         vol_sum += volumes[i];
      }
      double vol_avg = (double)vol_sum / volume_ma_period;
      
      long current_vol = volumes[0];
      double vol_ratio = (vol_avg > 0) ? ((double)current_vol / vol_avg) : 1.0;
      
      if(vol_ratio < 0.7)
      {
         spread_narrowing = true;
      }
   }
   
   void DetectStopHunts(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, timeframe, 0, 6, rates) < 6) return;
      
      for(int i = 1; i <= 5; i++)
      {
         double open = rates[i].open;
         double close = rates[i].close;
         double high = rates[i].high;
         double low = rates[i].low;
         
         double body = MathAbs(close - open);
         double upper_wick = high - MathMax(open, close);
         double lower_wick = MathMin(open, close) - low;
         
         if(lower_wick > body * 2.0 && close > open)
         {
            stop_hunt_detected = true;
            stop_hunt_score = MathMin(lower_wick / body / 3.0, 1.0);
            break;
         }
         
         if(upper_wick > body * 2.0 && close < open)
         {
            stop_hunt_detected = true;
            stop_hunt_score = MathMin(upper_wick / body / 3.0, 1.0);
            break;
         }
      }
   }
   
   void DetectWickTests(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, timeframe, 0, 6, rates) < 6) return;
      
      int wick_count = 0;
      
      for(int i = 1; i <= 5; i++)
      {
         double open = rates[i].open;
         double close = rates[i].close;
         double high = rates[i].high;
         double low = rates[i].low;
         
         double body = MathAbs(close - open);
         double upper_wick = high - MathMax(open, close);
         double lower_wick = MathMin(open, close) - low;
         double range = high - low;
         
         if(upper_wick > range * 0.3 && lower_wick > range * 0.3)
         {
            wick_count++;
         }
      }
      
      if(wick_count >= 2)
      {
         wick_test_detected = true;
         wick_score = MathMin((double)wick_count / 3.0, 1.0);
      }
      else
      {
         wick_score = (double)wick_count / 3.0;
      }
   }
   
   void DetectTimeframeAlignment(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      ENUM_TIMEFRAMES tf1 = PERIOD_M1;
      ENUM_TIMEFRAMES tf2 = PERIOD_M5;
      ENUM_TIMEFRAMES tf3 = PERIOD_M15;
      ENUM_TIMEFRAMES tf4 = PERIOD_H1;
      
      int bullish_count = 0;
      int bearish_count = 0;
      
      double ema_fast_1 = GetEMA(symbol, tf1, 12, 0);
      double ema_slow_1 = GetEMA(symbol, tf1, 26, 0);
      if(ema_fast_1 > ema_slow_1) bullish_count++; else bearish_count++;
      
      double ema_fast_2 = GetEMA(symbol, tf2, 12, 0);
      double ema_slow_2 = GetEMA(symbol, tf2, 26, 0);
      if(ema_fast_2 > ema_slow_2) bullish_count++; else bearish_count++;
      
      double ema_fast_3 = GetEMA(symbol, tf3, 12, 0);
      double ema_slow_3 = GetEMA(symbol, tf3, 26, 0);
      if(ema_fast_3 > ema_slow_3) bullish_count++; else bearish_count++;
      
      double ema_fast_4 = GetEMA(symbol, tf4, 12, 0);
      double ema_slow_4 = GetEMA(symbol, tf4, 26, 0);
      if(ema_fast_4 > ema_slow_4) bullish_count++; else bearish_count++;
      
      if(bullish_count >= 3 || bearish_count >= 3)
      {
         tf_aligned = true;
         tf_align_score = MathMax((double)bullish_count, (double)bearish_count) / 4.0;
      }
      else
      {
         tf_align_score = MathMax((double)bullish_count, (double)bearish_count) / 4.0;
      }
   }
   
   void DetectMomentumFreeze(string symbol, ENUM_TIMEFRAMES timeframe)
   {
      double rsi_current = GetRSI(symbol, timeframe, 0);
      double rsi_prev = GetRSI(symbol, timeframe, 5);
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(symbol, timeframe, 0, 6, rates) < 6) return;
      
      double price_current = rates[0].close;
      double price_prev = rates[5].close;
      
      double rsi_change = MathAbs(rsi_current - rsi_prev);
      double price_change = MathAbs(price_current - price_prev);
      
      if(rsi_change < 5.0 && price_change > SymbolInfoDouble(symbol, SYMBOL_POINT) * 20)
      {
         momentum_freeze = true;
      }
   }
   
   bool IsCompressionDetected() { return compression_detected; }
   bool AreSweepsDetected() { return sweeps_detected; }
   bool IsSpreadNarrowing() { return spread_narrowing; }
   bool IsStopHuntDetected() { return stop_hunt_detected; }
   bool IsWickTestDetected() { return wick_test_detected; }
   bool IsTimeframeAligned() { return tf_aligned; }
   bool IsMomentumFreeze() { return momentum_freeze; }
   
   double GetCompressionScore() { return compression_score; }
   double GetSweepScore() { return sweep_score; }
   double GetStopHuntScore() { return stop_hunt_score; }
   double GetWickScore() { return wick_score; }
   double GetTimeframeAlignment() { return tf_align_score; }
   
   double GetTotalSignalStrength()
   {
      return (compression_score * 0.25 + 
              sweep_score * 0.20 + 
              stop_hunt_score * 0.15 + 
              wick_score * 0.15 + 
              tf_align_score * 0.25);
   }
};
