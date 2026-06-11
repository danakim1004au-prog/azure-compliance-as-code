# Azure & M365 Compliance-as-Code Pipeline

Infrastructure compliance expressed as **Pester unit tests against live cloud state**, driven by a rule catalog in JSON and enforced in CI/CD. The pipeline connects to Azure (OIDC, no stored secrets) and Microsoft Graph (cert app-only), runs the test suite, publishes NUnit results to the pipeline UI, and **fails the build** when reality violates policy — the same red/green discipline applied to code, applied to cloud configuration.

## Purpose

Terraform answers "did we deploy what we declared?" — but most compliance failures happen *after* deployment: someone opens an NSG "temporarily," disables HTTPS-only on a storage account, or turns off a CA policy. This project closes that loop: the rule catalog is the contract, Pester is the auditor, and the pipeline runs it on every PR plus a nightly schedule. Pester + Graph + CI gating is a combination junior engineers almost never show — that's the point.

## Architecture

```
rules/azure.rules.json     rules/m365.rules.json
        │                          │
        ▼                          ▼
tests/Azure.Compliance.Tests.ps1   tests/M365.Compliance.Tests.ps1
  (rule catalog → dynamically generated `It` blocks via -ForEach)
        │
        ▼
scripts/Invoke-ComplianceRun.ps1
  Pester v5 · NUnit XML out · exit code = violation count
        │
   ┌────┴─────────────────────────────┐
   ▼                                  ▼
.github/workflows/compliance.yml   pipelines/azure-pipelines.yml
  azure/login via OIDC               AzureCLI@2 task + workload identity
  PR gate + nightly cron             PublishTestResults@2 → Tests tab
```

## Why dynamic tests from a JSON catalog

The naive version hard-codes assertions in the test file; adding a rule means editing PowerShell. Here the catalog is data:

```json
{ "id": "AZ-ST-01", "appliesTo": "storageAccount", "check": "supportsHttpsTrafficOnly",
  "expected": true, "severity": "critical", "description": "Storage accounts must enforce HTTPS" }
```

…and the test file generates one `It` block per rule × resource via Pester's `-ForEach`. New rule = one JSON object in a PR, reviewed like any code change. The Tests tab shows `AZ-ST-01: stproddata supportsHttpsTrafficOnly` as an individually passing/failing case.

## Rule coverage shipped

| Catalog | Rules |
|---|---|
| `azure.rules.json` | Required tags (owner/costCentre/environment) on all resources · storage HTTPS-only + min TLS 1.2 + no public blob access · no NSG rule allowing 0.0.0.0/0 inbound on 22/3389 · SQL auditing enabled · resources only in approved AU regions |
| `m365.rules.json` | Named CA policies exist & enabled · legacy auth blocked · SSPR enabled · guest invites restricted · unified audit log on |

## Tech stack

- Pester v5 (discovery/run phases, `-ForEach` data-driven cases, tags for `critical`-only runs)
- Az PowerShell + Microsoft Graph SDK
- GitHub Actions (azure/login with **OIDC federated credentials** — zero stored cloud secrets) and Azure DevOps (workload identity service connection) — same tests, both pipelines
- NUnit XML → native test reporting in both CIs

## Repo structure

```
azure-compliance-as-code/
├── README.md
├── .gitignore
├── rules/
│   ├── azure.rules.json
│   └── m365.rules.json
├── tests/
│   ├── Azure.Compliance.Tests.ps1
│   └── M365.Compliance.Tests.ps1
├── scripts/
│   └── Invoke-ComplianceRun.ps1
├── pipelines/
│   └── azure-pipelines.yml
├── .github/workflows/
│   └── compliance.yml
└── docs/
    └── screenshot-checklist.md
```

## Quick start

```powershell
Install-Module Pester, Az.Accounts, Az.Resources, Az.Storage, Az.Network, Microsoft.Graph.Authentication -Scope CurrentUser
Connect-AzAccount; Connect-MgGraph -Scopes 'Policy.Read.All'   # interactive for local runs

./scripts/Invoke-ComplianceRun.ps1                      # everything
./scripts/Invoke-ComplianceRun.ps1 -Tag critical       # gate-worthy rules only
./scripts/Invoke-ComplianceRun.ps1 -Suite azure        # skip M365
```

## Design decisions

- **Tests read, never write.** A compliance check with write permissions is a finding in itself. Remediation is a human (or a separate, deliberately-scoped tool like [`azure-monitor-selfheal`](../azure-monitor-selfheal)).
- **Severity tags, not severity if-statements.** `critical` rules gate PRs; `warning` rules only fail the nightly run. The mechanism is Pester tags, not custom logic.
- **OIDC over secrets.** The GitHub workflow authenticates with federated credentials — nothing to rotate, nothing to leak in logs.
