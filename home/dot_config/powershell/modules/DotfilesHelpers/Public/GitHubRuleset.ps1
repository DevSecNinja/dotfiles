# Build default-branch ruleset payloads.
#
# The rulesets API replaces the whole object on PUT, so building a payload
# is inherently destructive unless everything the baseline does not own is
# carried over. That carry-over is the entire point of this file.
#
# Part of the GitHub repository configuration tooling; see
# GitHubRepoConfig.ps1 for the public commands and docs/github-repo-config.md
# for the user-facing guide.

# Repository role IDs used as ruleset bypass actors. GitHub does not expose
# these by name on the rulesets API, so the admin role is pinned by ID.
# 5 = Repository admin, i.e. the repository owner on a personal account.
$script:GitHubRepositoryRoleAdmin = 5

function New-GitHubRulesetPayload {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Builds and returns a hashtable; does not change system state.')]
    <#
    .SYNOPSIS
        Build the rulesets API payload for the desired branch protection.
    .DESCRIPTION
        Translates the Ruleset section of the baseline into the request body
        accepted by POST/PUT /repos/{owner}/{repo}/rulesets. The payload is
        always complete, because the rulesets API replaces the whole object on
        update and a partial body would silently drop rules.

        That same replace-everything behaviour makes updates destructive, so
        when -ExistingRuleset is supplied any rule this baseline does not manage
        (required_status_checks and its context list, copilot_code_review, and
        so on) is carried over verbatim, and existing bypass actors are kept.
        Only the managed rules - deletion, non_fast_forward and pull_request -
        are replaced.
    .PARAMETER Ruleset
        The Ruleset section of a baseline hashtable.
    .PARAMETER ExistingRuleset
        The current ruleset as returned by the API, when updating in place.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Ruleset,

        [Parameter(Mandatory = $false)]
        $ExistingRuleset
    )

    # Rule types this baseline owns. Anything else found on an existing ruleset
    # is preserved untouched.
    $managedRuleTypes = @('deletion', 'non_fast_forward', 'pull_request')

    $rules = [System.Collections.Generic.List[object]]::new()
    $existingPullRequest = $null

    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.rules) {
        foreach ($rule in $ExistingRuleset.rules) {
            if ($managedRuleTypes -notcontains $rule.type) {
                $rules.Add($rule)
            }
            elseif ($rule.type -eq 'pull_request') {
                $existingPullRequest = $rule
            }
        }
    }

    if ($Ruleset.BlockDeletion) {
        $rules.Add(@{ type = 'deletion' })
    }

    if ($Ruleset.BlockForcePush) {
        $rules.Add(@{ type = 'non_fast_forward' })
    }

    if ($Ruleset.RequirePullRequest) {
        # Only two pull_request parameters belong to this baseline. Everything
        # else - code-owner review, stale-review dismissal, last-push approval,
        # thread resolution, and any parameter GitHub adds later - is carried
        # over from the existing rule, so remediating a merge-method drift never
        # silently switches someone's stricter review settings off.
        $prParameters = [ordered]@{}
        if ($null -ne $existingPullRequest -and $null -ne $existingPullRequest.parameters) {
            foreach ($property in $existingPullRequest.parameters.PSObject.Properties) {
                $prParameters[$property.Name] = $property.Value
            }
        }
        else {
            # No existing rule to inherit from: start from GitHub's defaults.
            $prParameters['dismiss_stale_reviews_on_push'] = $false
            $prParameters['require_code_owner_review'] = $false
            $prParameters['require_last_push_approval'] = $false
            $prParameters['required_review_thread_resolution'] = $false
        }

        $prParameters['allowed_merge_methods'] = @($Ruleset.AllowedMergeMethods)
        $prParameters['required_approving_review_count'] = $Ruleset.RequiredApprovingReviews

        $rules.Add(@{ type = 'pull_request'; parameters = $prParameters })
    }

    $bypassActors = [System.Collections.Generic.List[object]]::new()
    $hasAdminBypass = $false

    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.bypass_actors) {
        foreach ($actor in $ExistingRuleset.bypass_actors) {
            if ($actor.actor_type -eq 'RepositoryRole' -and $actor.actor_id -eq $script:GitHubRepositoryRoleAdmin) {
                $hasAdminBypass = $true
                if (-not $Ruleset.AdminCanBypass) { continue }
            }
            $bypassActors.Add($actor)
        }
    }

    if ($Ruleset.AdminCanBypass -and -not $hasAdminBypass) {
        # Lets the repository admin (you) push directly to the default branch
        # and merge without a PR when needed, while everything else - including
        # GitHub Actions - stays subject to the rules.
        $bypassActors.Add(@{
                actor_id    = $script:GitHubRepositoryRoleAdmin
                actor_type  = 'RepositoryRole'
                bypass_mode = 'always'
            })
    }

    $conditions = @{
        ref_name = @{
            include = @('~DEFAULT_BRANCH')
            exclude = @()
        }
    }

    # Keep a deliberately narrower or broader ref condition if one is already
    # configured; retargeting someone's ruleset is not this tool's job. The one
    # exception is a condition that does not cover the default branch at all -
    # preserving that would leave the branch unprotected, which is the whole
    # point of the ruleset, so the default-branch include is added to it.
    if ($null -ne $ExistingRuleset -and $null -ne $ExistingRuleset.conditions -and $null -ne $ExistingRuleset.conditions.ref_name) {
        $include = @($ExistingRuleset.conditions.ref_name.include)
        $coversDefault = ($include -contains '~ALL') -or ($include -contains '~DEFAULT_BRANCH')
        if (-not $coversDefault) {
            $include += '~DEFAULT_BRANCH'
        }
        $conditions = @{
            ref_name = @{
                include = $include
                exclude = @($ExistingRuleset.conditions.ref_name.exclude)
            }
        }
    }

    return @{
        name          = $Ruleset.Name
        target        = 'branch'
        enforcement   = $Ruleset.Enforcement
        bypass_actors = $bypassActors.ToArray()
        conditions    = $conditions
        rules         = $rules.ToArray()
    }
}
