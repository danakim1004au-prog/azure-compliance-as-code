#Requires -Modules Pester, Microsoft.Graph.Authentication
<#
    M365 compliance suite — Pester v5, data-driven from rules/m365.rules.json.
    Assumes Connect-MgGraph has already run (cert app-only in pipelines).
    Needs Policy.Read.All only.
#>

BeforeDiscovery {
    $script:rules = Get-Content "$PSScriptRoot/../rules/m365.rules.json" -Raw | ConvertFrom-Json
    $script:caCases = $script:rules.conditionalAccessPolicies | ForEach-Object { @{ Rule = $_ } }
    $script:authzCases = $script:rules.authorizationPolicy | ForEach-Object { @{ Rule = $_ } }
}

BeforeAll {
    $script:livePolicies = (Invoke-MgGraphRequest -Method GET `
        -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies').value
    $script:authz = Invoke-MgGraphRequest -Method GET `
        -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy'
}

Describe 'M365-CA: Conditional Access baseline' -Tag 'm365', 'critical' {
    It '<Rule.id>: policy "<Rule.displayName>" exists and is <Rule.expectedState>' -ForEach $script:caCases {
        $policy = $script:livePolicies | Where-Object displayName -eq $Rule.displayName
        $policy | Should -Not -BeNullOrEmpty -Because 'a baseline CA policy must not be deleted'
        $policy.state | Should -Be $Rule.expectedState -Because 'report-only or disabled means unenforced'
    }
}

Describe 'M365-AUTHZ: Tenant authorization policy' -Tag 'm365', 'warning' {
    It '<Rule.id>: <Rule.check> is acceptable' -ForEach $script:authzCases {
        $actual = switch ($Rule.check) {
            'allowInvitesFrom' { $script:authz.allowInvitesFrom }
            'allowedToUseSSPR' { $script:authz.allowedToUseSSPR }
        }
        $actual | Should -BeIn $Rule.expectedOneOf -Because $Rule.description
    }
}
