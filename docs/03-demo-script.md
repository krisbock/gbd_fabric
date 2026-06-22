# 03 — Demo script (live walkthrough)

**Audience:** data team / platform leads evaluating GitHub for Fabric.
**Duration:** ~15–20 minutes.
**One-liner:** *"Every change to our data platform is a reviewed, versioned, automated
promotion — from a developer's sandbox all the way to production — with full history and
approvals."*

Everything is pre-built. The only thing you click live is the **PR promotion story**.

---

## Before you start (have these tabs open)

1. GitHub repo → **Code** (showing branches) and **Pull requests**.
2. GitHub repo → **Actions**.
3. Fabric: the four workspaces — **Healthcare-Feature / Dev / Test / Prod**.
4. The **HospitalOps** report open in **Healthcare-Dev** and **Healthcare-Prod**.

---

## Act 1 — "Your data platform lives in Git" (3 min)

1. Show the repo. Point out the four branches: `feature/demo`, `dev`, `test`, `main`.
   > "Each branch is an environment. Nothing changes by hand in production — it changes
   > because Git changed."
2. Open the [`fabric/`](../fabric) folder. Show the item definitions: Variable Library,
   Lakehouse, Notebook, Data Pipeline, Semantic Model, Report.
   > "These are the **source of truth** for our lakehouse, pipeline, model and report —
   > readable, diffable, reviewable."
3. Call out the **Git folder** setting: in Fabric, open **Healthcare-Dev → Workspace
   settings → Git integration**. Show **Directory = `fabric`**.
   > "We deliberately put item definitions under `/fabric`, not the repo root, so the repo
   > stays clean and tooling/workflows sit alongside — not buried in Fabric metadata."

## Act 2 — "Four workspaces, four branches" (2 min)

1. In each workspace open **Source control**. Show it is bound to its branch
   (Feature→`feature/demo`, Dev→`dev`, Test→`test`, Prod→`main`).
2. Open the **HospitalOps** report in **Dev** and **Prod** side by side.
   Show the **Environment** card: *Development* vs *Production*, and the different KPI
   scales (Prod has 20× the data).
   > "Same definitions, different environment — driven by a **Variable Library** value set,
   > not by copy-pasted code."

## Act 3 — Make a change as a developer (3 min)

1. In **Healthcare-Feature**, make a small, visible change — pick one:
   - **Report:** add/rename a card, or change a title to *"Hospital Operations — v2"*.
   - **Variable Library:** bump a value (e.g. `RefreshWindowDays`) in the **Dev** value set.
   - **Notebook:** add a column to `env_banner` (e.g. a `Region` literal).
2. **Source control → Commit** to `feature/demo` with a clear message.
   > "I'm working in my own sandbox workspace. My commit goes to my feature branch — it
   > can't touch Dev, Test, or Prod yet."

## Act 4 — Collaboration via Pull Request (4 min)

1. In GitHub, open a PR **`feature/demo → dev`**.
2. Show the **Files changed** diff — the Fabric change is a readable text diff.
   > "This is the heart of it: a teammate reviews the *actual* change to our model/report
   > before it goes anywhere. Version control + collaboration + an audit trail."
3. (Optional) Add a review comment, then approve. **Merge** the PR.

## Act 5 — Automated promotion to Dev (2 min)

1. Switch to **Actions**. The **Deploy to Dev** workflow is running.
2. Open it and walk the log: *initializeConnection → Update From Git → set value set =
   Dev → run ETL → refresh model.*
   > "No one clicked around in Fabric. The merge triggered an automated, repeatable
   > deployment."
3. Refresh the **Dev** report — your change is live, still showing **Environment:
   Development**.

## Act 6 — Promote through Test to Production (4 min)

1. Open a PR **`dev → test`**, merge. **Deploy to Test** runs → Test report updates,
   **Environment: Test**, 5× data.
2. Open a PR **`test → main`**, merge. **Deploy to Prod** starts and **pauses for
   approval** (GitHub `prod` environment reviewer).
   > "Production has a gate. A human approves; the approval is recorded against the commit."
3. Approve. The workflow completes → **Prod** report updates, **Environment: Production**,
   20× data.

## Close — tie it back (1 min)

| Customer goal | What they just saw |
| --- | --- |
| **Version control** | Every item is text in Git, full history, diffable |
| **Collaboration** | Changes flow through reviewed Pull Requests |
| **Automation** | Merges trigger GitHub Actions that deploy to Fabric |
| **Governance** | Test gate + required approval for production |
| **Consistency** | One definition, environment differences via Variable Libraries |

> "This is how GitHub modernises a data project: the same engineering rigour your app
> teams already use — branches, PRs, CI/CD, approvals — applied to your Fabric lakehouse,
> pipeline, model, and report."

---

### Reset between runs

- Revert the demo change with a follow-up PR, **or** keep a clean `feature/demo` branch and
  re-point the Feature workspace to it.
- Re-run value sets / data anytime: `04-set-active-valueset.sh`, `05-load-data.sh`.
