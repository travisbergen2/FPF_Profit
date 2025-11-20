//+------------------------------------------------------------------+
//| TradeController.mqh                                                |
//| The Motor System: Orchestrates nervous system, intuition, trading |
//| Decides when to reach (enter) or pull back (exit) based on feel   |
//+------------------------------------------------------------------+
#property strict

#include "Types.mqh"
#include "TickFieldAccumulator.mqh"
#include "BarMetaLearner.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| TradeController: Main orchestration layer                         |
//| Nervous system → Intuition → Motor action (trades)                |
//+------------------------------------------------------------------+
class TradeController
{
private:
   string                  m_symbol;
   ENUM_TIMEFRAMES         m_tf;
   TickFieldAccumulator    *m_acc;           // nervous system
   BarMetaLearner          *m_learner;       // intuition/memory
   CTrade                  m_trade;          // order execution

   // Risk parameters
   double                  m_riskPercent;
   double                  m_maxDailyLossPercent;
   double                  m_startOfDayEquity;

   // State tracking
   BarSummary              m_lastBarSummary;
   bool                    m_hasLastBar;
   datetime                m_lastBarTime;

   // Position tracking for learning
   struct PositionMemory
   {
      ulong       ticket;
      datetime    entry_time;
      double      entry_price;
      double      sl;
      int         direction;  // +1 long, -1 short
      BarSummary  entry_bar;
      bool        active;
   };

   PositionMemory          m_positionMemory[];
   int                     m_numPositions;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   TradeController(const string symbol,
                   ENUM_TIMEFRAMES tf,
                   double riskPercent,
                   double maxDailyLossPercent)
   {
      m_symbol = symbol;
      m_tf = tf;
      m_riskPercent = riskPercent;
      m_maxDailyLossPercent = maxDailyLossPercent;

      m_acc = new TickFieldAccumulator(m_symbol, m_tf);
      m_learner = new BarMetaLearner(30, 0.1);

      m_hasLastBar = false;
      m_lastBarTime = 0;
      m_startOfDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);

      m_numPositions = 0;
      ArrayResize(m_positionMemory, 0);

      m_trade.SetExpertMagicNumber(123456);
      m_trade.SetDeviationInPoints(10);
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~TradeController()
   {
      if(m_acc != NULL)
         delete m_acc;
      if(m_learner != NULL)
         delete m_learner;
   }

   //+------------------------------------------------------------------+
   //| Init: Called from EA OnInit                                      |
   //+------------------------------------------------------------------+
   void Init()
   {
      m_startOfDayEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("TradeController initialized on ", m_symbol, " ", EnumToString(m_tf));
      Print("Nervous system active - sensing microstructure...");
   }

   //+------------------------------------------------------------------+
   //| OnTick: Main tick processing - the heartbeat                     |
   //| 1) Update nervous system (tick-level sensations)                 |
   //| 2) Check for bar boundaries                                      |
   //| 3) Manage open positions using current nervous state             |
   //| 4) Process closed positions for learning                         |
   //+------------------------------------------------------------------+
   void OnTick()
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);

      // 1) Update tick-level nervous system
      m_acc.OnTickUpdate(bid, ask);

      // 2) Check bar boundaries
      if(m_acc.IsNewBar())
      {
         BarSummary lastBar;
         if(m_acc.FinalizeLastBar(lastBar))
         {
            OnNewBar(lastBar);
         }
      }

      // 3) Manage existing positions using current nervous feel
      ManageOpenPositions();

      // 4) Process any just-closed trades to update learner
      ProcessClosedPositions();
   }

private:
   //+------------------------------------------------------------------+
   //| OnNewBar: Called when bar boundary is crossed                    |
   //| Use previous bar's fingerprint to predict next bar and decide    |
   //+------------------------------------------------------------------+
   void OnNewBar(const BarSummary &closedBar)
   {
      Print("New bar detected at ", closedBar.time,
            " | Learned contexts: ", m_learner.GetContextCount());

      // If we have a previous bar, use it to predict and maybe enter
      if(m_hasLastBar)
      {
         PredictionResult pred = m_learner.Predict(m_lastBarSummary);

         Print("Bar prediction - ExpR Long: ", DoubleToString(pred.expected_R_long, 2),
               " Short: ", DoubleToString(pred.expected_R_short, 2),
               " Conf: ", DoubleToString(pred.confidence, 2));

         // Evaluate entry at start of new bar
         EvaluateEntry(m_lastBarSummary, pred);
      }

      // Update last bar memory
      m_lastBarSummary = closedBar;
      m_hasLastBar = true;
      m_lastBarTime = closedBar.time;
   }

   //+------------------------------------------------------------------+
   //| EvaluateEntry: Decide whether to open trade at bar boundary      |
   //| Motor decision: reach (enter) or pull back (wait)?               |
   //+------------------------------------------------------------------+
   void EvaluateEntry(const BarSummary &recentBar, const PredictionResult &pred)
   {
      // Safety checks
      if(DailyLossExceeded())
      {
         Print("Daily loss limit exceeded - no new entries");
         return;
      }

      // Don't trade if already in position (simple version)
      if(PositionSelect(m_symbol))
      {
         Print("Already in position - skipping entry");
         return;
      }

      // Entry threshold: need positive expected R and minimum confidence
      double min_expected_R = 0.5;
      double min_confidence = 0.3;

      bool should_enter_long = (pred.expected_R_long > min_expected_R &&
                                 pred.confidence > min_confidence);

      bool should_enter_short = (pred.expected_R_short > min_expected_R &&
                                  pred.confidence > min_confidence);

      if(!should_enter_long && !should_enter_short)
      {
         Print("No entry signal - expected R or confidence too low");
         return;
      }

      // Decide direction based on stronger expected R
      int direction = 0;
      if(should_enter_long && pred.expected_R_long > pred.expected_R_short)
         direction = 1;
      else if(should_enter_short)
         direction = -1;

      if(direction != 0)
      {
         OpenTrade(direction, recentBar);
      }
   }

   //+------------------------------------------------------------------+
   //| OpenTrade: Execute entry based on nervous system intuition       |
   //+------------------------------------------------------------------+
   void OpenTrade(int direction, const BarSummary &entryBar)
   {
      double atr = entryBar.atr_value;
      if(atr <= 0)
      {
         Print("Invalid ATR - cannot calculate SL");
         return;
      }

      // Simple SL: 1.5 * ATR
      double sl_distance = atr * 1.5;
      double tp_distance = atr * 3.0;  // 2:1 R:R

      double price = (direction > 0) ?
                     SymbolInfoDouble(m_symbol, SYMBOL_ASK) :
                     SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double sl = (direction > 0) ? price - sl_distance : price + sl_distance;
      double tp = (direction > 0) ? price + tp_distance : price - tp_distance;

      // Calculate lot size based on risk
      double lots = CalculateLotSize(sl_distance);

      bool result = false;
      ulong ticket = 0;

      if(direction > 0)
      {
         result = m_trade.Buy(lots, m_symbol, price, sl, tp, "IntuitiveFlow Long");
         ticket = m_trade.ResultOrder();
      }
      else
      {
         result = m_trade.Sell(lots, m_symbol, price, sl, tp, "IntuitiveFlow Short");
         ticket = m_trade.ResultOrder();
      }

      if(result)
      {
         Print("Trade opened: ", (direction > 0 ? "LONG" : "SHORT"),
               " Lots: ", lots, " SL: ", sl, " TP: ", tp);

         // Store position memory for learning
         StorePositionMemory(ticket, price, sl, direction, entryBar);
      }
      else
      {
         Print("Trade failed: ", m_trade.ResultRetcodeDescription());
      }
   }

   //+------------------------------------------------------------------+
   //| ManageOpenPositions: Tick-level exit management                  |
   //| Use nervous system signals to exit early if needed               |
   //+------------------------------------------------------------------+
   void ManageOpenPositions()
   {
      // Simple version: let SL/TP handle exits
      // Could enhance with nervous system signals:
      // - Exit if compression spikes (danger sensation)
      // - Exit if alignment reverses (context shift)
      // For now, keep it simple
   }

   //+------------------------------------------------------------------+
   //| ProcessClosedPositions: Learn from closed trades                 |
   //| Feed outcomes back to meta-learner (build pattern memory)        |
   //+------------------------------------------------------------------+
   void ProcessClosedPositions()
   {
      for(int i = 0; i < m_numPositions; i++)
      {
         if(!m_positionMemory[i].active)
            continue;

         // Check if position still exists
         if(PositionSelectByTicket(m_positionMemory[i].ticket))
         {
            continue;  // Still open
         }

         // Position closed - calculate outcome
         if(HistorySelectByPosition(m_positionMemory[i].ticket))
         {
            int total = HistoryDealsTotal();
            if(total >= 2)  // Entry + exit deals
            {
               ulong exit_deal = HistoryDealGetTicket(total - 1);
               if(exit_deal > 0)
               {
                  double exit_price = HistoryDealGetDouble(exit_deal, DEAL_PRICE);
                  datetime exit_time = (datetime)HistoryDealGetInteger(exit_deal, DEAL_TIME);

                  // Calculate R-multiple
                  double entry_price = m_positionMemory[i].entry_price;
                  double sl = m_positionMemory[i].sl;
                  double sl_distance = MathAbs(entry_price - sl);

                  double profit_distance = 0.0;
                  if(m_positionMemory[i].direction > 0)
                     profit_distance = exit_price - entry_price;
                  else
                     profit_distance = entry_price - exit_price;

                  double R = (sl_distance > 0) ? profit_distance / sl_distance : 0.0;

                  // Create outcome
                  TradeOutcome outcome;
                  outcome.entry_time = m_positionMemory[i].entry_time;
                  outcome.exit_time = exit_time;
                  outcome.R_multiple = R;
                  outcome.direction = m_positionMemory[i].direction;
                  outcome.entry_bar = m_positionMemory[i].entry_bar;

                  // Feed to learner
                  m_learner.Update(outcome);

                  Print("Trade closed: R = ", DoubleToString(R, 2),
                        " | Meta-learner updated");

                  // Mark as processed
                  m_positionMemory[i].active = false;
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| StorePositionMemory: Remember position for learning              |
   //+------------------------------------------------------------------+
   void StorePositionMemory(ulong ticket, double entry_price, double sl,
                             int direction, const BarSummary &bar)
   {
      int newSize = m_numPositions + 1;
      ArrayResize(m_positionMemory, newSize);

      m_positionMemory[m_numPositions].ticket = ticket;
      m_positionMemory[m_numPositions].entry_time = TimeCurrent();
      m_positionMemory[m_numPositions].entry_price = entry_price;
      m_positionMemory[m_numPositions].sl = sl;
      m_positionMemory[m_numPositions].direction = direction;
      m_positionMemory[m_numPositions].entry_bar = bar;
      m_positionMemory[m_numPositions].active = true;

      m_numPositions++;
   }

   //+------------------------------------------------------------------+
   //| DailyLossExceeded: Check if daily risk limit hit                 |
   //+------------------------------------------------------------------+
   bool DailyLossExceeded() const
   {
      double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double loss_pct = (m_startOfDayEquity - current_equity) / m_startOfDayEquity * 100.0;

      return (loss_pct >= m_maxDailyLossPercent);
   }

   //+------------------------------------------------------------------+
   //| CalculateLotSize: Position sizing based on risk %                |
   //+------------------------------------------------------------------+
   double CalculateLotSize(double sl_points) const
   {
      double account_size = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amount = account_size * (m_riskPercent / 100.0);

      double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

      if(point == 0 || tick_value == 0)
         return 0.01;

      double lots = risk_amount / (sl_points * tick_value / point);

      // Normalize to allowed lot size
      double min_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      lots = MathFloor(lots / lot_step) * lot_step;
      lots = MathMax(min_lot, MathMin(max_lot, lots));

      return lots;
   }
};
