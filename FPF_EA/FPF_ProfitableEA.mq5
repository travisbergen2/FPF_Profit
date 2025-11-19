//+------------------------------------------------------------------+
//| FPF_ProfitableEA.mq5                                              |
//| Fractal Personality Field Trading EA                              |
//| Low DD, High Win Rate System with ML Gating                       |
//+------------------------------------------------------------------+
#property copyright "FPF Trading System"
#property version   "2.00"
#property strict

#include "Include/FPF_Engine.mqh"
#include "Include/BigMoveSignals.mqh"
#include "Include/RiskManager.mqh"

//--- Input Parameters
input group "=== FPF Core Settings ==="
input double      FPF_Phi_Entry = 0.08;           // Min Phi for entry (lowered from 0.12)
input double      FPF_DecisionPot_Min = 0.05;     // Min decision potential (lowered from 0.10)
input double      ML_Entry_Threshold = 0.55;      // ML probability threshold (lowered from 0.75)
input double      ML_Stop_Accuracy = 0.45;        // Stop trading if accuracy drops below (lowered from 0.60)

input group "=== Risk Management ==="
input double      Risk_Percent = 1.0;              // Risk per trade %
input double      Max_Daily_Loss_Percent = 3.0;   // Max daily loss %
input int         Max_Positions = 3;               // Max concurrent positions
input double      Base_SL_Points = 150;            // Base stop loss points
input double      Base_TP_Multiplier = 2.5;       // TP multiplier (R:R)

input group "=== Signal Detection ==="
input int         ATR_Period = 14;
input int         Compression_Lookback = 20;
input double      Compression_Threshold = 0.3;
input int         Volume_MA_Period = 20;
input double      Sweep_Tolerance_Points = 10;

input group "=== Timeframe Settings ==="
input ENUM_TIMEFRAMES TF_Primary = PERIOD_M15;
input ENUM_TIMEFRAMES TF_Secondary = PERIOD_M5;
input ENUM_TIMEFRAMES TF_Tertiary = PERIOD_M1;

input group "=== Advanced ==="
input bool        Enable_Breakeven = true;
input double      Breakeven_Profit_Points = 100;
input bool        Enable_Trailing = true;
input double      Trail_Start_Points = 150;
input double      Trail_Step_Points = 50;
input bool        Enable_Debug = true;           // ENABLED for debugging

//--- Global Objects
FractalPersonalityField fpf;
BigMoveSignalDetector signalDetector;
RiskManager riskMgr;

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
   
   // Initialize risk manager
   riskMgr.Init(Risk_Percent, Max_Daily_Loss_Percent, Max_Positions, 
                Base_SL_Points, Base_TP_Multiplier);
   
   // Initialize state
   state.dayStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   state.tradesWon = 0;
   state.tradesLost = 0;
   state.tradingEnabled = true;
   state.lastTradeTime = 0;
   ArrayResize(state.rollingAccuracy, 50);
   ArrayInitialize(state.rollingAccuracy, 0.5);
   
   Print("FPF Profitable EA Initialized Successfully");
   Print("ML Entry Threshold: ", ML_Entry_Threshold);
   Print("ML Stop Accuracy: ", ML_Stop_Accuracy);
   
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
   
   if(Enable_Debug)
   {
      Print("FPF Update - Phi: ", state.currentPhi, 
            " DecPot: ", state.currentDecPot,
            " Ae: ", Ae, " An: ", An);
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
//| Calculate ML Probability                                           |
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
   
   // Combine features (simplified ML model)
   double signalStrength = (compressionScore * 0.25 + sweepScore * 0.20 + 
                            stopHuntScore * 0.15 + wickScore * 0.15 + 
                            tfAlignScore * 0.25);
   
   double fpfStrength = (coh * 0.30 + align * 0.20 + S_val * 0.30 - A_val * 0.20);
   
   // Final probability
   double probability = (signalStrength * 0.60 + fpfStrength * 0.40);
   probability = MathMax(0.0, MathMin(1.0, probability));
   
   return probability;
}

//+------------------------------------------------------------------+
//| Check For Entry                                                    |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(Enable_Debug)
   {
      Print("========================================");
      Print("=== CHECKING FOR ENTRY ===");
      Print("Phi: ", state.currentPhi, " (Required: ", FPF_Phi_Entry, ")");
      Print("DecPot: ", state.currentDecPot, " (Required: ", FPF_DecisionPot_Min, ")");
      Print("ML Prob: ", state.mlProbability, " (Required: ", ML_Entry_Threshold, ")");
   }

   // Primary FPF gating
   if(state.currentPhi < FPF_Phi_Entry)
   {
      if(Enable_Debug) Print("Entry rejected - Low Phi: ", state.currentPhi);
      return;
   }

   if(state.currentDecPot < FPF_DecisionPot_Min)
   {
      if(Enable_Debug) Print("Entry rejected - Low DecPot: ", state.currentDecPot);
      return;
   }

   // ML gating
   if(state.mlProbability < ML_Entry_Threshold)
   {
      if(Enable_Debug) Print("Entry rejected - Low ML prob: ", state.mlProbability);
      return;
   }
   
   // Detect big move signals
   signalDetector.Update(_Symbol, TF_Primary);

   bool compressionDetected = signalDetector.IsCompressionDetected();
   bool sweepsDetected = signalDetector.AreSweepsDetected();
   bool spreadNarrowing = signalDetector.IsSpreadNarrowing();
   bool stopHuntDetected = signalDetector.IsStopHuntDetected();
   bool wickTestDetected = signalDetector.IsWickTestDetected();
   bool tfAlignment = signalDetector.IsTimeframeAligned();

   if(Enable_Debug)
   {
      Print("=== SIGNAL DETECTION ===");
      Print("Compression: ", compressionDetected, " (Score: ", signalDetector.GetCompressionScore(), ")");
      Print("Sweeps: ", sweepsDetected, " (Score: ", signalDetector.GetSweepScore(), ")");
      Print("StopHunt: ", stopHuntDetected, " (Score: ", signalDetector.GetStopHuntScore(), ")");
      Print("WickTest: ", wickTestDetected, " (Score: ", signalDetector.GetWickScore(), ")");
      Print("TF_Align: ", tfAlignment, " (Score: ", signalDetector.GetTimeframeAlignment(), ")");
   }
   
   // Require multiple signal confirmations
   int signalCount = 0;
   if(compressionDetected) signalCount++;
   if(sweepsDetected) signalCount++;
   if(stopHuntDetected) signalCount++;
   if(wickTestDetected) signalCount++;
   if(tfAlignment) signalCount++;

   if(signalCount < 2)  // Lowered from 3 to 2 for more trade opportunities
   {
      if(Enable_Debug) Print("Entry rejected - Insufficient signals: ", signalCount);
      return;
   }
   
   // Determine direction
   int direction = DetermineDirection();
   if(direction == 0)
   {
      if(Enable_Debug) Print("Entry rejected - No clear direction");
      return;
   }
   
   // Execute trade
   ExecuteTrade(direction);
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

   if(Enable_Debug)
   {
      Print("Direction Analysis: BullPri=", bullishPrimary, " BullSec=", bullishSecondary,
            " PriceAbove=", priceAboveEMA, " FPFBias=", fpfBias);
      Print("Direction Analysis: BearPri=", bearishPrimary, " BearSec=", bearishSecondary,
            " PriceBelow=", priceBelowEMA);
   }

   // Relaxed direction requirements - only need primary timeframe + FPF alignment
   if(bullishPrimary && priceAboveEMA && fpfBias > 0)
      return 1;  // Buy

   if(bearishPrimary && priceBelowEMA && fpfBias < 0)
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
      
      // Breakeven logic
      if(Enable_Breakeven)
      {
         riskMgr.MoveToBreakeven(ticket, Breakeven_Profit_Points);
      }
      
      // Trailing stop logic
      if(Enable_Trailing)
      {
         riskMgr.TrailingStop(ticket, Trail_Start_Points, Trail_Step_Points);
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
               
               // Update stats
               if(isWin) state.tradesWon++;
               else state.tradesLost++;
               
               Print("Trade closed - Profit: ", profit, " Reward: ", reward);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Update Dashboard                                                   |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   int totalTrades = state.tradesWon + state.tradesLost;
   double winRate = (totalTrades > 0) ? ((double)state.tradesWon / totalTrades * 100) : 0;
   
   string dashboard = "\n";
   dashboard += "=== FPF PROFITABLE EA ===\n";
   dashboard += "Status: " + (state.tradingEnabled ? "ACTIVE" : "PAUSED") + "\n";
   dashboard += "ML Probability: " + DoubleToString(state.mlProbability, 3) + "\n";
   dashboard += "Phi: " + DoubleToString(state.currentPhi, 3) + " | DecPot: " + DoubleToString(state.currentDecPot, 3) + "\n";
   dashboard += "---\n";
   dashboard += "Trades: " + IntegerToString(totalTrades) + " | Win Rate: " + DoubleToString(winRate, 1) + "%\n";
   dashboard += "W/L: " + IntegerToString(state.tradesWon) + "/" + IntegerToString(state.tradesLost) + "\n";
   dashboard += "Balance: " + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + "\n";
   dashboard += "Equity: " + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + "\n";
   dashboard += "Positions: " + IntegerToString(PositionsTotal()) + "/" + IntegerToString(Max_Positions) + "\n";
   
   Comment(dashboard);
}
