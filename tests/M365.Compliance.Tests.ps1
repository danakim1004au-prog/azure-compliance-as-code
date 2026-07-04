#Requires -Version 7.0
<#
    M365 compliance suite — Pester v5, data-driven from rules/m365.rules.json.
    Live mode assumes Connect-MgGraph has already run (cert app-only in pipelines,
    Policy.Read.All only). Fixtures mode reads tests/fixtures and needs no Graph
    connection — see tests/ComplianceData.ps1.
#>

BeforeDiscovery {
    $script:rules = Get-Content "$PSScriptRoot/../rules/m365.rules.json" -Raw | ConvertFrom-Json
    $script:caCases = $script:rules.conditionalAccessPolicies | ForEach-Object { @{ Rule = $_ } }
    $script:authzCases = $script:rules.authorizationPolicy | ForEach-Object { @{ Rule = $_ } }
}

BeforeAll {
    . "$PSScriptRoot/ComplianceData.ps1"
    $script:livePolicies = @(Get-ComplianceCaPolicy)
    $script:authz = Get-ComplianceAuthzPolicy
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
