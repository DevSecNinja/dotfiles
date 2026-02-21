# GitHub Issue Template for Toasty Integration

Copy the content below to create a GitHub issue:

---

**Title:** Integrate toasty notification CLI with PowerShell support

**Labels:** `enhancement`, `powershell`, `windows`, `macos`, `blocked`

**Description:**

## Summary
Integrate [Scott Hanselman's toasty](https://github.com/shanselman/toasty) notification CLI tool into dotfiles with PowerShell function support.

## Background
Toasty is a tiny (229 KB) Windows CLI tool that displays toast notifications. It's designed for developers using AI coding agents (Claude, GitHub Copilot CLI, Gemini) to get notified when long-running tasks complete.

**Key Features:**
- Lightweight (229 KB, no dependencies)
- Auto-registers on first run
- Simple: `toasty "Hello World" -t "Title"`
- Auto-detects AI agents
- Agent integration: `toasty --install`

## Blocked By
⚠️ **This integration is blocked pending upstream development:**

1. **macOS Support**: [PR #28](https://github.com/shanselman/toasty/pull/28) - Adds macOS support (Status: OPEN)
2. **WinGet Support**: [PR #39](https://github.com/shanselman/toasty/pull/39) - Windows Package Manager manifest (Status: DRAFT)

## Proposed Implementation

### PowerShell Function
Create `Invoke-ToastyNotification` in `functions.ps1`:
- Wraps toasty CLI for easy use
- Provides aliases: `toast`, `notify`
- Checks for toasty installation
- Supports Windows PowerShell 5.1+ and PowerShell 7+

### Example Usage
```powershell
# Simple notification
toast "Build completed!"

# With title
toast "Deployment successful" "Production Deploy"

# Agent-specific
toast "Task finished" -App copilot
```

### Installation
- Add to `home/.chezmoidata/packages.yaml` under `windows.winget`
- Create installation script when winget support is available
- Cross-platform aware (Windows first, macOS later)

## Implementation Tasks
- [ ] Monitor upstream macOS PR #28
- [ ] Monitor upstream winget support
- [ ] Add to packages.yaml
- [ ] Create PowerShell function
- [ ] Add aliases
- [ ] Write Pester tests
- [ ] Update documentation
- [ ] Test on Windows and macOS

## References
- Repository: https://github.com/shanselman/toasty
- macOS PR #28: https://github.com/shanselman/toasty/pull/28 (by @spboyer, status: OPEN)
- WinGet PR #39: https://github.com/shanselman/toasty/pull/39 (by @Copilot, status: DRAFT)

---

**Notes for issue creation:**
1. Create this issue in the DevSecNinja/dotfiles repository
2. Apply labels: `enhancement`, `powershell`, `windows`, `macos`, `blocked`
3. Consider adding this to a "Future Enhancements" project or milestone
