# Intuitive Flow EA - Implementation Guide

## Overview

This is a meta-learning microstructure trading system that:
- **Senses** tick-level microstructure via 7 BigMove signals (nervous system)
- **Remembers** bar-level fingerprints and their outcomes (pattern memory)
- **Predicts** next-bar behavior based on learned patterns (intuition)
- **Acts** on predictions with risk-aware motor decisions (trading)

## Architecture

```
IntuitiveFlowEA.mq5          # Main EA entry point
├── TradeController.mqh       # Motor system (orchestration)
│   ├── TickFieldAccumulator  # Nervous system (tick sensing)
│   │   └── BigMoveSignals    # 7 microstructure signals
│   └── BarMetaLearner        # Intuition (pattern memory)
└── Types.mqh                 # Shared data structures
```

## File Descriptions

### 1. **Types.mqh**
Shared data structures:
- `BarSummary`: Bar-level fingerprint (compressed nervous system state)
- `PredictionResult`: Meta-learner's intuition for next bar
- `TradeOutcome`: Realized results fed back to learner

### 2. **TickFieldAccumulator.mqh** (Nervous System)
- Processes every tick
- Accumulates 7 BigMove signal scores: compression, sweeps, spread, stop-hunts, wick-tests, alignment, freeze
- Computes means, maxima, and slopes over each bar
- Outputs `BarSummary` fingerprint at bar close

### 3. **BarMetaLearner.mqh** (Intuition)
- Encodes `BarSummary` into discrete context keys (simple bucketing)
- Tracks per-context statistics: total R, trade count, EWMA R
- Predicts next-bar outcomes based on pattern memory
- Updates learning when trade outcomes are realized

**Simple Context Encoding (you can iterate on this):**
- Compression mean: low/medium/high (0/1/2)
- Sweep mean: absent/present (0/1)
- Freeze slope: falling/rising (0/1)
- TF alignment: weak/strong (0/1)
- Regime volatility: low/normal/high (0/1/2)

### 4. **TradeController.mqh** (Motor System)
Main orchestrator that:
- Owns `TickFieldAccumulator` and `BarMetaLearner`
- Calls `OnTick()` → updates nervous system
- Detects bar boundaries → finalizes fingerprint → predicts → evaluates entry
- Manages positions
- Processes closed positions → feeds outcomes to meta-learner

### 5. **IntuitiveFlowEA.mq5** (Main EA)
Entry point that instantiates `TradeController` and routes ticks.

## Compilation & Testing

### To Compile:
1. Open MetaEditor
2. Open `/home/user/FPF_Profit/FPF_EA/IntuitiveFlowEA.mq5`
3. Press F7 (or Compile button)
4. Check for errors in the Errors tab

### Expected Behavior:
- EA will sense microstructure on every tick
- At each bar close, it compresses tick sensations into a `BarSummary`
- It uses the meta-learner to predict next-bar outcomes
- If prediction is favorable (expected R > 0.5, confidence > 0.3), it enters
- As trades close, it learns which bar fingerprints led to profit/loss
- Over time, its intuition improves

## Configuration

Key inputs in `IntuitiveFlowEA.mq5`:
- `InpSymbol`: Symbol to trade (empty = current chart)
- `InpTF`: Timeframe for bar analysis (default M15)
- `InpRiskPercent`: Risk per trade % (default 0.5%)
- `InpMaxDailyLossPct`: Max daily loss % (default 3.0%)

## Iteration Plan

### Phase 1: ✅ Initial Implementation (DONE)
- [x] Create all classes
- [x] Simple context encoding
- [x] Basic entry/exit logic
- [x] Ensure compilation

### Phase 2: Backtesting & Tuning
- [ ] Run backtest on M15
- [ ] Analyze which contexts are profitable
- [ ] Refine context encoding (add more features, adjust buckets)
- [ ] Tune entry thresholds (min expected R, confidence)

### Phase 3: Advanced Features
- [ ] Add tick-level exit logic using nervous system
- [ ] Implement trailing stops based on signal shifts
- [ ] Add regime filters
- [ ] Optimize context bucketing

## Nervous System Metaphor

The EA is designed to feel its own sensing apparatus:

- **Nervous system** (TickFieldAccumulator): Every tick is a nerve signal
- **Bar memory** (BarSummary): How did this bar feel overall?
- **Pattern memory** (BarMetaLearner): When I felt this before, what happened?
- **Motor system** (TradeController): Based on intuition, reach or pull back?

This creates a learning loop:
```
Sense → Remember → Predict → Act → Learn → (repeat)
```

## Next Steps

1. **Compile** the EA in MetaEditor
2. **Run backtest** on M15 timeframe (at least 3 months of data)
3. **Analyze logs** to see which contexts are being learned
4. **Iterate** on context encoding in `BarMetaLearner::EncodeContext()`
5. **Tune** entry thresholds and risk parameters

## Questions?

The code is heavily commented with the nervous system metaphor. Each file explains its role in the sensing → intuition → action loop.

Good luck with backtesting! 🚀
