//+------------------------------------------------------------------+
//| RiskManager.mqh                                                    |
//| Advanced risk management with dynamic position sizing             |
//| Low drawdown protection system                                     |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Risk Manager Class                                                 |
//+------------------------------------------------------------------+
class RiskManager
{
private:
   // Settings
   double risk_percent;
   double max_daily_loss_percent;
   int max_positions;
   double base_sl_points;
   double base_tp_multiplier;
   
   // State tracking
   double day_start_balance;
   datetime last_reset_day;
   
public:
   //+------------------------------------------------------------------+
   //| Constructor                                                        |
   //+------------------------------------------------------------------+
   RiskManager()
   {
      risk_percent = 1.0;
      max_daily_loss_percent = 3.0;
      max_positions = 3;
      base_sl_points = 150;
      base_tp_multiplier = 2.5;
      
      day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      last_reset_day = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Initialize                                                         |
   //+------------------------------------------------------------------+
   void Init(double risk_pct, double max_daily_loss, int max_pos, double sl_pts, double tp_mult)
   {
      risk_percent = risk_pct;
      max_daily_loss_percent = max_daily_loss;
      max_positions = max_pos;
      base_sl_points = sl_pts;
      base_tp_multiplier = tp_mult;
      
      day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      MqlDateTime dt;
      TimeCurrent(dt);
      last_reset_day = dt.day;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Dynamic Lot Size                                        |
   //+------------------------------------------------------------------+
   double CalculateLotSize(string symbol, double sl_points)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double risk_amount = balance * (risk_percent / 100.0);
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      // Calculate lot size
      double sl_in_currency = (sl_points * point) * (tick_value / tick_size);
      double lot_size = risk_amount / sl_in_currency;
      
      // Normalize to lot step
      lot_size = MathFloor(lot_size / lot_step) * lot_step;
      
      // Clamp to broker limits
      if(lot_size < min_lot) lot_size = min_lot;
      if(lot_size > max_lot) lot_size = max_lot;
      
      // Reduce size based on current positions (scaling down)
      int current_positions = PositionsTotal();
      if(current_positions > 0)
      {
         double scale_factor = 1.0 - (current_positions * 0.2);
         lot_size *= MathMax(scale_factor, 0.4);
      }
      
      return NormalizeLot(symbol, lot_size);
   }
   
   //+------------------------------------------------------------------+
   //| Calculate SL and TP Levels                                        |
   //+------------------------------------------------------------------+
   void CalculateSLTP(string symbol, int direction, double entry_price, 
                      double sl_points, double &sl, double &tp)
   {
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      if(direction > 0) // Buy
      {
         sl = NormalizeDouble(entry_price - (sl_points * point), digits);
         tp = NormalizeDouble(entry_price + (sl_points * base_tp_multiplier * point), digits);
      }
      else // Sell
      {
         sl = NormalizeDouble(entry_price + (sl_points * point), digits);
         tp = NormalizeDouble(entry_price - (sl_points * base_tp_multiplier * point), digits);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if can open new position                                    |
   //+------------------------------------------------------------------+
   bool CanOpenPosition()
   {
      // Check max positions
      int current_positions = PositionsTotal();
      if(current_positions >= max_positions)
         return false;
      
      // Check daily loss limit
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double daily_loss = day_start_balance - current_balance;
      double max_loss = day_start_balance * (max_daily_loss_percent / 100.0);
      
      if(daily_loss >= max_loss)
      {
         Print("Daily loss limit reached: ", daily_loss, " / ", max_loss);
         return false;
      }
      
      // Check available margin
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double margin_level = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      
      if(margin_level > 0 && margin_level < 200)
      {
         Print("Low margin level: ", margin_level, "%");
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Move position to breakeven                                        |
   //+------------------------------------------------------------------+
   bool MoveToBreakeven(ulong ticket, double profit_points)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      double current_price = (pos_type == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(symbol, SYMBOL_BID) :
                             SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      // Calculate profit in points
      double profit_in_points = 0;
      if(pos_type == POSITION_TYPE_BUY)
         profit_in_points = (current_price - entry_price) / point;
      else
         profit_in_points = (entry_price - current_price) / point;
      
      // Check if profit threshold reached and SL not at breakeven
      if(profit_in_points >= profit_points)
      {
         double new_sl = NormalizeDouble(entry_price, digits);
         
         // Check if SL needs updating
         bool needs_update = false;
         if(pos_type == POSITION_TYPE_BUY && new_sl > current_sl)
            needs_update = true;
         if(pos_type == POSITION_TYPE_SELL && new_sl < current_sl)
            needs_update = true;
         
         if(needs_update)
         {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.symbol = symbol;
            request.sl = new_sl;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result))
            {
               if(result.retcode == TRADE_RETCODE_DONE)
               {
                  Print("Moved to breakeven - Ticket: ", ticket);
                  return true;
               }
            }
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Trailing stop                                                      |
   //+------------------------------------------------------------------+
   bool TrailingStop(ulong ticket, double start_points, double step_points)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      long pos_type = PositionGetInteger(POSITION_TYPE);
      
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      
      double current_price = (pos_type == POSITION_TYPE_BUY) ? 
                             SymbolInfoDouble(symbol, SYMBOL_BID) :
                             SymbolInfoDouble(symbol, SYMBOL_ASK);
      
      // Calculate profit in points
      double profit_in_points = 0;
      if(pos_type == POSITION_TYPE_BUY)
         profit_in_points = (current_price - entry_price) / point;
      else
         profit_in_points = (entry_price - current_price) / point;
      
      // Only trail if past start threshold
      if(profit_in_points < start_points)
         return false;
      
      // Calculate new SL
      double new_sl = 0;
      if(pos_type == POSITION_TYPE_BUY)
      {
         new_sl = NormalizeDouble(current_price - (step_points * point), digits);
         
         // Only update if new SL is higher
         if(new_sl <= current_sl)
            return false;
      }
      else
      {
         new_sl = NormalizeDouble(current_price + (step_points * point), digits);
         
         // Only update if new SL is lower
         if(new_sl >= current_sl)
            return false;
      }
      
      // Update SL
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol = symbol;
      request.sl = new_sl;
      request.tp = PositionGetDouble(POSITION_TP);
      
      if(OrderSend(request, result))
      {
         if(result.retcode == TRADE_RETCODE_DONE)
         {
            Print("Trailing stop updated - Ticket: ", ticket, " New SL: ", new_sl);
            return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Get current drawdown percentage                                   |
   //+------------------------------------------------------------------+
   double GetCurrentDrawdown()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      if(balance > 0)
         return ((balance - equity) / balance) * 100.0;
      
      return 0.0;
   }
   
   //+------------------------------------------------------------------+
   //| Get daily P&L                                                      |
   //+------------------------------------------------------------------+
   double GetDailyPL()
   {
      double current_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      return current_balance - day_start_balance;
   }
   
   //+------------------------------------------------------------------+
   //| Reset daily tracking (call at start of new day)                  |
   //+------------------------------------------------------------------+
   void ResetDaily()
   {
      day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      MqlDateTime dt;
      TimeCurrent(dt);
      last_reset_day = dt.day;
   }
   
   //+------------------------------------------------------------------+
   //| Normalize lot size                                                |
   //+------------------------------------------------------------------+
   double NormalizeLot(string symbol, double lot_size)
   {
      double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      lot_size = MathFloor(lot_size / lot_step) * lot_step;
      
      if(lot_size < min_lot) lot_size = min_lot;
      if(lot_size > max_lot) lot_size = max_lot;
      
      return NormalizeDouble(lot_size, 2);
   }
   
   //+------------------------------------------------------------------+
   //| Get position size based on volatility                             |
   //+------------------------------------------------------------------+
   double GetVolatilityAdjustedSize(string symbol, double base_size)
   {
      // Get ATR for volatility
      double atr = iATR(symbol, PERIOD_H1, 14);
      double price = SymbolInfoDouble(symbol, SYMBOL_BID);
      
      if(price == 0) return base_size;
      
      double volatility = atr / price;
      
      // Reduce size during high volatility
      double adjustment = 1.0;
      if(volatility > 0.02)
         adjustment = 0.7;
      else if(volatility > 0.015)
         adjustment = 0.85;
      
      return base_size * adjustment;
   }
   
   //+------------------------------------------------------------------+
   //| Emergency close all positions                                     |
   //+------------------------------------------------------------------+
   void EmergencyCloseAll()
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action = TRADE_ACTION_DEAL;
         request.position = ticket;
         request.symbol = PositionGetString(POSITION_SYMBOL);
         request.volume = PositionGetDouble(POSITION_VOLUME);
         request.type = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 
                        ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (request.type == ORDER_TYPE_BUY) ? 
                        SymbolInfoDouble(request.symbol, SYMBOL_ASK) :
                        SymbolInfoDouble(request.symbol, SYMBOL_BID);
         
         if(!OrderSend(request, result))
         {
            Print("Emergency close failed for ticket: ", ticket, " Error: ", result.retcode);
         }
      }
      
      Print("EMERGENCY: All positions close attempted!");
   }
};
