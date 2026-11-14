#Requires -Version 5.1
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Placeholder credential for a throwaway repository; not a real key.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Destructive opt-in test; announcing the repository it creates and deletes is the point.')]
param()
<#
.SYNOPSIS
    Opt-in contract tests for the GitHub repository configuration tooling,
    run against a real, disposable GitHub repository.

.DESCRIPTION
    Every other test in this suite mocks at the CLI wrapper boundary, which
    proves the module's own logic but says nothing about whether the payloads
    it builds are ones the GitHub API actually accepts, or whether the shapes
    it parses are ones the API actually returns. Two of the four bugs found in
    review were exactly that: assumptions about API shapes that the mocks
    happily confirmed because the fixtures were written from the same
    assumptions.

    These tests close that gap. They create a throwaway repository, drive the
    real audit/remediate cycle against it, and delete it again.

    DESTRUCTIVE and NOT run by default. They are skipped unless
    DOTFILES_CONTRACT_TEST=1, so a stray CI run or a normal local suite can
    never create repositories.

    Requirements:
      - DOTFILES_CONTRACT_TEST=1
      - `gh` authenticated with a token that can create and delete
        repositories, and administer them:
          Repository creation (account level)
          Administration: read & write   (settings, rulesets, Actions perms)
          Secrets / Variables: read & write
          Environments: read & write
          Contents: read
      - Optional: DOTFILES_CONTRACT_OWNER to place the repository somewhere
        other than the authenticated user.

    The repository is created public because GitHub environments and
    deployment branch policies are public-repository-only on the Free plan,
    and the environment pinning behaviour is one of the things worth
    verifying. It is empty, exists for the duration of the run, and is
    deleted in AfterAll even when a test fails.
#>

BeforeDiscovery {
    $script:ContractEnabled = $env:DOTFILES_CONTRACT_TEST -eq '1'
}

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $modulePath = Join-Path $script:RepoRoot 'home/dot_config/powershell/modules/DotfilesHelpers'
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $script:Owner = if ($env:DOTFILES_CONTRACT_OWNER) {
        $env:DOTFILES_CONTRACT_OWNER
    }
    else {
        (& gh api user --jq '.login' | Out-String).Trim()
    }

    # Name carries its own explanation, so an orphan left by a hard kill is
    # obviously safe to delete.
    $script:RepoName = "zz-delete-me-dotfiles-contract-$(Get-Random -Minimum 100000 -Maximum 999999)"
    $script:Target = "$($script:Owner)/$($script:RepoName)"

    Write-Host "[contract] creating disposable repository $($script:Target)" -ForegroundColor Cyan
    $created = & gh api -X POST user/repos `
        -f name=$script:RepoName `
        -f description='Disposable repository for dotfiles contract tests. Safe to delete.' `
        -F private=false `
        -F auto_init=true 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Could not create $($script:Target): $created"
    }

    # auto_init commits a README, so there is a default branch to protect.
    $script:DefaultBranch = (& gh api "repos/$script:Target" --jq '.default_branch' | Out-String).Trim()
}

AfterAll {
    if ($script:Target) {
        Write-Host "[contract] deleting $($script:Target)" -ForegroundColor Cyan
        $null = & gh api -X DELETE "repos/$script:Target" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Could not delete $($script:Target). Delete it by hand: gh repo delete $($script:Target) --yes"
        }
        else {
            # Deletion is the one thing that must not silently fail, so confirm.
            $null = & gh api "repos/$script:Target" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Warning "$($script:Target) still exists after delete; remove it by hand."
            }
        }
    }
}

Describe "Repository settings round-trip" -Tag "Contract" -Skip:(-not $script:ContractEnabled) {
    It "reports drift on a freshly created repository" {
        $result = Get-GitHubRepoConfig -Repository $script:Target -Check Settings
        $result.DriftCount | Should -BeGreaterThan 0 -Because 'a new repository uses GitHub defaults, not the baseline'
    }

    It "converges to compliant after remediation" {
        Get-GitHubRepoConfig -Repository $script:Target -Check Settings |
            Set-GitHubRepoConfig -Category Settings -Confirm:$false

        $after = Get-GitHubRepoConfig -Repository $script:Target -Check Settings
        $after.DriftCount | Should -Be 0
        $after.IsCompliant | Should -BeTrue
    }

    It "is idempotent: a second run writes nothing" {
        $result = Get-GitHubRepoConfig -Repository $script:Target -Check Settings |
            Set-GitHubRepoConfig -Category Settings -Confirm:$false -PassThru
        @($result.Applied).Count | Should -Be 0
    }

    It "actually applied the baseline values, not just its own idea of them" {
        # Read straight from the API rather than through the module, so a
        # symmetrical bug in audit and remediate cannot hide.
        $repo = & gh api "repos/$script:Target" | ConvertFrom-Json
        $repo.allow_squash_merge | Should -BeTrue
        $repo.allow_merge_commit | Should -BeFalse
        $repo.allow_rebase_merge | Should -BeFalse
        $repo.delete_branch_on_merge | Should -BeTrue
        $repo.squash_merge_commit_title | Should -Be 'PR_TITLE'
        $repo.squash_merge_commit_message | Should -Be 'BLANK'
    }
}

Describe "Ruleset round-trip" -Tag "Contract" -Skip:(-not $script:ContractEnabled) {
    It "creates a ruleset the API accepts" {
        Get-GitHubRepoConfig -Repository $script:Target -Check Ruleset |
            Set-GitHubRepoConfig -Category Ruleset -Confirm:$false

        $after = Get-GitHubRepoConfig -Repository $script:Target -Check Ruleset
        $after.DriftCount | Should -Be 0
    }

    It "produced a repository-owned branch ruleset covering the default branch" {
        $rulesets = & gh api "repos/$script:Target/rulesets" | ConvertFrom-Json
        $default = @($rulesets | Where-Object { $_.name -eq 'Default' })[0]
        $default | Should -Not -BeNullOrEmpty
        $default.target | Should -Be 'branch'

        $detail = & gh api "repos/$script:Target/rulesets/$($default.id)" | ConvertFrom-Json
        $detail.conditions.ref_name.include | Should -Contain '~DEFAULT_BRANCH'
        @($detail.rules | ForEach-Object { $_.type }) | Should -Contain 'pull_request'
    }

    It "kept the admin bypass so the owner is not locked out" {
        $rulesets = & gh api "repos/$script:Target/rulesets" | ConvertFrom-Json
        $default = @($rulesets | Where-Object { $_.name -eq 'Default' })[0]
        $detail = & gh api "repos/$script:Target/rulesets/$($default.id)" | ConvertFrom-Json

        @($detail.bypass_actors | Where-Object {
                $_.actor_type -eq 'RepositoryRole' -and $_.actor_id -eq 5
            }).Count | Should -Be 1
    }

    It "preserves pull_request parameters the baseline does not own" {
        # The regression the mocks could not catch: set a stricter review
        # setting through the real API, force a merge-method drift, remediate,
        # and confirm the stricter setting survived.
        $rulesets = & gh api "repos/$script:Target/rulesets" | ConvertFrom-Json
        $default = @($rulesets | Where-Object { $_.name -eq 'Default' })[0]
        $detail = & gh api "repos/$script:Target/rulesets/$($default.id)" | ConvertFrom-Json

        $rules = @($detail.rules | Where-Object { $_.type -ne 'pull_request' })
        $rules += @{
            type       = 'pull_request'
            parameters = @{
                allowed_merge_methods             = @('merge', 'squash', 'rebase')
                required_approving_review_count   = 0
                require_code_owner_review         = $true
                dismiss_stale_reviews_on_push     = $true
                require_last_push_approval        = $false
                required_review_thread_resolution = $true
            }
        }

        $body = @{
            name          = $detail.name
            target        = 'branch'
            enforcement   = 'active'
            bypass_actors = @($detail.bypass_actors)
            conditions    = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
            rules         = $rules
        } | ConvertTo-Json -Depth 10 -Compress

        $null = $body | & gh api "repos/$script:Target/rulesets/$($default.id)" --method PUT --input - 2>&1
        $LASTEXITCODE | Should -Be 0 -Because 'the seeding call itself must succeed for this test to mean anything'

        Get-GitHubRepoConfig -Repository $script:Target -Check Ruleset |
            Set-GitHubRepoConfig -Category Ruleset -Confirm:$false

        $final = & gh api "repos/$script:Target/rulesets/$($default.id)" | ConvertFrom-Json
        $pr = @($final.rules | Where-Object { $_.type -eq 'pull_request' })[0]

        $pr.parameters.require_code_owner_review | Should -BeTrue -Because 'remediating merge methods must not weaken review requirements'
        $pr.parameters.dismiss_stale_reviews_on_push | Should -BeTrue
        $pr.parameters.required_review_thread_resolution | Should -BeTrue
        $pr.parameters.allowed_merge_methods | Should -Be @('squash')
    }

    It "leaves a same-named tag ruleset untouched" {
        $tagBody = @{
            name        = 'Default'
            target      = 'tag'
            enforcement = 'active'
            conditions  = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }
            rules       = @(@{ type = 'deletion' })
        } | ConvertTo-Json -Depth 10 -Compress

        $created = $tagBody | & gh api "repos/$script:Target/rulesets" --method POST --input - 2>&1
        $LASTEXITCODE | Should -Be 0
        $tagId = ($created | ConvertFrom-Json).id

        Get-GitHubRepoConfig -Repository $script:Target -Check Ruleset |
            Set-GitHubRepoConfig -Category Ruleset -Confirm:$false

        $tag = & gh api "repos/$script:Target/rulesets/$tagId" | ConvertFrom-Json
        $tag.target | Should -Be 'tag' -Because 'a tag ruleset sharing the name must never be overwritten with a branch payload'
        @($tag.rules | ForEach-Object { $_.type }) | Should -Be @('deletion')
    }
}

Describe "Environment credential placement" -Tag "Contract" -Skip:(-not $script:ContractEnabled) {
    BeforeAll {
        # A placeholder, not a real key: this exercises placement against the
        # live API without needing 1Password or a genuine App credential.
        $script:FakeCredential = [PSCustomObject]@{
            PSTypeName = 'Dotfiles.GitHubAppCredential'
            AppId      = '000000'
            PrivateKey = (ConvertTo-SecureString "-----BEGIN RSA PRIVATE KEY-----`nCONTRACTTEST`n-----END RSA PRIVATE KEY-----" -AsPlainText -Force)
        }
    }

    It "creates the environment, pins it, and stores the credential" {
        Get-GitHubRepoConfig -Repository $script:Target -Check AppCredential |
            Set-GitHubRepoConfig -Category AppCredential -AppCredential $script:FakeCredential -Confirm:$false

        $after = Get-GitHubRepoConfig -Repository $script:Target -Check AppCredential
        $after.DriftCount | Should -Be 0
    }

    It "pinned the environment to the default branch and nothing else" {
        $policies = & gh api "repos/$script:Target/environments/production/deployment-branch-policies" | ConvertFrom-Json
        @($policies.branch_policies).Count | Should -Be 1
        $policies.branch_policies[0].name | Should -Be $script:DefaultBranch
    }

    It "stored the secret in the environment, not at repository level" {
        $envSecrets = & gh api "repos/$script:Target/environments/production/secrets" | ConvertFrom-Json
        @($envSecrets.secrets | Where-Object { $_.name -eq 'AUTOMATION_APP_PRIVATE_KEY' }).Count | Should -Be 1

        $repoSecrets = & gh api "repos/$script:Target/actions/secrets" | ConvertFrom-Json
        @($repoSecrets.secrets | Where-Object { $_.name -eq 'AUTOMATION_APP_PRIVATE_KEY' }).Count | Should -Be 0
    }

    It "removes a broader branch policy rather than leaving it alongside the pin" {
        $null = @{ name = 'feature/*'; type = 'branch' } | ConvertTo-Json -Compress |
            & gh api "repos/$script:Target/environments/production/deployment-branch-policies" --method POST --input - 2>&1
        $LASTEXITCODE | Should -Be 0

        $audit = Get-GitHubRepoConfig -Repository $script:Target -Check AppCredential
        @($audit.Drift | Where-Object { $_.Setting -eq 'environment_pinned_to_default_branch' }).Count |
            Should -Be 1 -Because 'main plus feature/* is not pinned'

        $audit | Set-GitHubRepoConfig -Category AppCredential -AppCredential $script:FakeCredential -Confirm:$false

        $policies = & gh api "repos/$script:Target/environments/production/deployment-branch-policies" | ConvertFrom-Json
        @($policies.branch_policies).Count | Should -Be 1
        $policies.branch_policies[0].name | Should -Be $script:DefaultBranch
    }
}

Describe "Actions permissions round-trip" -Tag "Contract" -Skip:(-not $script:ContractEnabled) {
    It "applies and converges" {
        Get-GitHubRepoConfig -Repository $script:Target -Check Actions |
            Set-GitHubRepoConfig -Category Actions -Confirm:$false

        $after = Get-GitHubRepoConfig -Repository $script:Target -Check Actions
        $after.DriftCount | Should -Be 0

        $perms = & gh api "repos/$script:Target/actions/permissions/workflow" | ConvertFrom-Json
        $perms.default_workflow_permissions | Should -Be 'read'
        $perms.can_approve_pull_request_reviews | Should -BeFalse
    }
}
