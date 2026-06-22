# 02 — Setup guide

Build the full four-environment estate. Do this **before** the demo (it is not part of
the live demo). Allow time for items to provision after the first Git sync.

> Assumes you completed [`01-prerequisites.md`](01-prerequisites.md).

## 0. Push this repo to GitHub and create the branches

```bash
git init
git add .
git commit -m "Healthcare Fabric Git-deployment demo"
git branch -M main
git remote add origin https://github.com/krisbock/gbd_fabric.git
git push -u origin main

# Long-lived environment branches (each maps to a workspace)
git push origin main:dev
git push origin main:test
git push origin main:feature/demo
```

You now have four branches: `feature/demo`, `dev`, `test`, `main`.

## 1. Fill in the config

```bash
cp scripts/config.sample.json scripts/config.json
```

Edit `scripts/config.json` with your `tenantId`, `clientId`, `clientSecret`,
`capacityId`, and the `gitHub` owner / repo / PAT. `config.json` is git-ignored.

## 2. Create workspaces

```bash
./scripts/01-create-workspaces.sh                # or: FABRIC_AUTH=azcli ./scripts/01-create-workspaces.sh
```

Copy the four workspace IDs it prints into your GitHub secrets
(`DEV_WORKSPACE_ID`, `TEST_WORKSPACE_ID`, `PROD_WORKSPACE_ID`).

## 3. Create the Fabric → GitHub connection (PAT)

```bash
./scripts/02-create-git-connection.sh
```

## 4. Connect each workspace to its branch and sync

```bash
./scripts/03-connect-git.sh
```

This sets the **Git folder to `fabric`** on every workspace, so item definitions live
under `/fabric` and the repo root stays clean. After this, every workspace contains the
Variable Library, Lakehouse, Notebook, Pipeline, Semantic Model, and Report.

> Wait ~1 minute for the Lakehouse **SQL analytics endpoint** to provision before step 6.

## 5. Set each environment's active value set

```bash
./scripts/04-set-active-valueset.sh
```

Feature/Dev → `Dev`, Test → `Test`, Prod → `Prod`.

## 6. One-time per-workspace bindings

Two items carry physical, environment-specific references. These are the *only* manual
touch-points — paid once here, never during the daily demo. (They are also a great
talking point about **why** Fabric CI/CD tooling and Variable Libraries exist.)

```bash
./scripts/bind-pipeline.sh                # pipeline activity -> local notebook
./scripts/bind-semanticmodel.sh           # model SqlEndpoint -> local lakehouse + refresh
```

## 7. Populate data

```bash
./scripts/05-load-data.sh
```

Each workspace runs `HospitalETL`, which reads its own value set and writes its own
`env_banner` row (Dev 1×, Test 5×, Prod 20×).

## 8. Finish the report visuals once (recommended Fabric authoring step)

The repo ships a valid, openable report shell bound to the `HospitalOps` model. Build the
final visuals **once** in the **Healthcare-Feature** workspace, then commit — Fabric writes
correct definitions that flow to every environment via Git:

1. Open **Healthcare-Feature → HospitalOps** report → **Edit**.
2. Add a **Card** visual → field **EnvBanner[EnvironmentName]** → title it *Environment*.
3. Add **Card** visuals for the measures **Total Encounters**, **Avg Length of Stay**,
   **Readmission Rate %**.
4. Optionally add a column chart of **Total Encounters by DimDepartment[DepartmentName]**.
5. **Save**, then **Source control → Commit** to `feature/demo`.
6. Open a PR `feature/demo → dev` and merge — the **Deploy to Dev** Action carries the
   report (and value set) into Healthcare-Dev. Repeat the promotion to test/main once to
   seed all environments. From now on the report shows **Environment: Development / Test /
   Production** automatically per workspace.

## 9. Verify

For each workspace, open the **HospitalOps** report (or query `SELECT * FROM env_banner`
on the Lakehouse SQL endpoint). The Environment card should read Development, Test, and
Production respectively. You are ready to rehearse [`03-demo-script.md`](03-demo-script.md).

### Troubleshooting

| Symptom | Fix |
| --- | --- |
| `Service principals can't use Fabric APIs` | Enable the tenant switch and add the SP to the allowed group. |
| Git connect fails with credential error | GitHub+SP needs the **ConfiguredConnection** (step 3), not Automatic. Re-run `02`. |
| Model has no data | SQL endpoint may not have been ready; re-run `bind-semanticmodel.sh`, then `05-load-data.sh`. |
| Report visuals empty | Complete step 8 in the Feature workspace and promote. |
| Value set didn't change | Confirm the workspace has the `EnvConfig` library, then re-run `04`. |
