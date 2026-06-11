# Screenshot checklist

Store under `docs/img/`, embed hero shots in README.

1. **Local run, all green** — `Invoke-ComplianceRun.ps1` detailed Pester output showing rule IDs as test names (`AZ-ST-01: stproddata supportsHttpsTrafficOnly`).
2. **Induce a violation** — portal: disable HTTPS-only on a lab storage account, or add an NSG rule allowing 3389 from `*`. Screenshot the portal change.
3. **Local run, red** — failed test with the `-Because` message visible (e.g. "SSH/RDP must come via Bastion or VPN"). Hero shot #1.
4. **GitHub Actions PR gate** — a PR (e.g. adding a rule to the catalog) with the red `Compliance results` check blocking merge; the publish-unit-test-result summary showing which case failed. Hero shot #2.
5. **Azure DevOps Tests tab** — NUnit results rendered as individual test cases with pass/fail history.
6. **Nightly schedule** — Actions run list showing the cron runs.
7. **Fix & green** — revert the violation, re-run, green check on the same PR. ("Detected → blocked → remediated → verified" narrative.)
8. **Rule catalog diff** — a PR diff adding one JSON rule object, demonstrating "new compliance control = one reviewed JSON object, zero PowerShell changes."
