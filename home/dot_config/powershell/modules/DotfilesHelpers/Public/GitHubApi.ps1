# Transport and identity helpers for the GitHub CLI.
#
# Every `gh` invocation in the DotfilesHelpers module goes through
# Invoke-GitHubCli, so error handling is uniform and the whole GitHub
# surface can be unit-tested by mocking one function - no `gh` binary
# required on the test machine.
#
# Part of the GitHub repository configuration tooling; see
# GitHubRepoConfig.ps1 for the public commands and docs/github-repo-config.md
# for the user-facing guide.

function Invoke-GitHubCli {
    <#
    .SYNOPSIS
        Invoke the `gh` CLI and return its stdout.
    .DESCRIPTION
        Single choke point for every `gh` invocation in this file. Keeping the
        process launch in one place means error handling is uniform and the
        whole module can be unit-tested by mocking this one function, without
        `gh` being installed on the test machine.
    .PARAMETER Arguments
        Argument array passed verbatim to `gh`.
    .PARAMETER StdIn
        Optional string piped to the process on standard input. Used for
        request bodies and secret values so they never appear in a process
        argument list, which is world-readable on most systems.
    .PARAMETER AllowFailure
        Return $null on a non-zero exit code instead of throwing.
    .PARAMETER ErrorContext
        Human-readable description of the operation, used in the error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [string]$StdIn,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFailure,

        [Parameter(Mandatory = $false)]
        [string]$ErrorContext
    )

    if ([string]::IsNullOrWhiteSpace($ErrorContext)) {
        $ErrorContext = "gh $($Arguments -join ' ')"
    }

    if ($PSBoundParameters.ContainsKey('StdIn')) {
        $output = $StdIn | & gh @Arguments 2>&1
    }
    else {
        $output = & gh @Arguments 2>&1
    }

    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Verbose "$ErrorContext failed (exit $LASTEXITCODE): $output"
            return $null
        }
        throw "$ErrorContext failed (exit $LASTEXITCODE): $output"
    }

    return ($output | Out-String).Trim()
}

function Test-GitHubCliReady {
    <#
    .SYNOPSIS
        Throw unless the `gh` CLI is installed and authenticated.
    .DESCRIPTION
        Central pre-flight for every function in this file. Failing fast here
        produces a single actionable error instead of a cascade of confusing
        API failures halfway through a bulk operation.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "The GitHub CLI (gh) was not found on PATH. Install it from https://cli.github.com/ and run 'gh auth login'."
    }

    $null = & gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "The GitHub CLI is not authenticated. Run 'gh auth login' first."
    }
}

function Invoke-GitHubApi {
    <#
    .SYNOPSIS
        Invoke `gh api` and return the parsed JSON response.
    .DESCRIPTION
        Thin wrapper that centralises argument construction, error handling and
        JSON parsing. Request bodies are passed on stdin rather than as `-f`
        flags so that booleans and nulls survive with their real JSON types.
    .PARAMETER Endpoint
        API path, e.g. 'repos/OWNER/REPO'.
    .PARAMETER Method
        HTTP method. Defaults to GET.
    .PARAMETER Body
        Hashtable serialised to JSON and sent on stdin.
    .PARAMETER AllowFailure
        Return $null on a non-zero exit code instead of throwing. Used for
        endpoints that legitimately 404 (an absent ruleset) or 403 (a plan that
        does not include the feature).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [hashtable]$Body,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFailure
    )

    $ghArgs = @('api', $Endpoint, '--method', $Method)
    $cliArgs = @{
        Arguments    = $ghArgs
        ErrorContext = "gh api $Endpoint"
        AllowFailure = [bool]$AllowFailure
    }

    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body -and $Body.Count -gt 0) {
        $cliArgs['Arguments'] = $ghArgs + @('--input', '-')
        $cliArgs['StdIn'] = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    $text = Invoke-GitHubCli @cliArgs

    if ($null -eq $text -or [string]::IsNullOrWhiteSpace($text)) { return $null }

    # A JSON array has to be reassembled explicitly. Piping into
    # ConvertFrom-Json enumerates the result, so `$x = '[]' | ConvertFrom-Json`
    # yields $null - indistinguishable from a failed call - and a single-element
    # list would arrive as a bare object. Wrapping in @() fixes both, and the
    # unary comma on return stops the pipeline unrolling it again. (PowerShell
    # unwraps exactly one level on the way out, so the caller still receives the
    # array itself, not a nested one. ConvertFrom-Json -NoEnumerate would be
    # tidier but does not exist on Windows PowerShell 5.1, which this module
    # supports.)
    $looksLikeArray = $text.TrimStart().StartsWith('[')

    try {
        $parsed = @($text | ConvertFrom-Json)
    }
    catch {
        throw "Could not parse the response from gh api $Endpoint as JSON: $_"
    }

    if ($looksLikeArray) {
        return , $parsed
    }

    return $parsed[0]
}

function Get-GitHubRulesetList {
    <#
    .SYNOPSIS
        List the rulesets on a repository, distinguishing empty from unreadable.
    .DESCRIPTION
        `GET /repos/{owner}/{repo}/rulesets` returns `[]` for a repository with
        no rulesets and fails outright when the caller lacks the administration
        permission or the repository is private on a plan without rulesets.
        Those two cases require opposite handling - one is drift to remediate,
        the other must be skipped - so this returns an explicit Available flag
        rather than relying on $null.
    .PARAMETER Repository
        Repository in 'owner/name' form.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Repository
    )

    $response = Invoke-GitHubCli -Arguments @('api', "repos/$Repository/rulesets", '--method', 'GET') `
        -AllowFailure -ErrorContext "gh api repos/$Repository/rulesets"

    if ($null -eq $response) {
        return [PSCustomObject]@{ Available = $false; Rulesets = @() }
    }

    if ([string]::IsNullOrWhiteSpace($response)) {
        return [PSCustomObject]@{ Available = $true; Rulesets = @() }
    }

    try {
        return [PSCustomObject]@{ Available = $true; Rulesets = @($response | ConvertFrom-Json) }
    }
    catch {
        throw "Could not parse the ruleset list for ${Repository} as JSON: $_"
    }
}

function Resolve-GitHubRepoName {
    <#
    .SYNOPSIS
        Normalise a repository reference to 'owner/name'.
    .DESCRIPTION
        Accepts a bare name ('docker'), a qualified name ('DevSecNinja/docker')
        or a full URL and always returns 'owner/name'. Bare names are qualified
        with -Owner.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Repository,

        [Parameter(Mandatory = $false)]
        [string]$Owner
    )

    $name = $Repository.Trim()
    $name = $name -replace '^https?://github\.com/', ''
    $name = $name -replace '\.git$', ''
    $name = $name.Trim('/')

    if ($name -match '/') {
        $parts = $name -split '/'
        if ($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "'$Repository' is not a valid repository reference. Use 'name' or 'owner/name'."
        }
        return "$($parts[0])/$($parts[1])"
    }

    if ([string]::IsNullOrWhiteSpace($Owner)) {
        throw "Repository '$Repository' has no owner. Pass 'owner/name' or supply -Owner."
    }

    return "$Owner/$name"
}

function Get-GitHubCurrentOwner {
    <#
    .SYNOPSIS
        Return the login of the authenticated GitHub user.
    .DESCRIPTION
        Prefers CHEZMOI_GITHUB_USERNAME (exported by the chezmoi-rendered
        PowerShell config) to save an API round-trip, and falls back to the
        authenticated user behind the `gh` CLI.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:CHEZMOI_GITHUB_USERNAME)) {
        return $env:CHEZMOI_GITHUB_USERNAME
    }

    $user = Invoke-GitHubApi -Endpoint 'user'
    if ($null -eq $user -or [string]::IsNullOrWhiteSpace($user.login)) {
        throw "Could not determine the authenticated GitHub user. Run 'gh auth login' or pass -Owner."
    }

    return $user.login
}
