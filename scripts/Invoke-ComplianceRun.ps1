#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs the compliance Pester suites and writes NUnit XML for CI test tabs.
.DESCRIPTION
    Exit code = number of failed checks, so any violation fails the pipeline
    step. -Tag critical limits to gate-worthy rules (the PR gate); the
    nightly run executes everything.
.EXAMPLE
    ./Invoke-ComplianceRun.ps1 -Suite azure -Tag critical
#>
#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('azure', 'm365', 'all')]
    [string]$Suite = 'all',
    [string[]]$Tag,
    [string]$ResultPath = "$PSScriptRoot/../results"
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Path $ResultPath -Force | Out-Null

$dataSource = if ($env:COMPLIANCE_DATA_SOURCE) { $env:COMPLIANCE_DATA_SOURCE } else { 'live' }
Write-Host "Data source: $dataSource (set COMPLIANCE_DATA_SOURCE=fixtures for an offline demo run)" -ForegroundColor Cyan

$testPaths = switch ($Suite) {
    'azure' { @("$PSScriptRoot/../tests/Azure.Compliance.Tests.ps1") }
    'm365'  { @("$PSScriptRoot/../tests/M365.Compliance.Tests.ps1") }
    'all'   { @("$PSScriptRoot/../tests") }
}

$config = New-PesterConfiguration
$config.Run.Path = $testPaths
$config.Run.PassThru = $true
$config.Run.Exit = $false
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = Join-Path $ResultPath "compliance-$Suite-$(Get-Date -Format 'yyyyMMdd-HHmm').xml"
if ($Tag) { $config.Filter.Tag = $Tag }

$result = Invoke-Pester -Configuration $config

Write-Host ("`nCompliance: {0} passed, {1} failed, {2} skipped → {3}" -f
    $result.PassedCount, $result.FailedCount, $result.SkippedCount, $config.TestResult.OutputPath.Value) `
    -ForegroundColor $(if ($result.FailedCount) { 'Red' } else { 'Green' })

exit $result.FailedCount
