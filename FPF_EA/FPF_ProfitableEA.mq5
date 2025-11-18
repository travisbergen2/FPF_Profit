//+------------------------------------------------------------------+
//| FPF_ProfitableEA.mq5                                              |
//| Fractal Personality Field Trading EA                              |
//| v2.1 - ADAPTIVE LEARNING + COMPLIANCE MONITORING                  |
//+------------------------------------------------------------------+
#property copyright "FPF Trading System"
#property version   "2.10"
#property strict

#include <FPF_Engine.mqh>
#include <BigMoveSignals.mqh>
#include <RiskManager.mqh>
#include <ComplianceMonitor.mqh>
#include <AdaptiveLearning.mqh>

//--- Input Parameters
input group "=== FPF Core Settings ==="
input double      FPF_Phi_Entry = 0.08;           // Min Phi for entry (LOWERED for more trades)
input double      FPF_DecisionPot_Min = 0.06;     // Min decision potential (LOWERED)
input double      ML_Entry_Threshold = 0.65;      // ML probability threshold (LOWERED)
input double      ML_Stop_Accuracy = 0.55;        // Stop trading if accuracy drops below

input group "=== Risk Management ==="
input double      Risk_Percent = 1.5;              // Risk per trade % (INCREASED)
input double      Max_Daily_Loss_Percent = 4.0;   // Max daily loss % (INCREASED)
input int         Max_Positions = 5;               // Max concurrent positions (INCREASED)
input double      ATR_SL_Multiplier = 2.0;         // Stop loss ATR multiplier (DYNAMIC)
input double      Base_TP_Multiplier = 3.0;        // TP multiplier (R:R) (INCREASED)
input bool        Use_Partial_TP = true;           // Use partial take profits
input double      Partial_TP1_Ratio = 0.4;         // Close 40% at 1.5R
input double      Partial_TP2_Ratio = 0.3;         // Close 30% at 2.5R

input group "=== Signal Detection ==="
input int         ATR_Period = 14;
input int         Compression_Lookback = 20;
input double      Compression_Threshold = 0.25;    // TIGHTENED
input int         Volume_MA_Period = 20;
input double      Sweep_Tolerance_Points = 8;      // TIGHTENED
input int         Min_Signals_Required = 2;        // Min signals (LOWERED from 3)

input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES TF_Primary = PERIOD_M15;
input ENUM_TIMEFRAMES TF_Secondary = PERIOD_M5;
input ENUM_TIMEFRAMES TF_Tertiary = PERIOD_M1;

input group "=== Time Filtering ==="
input bool        Use_Time_Filter = true;          // Enable session filtering
input int         Trade_Start_Hour = 2;            // Start hour (UTC) - London open
input int         Trade_End_Hour = 16;             // End hour (UTC) - NY close
input int         Trade_Cooldown_Minutes = 30;     // Minutes between trades

input group "=== Advanced ==="
input bool        Enable_Breakeven = true;
input double      Breakeven_Profit_Multiplier = 0.5; // Move to BE at 0.5R
input bool        Enable_Trailing = true;
input double      Trail_Start_Multiplier = 1.0;    // Start trailing at 1R
input double      Trail_Step_Multiplier = 0.3;     // Trail by 0.3R
input bool        Enable_Debug = false;
input bool        Adaptive_Risk = true;            // Reduce risk after losses

input group "=== Adaptive Learning ==="
input bool        Enable_Learning = true;          // Enable adaptive learning
input bool        Use_Learned_Thresholds = true;   // Use learned optimal thresholds
input bool        Use_Predictions = true;          // Use predictive analytics
input int         Min_Learning_Samples = 20;       // Min trades before learning kicks in

input group "=== Compliance ==="
input bool        Enable_Compliance = true;        // Enable compliance monitoring
input int         Max_Trades_Per_Hour = 10;        // Max trades per hour
input int         Max_Daily_Trades = 50;           // Max trades per day
input int         Max_Rapid_Reversals = 3;         // Max reversals in 15 min
input double      Min_Hold_Time_Sec = 60;          // Min holding time (seconds)

//--- Global Objects
FractalPersonalityField fpf;
BigMoveSignalDetector signalDetector;
RiskManager riskMgr;
ComplianceMonitor compliance;
AdaptiveLearningEngine learningEngine;

//--- Trading State
struct TradingState {
   double dayStartBalance;
   int tradesWon;
   int tradesLost;
   datetime lastTradeTime;
   double[] rollingAccuracy;
   bool tradingEnabled;
   datetime lastMLUpdate;
   double currentPhi;
   double currentDecPot;
   double mlProbability;
   double currentATR;
   int consecutiveLosses;
   int consecutiveWins;
   double currentRiskMultiplier;
   bool isHighVolatility;
   bool isTrendingMarket;
   double predictedSuccess;        // Learned prediction
   double learnedPhiMin;           // Adaptive threshold
   double learnedMLProbMin;        // Adaptive threshold
   bool complianceOK;              // Compliance status
   ulong lastTradeTicket;          // Track for learning
   datetime lastTradeOpenTime;     // Track for learning
   double lastTradeOpenPrice;      // Track for learning
};
TradingState state;

//--- Constants
#define MAGIC_NUMBER 20241118

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize FPF
   fpf.Init();
   
   // Initialize signal detector
   signalDetector.Init(ATR_Period, Compression_Lookback, Compression_Threshold,
                      Volume_MA_Period, Sweep_Tolerance_Points);

   // Initialize risk manager with ATR multiplier
   riskMgr.Init(Risk_Percent, Max_Daily_Loss_Percent, Max_Positions,
                ATR_SL_Multiplier, Base_TP_Multiplier);

   // Initialize compliance monitor
   if(Enable_Compliance)
   {
      compliance.Init(Max_Daily_Trades, Max_Trades_Per_Hour, Max_Rapid_Reversals,
                      Min_Hold_Time_Sec, 5);
      Print("Compliance Monitor: ENABLED");
   }

   // Initialize learning engine
   if(Enable_Learning)
   {
      learningEngine.SetLearningEnabled(true);
      Print("Adaptive Learning: ENABLED");
   }

   // Initialize state
   state.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   state.tradesWon = 0;
   state.tradesLost = 0;
   state.tradingEnabled = true;
   state.lastTradeTime = 0;
   state.consecutiveLosses = 0;
   state.consecutiveWins = 0;
   state.currentRiskMultiplier = 1.0;
   state.isHighVolatility = false;
   state.isTrendingMarket = false;
   state.predictedSuccess = 0.55;
   state.learnedPhiMin = FPF_Phi_Entry;
   state.learnedMLProbMin = ML_Entry_Threshold;
   state.complianceOK = true;
   state.lastTradeTicket = 0;
   state.lastTradeOpenTime = 0;
   state.lastTradeOpenPrice = 0;
   ArrayResize(state.rollingAccuracy, 50);
   ArrayInitialize(state.rollingAccuracy, 0.5);

   Print("===========================================");
   Print("FPF OPTIMIZED EA v2.1 - FULLY INITIALIZED");
   Print("===========================================");
   Print("Adaptive Learning: ", (Enable_Learning ? "ON" : "OFF"));
   Print("Compliance Monitoring: ", (Enable_Compliance ? "ON" : "OFF"));
   Print("ML Entry Threshold: ", ML_Entry_Threshold);
   Print("ML Stop Accuracy: ", ML_Stop_Accuracy);
   Print("===========================================");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if new bar
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(_Symbol, TF_Primary, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Daily reset check
   CheckDailyReset();
   
   // Update FPF state
   UpdateFPFState();
   
   // Check ML gating
   UpdateMLGating();
   
   // Manage existing positions
   ManagePositions();
   
   // Check for new entries if trading enabled
   if(state.tradingEnabled && riskMgr.CanOpenPosition())
   {
      CheckForEntry();
   }
   
   // Update dashboard
   UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Update FPF State                                                   |
//+------------------------------------------------------------------+
void UpdateFPFState()
{
   // Get current ATR
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   int h_atr = iATR(_Symbol, TF_Primary, ATR_Period);
   if(h_atr != INVALID_HANDLE)
   {
      CopyBuffer(h_atr, 0, 0, 1, atr_buffer);
      state.currentATR = atr_buffer[0];
      IndicatorRelease(h_atr);
   }

   // Detect market regime
   DetectMarketRegime();

   // Compute emotive force (market sentiment)
   double Ae = ComputeEmotiveForce();

   // Compute volatility-scaled noise (novelty)
   double An = ComputeNoveltyNoise();

   // Update FPF with RK4 integration
   double dt = 1.0;
   fpf.UpdateP_RK4(Ae, An, dt);

   // Calculate projection metrics
   state.currentPhi = fpf.GetPhi(1.0);
   state.currentDecPot = fpf.GetDecisionPotential(0.5);

   // Update adaptive risk
   UpdateAdaptiveRisk();

   // Update learned thresholds if using adaptive learning
   if(Enable_Learning && Use_Learned_Thresholds)
   {
      state.learnedPhiMin = learningEngine.GetOptimalPhiMin();
      state.learnedMLProbMin = learningEngine.GetOptimalMLProbMin();
   }

   // Generate prediction if learning enabled
   if(Enable_Learning && Use_Predictions)
   {
      MqlDateTime dt;
      TimeCurrent(dt);

      double comp = signalDetector.GetCompressionScore();
      double sweep = signalDetector.GetSweepScore();
      double tfAlign = signalDetector.GetTimeframeAlignment();

      state.predictedSuccess = learningEngine.PredictSuccessProbability(
         state.currentPhi, state.mlProbability, comp, sweep, tfAlign,
         dt.hour, state.isTrendingMarket, state.isHighVolatility
      );
   }

   if(Enable_Debug)
   {
      Print("FPF Update - Phi: ", state.currentPhi,
            " DecPot: ", state.currentDecPot,
            " Ae: ", Ae, " An: ", An,
            " Regime: ", (state.isTrendingMarket ? "TRENDING" : "RANGING"),
            " RiskMult: ", state.currentRiskMultiplier,
            " Prediction: ", state.predictedSuccess);
   }
}

//+------------------------------------------------------------------+
//| Compute Emotive Force                                              |
//+------------------------------------------------------------------+
double ComputeEmotiveForce()
{
   // Get ATR
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   int h_atr = iATR(_Symbol, TF_Primary, ATR_Period);
   if(h_atr == INVALID_HANDLE) return 0;
   
   CopyBuffer(h_atr, 0, 0, 1, atr_buffer);
   double atr = atr_buffer[0];
   IndicatorRelease(h_atr);
   
   // Get price data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, TF_Primary, 0, 6, rates) < 6) return 0;
   
   double price = rates[0].close;
   
   // Volatility component
   double volRatio = (price > 0) ? (atr / price) : 0;
   
   // Price momentum component
   double close0 = rates[0].close;
   double close5 = rates[5].close;
   double momentum = (close5 > 0) ? ((close0 - close5) / close5) : 0;
   
   // Volume component
   long volumes[];
   ArraySetAsSeries(volumes, true);
   if(CopyTickVolume(_Symbol, TF_Primary, 0, 2, volumes) < 2) return 0;
   
   long vol0 = volumes[0];
   long vol1 = volumes[1];
   double volSpike = (vol1 > 0) ? ((double)vol0 / vol1) : 1.0;
   
   // Combine into emotive force
   double Ae = MathTanh(momentum * 10.0) * volRatio * MathMin(volSpike, 2.0);
   
   return Ae;
}

//+------------------------------------------------------------------+
//| Compute Novelty Noise                                              |
//+------------------------------------------------------------------+
double ComputeNoveltyNoise()
{
   // Get ATR
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   int h_atr = iATR(_Symbol, TF_Primary, ATR_Period);
   if(h_atr == INVALID_HANDLE) return 0;
   
   CopyBuffer(h_atr, 0, 0, 1, atr_buffer);
   double atr = atr_buffer[0];
   IndicatorRelease(h_atr);
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, TF_Primary, 0, 1, rates) < 1) return 0;
   
   double price = rates[0].close;
   double volFactor = (price > 0) ? (atr / price) : 0;
   
   // Box-Muller transform for Gaussian noise
   double u1 = (double)MathRand() / 32767.0;
   double u2 = (double)MathRand() / 32767.0;
   double z = MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
   
   double An = z * volFactor * 2.0;
   return An;
}

//+------------------------------------------------------------------+
//| Update ML Gating                                                   |
//+------------------------------------------------------------------+
void UpdateMLGating()
{
   // Calculate rolling accuracy
   int total = 0;
   int wins = 0;
   for(int i = 0; i < ArraySize(state.rollingAccuracy); i++)
   {
      if(state.rollingAccuracy[i] > 0)
      {
         total++;
         wins += (int)state.rollingAccuracy[i];
      }
   }
   
   double accuracy = (total > 0) ? ((double)wins / total) : 0.75;
   
   // Calculate ML probability based on FPF state and signals
   state.mlProbability = CalculateMLProbability();
   
   // Gate trading based on accuracy and probability
   if(accuracy < ML_Stop_Accuracy)
   {
      state.tradingEnabled = false;
      if(Enable_Debug)
         Print("Trading DISABLED - Accuracy: ", accuracy, " < ", ML_Stop_Accuracy);
   }
   else
   {
      state.tradingEnabled = true;
   }
}

//+------------------------------------------------------------------+
//| Calculate ML Probability (OPTIMIZED WEIGHTS)                       |
//+------------------------------------------------------------------+
double CalculateMLProbability()
{
   // Get FPF state values
   double coh = fpf.P[fpf.P_COH];
   double align = fpf.P[fpf.P_ALIGN];
   double S_val = fpf.P[fpf.P_S];
   double A_val = fpf.P[fpf.P_A];

   // Get signal strengths
   double compressionScore = signalDetector.GetCompressionScore();
   double sweepScore = signalDetector.GetSweepScore();
   double stopHuntScore = signalDetector.GetStopHuntScore();
   double wickScore = signalDetector.GetWickScore();
   double tfAlignScore = signalDetector.GetTimeframeAlignment();

   // OPTIMIZED: Compression and TF alignment are strongest predictors
   double signalStrength = (compressionScore * 0.30 +     // Increased from 0.25
                            sweepScore * 0.15 +           // Decreased from 0.20
                            stopHuntScore * 0.15 +        // Same
                            wickScore * 0.10 +            // Decreased from 0.15
                            tfAlignScore * 0.30);         // Increased from 0.25

   // OPTIMIZED: Coherence and S are most important for FPF
   double fpfStrength = (coh * 0.35 +         // Increased from 0.30
                         align * 0.15 +       // Decreased from 0.20
                         S_val * 0.35 +       // Increased from 0.30
                         -A_val * 0.15);      // Decreased from 0.20

   // Market regime adjustment
   double regimeBoost = 1.0;
   if(state.isTrendingMarket && !state.isHighVolatility)
      regimeBoost = 1.15; // Boost confidence in trending, normal vol
   else if(state.isHighVolatility)
      regimeBoost = 0.85; // Reduce confidence in high volatility

   // Final probability with regime adjustment
   double probability = (signalStrength * 0.65 + fpfStrength * 0.35) * regimeBoost;
   probability = MathMax(0.0, MathMin(1.0, probability));

   return probability;
}

//+------------------------------------------------------------------+
//| Check For Entry                                                    |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   // Time filtering
   if(Use_Time_Filter && !IsWithinTradingHours())
   {
      if(Enable_Debug) Print("Entry rejected - Outside trading hours");
      return;
   }

   // Trade cooldown
   if(Trade_Cooldown_Minutes > 0)
   {
      datetime timeSinceLastTrade = TimeCurrent() - state.lastTradeTime;
      if(timeSinceLastTrade < Trade_Cooldown_Minutes * 60)
      {
         if(Enable_Debug) Print("Entry rejected - Cooldown period");
         return;
      }
   }

   // Use learned thresholds if enabled, otherwise use configured
   double phi_threshold = Use_Learned_Thresholds ? state.learnedPhiMin : FPF_Phi_Entry;
   double ml_threshold = Use_Learned_Thresholds ? state.learnedMLProbMin : ML_Entry_Threshold;

   // Primary FPF gating (adaptive or configured thresholds)
   if(state.currentPhi < phi_threshold)
   {
      if(Enable_Debug) Print("Entry rejected - Low Phi: ", state.currentPhi, " < ", phi_threshold);
      return;
   }

   if(state.currentDecPot < FPF_DecisionPot_Min)
   {
      if(Enable_Debug) Print("Entry rejected - Low DecPot: ", state.currentDecPot);
      return;
   }

   // ML gating (adaptive or configured threshold)
   if(state.mlProbability < ml_threshold)
   {
      if(Enable_Debug) Print("Entry rejected - Low ML prob: ", state.mlProbability, " < ", ml_threshold);
      return;
   }

   // Predictive gating (if learning enabled)
   if(Enable_Learning && Use_Predictions)
   {
      if(!learningEngine.ShouldTakeTrade(state.currentPhi, state.mlProbability, state.predictedSuccess))
      {
         if(Enable_Debug) Print("Entry rejected - Learned pattern suggests low success: ", state.predictedSuccess);
         return;
      }
   }

   // Detect big move signals
   signalDetector.Update(_Symbol, TF_Primary);

   bool compressionDetected = signalDetector.IsCompressionDetected();
   bool sweepsDetected = signalDetector.AreSweepsDetected();
   bool spreadNarrowing = signalDetector.IsSpreadNarrowing();
   bool stopHuntDetected = signalDetector.IsStopHuntDetected();
   bool wickTestDetected = signalDetector.IsWickTestDetected();
   bool tfAlignment = signalDetector.IsTimeframeAligned();

   // Require multiple signal confirmations (LOWERED from 3 to configurable)
   int signalCount = 0;
   if(compressionDetected) signalCount++;
   if(sweepsDetected) signalCount++;
   if(stopHuntDetected) signalCount++;
   if(wickTestDetected) signalCount++;
   if(tfAlignment) signalCount++;

   if(signalCount < Min_Signals_Required)
   {
      if(Enable_Debug) Print("Entry rejected - Insufficient signals: ", signalCount, " < ", Min_Signals_Required);
      return;
   }

   // Determine direction with improved logic
   int direction = DetermineDirectionImproved();
   if(direction == 0) return;

   // Compliance check before executing
   if(Enable_Compliance)
   {
      double volume = riskMgr.CalculateLotSize(_Symbol, state.currentATR * ATR_SL_Multiplier / SymbolInfoDouble(_Symbol, SYMBOL_POINT));
      if(!compliance.IsTradeCompliant(_Symbol, direction, volume))
      {
         state.complianceOK = false;
         Print("COMPLIANCE VIOLATION: Trade blocked - ", compliance.GetViolationReason());
         return;
      }
      state.complianceOK = true;
   }

   // Execute trade with dynamic SL/TP
   ExecuteTradeWithDynamicLevels(direction);
}

//+------------------------------------------------------------------+
//| Determine Trade Direction                                          |
//+------------------------------------------------------------------+
int DetermineDirection()
{
   // Get EMA values using handles
   double ema_fast_pri[], ema_slow_pri[], ema_fast_sec[], ema_slow_sec[];
   ArraySetAsSeries(ema_fast_pri, true);
   ArraySetAsSeries(ema_slow_pri, true);
   ArraySetAsSeries(ema_fast_sec, true);
   ArraySetAsSeries(ema_slow_sec, true);
   
   // Primary timeframe
   int h_ema_fast_pri = iMA(_Symbol, TF_Primary, 12, 0, MODE_EMA, PRICE_CLOSE);
   int h_ema_slow_pri = iMA(_Symbol, TF_Primary, 26, 0, MODE_EMA, PRICE_CLOSE);
   
   if(h_ema_fast_pri == INVALID_HANDLE || h_ema_slow_pri == INVALID_HANDLE)
      return 0;
   
   CopyBuffer(h_ema_fast_pri, 0, 0, 1, ema_fast_pri);
   CopyBuffer(h_ema_slow_pri, 0, 0, 1, ema_slow_pri);
   
   // Secondary timeframe
   int h_ema_fast_sec = iMA(_Symbol, TF_Secondary, 12, 0, MODE_EMA, PRICE_CLOSE);
   int h_ema_slow_sec = iMA(_Symbol, TF_Secondary, 26, 0, MODE_EMA, PRICE_CLOSE);
   
   if(h_ema_fast_sec == INVALID_HANDLE || h_ema_slow_sec == INVALID_HANDLE)
   {
      IndicatorRelease(h_ema_fast_pri);
      IndicatorRelease(h_ema_slow_pri);
      return 0;
   }
   
   CopyBuffer(h_ema_fast_sec, 0, 0, 1, ema_fast_sec);
   CopyBuffer(h_ema_slow_sec, 0, 0, 1, ema_slow_sec);
   
   // Get current price
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, TF_Primary, 0, 1, rates);
   double price = rates[0].close;
   
   // Check alignment
   bool bullishPrimary = ema_fast_pri[0] > ema_slow_pri[0];
   bool bullishSecondary = ema_fast_sec[0] > ema_slow_sec[0];
   bool priceAboveEMA = price > ema_fast_pri[0];
   
   bool bearishPrimary = ema_fast_pri[0] < ema_slow_pri[0];
   bool bearishSecondary = ema_fast_sec[0] < ema_slow_sec[0];
   bool priceBelowEMA = price < ema_fast_pri[0];
   
   // Additional FPF bias
   double fpfBias = fpf.GetPhi(1.0);
   
   // Release handles
   IndicatorRelease(h_ema_fast_pri);
   IndicatorRelease(h_ema_slow_pri);
   IndicatorRelease(h_ema_fast_sec);
   IndicatorRelease(h_ema_slow_sec);
   
   if(bullishPrimary && bullishSecondary && priceAboveEMA && fpfBias > 0)
      return 1;  // Buy
   
   if(bearishPrimary && bearishSecondary && priceBelowEMA && fpfBias < 0)
      return -1; // Sell
   
   return 0; // No clear direction
}

//+------------------------------------------------------------------+
//| Execute Trade                                                      |
//+------------------------------------------------------------------+
void ExecuteTrade(int direction)
{
   double lotSize = riskMgr.CalculateLotSize(_Symbol, Base_SL_Points);
   if(lotSize <= 0) return;
   
   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : 
                                     SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   double sl, tp;
   riskMgr.CalculateSLTP(_Symbol, direction, price, Base_SL_Points, sl, tp);
   
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.type = (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = StringFormat("FPF_ML:%.2f_Phi:%.2f", state.mlProbability, state.currentPhi);
   
   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Trade opened successfully - Ticket: ", result.order, 
               " Direction: ", (direction > 0 ? "BUY" : "SELL"),
               " ML Prob: ", state.mlProbability);
         state.lastTradeTime = TimeCurrent();
      }
      else
      {
         Print("Trade failed - Return code: ", result.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Positions                                                   |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER) continue;

      // Get position info
      double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      double current_volume = PositionGetDouble(POSITION_VOLUME);

      // Calculate SL distance in points (using ATR)
      double sl_distance_price = MathAbs(entry_price - current_sl);
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double sl_distance_points = sl_distance_price / point;

      // Partial take profits
      if(Use_Partial_TP)
      {
         ManagePartialTakeProfits(ticket, entry_price, sl_distance_points);
      }

      // Breakeven logic (using multiplier of SL distance)
      if(Enable_Breakeven)
      {
         double be_profit_points = sl_distance_points * Breakeven_Profit_Multiplier;
         riskMgr.MoveToBreakeven(ticket, be_profit_points);
      }

      // Trailing stop logic (using multiplier of SL distance)
      if(Enable_Trailing)
      {
         double trail_start = sl_distance_points * Trail_Start_Multiplier;
         double trail_step = sl_distance_points * Trail_Step_Multiplier;
         riskMgr.TrailingStop(ticket, trail_start, trail_step);
      }
   }
}

//+------------------------------------------------------------------+
//| Check Daily Reset                                                  |
//+------------------------------------------------------------------+
void CheckDailyReset()
{
   static datetime lastResetDay = 0;
   MqlDateTime dt;
   TimeCurrent(dt);
   
   if(dt.day != lastResetDay)
   {
      state.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      lastResetDay = dt.day;
      
      // Check if max daily loss exceeded
      double currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double dailyLoss = state.dayStartBalance - currentBalance;
      double maxLoss = state.dayStartBalance * (Max_Daily_Loss_Percent / 100.0);
      
      if(dailyLoss >= maxLoss)
      {
         state.tradingEnabled = false;
         Print("TRADING HALTED - Max daily loss reached: ", dailyLoss);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Event Handler                                                |
//+------------------------------------------------------------------+
void OnTrade()
{
   // Update plasticity after trade closes
   if(HistorySelect(TimeCurrent() - 86400, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      if(total > 0)
      {
         ulong ticket = HistoryDealGetTicket(total - 1);
         if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == MAGIC_NUMBER)
         {
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
               double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
               double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
               long deal_type = HistoryDealGetInteger(ticket, DEAL_TYPE);
               double close_price = HistoryDealGetDouble(ticket, DEAL_PRICE);
               datetime close_time = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

               // Get entry data
               double open_price = state.lastTradeOpenPrice;
               datetime open_time = state.lastTradeOpenTime;
               int direction = (deal_type == DEAL_TYPE_SELL) ? 1 : -1; // Opposite of exit type

               // Update rolling accuracy
               bool isWin = profit > 0;
               for(int i = ArraySize(state.rollingAccuracy) - 1; i > 0; i--)
               {
                  state.rollingAccuracy[i] = state.rollingAccuracy[i-1];
               }
               state.rollingAccuracy[0] = isWin ? 1.0 : 0.0;

               // Update FPF plasticity
               double reward = MathTanh(profit / 1000.0);
               fpf.UpdateJ(reward);

               // Calculate R-multiple
               double sl_distance = MathAbs(open_price - state.lastTradeOpenPrice);
               double rMultiple = (sl_distance > 0) ? MathAbs(profit) / sl_distance : 0;

               // Record pattern for learning
               if(Enable_Learning)
               {
                  MqlDateTime dt;
                  TimeToStruct(open_time, dt);

                  learningEngine.RecordPattern(
                     state.currentPhi, state.currentDecPot, state.mlProbability,
                     state.currentATR, 50.0, // RSI placeholder
                     signalDetector.GetCompressionScore(),
                     signalDetector.GetSweepScore(),
                     signalDetector.GetTimeframeAlignment(),
                     state.isTrendingMarket, state.isHighVolatility,
                     direction, dt.hour, profit, rMultiple, open_time
                  );
               }

               // Record for compliance
               if(Enable_Compliance)
               {
                  compliance.RecordTrade(open_time, close_time, open_price,
                                        close_price, profit, volume, direction, _Symbol);
               }

               // Update stats and consecutive tracking
               if(isWin)
               {
                  state.tradesWon++;
                  state.consecutiveWins++;
                  state.consecutiveLosses = 0;
               }
               else
               {
                  state.tradesLost++;
                  state.consecutiveLosses++;
                  state.consecutiveWins = 0;
               }

               Print("Trade closed - Profit: ", profit, " R-Mult: ", rMultiple,
                     " Reward: ", reward,
                     " Consecutive W/L: ", state.consecutiveWins, "/", state.consecutiveLosses);

               // Trigger learning update periodically
               if(Enable_Learning && (state.tradesWon + state.tradesLost) % 10 == 0)
               {
                  Print("LEARNING: Triggering periodic optimization...");
                  learningEngine.LearnFromPatterns();
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                      |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   MqlDateTime dt;
   TimeCurrent(dt);

   // Check if current hour is within trading window
   if(dt.hour >= Trade_Start_Hour && dt.hour < Trade_End_Hour)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Detect Market Regime (Trending vs Ranging)                        |
//+------------------------------------------------------------------+
void DetectMarketRegime()
{
   // Use ADX to determine if trending or ranging
   double adx_buffer[];
   ArraySetAsSeries(adx_buffer, true);

   int h_adx = iADX(_Symbol, TF_Primary, 14);
   if(h_adx == INVALID_HANDLE) return;

   if(CopyBuffer(h_adx, 0, 0, 1, adx_buffer) > 0)
   {
      double adx = adx_buffer[0];
      state.isTrendingMarket = (adx > 25.0); // ADX > 25 = trending
   }
   IndicatorRelease(h_adx);

   // Check volatility
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, TF_Primary, 0, 1, rates) > 0)
   {
      double price = rates[0].close;
      if(price > 0 && state.currentATR > 0)
      {
         double atr_pct = (state.currentATR / price) * 100.0;
         state.isHighVolatility = (atr_pct > 1.5); // ATR > 1.5% of price
      }
   }
}

//+------------------------------------------------------------------+
//| Update Adaptive Risk Based on Performance                         |
//+------------------------------------------------------------------+
void UpdateAdaptiveRisk()
{
   if(!Adaptive_Risk)
   {
      state.currentRiskMultiplier = 1.0;
      return;
   }

   // Reduce risk after consecutive losses
   if(state.consecutiveLosses >= 3)
      state.currentRiskMultiplier = 0.5; // Half risk
   else if(state.consecutiveLosses == 2)
      state.currentRiskMultiplier = 0.75; // 75% risk
   // Increase risk after consecutive wins
   else if(state.consecutiveWins >= 3)
      state.currentRiskMultiplier = 1.3; // 130% risk
   else if(state.consecutiveWins >= 2)
      state.currentRiskMultiplier = 1.15; // 115% risk
   else
      state.currentRiskMultiplier = 1.0; // Normal risk

   // Cap multiplier
   if(state.currentRiskMultiplier > 1.5) state.currentRiskMultiplier = 1.5;
   if(state.currentRiskMultiplier < 0.3) state.currentRiskMultiplier = 0.3;
}

//+------------------------------------------------------------------+
//| Improved Direction Determination with Momentum                    |
//+------------------------------------------------------------------+
int DetermineDirectionImproved()
{
   // Get EMA values
   double ema_fast_pri[], ema_slow_pri[], ema_fast_sec[], ema_slow_sec[];
   ArraySetAsSeries(ema_fast_pri, true);
   ArraySetAsSeries(ema_slow_pri, true);
   ArraySetAsSeries(ema_fast_sec, true);
   ArraySetAsSeries(ema_slow_sec, true);

   int h_ema_fast_pri = iMA(_Symbol, TF_Primary, 12, 0, MODE_EMA, PRICE_CLOSE);
   int h_ema_slow_pri = iMA(_Symbol, TF_Primary, 26, 0, MODE_EMA, PRICE_CLOSE);
   int h_ema_fast_sec = iMA(_Symbol, TF_Secondary, 12, 0, MODE_EMA, PRICE_CLOSE);
   int h_ema_slow_sec = iMA(_Symbol, TF_Secondary, 26, 0, MODE_EMA, PRICE_CLOSE);

   if(h_ema_fast_pri == INVALID_HANDLE || h_ema_slow_pri == INVALID_HANDLE ||
      h_ema_fast_sec == INVALID_HANDLE || h_ema_slow_sec == INVALID_HANDLE)
      return 0;

   CopyBuffer(h_ema_fast_pri, 0, 0, 1, ema_fast_pri);
   CopyBuffer(h_ema_slow_pri, 0, 0, 1, ema_slow_pri);
   CopyBuffer(h_ema_fast_sec, 0, 0, 1, ema_fast_sec);
   CopyBuffer(h_ema_slow_sec, 0, 0, 1, ema_slow_sec);

   // Get RSI for momentum confirmation
   double rsi_buffer[];
   ArraySetAsSeries(rsi_buffer, true);
   int h_rsi = iRSI(_Symbol, TF_Primary, 14, PRICE_CLOSE);
   double rsi = 50.0;
   if(h_rsi != INVALID_HANDLE)
   {
      if(CopyBuffer(h_rsi, 0, 0, 1, rsi_buffer) > 0)
         rsi = rsi_buffer[0];
      IndicatorRelease(h_rsi);
   }

   // Get current price and volume
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   CopyRates(_Symbol, TF_Primary, 0, 3, rates);
   double price = rates[0].close;

   // Volume confirmation
   long volumes[];
   ArraySetAsSeries(volumes, true);
   CopyTickVolume(_Symbol, TF_Primary, 0, 3, volumes);
   double vol_ratio = (volumes[1] > 0) ? ((double)volumes[0] / volumes[1]) : 1.0;

   // Check alignment
   bool bullishPrimary = ema_fast_pri[0] > ema_slow_pri[0];
   bool bullishSecondary = ema_fast_sec[0] > ema_slow_sec[0];
   bool priceAboveEMA = price > ema_fast_pri[0];

   bool bearishPrimary = ema_fast_pri[0] < ema_slow_pri[0];
   bool bearishSecondary = ema_fast_sec[0] < ema_slow_sec[0];
   bool priceBelowEMA = price < ema_fast_pri[0];

   // FPF bias
   double fpfBias = fpf.GetPhi(1.0);

   // Release handles
   IndicatorRelease(h_ema_fast_pri);
   IndicatorRelease(h_ema_slow_pri);
   IndicatorRelease(h_ema_fast_sec);
   IndicatorRelease(h_ema_slow_sec);

   // BULLISH conditions: EMAs aligned + RSI confirming + volume + FPF positive
   if(bullishPrimary && bullishSecondary && priceAboveEMA &&
      rsi > 45 && rsi < 75 && // Not overbought
      vol_ratio > 0.8 && // Decent volume
      fpfBias > 0)
      return 1;

   // BEARISH conditions: EMAs aligned + RSI confirming + volume + FPF negative
   if(bearishPrimary && bearishSecondary && priceBelowEMA &&
      rsi < 55 && rsi > 25 && // Not oversold
      vol_ratio > 0.8 &&
      fpfBias < 0)
      return -1;

   return 0;
}

//+------------------------------------------------------------------+
//| Execute Trade With Dynamic ATR-Based Levels                       |
//+------------------------------------------------------------------+
void ExecuteTradeWithDynamicLevels(int direction)
{
   // Calculate ATR-based stop loss
   double atr_sl_distance = state.currentATR * ATR_SL_Multiplier;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double sl_points = atr_sl_distance / point;

   // Adjust lot size with adaptive risk
   double base_lot = riskMgr.CalculateLotSize(_Symbol, sl_points);
   double adjusted_lot = base_lot * state.currentRiskMultiplier;

   // Normalize
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   adjusted_lot = MathFloor(adjusted_lot / lot_step) * lot_step;
   if(adjusted_lot < min_lot) adjusted_lot = min_lot;
   if(adjusted_lot > max_lot) adjusted_lot = max_lot;

   if(adjusted_lot <= 0) return;

   double price = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) :
                                     SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double sl, tp;
   riskMgr.CalculateSLTP(_Symbol, direction, price, sl_points, sl, tp);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.symbol = _Symbol;
   request.volume = adjusted_lot;
   request.type = (direction > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   request.price = price;
   request.sl = sl;
   request.tp = tp;
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = StringFormat("FPF_ML:%.2f_Phi:%.2f_ATR:%.1f",
                                   state.mlProbability, state.currentPhi, state.currentATR);

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("Trade opened - Ticket: ", result.order,
               " Dir: ", (direction > 0 ? "BUY" : "SELL"),
               " Lot: ", adjusted_lot,
               " SL: ", sl_points, " pts",
               " ML: ", state.mlProbability,
               " Prediction: ", state.predictedSuccess,
               " RiskMult: ", state.currentRiskMultiplier);

         state.lastTradeTime = TimeCurrent();
         state.lastTradeTicket = result.order;
         state.lastTradeOpenTime = TimeCurrent();
         state.lastTradeOpenPrice = price;
      }
      else
      {
         Print("Trade failed - Return code: ", result.retcode);
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Partial Take Profits                                       |
//+------------------------------------------------------------------+
void ManagePartialTakeProfits(ulong ticket, double entry_price, double sl_distance_points)
{
   if(!PositionSelectByTicket(ticket)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long pos_type = PositionGetInteger(POSITION_TYPE);
   double current_volume = PositionGetDouble(POSITION_VOLUME);
   string comment = PositionGetString(POSITION_COMMENT);

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double current_price = (pos_type == POSITION_TYPE_BUY) ?
                          SymbolInfoDouble(symbol, SYMBOL_BID) :
                          SymbolInfoDouble(symbol, SYMBOL_ASK);

   // Calculate profit in R (risk units)
   double profit_points = 0;
   if(pos_type == POSITION_TYPE_BUY)
      profit_points = (current_price - entry_price) / point;
   else
      profit_points = (entry_price - current_price) / point;

   double profit_R = profit_points / sl_distance_points;

   // Check if TP1 hit (1.5R) - close 40%
   if(profit_R >= 1.5 && StringFind(comment, "TP1") < 0)
   {
      double close_volume = NormalizeDouble(current_volume * Partial_TP1_Ratio, 2);
      if(close_volume >= SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
      {
         ClosePartialPosition(ticket, close_volume, "TP1_1.5R");
         Print("Partial TP1 executed at 1.5R - Closed ", (Partial_TP1_Ratio*100), "%");
      }
   }

   // Check if TP2 hit (2.5R) - close 30%
   if(profit_R >= 2.5 && StringFind(comment, "TP2") < 0)
   {
      double close_volume = NormalizeDouble(current_volume * Partial_TP2_Ratio, 2);
      if(close_volume >= SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN))
      {
         ClosePartialPosition(ticket, close_volume, "TP2_2.5R");
         Print("Partial TP2 executed at 2.5R - Closed ", (Partial_TP2_Ratio*100), "%");
      }
   }
   // Remaining 30% rides to full TP or gets trailed
}

//+------------------------------------------------------------------+
//| Close Partial Position                                            |
//+------------------------------------------------------------------+
void ClosePartialPosition(ulong ticket, double volume, string reason)
{
   if(!PositionSelectByTicket(ticket)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long pos_type = PositionGetInteger(POSITION_TYPE);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = symbol;
   request.volume = volume;
   request.type = (pos_type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = (request.type == ORDER_TYPE_BUY) ?
                   SymbolInfoDouble(symbol, SYMBOL_ASK) :
                   SymbolInfoDouble(symbol, SYMBOL_BID);
   request.deviation = 10;
   request.magic = MAGIC_NUMBER;
   request.comment = reason;

   OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int totalTrades = state.tradesWon + state.tradesLost;
   double winRate = (totalTrades > 0) ? ((double)state.tradesWon / totalTrades * 100) : 0;
   double dailyPL = AccountInfoDouble(ACCOUNT_BALANCE) - state.dayStartBalance;
   double dailyPL_pct = (state.dayStartBalance > 0) ? (dailyPL / state.dayStartBalance * 100) : 0;

   string dashboard = "\n";
   dashboard += "=== FPF OPTIMIZED EA v2.1 (LEARNING + COMPLIANCE) ===\n";
   dashboard += "Status: " + (state.tradingEnabled ? "ACTIVE" : "PAUSED") +
                " | Compliance: " + (state.complianceOK ? "OK" : "VIOLATION") + "\n";
   dashboard += "ML Prob: " + DoubleToString(state.mlProbability, 3) +
                " | Phi: " + DoubleToString(state.currentPhi, 3) +
                " | DecPot: " + DoubleToString(state.currentDecPot, 3) + "\n";

   // Show learning metrics if enabled
   if(Enable_Learning)
   {
      dashboard += "Prediction: " + DoubleToString(state.predictedSuccess * 100, 1) + "%" +
                   " | Learned Phi>: " + DoubleToString(state.learnedPhiMin, 3) +
                   " | ML>: " + DoubleToString(state.learnedMLProbMin, 3) + "\n";
   }

   dashboard += "Regime: " + (state.isTrendingMarket ? "TRENDING" : "RANGING") +
                " | Vol: " + (state.isHighVolatility ? "HIGH" : "NORMAL") +
                " | ATR: " + DoubleToString(state.currentATR, 1) + "\n";
   dashboard += "Risk Mult: " + DoubleToString(state.currentRiskMultiplier, 2) +
                " | Streak W/L: " + IntegerToString(state.consecutiveWins) + "/" +
                IntegerToString(state.consecutiveLosses) + "\n";
   dashboard += "---\n";
   dashboard += "Trades: " + IntegerToString(totalTrades) +
                " | Win Rate: " + DoubleToString(winRate, 1) + "%" +
                " | W/L: " + IntegerToString(state.tradesWon) + "/" +
                IntegerToString(state.tradesLost) + "\n";
   dashboard += "Daily P/L: " + DoubleToString(dailyPL, 2) +
                " (" + DoubleToString(dailyPL_pct, 2) + "%)\n";
   dashboard += "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) +
                " | Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   dashboard += "Positions: " + IntegerToString(PositionsTotal()) + "/" +
                IntegerToString(Max_Positions) + "\n";

   Comment(dashboard);
}
