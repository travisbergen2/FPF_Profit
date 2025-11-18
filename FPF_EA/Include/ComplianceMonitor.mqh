//+------------------------------------------------------------------+
//| ComplianceMonitor.mqh                                             |
//| Monitors for forbidden trading patterns and compliance issues     |
//| Prevents wash trading, churning, and other prohibited behaviors   |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| Trade Record for Compliance Tracking                              |
//+------------------------------------------------------------------+
struct TradeRecord {
   datetime openTime;
   datetime closeTime;
   double openPrice;
   double closePrice;
   double profit;
   double volume;
   int direction;  // 1 = buy, -1 = sell
   string symbol;
};

//+------------------------------------------------------------------+
//| Compliance Monitor Class                                          |
//+------------------------------------------------------------------+
class ComplianceMonitor
{
private:
   TradeRecord tradeHistory[];
   int maxHistorySize;

   // Compliance thresholds
   double maxDailyTurnover;
   int maxTradesPerHour;
   int maxRapidReversals;
   double minHoldingTimeSec;
   double maxCorrelatedTrades;

   // Tracking
   datetime lastTradeTime;
   int tradesThisHour;
   datetime hourStartTime;

   // Flags
   bool complianceViolation;
   string lastViolationReason;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                        |
   //+------------------------------------------------------------------+
   ComplianceMonitor()
   {
      maxHistorySize = 1000;
      ArrayResize(tradeHistory, 0);

      // Set compliance limits
      maxDailyTurnover = 50.0;        // Max 50 trades per day
      maxTradesPerHour = 10;          // Max 10 trades per hour
      maxRapidReversals = 3;          // Max 3 rapid reversals in 15 min
      minHoldingTimeSec = 60;         // Min 1 minute holding time
      maxCorrelatedTrades = 5;        // Max 5 highly correlated trades

      tradesThisHour = 0;
      hourStartTime = TimeCurrent();
      complianceViolation = false;
      lastViolationReason = "";
   }

   //+------------------------------------------------------------------+
   //| Initialize with custom parameters                                 |
   //+------------------------------------------------------------------+
   void Init(double daily_turnover, int trades_per_hour, int rapid_reversals,
             double min_hold_sec, double corr_trades)
   {
      maxDailyTurnover = daily_turnover;
      maxTradesPerHour = trades_per_hour;
      maxRapidReversals = rapid_reversals;
      minHoldingTimeSec = min_hold_sec;
      maxCorrelatedTrades = corr_trades;
   }

   //+------------------------------------------------------------------+
   //| Check if trade is compliant before opening                        |
   //+------------------------------------------------------------------+
   bool IsTradeCompliant(string symbol, int direction, double volume)
   {
      complianceViolation = false;
      lastViolationReason = "";

      // Check 1: Rate limiting (trades per hour)
      if(!CheckRateLimit())
      {
         complianceViolation = true;
         lastViolationReason = "Exceeded max trades per hour limit";
         return false;
      }

      // Check 2: Daily turnover
      if(!CheckDailyTurnover())
      {
         complianceViolation = true;
         lastViolationReason = "Exceeded daily turnover limit";
         return false;
      }

      // Check 3: Rapid reversals (wash trading detection)
      if(!CheckRapidReversals(symbol, direction))
      {
         complianceViolation = true;
         lastViolationReason = "Rapid reversal pattern detected (possible wash trading)";
         return false;
      }

      // Check 4: Position churning detection
      if(!CheckChurning(symbol, volume))
      {
         complianceViolation = true;
         lastViolationReason = "Excessive churning detected";
         return false;
      }

      // Check 5: Self-trade detection
      if(!CheckSelfTrading(symbol, direction))
      {
         complianceViolation = true;
         lastViolationReason = "Self-trading pattern detected";
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Record trade in history                                           |
   //+------------------------------------------------------------------+
   void RecordTrade(datetime open_time, datetime close_time, double open_price,
                    double close_price, double profit, double volume,
                    int direction, string symbol)
   {
      int size = ArraySize(tradeHistory);

      // Maintain max history size
      if(size >= maxHistorySize)
      {
         // Shift array left (remove oldest)
         for(int i = 0; i < size - 1; i++)
         {
            tradeHistory[i] = tradeHistory[i + 1];
         }
         size = maxHistorySize - 1;
      }

      ArrayResize(tradeHistory, size + 1);

      tradeHistory[size].openTime = open_time;
      tradeHistory[size].closeTime = close_time;
      tradeHistory[size].openPrice = open_price;
      tradeHistory[size].closePrice = close_price;
      tradeHistory[size].profit = profit;
      tradeHistory[size].volume = volume;
      tradeHistory[size].direction = direction;
      tradeHistory[size].symbol = symbol;

      lastTradeTime = close_time;
   }

   //+------------------------------------------------------------------+
   //| Check rate limiting                                               |
   //+------------------------------------------------------------------+
   bool CheckRateLimit()
   {
      datetime now = TimeCurrent();

      // Reset hour counter if new hour
      if(now - hourStartTime >= 3600)
      {
         tradesThisHour = 0;
         hourStartTime = now;
      }

      // Check limit
      if(tradesThisHour >= maxTradesPerHour)
      {
         Print("COMPLIANCE: Rate limit exceeded - ", tradesThisHour, " trades this hour");
         return false;
      }

      tradesThisHour++;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check daily turnover                                              |
   //+------------------------------------------------------------------+
   bool CheckDailyTurnover()
   {
      datetime now = TimeCurrent();
      datetime dayStart = now - (now % 86400); // Start of current day

      int todayTrades = 0;
      int size = ArraySize(tradeHistory);

      for(int i = size - 1; i >= 0; i--)
      {
         if(tradeHistory[i].closeTime >= dayStart)
            todayTrades++;
         else
            break; // Older trades
      }

      if(todayTrades >= maxDailyTurnover)
      {
         Print("COMPLIANCE: Daily turnover exceeded - ", todayTrades, " trades today");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check for rapid reversals (wash trading indicator)                |
   //+------------------------------------------------------------------+
   bool CheckRapidReversals(string symbol, int direction)
   {
      datetime now = TimeCurrent();
      datetime window = now - 900; // 15 minute window

      int reversals = 0;
      int prevDirection = 0;
      int size = ArraySize(tradeHistory);

      for(int i = size - 1; i >= 0; i--)
      {
         if(tradeHistory[i].closeTime < window)
            break;

         if(tradeHistory[i].symbol != symbol)
            continue;

         if(prevDirection != 0 && tradeHistory[i].direction != prevDirection)
            reversals++;

         prevDirection = tradeHistory[i].direction;
      }

      // Check if new trade would create another reversal
      if(size > 0 && tradeHistory[size - 1].direction != direction)
         reversals++;

      if(reversals > maxRapidReversals)
      {
         Print("COMPLIANCE: Rapid reversals detected - ", reversals, " in 15 minutes");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check for churning (excessive trading without profit)             |
   //+------------------------------------------------------------------+
   bool CheckChurning(string symbol, double volume)
   {
      int size = ArraySize(tradeHistory);
      if(size < 5) return true; // Need history

      // Look at last 10 trades
      int lookback = MathMin(10, size);
      double totalProfit = 0;
      double totalVolume = 0;
      int symbolTrades = 0;

      for(int i = size - 1; i >= size - lookback; i--)
      {
         if(tradeHistory[i].symbol == symbol)
         {
            totalProfit += tradeHistory[i].profit;
            totalVolume += tradeHistory[i].volume;
            symbolTrades++;
         }
      }

      // If many trades with minimal profit = churning
      if(symbolTrades >= 5 && MathAbs(totalProfit) < totalVolume * 0.001)
      {
         Print("COMPLIANCE: Churning detected - ", symbolTrades, " trades with minimal P/L");
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check for self-trading patterns                                   |
   //+------------------------------------------------------------------+
   bool CheckSelfTrading(string symbol, int direction)
   {
      datetime now = TimeCurrent();
      datetime window = now - 60; // 1 minute window

      int size = ArraySize(tradeHistory);

      // Look for trades in opposite direction within short timeframe
      for(int i = size - 1; i >= 0; i--)
      {
         if(tradeHistory[i].closeTime < window)
            break;

         if(tradeHistory[i].symbol == symbol &&
            tradeHistory[i].direction == -direction)
         {
            // Found opposite trade within 1 minute
            double timeDiff = (double)(now - tradeHistory[i].closeTime);
            if(timeDiff < minHoldingTimeSec)
            {
               Print("COMPLIANCE: Self-trading detected - opposite trade within ", timeDiff, " seconds");
               return false;
            }
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Get compliance status                                             |
   //+------------------------------------------------------------------+
   bool IsCompliant() { return !complianceViolation; }

   string GetViolationReason() { return lastViolationReason; }

   //+------------------------------------------------------------------+
   //| Get trade statistics for analysis                                 |
   //+------------------------------------------------------------------+
   void GetTradeStats(int &total, double &winRate, double &avgProfit)
   {
      int size = ArraySize(tradeHistory);
      total = size;

      if(size == 0)
      {
         winRate = 0;
         avgProfit = 0;
         return;
      }

      int wins = 0;
      double totalProfit = 0;

      for(int i = 0; i < size; i++)
      {
         if(tradeHistory[i].profit > 0) wins++;
         totalProfit += tradeHistory[i].profit;
      }

      winRate = (double)wins / size * 100.0;
      avgProfit = totalProfit / size;
   }

   //+------------------------------------------------------------------+
   //| Clear old history (beyond retention period)                       |
   //+------------------------------------------------------------------+
   void ClearOldHistory(int daysToKeep = 30)
   {
      datetime cutoff = TimeCurrent() - (daysToKeep * 86400);
      int size = ArraySize(tradeHistory);
      int keepFrom = 0;

      // Find first trade to keep
      for(int i = 0; i < size; i++)
      {
         if(tradeHistory[i].closeTime >= cutoff)
         {
            keepFrom = i;
            break;
         }
      }

      if(keepFrom > 0)
      {
         // Shift array to remove old trades
         int newSize = size - keepFrom;
         TradeRecord temp[];
         ArrayResize(temp, newSize);

         for(int i = 0; i < newSize; i++)
         {
            temp[i] = tradeHistory[keepFrom + i];
         }

         ArrayResize(tradeHistory, newSize);
         for(int i = 0; i < newSize; i++)
         {
            tradeHistory[i] = temp[i];
         }

         Print("COMPLIANCE: Cleared ", keepFrom, " old trade records");
      }
   }

   //+------------------------------------------------------------------+
   //| Generate compliance report                                        |
   //+------------------------------------------------------------------+
   string GenerateReport()
   {
      int total;
      double winRate, avgProfit;
      GetTradeStats(total, winRate, avgProfit);

      string report = "\n=== COMPLIANCE REPORT ===\n";
      report += "Total Trades Monitored: " + IntegerToString(total) + "\n";
      report += "Win Rate: " + DoubleToString(winRate, 2) + "%\n";
      report += "Avg Profit per Trade: " + DoubleToString(avgProfit, 2) + "\n";
      report += "Trades This Hour: " + IntegerToString(tradesThisHour) + "/" + IntegerToString(maxTradesPerHour) + "\n";
      report += "Compliance Status: " + (complianceViolation ? "VIOLATION" : "OK") + "\n";

      if(complianceViolation)
         report += "Last Violation: " + lastViolationReason + "\n";

      return report;
   }
};
