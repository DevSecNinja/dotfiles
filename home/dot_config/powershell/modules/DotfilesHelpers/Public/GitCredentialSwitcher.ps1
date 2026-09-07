function Get-GitCredentialSwitchConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    $answer = Read-Host "$Message [y/N]"
    return $answer -in @("y", "yes")
}

function Invoke-GitWithCredentialSwitch {
    <#
    .SYNOPSIS
        Runs Git and switches GitHub CLI accounts after an HTTPS authentication failure.

    .DESCRIPTION
        Passes all arguments to the native Git executable. A failed push or pull
        whose stderr contains "fatal: Authentication failed for" triggers
        a confirmation naming the current and alternate GitHub accounts. On
        approval, it switches the account and retries the Git command once.
    #>
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [object[]]$ArgumentList
    )

    $gitCommand = Get-Command -Name git -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $gitCommand) {
        throw "Git executable not found."
    }

    $gitOperation = $null
    foreach ($argument in $ArgumentList) {
        if ([string]$argument -in @("push", "pull")) {
            $gitOperation = [string]$argument
            break
        }
    }

    if ($env:GIT_CREDENTIAL_SWITCHER_DISABLE -eq "1" -or -not $gitOperation) {
        & $gitCommand.Source @ArgumentList
        return
    }

    $errorPath = [System.IO.Path]::GetTempFileName()
    $firstStatus = 1

    try {
        & $gitCommand.Source @ArgumentList 2> $errorPath
        $firstStatus = $LASTEXITCODE
        $errorText = [System.IO.File]::ReadAllText($errorPath)

        if ($errorText) {
            [Console]::Error.Write($errorText)
        }

        if ($firstStatus -eq 0 -or
            $errorText -notmatch "fatal: Authentication failed for") {
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $authMatch = [regex]::Match(
            $errorText,
            'fatal: Authentication failed for [''"]https://(?:[^/@]+@)?(?<host>[^/''"]+)'
        )
        if (-not $authMatch.Success) {
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $canPrompt = $env:GIT_CREDENTIAL_SWITCHER_FORCE -eq "1" -or
            (-not [Console]::IsInputRedirected -and -not [Console]::IsErrorRedirected)
        if (-not $canPrompt) {
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $ghCommand = Get-Command -Name gh -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $ghCommand) {
            Write-Warning "GitHub CLI is unavailable; credentials were not switched."
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $hostName = $authMatch.Groups["host"].Value
        $authJson = & $ghCommand.Source auth status --hostname $hostName --json hosts
        if ($LASTEXITCODE -ne 0 -or -not $authJson) {
            Write-Warning "Could not read GitHub accounts for $hostName."
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $authStatus = $authJson | ConvertFrom-Json
        $hostProperty = $authStatus.hosts.PSObject.Properties[$hostName]
        $accounts = if ($hostProperty) { @($hostProperty.Value) } else { @() }
        $currentAccount = $accounts |
            Where-Object { $_.active } |
            Select-Object -First 1 -ExpandProperty login
        $nextAccount = $accounts |
            Where-Object { $_.login -ne $currentAccount } |
            Select-Object -First 1 -ExpandProperty login

        if (-not $nextAccount) {
            Write-Warning "No alternate GitHub account is configured for $hostName."
            $global:LASTEXITCODE = $firstStatus
            return
        }

        if (-not $currentAccount) {
            $currentAccount = "the current account"
        }

        $confirmationMessage = "Failed to authenticate with GitHub credential $currentAccount. " +
            "Switch context to $nextAccount and retry git ${gitOperation}?"
        if (-not (Get-GitCredentialSwitchConfirmation -Message $confirmationMessage)) {
            Write-Information "GitHub credential switch declined." -InformationAction Continue
            $global:LASTEXITCODE = $firstStatus
            return
        }

        $originalGhToken = $env:GH_TOKEN
        $originalGitHubToken = $env:GITHUB_TOKEN
        try {
            $env:GH_TOKEN = $null
            $env:GITHUB_TOKEN = $null

            & $ghCommand.Source auth switch --hostname $hostName --user $nextAccount
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "GitHub account switch failed."
                $global:LASTEXITCODE = $firstStatus
                return
            }

            Write-Information "Active GitHub account switched from $currentAccount to $nextAccount. Retrying git $gitOperation." -InformationAction Continue
            & $gitCommand.Source @ArgumentList
            $global:LASTEXITCODE = $LASTEXITCODE
        }
        finally {
            $env:GH_TOKEN = $originalGhToken
            $env:GITHUB_TOKEN = $originalGitHubToken
        }
    }
    finally {
        Remove-Item -LiteralPath $errorPath -Force -ErrorAction SilentlyContinue
    }
}
