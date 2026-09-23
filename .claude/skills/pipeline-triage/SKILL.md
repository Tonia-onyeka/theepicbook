---
name: pipeline-triage
description: Run the read-only CI/CD pipeline failure-triage script, analyze the evidence, and produce a concise diagnosis with a recommended fix. Never re-runs, cancels, or approves a pipeline, and never touches secrets or service connections.
allowed-tools: Bash, Read, Grep
disable-model-invocation: true
---

# Pipeline Triage Skill

When `/pipeline-triage` is invoked:

1. Read `CLAUDE.md` before doing anything else.
2. Run `bash pipeline-triage.sh || true`.
3. Read `reports/pipeline-health-report.txt` and `reports/pipeline-last-run.log`.
4. Report the following:
   - Overall status
   - Every WARN or FAIL result
   - The exact log evidence supporting each result (quote the matching line)
   - The most likely failure category: dependency install failure, build/compile failure, test failure, authentication/permission failure, or agent/runner availability issue
   - One specific, actionable fix recommendation for the human to review (e.g. "update the expired PAT in the service connection", "add a missing `npm ci` step before the build step", "the assertion at the quoted line expects a different value than the code returns")
   - One verification command or step the human can use after applying the fix
5. If every check passes, clearly state that the pipeline is healthy and no fix is required.
6. Do not edit any file, including pipeline YAML.
7. Do not re-trigger, retry, cancel, or approve a pipeline run.
8. Do not read, modify, or reference the value of any secret, token, or service connection credential — only note that one may be expired or missing based on log evidence.
9. Ask the human to review and apply any recommended fix manually, then re-run `/pipeline-triage` to verify.
