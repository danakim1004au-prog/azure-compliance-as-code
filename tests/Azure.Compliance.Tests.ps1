#Requires -Version 7.0
<#
    Azure compliance suite — Pester v5, data-driven from rules/azure.rules.json.
    Live mode assumes Connect-AzAccount has already run (pipeline does OIDC login
    first) and needs Az.Accounts/Resources/Storage/Network. Fixtures mode reads
    tests/fixtures and needs no cloud connection — see tests/ComplianceData.ps1.
    Read-only by design: these tests hold no write permissions.
#>

BeforeDiscovery {
    # Discovery phase: build the case lists that -ForEach expands into It blocks.
    . "$PSScriptRoot/ComplianceData.ps1"
    $script:rules = Get-Content "$PSScriptRoot/../rules/azure.rules.json" -Raw | ConvertFrom-Json

    $script:allResources = @(Get-ComplianceResource)
    $script:storageAccounts = @(Get-ComplianceStorageAccount)
    $script:nsgs = @(Get-ComplianceNsg)

    $script:tagCases = foreach ($r in $script:allResources) {
        foreach ($tag in $script:rules.requiredTags) {
            @{ ResourceName = $r.Name; ResourceType = $r.ResourceType; Tag = $tag; Tags = $r.Tags }
        }
    }
    $script:regionCases = $script:allResources | ForEach-Object {
        @{ ResourceName = $_.Name; Location = $_.Location; Approved = $script:rules.approvedRegions }
    }
    $script:storageCases = foreach ($sa in $script:storageAccounts) {
        foreach ($rule in $script:rules.storageRules) {
            @{ Rule = $rule; Account = $sa; AccountName = $sa.StorageAccountName }
        }
    }
    $script:nsgCases = foreach ($nsg in $script:nsgs) {
        @{ NsgName = $nsg.Name; Nsg = $nsg; ForbiddenPorts = $script:rules.forbiddenInboundPorts }
    }
}

Describe 'AZ-TAG: Required tags' -Tag 'azure', 'warning' {
    It 'AZ-TAG-01: <ResourceName> has tag <Tag>' -ForEach $script:tagCases {
        $Tags.Keys | Should -Contain $Tag -Because "every resource needs $Tag for cost attribution and ownership"
    }
}

Describe 'AZ-LOC: Approved regions' -Tag 'azure', 'critical' {
    It 'AZ-LOC-01: <ResourceName> is in an approved AU region' -ForEach $script:regionCases {
        $Location | Should -BeIn $Approved -Because 'data residency: AU regions only'
    }
}

Describe 'AZ-ST: Storage account hardening' -Tag 'azure', 'critical' {
    It '<Rule.id>: <AccountName> <Rule.check>' -ForEach $script:storageCases {
        $actual = switch ($Rule.check) {
            'supportsHttpsTrafficOnly' { $Account.EnableHttpsTrafficOnly }
            'minimumTlsVersion'        { [string]$Account.MinimumTlsVersion }
            'allowBlobPublicAccess'    { [bool]$Account.AllowBlobPublicAccess }
        }
        $actual | Should -Be $Rule.expected -Because $Rule.description
    }
}

Describe 'AZ-NSG: No management ports open to the internet' -Tag 'azure', 'critical' {
    It 'AZ-NSG-01: <NsgName> has no Allow rule for 22/3389 from any' -ForEach $script:nsgCases {
        $offending = $Nsg.SecurityRules | Where-Object {
            $_.Access -eq 'Allow' -and $_.Direction -eq 'Inbound' -and
            ($_.SourceAddressPrefix -in '*', '0.0.0.0/0', 'Internet') -and
            ($_.DestinationPortRange | Where-Object {
                $range = $_
                $ForbiddenPorts | Where-Object {
                    $range -eq '*' -or $range -eq "$_" -or
                    ($range -match '^(\d+)-(\d+)$' -and $_ -ge [int]$Matches[1] -and $_ -le [int]$Matches[2])
                }
            })
        }
        $offending | Should -BeNullOrEmpty -Because "rules found: $($offending.Name -join ', ') — SSH/RDP must come via Bastion or VPN"
    }
}
