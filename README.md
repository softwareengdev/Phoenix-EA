# 🔥 PHOENIX EA v3.0 — Autonomous Multi-Strategy Trading System

**Advanced Expert Advisor for MetaTrader 5 with Custom Backtesting Framework**

## Overview

Phoenix is a fully autonomous Expert Advisor written in **100% pure MQL5** for MetaTrader 5. It implements a multi-strategy, multi-symbol, self-optimizing trading system with institutional-grade risk management and an advanced custom backtesting framework.

## Key Features

### Trading Engine
- **4 Strategies**: Trend Following (EMA+ADX), Mean Reversion (BB+RSI), Breakout (Donchian+Volume), Scalper (Fast EMA+MACD)
- **Signal Aggregator**: Weighted multi-strategy scoring with regime-based filtering
- **Market Regime Detection**: 6 regimes (Trending Up/Down, Ranging, Volatile, Breakout, Uncertain)
- **Multi-Symbol**: Trade up to 10 symbols simultaneously from a single chart
- **Session Awareness**: Adjusts aggressiveness by London/NY/Tokyo/Sydney sessions

### Risk Management
- **Kelly Criterion** position sizing with configurable fraction
- **3-Tier Drawdown Guard**: Progressive risk reduction at Yellow/Orange/Red zones
- **Circuit Breakers**: Daily loss limit, max drawdown, consecutive losses, spread spikes
- **Correlation Matrix**: Prevents correlated position concentration
- **Auto Account Detection**: Micro/Small/Medium/Large account modes

### Execution
- **Smart Order Routing**: Retry logic with progressive slippage
- **ATR Trailing Stops**: Dynamic stop management
- **Breakeven Protection**: Auto-move SL to entry + offset
- **Partial Close**: Take profit at configurable ratio

### Optimization & Monitoring
- **Genetic Allocator**: 50-population GA optimizes strategy capital allocation
- **Sharpe/Sortino/Calmar** real-time performance metrics
- **Telegram Notifications**: Trade alerts, daily reports, risk warnings
- **State Persistence**: Binary save/restore survives MT5 restarts

### Custom Backtesting Framework
- **5 Fitness Functions**: Sharpe, Sortino, Calmar, PF×WR, Composite
- **Monte Carlo Simulation**: 1000+ permutation runs with risk-of-ruin analysis
- **Walk-Forward Analysis**: In-sample/Out-of-sample window validation
- **Dark-Themed HTML Reports**: Equity curves, monthly heatmap, strategy breakdown, trade log
- **Automatic Penalty**: -50% fitness if Monte Carlo ruin >20%, -40% if Walk-Forward fails

## Project Structure (MetaEditor Format)
```
Phoenix/
├── Phoenix.mqproj              # MetaEditor project file
├── Phoenix.mq5                 # Main EA entry point
├── Headers/
│   ├── Core/                   # Defines, Logger, Globals
│   ├── Data/                   # DataEngine, SymbolInfo, Sessions, Calendar
│   ├── Signal/                 # SignalBase + Trend/MeanRevert/Breakout/Scalper + Aggregator
│   ├── Risk/                   # RiskManager, CircuitBreaker, DrawdownGuard, Correlation
│   ├── Execution/              # TradeExecutor (trailing, breakeven, partial close)
│   ├── Optimization/           # PerformanceTracker, GeneticAllocator
│   ├── Persistence/            # StateManager (binary state save/restore)
│   ├── Monitor/                # TelegramBot
│   └── Backtest/               # FitnessFunction, BacktestEngine, MonteCarloSim,
│                               # WalkForward, ReportGenerator
├── Sources/                    # Phoenix_Monitor.mq5 (chart dashboard indicator)
├── Resources/
├── Settings/                   # Conservative, Moderate, Aggressive presets (.set)
├── Files/                      # Runtime data (logs, state, reports)
└── Docs/                       # Architecture & deployment documentation
```

## Quick Start

1. **Open in MetaEditor**: File → Open Project → Phoenix.mqproj
2. **Compile**: Press F7 (all headers compile through Phoenix.mq5)
3. **Load Preset**: Strategy Tester → Load Settings → choose from `Settings/`
4. **Backtest**: Run in Strategy Tester; check `Files/` for HTML report
5. **Go Live**: Attach to chart, enable auto-trading, configure Telegram

## Presets

| Preset | Risk/Trade | Max DD | Strategies | Best For |
|--------|-----------|--------|------------|----------|
| Conservative | 1.5% | 15% | Trend + MeanRev | Live ≥$10K |
| Moderate | 3.0% | 25% | All 4 | Demo / $500-$10K |
| Aggressive | 4.0% | 35% | All 5 | Micro <$500 / Demo |

## Custom Backtesting

The built-in backtesting framework runs automatically during Strategy Tester optimization:

1. **OnTester()** collects all trades and computes fitness
2. **Monte Carlo**: Shuffles trade order 1000× to estimate worst-case drawdown
3. **Walk-Forward**: Validates parameter stability across IS/OOS windows
4. **HTML Report**: Generated automatically at `Files/Phoenix_Report.html`

### Fitness Functions (select via InpCustomFitness)
- `0` = Sharpe Ratio
- `1` = Sortino Ratio  
- `2` = Calmar Ratio
- `3` = Profit Factor × Win Rate
- `4` = Composite (default — weighted blend of all)

## Requirements

- MetaTrader 5 (build 2190+ for Calendar API)
- Broker with hedging account
- VPS recommended for 24/7 operation

## License

Proprietary — Copyright 2025, Phoenix Trading Systems. All rights reserved.
