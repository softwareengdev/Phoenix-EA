# PHOENIX EA — System Architecture

## Mermaid Diagram

```mermaid
graph TB
    subgraph "PHOENIX EA — Main Loop"
        TICK[OnTick Event] --> WARMUP{Warmup Complete?}
        WARMUP -->|No| WAIT[Wait for Data]
        WARMUP -->|Yes| SESSION{Session Allowed?}
        SESSION -->|No| SKIP[Skip Tick]
        SESSION -->|Yes| NEWS{News Filter OK?}
        NEWS -->|No| SKIP
        NEWS -->|Yes| MANAGE[Manage Open Positions]
        MANAGE --> RISK_CHECK{Circuit Breaker OK?}
        RISK_CHECK -->|Triggered| EMERGENCY[Emergency Mode]
        RISK_CHECK -->|OK| SIGNALS[Process Signals]
    end

    subgraph "Signal Generation"
        SIGNALS --> AGG[SignalAggregator]
        AGG --> ST[SignalTrend<br/>EMA Cross + ADX]
        AGG --> SMR[SignalMeanRevert<br/>BB + RSI + Stoch]
        AGG --> SB[SignalBreakout<br/>Donchian + Volume]
        AGG --> SS[SignalScalper<br/>M15 EMA + MACD]
        ST --> FILTER[Regime Filter + Rank by Score]
        SMR --> FILTER
        SB --> FILTER
        SS --> FILTER
    end

    subgraph "Risk Management"
        FILTER --> RM[RiskManager]
        RM --> KELLY[Kelly Position Sizing]
        RM --> CB[CircuitBreaker]
        RM --> DDG[DrawdownGuard]
        RM --> CORR[CorrelationMatrix]
        RM --> VALIDATE{Valid Trade?}
    end

    subgraph "Execution"
        VALIDATE -->|Yes| EXEC[TradeExecutor]
        EXEC --> RETRY[Retry with Backoff]
        EXEC --> TRAIL[Trailing Stop]
        EXEC --> BE[Break-Even]
        EXEC --> BROKER((Broker / MT5))
    end

    subgraph "Data Layer"
        DE[DataEngine] --> SI[SymbolInfo Cache]
        DE --> SD[SessionDetector]
        DE --> CF[CalendarFilter]
        DE --> REG[Regime Detection<br/>ADX + ATR + BB]
    end

    subgraph "Self-Optimization (OnTimer)"
        TIMER[OnTimer 30s] --> PT[PerformanceTracker]
        PT --> GA[GeneticAllocator]
        GA --> WEIGHTS[Update Strategy Weights]
        TIMER --> SM[StateManager]
        SM --> SAVE[(Binary State File)]
        TIMER --> TG[TelegramBot]
    end

    subgraph "Event Tracking (OnTrade)"
        TRADE[OnTrade Event] --> PNL[P&L Calculation]
        PNL --> METRICS[Update Strategy Metrics]
        METRICS --> PT
        PNL --> CB
        PNL --> TG
    end

    DE --> TICK
    TIMER --> DE

    style EXEC fill:#2d9e2d,stroke:#1a6e1a,color:#fff
    style CB fill:#e63946,stroke:#a6282f,color:#fff
    style GA fill:#457b9d,stroke:#2e5a71,color:#fff
    style BROKER fill:#f4a261,stroke:#c67e3d,color:#fff
```

## Component Dependencies

```
Phoenix_EA.mq5
├── Core/Defines.mqh          (constants, enums, structs)
├── Core/Logger.mqh           (leveled logging with rotation)
├── Core/Globals.mqh          (state hub, account detection)
├── Data/DataEngine.mqh       (multi-symbol data aggregation)
│   ├── Data/SymbolInfo.mqh   (cached symbol properties)
│   ├── Data/SessionDetector.mqh (trading session awareness)
│   └── Data/CalendarFilter.mqh  (economic news filter)
├── Signal/SignalAggregator.mqh  (strategy orchestrator)
│   ├── Signal/SignalBase.mqh    (abstract base class)
│   ├── Signal/SignalTrend.mqh   (trend following)
│   ├── Signal/SignalMeanRevert.mqh (mean reversion)
│   ├── Signal/SignalBreakout.mqh   (breakout/momentum)
│   └── Signal/SignalScalper.mqh    (session scalper)
├── Risk/RiskManager.mqh      (position sizing + validation)
│   ├── Risk/CircuitBreaker.mqh  (emergency stop)
│   └── Risk/DrawdownGuard.mqh   (progressive risk scaling)
├── Risk/CorrelationMatrix.mqh   (cross-pair filter)
├── Execution/TradeExecutor.mqh  (smart execution + trailing)
├── Optimization/PerformanceTracker.mqh (Sharpe, win rate, expectancy)
├── Optimization/GeneticAllocator.mqh   (capital allocation GA)
├── Persistence/StateManager.mqh (binary state save/restore)
└── Monitor/TelegramBot.mqh     (WebRequest notifications)
```

## Data Flow

1. **Tick arrives** → DataEngine refreshes symbol cache
2. **Session check** → SessionDetector validates trading hours
3. **News check** → CalendarFilter blocks if high-impact news imminent
4. **Position management** → TradeExecutor applies trailing/break-even
5. **Risk check** → CircuitBreaker + DrawdownGuard validate system health
6. **Signal generation** → All 4 strategies evaluate independently
7. **Signal filtering** → Regime suitability + correlation check
8. **Signal ranking** → Confidence × R:R × allocation weight
9. **Position sizing** → Kelly fraction + ATR volatility targeting
10. **Execution** → TradeExecutor with retries + slippage control
11. **Feedback** → OnTrade updates metrics → feeds into genetic optimizer

## Risk Layers (Defense in Depth)

| Layer | Component | Protection |
|-------|-----------|------------|
| 1 | Individual SL/TP | Per-trade risk capped |
| 2 | Position Sizing | Kelly + ATR = risk-calibrated lots |
| 3 | Max Positions | Capital concentration limit |
| 4 | Correlation Filter | Cross-pair exposure limit |
| 5 | Drawdown Guard | Progressive risk reduction |
| 6 | Circuit Breaker | Full stop on daily/total DD |
| 7 | News Filter | Pause before volatility events |
| 8 | Session Filter | Only trade in liquid hours |
| 9 | Regime Filter | Match strategy to market condition |
