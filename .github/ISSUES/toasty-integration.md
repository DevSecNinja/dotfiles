# Issue: Integrate Toasty Notification CLI

## Summary
Integrate [Scott Hanselman's toasty](https://github.com/shanselman/toasty) notification CLI tool into the dotfiles repository with PowerShell support.

## Description
Toasty is a tiny (229 KB) Windows command-line tool that displays toast notifications in the corner of the screen. It's designed for developers using AI coding agents (Claude, GitHub Copilot CLI, Gemini) to get notified when long-running tasks complete.

### Key Features
- Lightweight with no dependency bloat
- Auto-registers on first run
- Simple CLI: `toasty "Hello World" -t "Title"`
- Auto-detects AI coding agents (Claude, Copilot, Gemini)
- One-click agent integration via `toasty --install`
- Customizable with presets and manual configuration

## Prerequisites
This integration should **wait until the following upstream PRs are merged**:

1. **macOS Support**: PR [#28](https://github.com/shanselman/toasty/pull/28) - Adds macOS support using native notification system (Status: OPEN, by @spboyer)
2. **WinGet Support**: PR [#39](https://github.com/shanselman/toasty/pull/39) - Windows Package Manager manifest files for `winget install shanselman.toasty` (Status: DRAFT, by @Copilot)

## Integration Requirements

### PowerShell Function
Create a PowerShell function that:
- Wraps the `toasty` CLI for easy invocation
- Provides a friendly alias (e.g., `toast`, `notify`)
- Handles installation check (via winget when available)
- Supports common notification scenarios
- Works in both Windows PowerShell 5.1+ and PowerShell 7+

### Installation
- Add toasty to `home/.chezmoidata/packages.yaml` under `windows.winget` packages
- Create a `run_once_` or `run_onchange_` script to install toasty via winget (when winget support is available)
- Ensure installation is cross-platform aware (Windows only initially, macOS when PR #28 is merged)

### Function Signature Example
```powershell
function Invoke-ToastyNotification {
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,
        
        [Parameter(Position = 1)]
        [string]$Title = "Notification",
        
        [Parameter()]
        [ValidateSet("claude", "copilot", "gemini", "default")]
        [string]$App,
        
        [Parameter()]
        [switch]$Install
    )
    
    # Implementation
}

Set-Alias -Name toast -Value Invoke-ToastyNotification
Set-Alias -Name notify -Value Invoke-ToastyNotification
```

### Use Cases
1. **Long-running command notifications**: 
   ```powershell
   npm run build; toast "Build completed!"
   ```

2. **AI agent integration**:
   ```powershell
   # Auto-detect agent and notify
   toast "Task finished" -App copilot
   ```

3. **Custom notifications**:
   ```powershell
   toast "Deployment successful" -Title "Production Deploy"
   ```

## Implementation Checklist
- [ ] Wait for upstream macOS PR #28 to be merged
- [ ] Wait for upstream winget support to be implemented
- [ ] Add toasty to `packages.yaml` under `windows.winget`
- [ ] Create PowerShell function `Invoke-ToastyNotification` in `functions.ps1`
- [ ] Add aliases: `toast`, `notify`
- [ ] Create installation script (run_once or run_onchange)
- [ ] Add Pester tests for the PowerShell function
- [ ] Update PowerShell `Show-Aliases` function to document new commands
- [ ] Add documentation to README or STRUCTURE.md
- [ ] Test on Windows (PowerShell 5.1 and 7+)
- [ ] Test on macOS (when macOS support is available)

## References
- **GitHub Repository**: https://github.com/shanselman/toasty
- **macOS Support PR**: https://github.com/shanselman/toasty/pull/28
- **WinGet Documentation**: https://learn.microsoft.com/en-us/windows/package-manager/

## Labels
`enhancement`, `powershell`, `windows`, `macos`, `blocked`

## Notes
- This issue is blocked pending upstream development
- When creating this as a GitHub issue, add the `blocked` label
- Monitor the toasty repository for PR merge status
- Consider creating a draft implementation that can be quickly merged once dependencies are ready
