# PHOENIX EA — Deployment Guide (VPS Windows + MT5)

## Prerequisites
- Windows VPS (2+ CPU, 4GB+ RAM, 50GB SSD)
- Recommended: Contabo VPS M or Hetzner CX21 (~€10-15/month)
- MetaTrader 5 installed (download from broker)
- Broker with hedging account and low spreads (ICMarkets, Pepperstone, FPMarkets)

## Step 1: VPS Setup

### 1.1 Initial Configuration
```powershell
# Enable RDP (should be enabled by default)
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0

# Disable Windows Update auto-restart
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoRebootWithLoggedOnUsers /t REG_DWORD /d 1

# Set power plan to High Performance
powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

# Disable screen saver
reg add "HKCU\Control Panel\Desktop" /v ScreenSaveActive /t REG_SZ /d 0
```

### 1.2 Auto-Login (Required for MT5)
```powershell
# Set auto-login so MT5 launches after reboot
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d "YOUR_USERNAME"
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "YOUR_PASSWORD"
```

## Step 2: MetaTrader 5 Installation

### 2.1 Install MT5
1. Download MT5 from your broker's website
2. Install to `C:\Program Files\MetaTrader 5\`
3. Login with your trading account
4. Enable algo trading: Tools > Options > Expert Advisors
   - [x] Allow algorithmic trading
   - [x] Allow DLL imports (if needed)
   - Add to allowed URLs: `https://api.telegram.org`

### 2.2 Install Phoenix EA Files
Copy the Phoenix project files to MT5 data folder:

```powershell
# Find MT5 data folder
$mt5Data = "$env:APPDATA\MetaQuotes\Terminal\<YOUR_TERMINAL_ID>"

# Copy files
Copy-Item -Recurse "Phoenix\Experts\Phoenix" "$mt5Data\MQL5\Experts\Phoenix"
Copy-Item -Recurse "Phoenix\Include\Phoenix" "$mt5Data\MQL5\Include\Phoenix"
Copy-Item -Recurse "Phoenix\Indicators\Phoenix" "$mt5Data\MQL5\Indicators\Phoenix"
Copy-Item -Recurse "Phoenix\Presets\Phoenix" "$mt5Data\MQL5\Presets\Phoenix"
```

### 2.3 Compile
1. Open MetaEditor (F4 in MT5)
2. Open `Experts\Phoenix\Phoenix_EA.mq5`
3. Press F7 (Compile)
4. Check for 0 errors (warnings about unused variables are OK)
5. Compile `Indicators\Phoenix\Phoenix_Monitor.mq5`

## Step 3: Configure and Launch

### 3.1 Attach EA to Chart
1. Open a chart for any of your configured symbols (e.g., EURUSD H1)
2. Drag `Phoenix_EA` from Navigator onto the chart
3. Configure input parameters:
   - Set your symbols (EURUSD, GBPUSD, USDJPY, XAUUSD)
   - Risk: start with 3% (default)
   - Enter Telegram bot token and chat ID if desired
4. Click OK
5. Verify the smiley face icon in the top-right corner of the chart

### 3.2 Attach Monitor (Optional)
1. Open a second chart window
2. Drag `Phoenix_Monitor` indicator onto it
3. You'll see the real-time dashboard

### 3.3 Verify Operation
- Check Experts tab (Ctrl+E) for initialization logs
- Verify "PHOENIX EA v1.0.0 INICIANDO" message
- Confirm "Estado: ACTIVE" after warmup
- Check that symbols are loaded in Market Watch

## Step 4: Auto-Start on Reboot

### 4.1 MT5 Auto-Start
```powershell
# Create startup shortcut
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\MT5.lnk")
$shortcut.TargetPath = "C:\Program Files\MetaTrader 5\terminal64.exe"
$shortcut.Arguments = "/portable"
$shortcut.Save()
```

### 4.2 Watchdog Script (Restart MT5 if it crashes)
Create `C:\Phoenix\watchdog.ps1`:
```powershell
while ($true) {
    $mt5 = Get-Process -Name "terminal64" -ErrorAction SilentlyContinue
    if (-not $mt5) {
        Write-Host "$(Get-Date) - MT5 not running, restarting..."
        Start-Process "C:\Program Files\MetaTrader 5\terminal64.exe"
        Start-Sleep -Seconds 30
    }
    Start-Sleep -Seconds 60
}
```

Register as scheduled task:
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File C:\Phoenix\watchdog.ps1"
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName "PhoenixWatchdog" -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest
```

## Step 5: Backtesting Before Live

### 5.1 Strategy Tester Configuration
1. Open Strategy Tester (Ctrl+R)
2. Select `Phoenix_EA`
3. Settings:
   - Symbol: EURUSD (or multi-currency if supported)
   - Period: H1
   - Date: last 2 years
   - Model: Every tick based on real ticks
   - Deposit: 50 (your starting capital)
   - Leverage: match your broker
   - Optimization: Genetic algorithm
4. Load preset: `Phoenix_EA_Optimize.set`
5. Run optimization

### 5.2 Walk-Forward Validation
1. Run backtest on 70% of data (training)
2. Forward-test on remaining 30% (out-of-sample)
3. Compare Sharpe ratios: OOS should be >60% of IS Sharpe

### 5.3 Demo Account Test
1. Run on demo account for minimum 2-4 weeks
2. Verify: positive expectancy, drawdown within limits, execution quality
3. Only go live after consistent demo performance

## Cost Analysis

| Item | Monthly Cost |
|------|-------------|
| VPS (Contabo VPS M) | €10-15 |
| Broker (spreads + commissions) | ~€5-20 (depending on volume) |
| Data feed | Included with broker |
| Telegram bot | Free |
| **Total** | **~€15-35/month** |

Break-even: ~0.07% return on €50K account, or 1 winning trade.

## Emergency Procedures

### Stop All Trading
1. In MT5: Tools > Options > Expert Advisors > Uncheck "Allow algo trading"
2. Or: Remove EA from chart (right-click > Expert list > Remove)
3. EA will stop immediately, existing positions remain

### Close All Positions
1. In MT5: Trade tab > right-click > Close All
2. Or: set InpMaxTotalDD to 0.01 (triggers circuit breaker)

### VPS Emergency Access
- Always have RDP credentials saved locally and on mobile
- Set up Telegram bot for alerts — you'll know if something goes wrong
- Consider a backup VPS with MT5 (read-only monitoring)

## Monthly Maintenance Checklist
- [ ] Review Experts log for errors
- [ ] Check strategy allocation weights
- [ ] Verify VPS uptime and resources
- [ ] Review broker execution quality (slippage stats in log)
- [ ] Update MT5 if new version available
- [ ] Backup state files and logs
- [ ] Review correlation matrix for changes
- [ ] Check calendar filter accuracy
