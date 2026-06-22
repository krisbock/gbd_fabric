# Healthcare Analytics on Microsoft Fabric — Git-based Deployment Demo

> **Demo 1 of 2** — *Streamlining and modernising data projects with GitHub:
> collaboration, version control, and automation.*

This repository demonstrates a **Git-based deployment** model for Microsoft Fabric,
where four Fabric workspaces are each connected to their own Git branch and changes
are **promoted through environments via Pull Requests and GitHub Actions**.

The sample solution is a small **hospital operations** analytics estate:

| Item | Type | Purpose |
| --- | --- | --- |
| `Healthcare` | Lakehouse | Stores the star schema (dims + `fact_encounter`) and the `env_banner` table |
| `HospitalETL` | Notebook | Generates/loads data, **driven by the Variable Library** |
| `HospitalOpsETL` | Data Pipeline | Orchestrates the notebook |
| `HospitalOps` | Semantic Model | Star-schema model over the lakehouse |
| `HospitalOps` | Report | KPIs + an **Environment** banner card |
| `EnvConfig` | Variable Library | Per-environment values (Dev / Test / Prod) |

## The environment topology

```text
 feature/*  ──PR──►  dev  ──PR──►  test  ──PR──►  main (prod)
    │                 │             │               │
    ▼                 ▼             ▼               ▼
 Healthcare-      Healthcare-   Healthcare-     Healthcare-
  Feature           Dev            Test            Prod
 (value set:      (value set:   (value set:     (value set:
   Dev)              Dev)          Test)           Prod)
```

Each workspace is connected to its branch with the **Git folder set to `fabric`**, so
Fabric item definitions live under [`fabric/`](fabric) and never clutter the repo root.

When a PR merges into `dev`, `test`, or `main`, a **GitHub Action**:

1. Calls the Fabric **Update From Git** API to sync the target workspace to the branch.
2. Sets the **active Variable Library value set** for that environment.
3. (Optional) Runs the pipeline and refreshes the semantic model.

The report's **Environment** card then visibly reads *Development*, *Test*, or
*Production* — proving the promotion end-to-end.

## Repository layout

```text
fabric/                     # Fabric item definitions (Git folder = "fabric")
  EnvConfig.VariableLibrary/
  Healthcare.Lakehouse/
  HospitalETL.Notebook/
  HospitalOpsETL.DataPipeline/
  HospitalOps.SemanticModel/
  HospitalOps.Report/
.github/workflows/          # deploy-dev.yml, deploy-test.yml, deploy-prod.yml
scripts/                    # bash setup + binding + data scripts (curl + jq)
data/                       # Healthcare sample data + generator
docs/                       # Prerequisites, setup guide, demo script
```

## Getting started

1. Read [`docs/01-prerequisites.md`](docs/01-prerequisites.md) and complete the one-time tenant / identity setup.
2. Run the scripts in [`docs/02-setup-guide.md`](docs/02-setup-guide.md) to build all four workspaces.
3. Rehearse with [`docs/03-demo-script.md`](docs/03-demo-script.md).

> This is **Demo 1 (Git-based deployment)**. Demo 2 (Fabric **Deployment Pipelines**
> with Git integration) is delivered separately.
