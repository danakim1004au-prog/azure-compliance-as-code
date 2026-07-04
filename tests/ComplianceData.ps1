<#
    Data-source abstraction for the compliance suites.

    COMPLIANCE_DATA_SOURCE = 'live'     -> query the connected Azure / Graph tenant
                           = 'fixtures' -> load committed sample state from tests/fixtures

    Defaults to 'live', so a local run after Connect-AzAccount / Connect-MgGraph
    behaves exactly as documented in the README. CI sets 'fixtures' when no OIDC
    secrets are configured, so the same suites go green with no cloud account —
    the rule engine is exercised against a known-compliant reference tenant.
#>

function Get-ComplianceDataSource {
    if ($env:COMPLIANCE_DATA_SOURCE) { $env:COMPLIANCE_DATA_SOURCE } else { 'live' }
}

$script:FixtureRoot = Join-Path $PSScriptRoot 'fixtures'

function Import-Fixture {
    param(
        [Parameter(Mandatory)][string]$RelativePath,
        [switch]$AsHashtable
    )
    $path = Join-Path $script:FixtureRoot $RelativePath
    Get-Content $path -Raw | ConvertFrom-Json -AsHashtable:$AsHashtable
}

# --- Azure ------------------------------------------------------------------

function Get-ComplianceResource {
    # -AsHashtable so a resource's .Tags exposes .Keys, matching the live
    # Az.Resources object shape the tests assert against.
    if ((Get-ComplianceDataSource) -eq 'fixtures') { return @(Import-Fixture 'azure/resources.json' -AsHashtable) }
    Get-AzResource
}

function Get-ComplianceStorageAccount {
    if ((Get-ComplianceDataSource) -eq 'fixtures') { return @(Import-Fixture 'azure/storageAccounts.json') }
    Get-AzStorageAccount
}

function Get-ComplianceNsg {
    if ((Get-ComplianceDataSource) -eq 'fixtures') { return @(Import-Fixture 'azure/nsgs.json') }
    Get-AzNetworkSecurityGroup
}

# --- Microsoft 365 / Graph --------------------------------------------------

function Get-ComplianceCaPolicy {
    if ((Get-ComplianceDataSource) -eq 'fixtures') { return @(Import-Fixture 'm365/conditionalAccessPolicies.json') }
    (Invoke-MgGraphRequest -Method GET `
        -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies').value
}

function Get-ComplianceAuthzPolicy {
    if ((Get-ComplianceDataSource) -eq 'fixtures') { return Import-Fixture 'm365/authorizationPolicy.json' }
    Invoke-MgGraphRequest -Method GET `
        -Uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy'
}
