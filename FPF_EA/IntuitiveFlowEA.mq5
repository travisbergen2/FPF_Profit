//+------------------------------------------------------------------+
//|                                             IntuitiveFlowEA.mq5   |
//|                                                                    |
//| Intuitive Flow EA - Meta-Learning Microstructure Trading System   |
//|                                                                    |
//| Architecture:                                                      |
//| - TickFieldAccumulator: Nervous system (tick-level sensing)       |
//| - BarMetaLearner: Intuition (pattern memory & predictions)        |
//| - TradeController: Motor system (orchestration & execution)       |
//|                                                                    |
//| The EA is "aware of its own nervous system":                      |
//| Every tick → nervous sensations (7 BigMove signals)               |
//| Every bar → compress sensations into memory fingerprint           |
//| Meta-learner → predicts outcomes based on fingerprint patterns    |
//| Controller → acts on predictions with risk-aware motor decisions  |
//+------------------------------------------------------------------+
#property copyright "Intuitive Flow Trading System"
#property link      ""
#property version   "1.00"
#property strict

#include "Include/TradeController.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input string         InpSymbol           = "";           // Symbol (empty = current)
input ENUM_TIMEFRAMES InpTF              = PERIOD_M15;   // Timeframe for bar analysis
input double         InpRiskPercent      = 0.5;          // Risk per trade (%)
input double         InpMaxDailyLossPct  = 3.0;          // Max daily loss (%)

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
TradeController *g_controller = NULL;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=================================================");
   Print("Intuitive Flow EA - Initializing...");
   Print("=================================================");

   // Determine symbol
   string symbol = (InpSymbol == "" || InpSymbol == NULL) ? _Symbol : InpSymbol;

   // Create controller (nervous system + intuition + motor control)
   g_controller = new TradeController(symbol,
                                      InpTF,
                                      InpRiskPercent,
                                      InpMaxDailyLossPct);

   if(g_controller == NULL)
   {
      Print("ERROR: Failed to create TradeController");
      return(INIT_FAILED);
   }

   g_controller.Init();

   Print("=================================================");
   Print("Nervous system active on ", symbol, " ", EnumToString(InpTF));
   Print("Sensing microstructure... Building intuition...");
   Print("=================================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=================================================");
   Print("Intuitive Flow EA - Shutting down...");
   Print("Reason: ", reason);
   Print("=================================================");

   if(g_controller != NULL)
   {
      delete g_controller;
      g_controller = NULL;
   }
}

//+------------------------------------------------------------------+
//| Expert tick function - The heartbeat                              |
//| Every tick pulses through: nervous system → memory → action       |
//+------------------------------------------------------------------+
void OnTick()
{
   if(g_controller != NULL)
   {
      g_controller.OnTick();
   }
}

//+------------------------------------------------------------------+
//| Trade transaction function - Optional event handler               |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   // Could add transaction logging here if needed
}
