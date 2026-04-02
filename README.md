# 🔥 PHOENIX EA — Autonomous MQL5 Trading System

**Micro-Account Compounder: €50 → €10,000 in 6-12 months**

## Overview
Phoenix is a fully autonomous Expert Advisor written in **100% pure MQL5** for MetaTrader 5. It implements a multi-strategy, multi-symbol, self-optimizing trading system with institutional-grade risk management.

## Architecture
- **Multi-Strategy Engine**: Trend Following, Mean Reversion, Breakout, Scalper — running simultaneously
- **Genetic Allocator**: Dynamically assigns capital to best-performing strategies
- **Adaptive Risk**: Kelly Criterion + ATR volatility targeting + progressive drawdown guard
- **Circuit Breakers**: Daily loss limit, max drawdown, consecutive losses, spread spikes
- **Session Awareness**: Adjusts aggressiveness by London/NY/Tokyo/Sydney sessions
- **Economic Calendar Filter**: Pauses trading before high-impact news
- **Self-Optimization**: Walk-forward analysis with genetic parameter tuning
- **State Persistence**: Survives MT5 restarts and VPS reboots
- **Telegram Notifications**: Real-time trade alerts and daily reports

## Project Structure
```
Phoenix/
├── Experts/Phoenix/         # Main EA and monitor EA
├── Indicators/Phoenix/      # Custom indicators
├── Include/Phoenix/         # Library modules (.mqh)
│   ├── Core/               # Defines, Logger, Globals
│   ├── Data/               # DataEngine, SymbolInfo, Sessions, Calendar
│   ├── Signal/             # Strategy base class + implementations
│   ├── Risk/               # RiskManager, CircuitBreaker, DrawdownGuard
│   ├── Execution/          # TradeExecutor, trailing, position tracking
│   ├── Optimization/       # GeneticAllocator, PerformanceTracker
│   ├── Monitor/            # Telegram, Dashboard, Heartbeat
│   └── Persistence/        # StateManager, binary storage
├── Files/Phoenix/          # Runtime data (logs, state, journal)
├── Presets/Phoenix/        # Optimization preset files (.set)
└── Docs/                   # Documentation
```

## Risk Parameters
| Parameter | Micro (€50-500) | Small (€500-2K) | Medium (€2K-10K) | Large (€10K+) |
|-----------|-----------------|------------------|-------------------|----------------|
| Risk/trade | 4% | 3.5% | 3% | 2% |
| Max positions | 2 | 3 | 5 | 10 |
| Max daily DD | 5% | 5% | 5% | 5% |
| Max total DD | 30% | 30% | 30% | 30% |

## Requirements
- MetaTrader 5 (build 4000+)
- Broker with hedging account
- VPS recommended for 24/7 operation

## License
Proprietary — All rights reserved.
