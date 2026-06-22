# 01 — Prerequisites (one-time)

Complete these before running any setup scripts. Most are one-time tenant/identity tasks.

## 1. Tooling on your machine

| Tool | Why | Install |
| --- | --- | --- |
| Bash + curl + jq | Runs the setup scripts | `jq`: <https://jqlang.github.io/jq/> (curl/bash ship with most systems) |
| Git | Branch + PR workflow | <https://git-scm.com> |
| Azure CLI *(optional)* | `FABRIC_AUTH=azcli` fallback to log in as **yourself** instead of a service principal | <https://aka.ms/azcli> |
| Python 3.10+ *(optional)* | Generate sample CSVs | <https://python.org> |

## 2. A Fabric capacity

You need one Fabric (or Premium) capacity the four workspaces can use. Copy its
**capacity ID** (Fabric Admin portal → Capacity settings) into `scripts/config.json`.

> All four demo workspaces can share a single capacity.

## 3. Fabric tenant switches (Admin portal → Tenant settings)

Ask your Fabric admin to enable:

- **Service principals can use Fabric APIs** (scope it to a security group your SP is in).
- **Service principals can use Git integration APIs** *(if present in your tenant)*.
- **Users can create Fabric items**.
- **Users can synchronize workspace items with their Git repositories**.

## 4. A service principal (recommended for automation)

The GitHub Actions and setup scripts authenticate as a **service principal (SP)**:

1. Microsoft Entra admin center → **App registrations** → **New registration**.
2. Note the **Application (client) ID** and **Directory (tenant) ID**.
3. **Certificates & secrets** → **New client secret** → copy the value.
4. Add the SP to the security group allowed to use Fabric APIs (step 3).
5. Add the SP as an **Admin** on each workspace (the setup scripts create the
   workspaces under the SP, so it is owner automatically).

> **No SP available?** You can run the *setup* scripts as yourself with `FABRIC_AUTH=azcli`
> (after `az login`). The **GitHub Actions still require an SP** because they run unattended.

## 5. A GitHub Personal Access Token (PAT) for the Fabric → GitHub connection

Fabric + service principal **cannot** use "Automatic" Git credentials, so we create a
Fabric connection backed by a PAT.

- Fine-grained PAT scoped to **this repository** with **Contents: Read and write**
  (classic PATs with `repo` scope also work).
- Put it in `scripts/config.json` → `gitHub.personalAccessToken`.

## 6. GitHub repository secrets (for the Actions)

In **GitHub → Settings → Secrets and variables → Actions**, add:

| Secret | Value |
| --- | --- |
| `FABRIC_CLIENT_ID` | SP application (client) ID |
| `FABRIC_CLIENT_SECRET` | SP client secret |
| `FABRIC_TENANT_ID` | Directory (tenant) ID |
| `DEV_WORKSPACE_ID` | Healthcare-Dev workspace ID (printed by `01-create-workspaces.sh`) |
| `TEST_WORKSPACE_ID` | Healthcare-Test workspace ID |
| `PROD_WORKSPACE_ID` | Healthcare-Prod workspace ID |

Also create three **Environments** (`dev`, `test`, `prod`) and add a **required reviewer**
to `prod` so production promotion waits for an approval.

➡️ Next: [`02-setup-guide.md`](02-setup-guide.md)
