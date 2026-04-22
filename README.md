# Neutron Data Platform – RBAC & Access Model (Target State)

**Status:** Draft for review  
**Date:** April 2026  
**Platform:** `neutron-data-platform`  
**Scope:** Target-state access model for onboarding new environments

> **How to use this document:** This document explains how access is intended to work for a newly onboarded NDP environment. It covers the main personas, how access is requested, how groups are structured, and how managed identities are permissioned. Where the current platform behaves differently, this document describes the model we want to move toward.

---

## Table of Contents

1. [Foundational Principles](#1-foundational-principles)
2. [AC1 - Personas and Required Permissions](#2-ac1---personas-and-required-permissions)
3. [AC2 - Access Request Workflows](#3-ac2---access-request-workflows)
4. [AC3 - Group Structure, Naming, and Ownership](#4-ac3---group-structure-naming-and-ownership)
5. [AC4 - UAMI Permissions Model](#5-ac4---uami-permissions-model)
6. [AC5 - Persona-to-Group Mapping](#6-ac5---persona-to-group-mapping)
7. [PIM - Privileged Identity Management](#7-pim---privileged-identity-management)
8. [Resolved Decisions](#8-resolved-decisions)
9. [Review Items / Stubs](#9-review-items--stubs)

---

## 1. Foundational Principles

This access model is built around a small number of design decisions. The aim is to make the platform easier to operate, easier to audit, and easier to scale as more applications are onboarded.

### 1.1 Key Design Decisions

- **Groups are managed outside Terraform.** Terraform looks up existing groups and binds permissions to them. If a required group does not exist in Entra ID at apply time, the deployment fails. The CSV in `neutron-data-platform` is the reconciliation mechanism used to keep this process aligned.
- **App-level groups are the standard.** The platform is moving away from stamp-level grouping. Each application has its own admin, developer, and reader group per environment.
- **No SCIM connector is used.** Databricks group membership is expected to sync through Entra ID’s native integration rather than the Databricks SCIM connector.
- **The governance workspace is out of scope** for this document.
- **PIM applies to platform-owned privileged access.** App teams are not expected to use PIM for normal day-to-day access. See [Section 7](#7-pim---privileged-identity-management).

### 1.2 Design Intent

At a high level, the model is designed to separate:
- **business approval** from **technical enforcement**
- **human access** from **automation access**
- **application-scoped access** from **platform-wide privileged access**

---

## 2. AC1 - Personas and Required Permissions

### 2.1 Persona Overview


There are two broad sets of personas in this model:

- **App team personas**, used by teams who build, run, or consume data products
- **Platform personas**, used by the internal FIS platform engineering team

App-team personas:
- Admin
- Developer
- Reader

Platform personas (internal-team personas):
- Platform Engineer: Monitor and support the platform, with standing read access and PIM-eligible break-glass support.
- SDC Engineer: Manage SDC infrastructure within the SDC subscription boundary (permissions TBD).
- Snowflake Engineer: Manage Snowflake-related infrastructure and the Snowflake catalog layer (permissions TBD).
- Metadata Reader: Group for humans and non-humans needing metadata-level (BROWSE) privileges across catalogs, no data read/write.

App-team access is expected to be stable. Platform-level privileged access is expected to be more tightly controlled through PIM.

App-team access is expected to be stable. Platform-level privileged access is expected to be more tightly controlled through PIM.

```text
┌─────────────────────────────────────────────────────────┐
│                    ndp Platform                         │
│                                                         │
│  App Team Personas          Platform Personas           │
│  ──────────────────         ─────────────────────────── │
│  • Admin                    • Platform Engineer         │
│  • Developer                • Platform Admin (PIM)      │
│  • Reader                   • SDC Engineer              │
│                             • Snowflake Engineer        │
│                             • Metadata Reader           │
└─────────────────────────────────────────────────────────┘
```

---

### 2.2 App Team Personas

These personas are assigned per application and per environment. In practice, access is managed through FIS MyAccess, with membership flowing into Entra ID groups and then into Databricks.

---

#### Admin

**Who this is for:**  
Application leads, data owners, and engineers who are responsible for the full lifecycle of a data application.

**Intended access level:**  
Admins are expected to be able to build, operate, and manage their application end to end within the application boundary. That includes reading and writing data, creating schemas and other objects, managing application secrets, and tagging data assets. They cannot grant themselves broader platform privileges outside that scope.


**Azure Role Assignments**

| Scope | Role |
|---|---|
| Application Resource Group | Reader |
| Application Monitoring Resource Group | Reader |
| Storage Resource Group | Reader |
| Application Key Vault | Key Vault Secrets Officer |
| Databricks Engineering Workspace (ARM resource) | Reader |
| Subscription Budget | Cost Management Reader |


**Databricks Unity Catalog Grants**  
*(applied to Bronze, Silver, Gold, and Snowflake catalogs for the application)*

| Category | Privileges |
|---|---|
| Navigation | `USE_CATALOG`, `USE_SCHEMA` |
| Metadata | `BROWSE`, `APPLY_TAG` |
| Read | `SELECT`, `EXECUTE`, `READ_VOLUME` |
| Write | `MODIFY`, `WRITE_VOLUME`, `REFRESH` |
| Create | `CREATE_SCHEMA`, `CREATE_TABLE`, `CREATE_VOLUME`, `CREATE_FUNCTION`, `CREATE_MATERIALIZED_VIEW`, `CREATE_MODEL` |


**Databricks External Location Grants**  
*(Bronze, Silver, Gold, and Snowflake external locations for the application)*

| Category | Privileges |
|---|---|
| Metadata | `BROWSE` |
| Read | `READ_FILES` |
| Write | `WRITE_FILES` |
| Create | `CREATE_EXTERNAL_TABLE`, `CREATE_EXTERNAL_VOLUME`, `CREATE_FOREIGN_SECURABLE`, `CREATE_MANAGED_STORAGE` |


**Databricks Storage Credential:** `READ_FILES`, `WRITE_FILES`, `CREATE_EXTERNAL_LOCATION`, `CREATE_EXTERNAL_TABLE`  
**Databricks Service Credential:** `ACCESS`, `CREATE_CONNECTION`

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Application Directory (Repos) | `CAN_MANAGE` |
| Cluster Policies | `CAN_USE` |
| SQL Endpoints | `CAN_MONITOR` |
| Secret Scope - platform-default | `READ` |
| Secret Scope - app-specific | `READ` |
| Budget Policy | `roles/budgetPolicy.user` |

---

#### Developer

**Who this is for:**  
Data engineers, ML engineers, and analysts who build and maintain pipelines, models, and related application assets.

**Intended access level:**  
Developers should be able to do day-to-day engineering work without owning application storage or managing secrets. They can read and write data, use compute, and work with the same Databricks surface as Admin in the current target state, but they do not get storage ownership or secret-management rights in Azure.

**How Developer differs from Admin**

| Aspect | Admin | Developer |
|---|---|---|
| Key Vault | Secrets **Officer** (create/rotate) | Secrets **User** (read-only) |
| Databricks UC privileges | Full | Full *(currently identical to Admin)* |
| Cluster Policy | `CAN_USE` | *Not granted* |
| SQL Endpoint | `CAN_MONITOR` | `CAN_MONITOR` |

> **Note:** Developer is optional. If no developer group is specified for an application, no developer bindings are created.


**Azure Role Assignments** *(differences from Admin only)*

| Scope | Role |
|---|---|
| Application Key Vault | Key Vault Secrets **User** *(not Officer)* |

All other Azure assignments are identical to Admin.


**Databricks Unity Catalog, External Location, Storage Credential, and Service Credential Grants:**  
Identical to Admin in the current target state (across Bronze, Silver, Gold, and Snowflake catalogs).

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Application Directory | `CAN_MANAGE` |
| Cluster Policies | *Not granted* |
| SQL Endpoints | `CAN_MONITOR` |
| Secret Scopes | `READ` |
| Budget Policy | `roles/budgetPolicy.user` |

---

#### Reader

**Who this is for:**  
Business users, analysts, and other consumers who need read-only access to approved datasets.

**Intended access level:**  
Readers are intended to have read-only access for consumption scenarios. They should be able to discover and query the data they are meant to use, but they should not be able to modify data, manage secrets, or administer compute. Any broader access should be explicitly justified and documented per application.

> **Note:** Reader is optional. If no reader group is specified for an application, no reader bindings are created.


**Azure Role Assignments**

| Scope | Role |
|---|---|
| Application & Monitoring Resource Groups | Reader |
| Storage Resource Group | Reader |
| Key Vault | *No access* |
| Databricks Engineering Workspace (ARM) | Reader |
| Subscription Budget | Cost Management Reader |


**Databricks Unity Catalog Grants**  
*(restricted to approved read-only Bronze, Silver, Gold, and Snowflake catalogs/schemas for the application)*

| Privileges |
|---|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE`, `SELECT`, `EXECUTE`, `READ_VOLUME` |

No write, create, or tag privileges.


**External Locations:** `BROWSE`, `READ_FILES` only  
**Storage Credential:** `READ_FILES` only  
**Service Credential:** `ACCESS` only

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Application Directory | `CAN_READ` |
| Cluster Policies | *Not granted* |
| SQL Endpoints | `CAN_USE` |
| Secret Scopes | *Not granted* |
| Budget Policy | `roles/budgetPolicy.user` |

---


### 2.3 Platform Personas (Internal-Team Personas)

These personas apply to the internal FIS platform engineering team and specialist teams, rather than to individual applications. Most privileged actions should happen through automation, and human access should be reserved for time-bound operational needs.

---

#### Platform Engineer

**Who this is for:**  
Members of the NDP platform team responsible for deploying and maintaining the `neutron-data-platform` infrastructure.

**Azure Role Assignments**

| Scope | Role |
|---|---|
| Platform Resource Groups | Reader |
| Platform Key Vaults | Key Vault Reader |
| Databricks Account | Account Admin (PIM-eligible) |

**Databricks Unity Catalog Grants**

| Privileges |
|---|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE` |
| `SELECT`, `EXECUTE` |
| `APPLY_TAG` |
| `MODIFY`, `REFRESH` |
| `CREATE_SCHEMA`, `CREATE_TABLE`, `CREATE_FUNCTION` |

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Workspace membership (`USER`) | ✔ |
| Application Directory | `CAN_MANAGE` |
| Cluster Policies | `CAN_USE` |
| SQL Endpoints | `CAN_MONITOR` |
| Secret Scopes | `READ` |

---

#### Platform Admin *(PIM-eligible)*

**Who this is for:**  
Senior platform engineers who may need elevated access for incident response, configuration changes, or break-glass scenarios.

**Access pattern:**  
This access is intended to be just-in-time, time-bound, and auditable. Elevation requires justification and, where configured, approval. Standing privileged access should be avoided by default.

**Proposed PIM-eligible permissions**

| Scope | Role | Activation Required |
|---|---|---|
| Subscription | Contributor | Yes - PIM |
| Subscription | User Access Administrator | Yes - PIM |
| Databricks Account | Account Admin | Yes - PIM |
| Key Vaults (platform) | Key Vault Crypto Officer | Yes - PIM |
| Key Vaults (platform) | Key Vault Secrets Officer | Yes - PIM |

---

#### SDC Engineer

**Who this is for:**  
Engineers responsible for managing SDC infrastructure within the SDC subscription boundary.

**Azure Role Assignments**

| Scope | Role |
|---|---|
| SDC Resource Groups | Contributor |
| SDC Key Vaults | Key Vault Secrets Officer |
| Databricks Account | User (scoped to SDC resources) |

**Databricks Unity Catalog Grants**

| Privileges |
|---|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE` |
| `SELECT`, `EXECUTE` |
| `APPLY_TAG` |
| `MODIFY`, `REFRESH` |
| `CREATE_SCHEMA`, `CREATE_TABLE` |

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Workspace membership (`USER`) | ✔ |
| Application Directory | `CAN_MANAGE` |
| Cluster Policies | `CAN_USE` |
| SQL Endpoints | `CAN_MONITOR` |
| Secret Scopes | `READ` |

---

#### Snowflake Engineer

**Who this is for:**  
Engineers responsible for managing Snowflake-related infrastructure and the Snowflake catalog layer.

**Azure Role Assignments**

| Scope | Role |
|---|---|
| Snowflake Resource Groups | Contributor |
| Snowflake Key Vaults | Key Vault Secrets Officer |
| Databricks Account | User (scoped to Snowflake resources) |

**Databricks Unity Catalog Grants**

| Privileges |
|---|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE` |
| `SELECT`, `EXECUTE` |
| `APPLY_TAG` |
| `MODIFY`, `REFRESH` |
| `CREATE_SCHEMA`, `CREATE_TABLE` |

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Workspace membership (`USER`) | ✔ |
| Application Directory | `CAN_MANAGE` |
| Cluster Policies | `CAN_USE` |
| SQL Endpoints | `CAN_MONITOR` |
| Secret Scopes | `READ` |

---

#### Metadata Reader

**Who this is for:**  
Humans and non-human identities that require metadata-level (BROWSE) privileges across catalogs. No data read, no write.

**Azure Role Assignments**

| Scope | Role |
|---|---|
| Platform Resource Groups | Reader |
| Databricks Account | User (metadata only) |

**Databricks Unity Catalog Grants**

| Privileges |
|---|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE` |

**Databricks Workspace Object Permissions**

| Object | Permission |
|---|---|
| Workspace membership (`USER`) | ✔ |
| Application Directory | `CAN_READ` |
| Cluster Policies | - |
| SQL Endpoints | - |
| Secret Scopes | - |

---

## 3. AC2 - Access Request Workflows

The access-request model is designed to separate business approval from technical enforcement. App-team access is requested through MyAccess. Platform-level privileged access is handled through PIM because it carries wider operational impact.

### 3.1 User Access - FIS MyAccess

All normal human access to the NDP platform is requested and managed through **FIS MyAccess**.

**Workflow for requesting app-team access**

```text
1. Requester    → Logs into FIS MyAccess and raises an access request
                  for the target application and role tier
                  (e.g. "ndp - <App Name> - Developer - <Env>")

2. MyAccess     → Routes the request to the application data owner
                  for approval

3. Data Owner   → Approves or rejects the request in MyAccess

4. MyAccess     → On approval, adds the user to the appropriate
                  Entra ID security group via the Active Roles integration

5. Entra Sync   → Entra ID native sync propagates the group membership
                  to the Databricks workspace automatically
                  (no SCIM, no manual step)

6. User         → Has access within the next sync cycle
```

**Workflow for requesting platform-team privileged access (PIM)**

```text
1. Engineer     → Requests PIM activation in Azure Portal
                  with justification and duration

2. PIM          → Routes for approval (if approval is required
                  for that role)

3. Approver     → Reviews and approves time-bound elevation

4. PIM          → Activates the role assignment for the
                  specified period

5. Engineer     → Performs the required privileged action

6. PIM          → Role assignment expires automatically
                  at the end of the activation window
```

### 3.2 New Application Onboarding

When a new data application is onboarded onto the platform, the following steps must happen **before** Terraform can deploy the application:

| Step | Actor | Action |
|---|---|---|
| 1 | App team / Platform team | Define the application name, environment, and required role groups |
| 2 | Platform team | Run the PowerShell script in `active-roles-ad-automation` to create the Entra ID groups (admin, developer, reader) per environment |
| 3 | Platform team | Commit the resulting CSV output to the `neutron-data-platform` repo as the authoritative group registry |
| 4 | App team | Submit access requests via FIS MyAccess to populate group membership |
| 5 | Platform team | Add the application configuration (YAML) to `neutron-data-platform` and raise a PR |
| 6 | CI/CD pipeline | On merge, Terraform reads group names via data lookups and creates the Azure and Databricks permission bindings |

> **Critical prerequisite:** The Entra ID groups must exist before Terraform apply runs. If a group does not exist in Entra ID, the `data.azuread_group` lookup fails and the deployment errors. The CSV registry exists to make that dependency visible and trackable.

### 3.3 Access Removal

| Trigger | Action |
|---|---|
| User offboarding | Entra ID group membership is removed via MyAccess / HR process; Entra sync then removes access from Databricks |
| Role change | Old group membership is removed and new access is requested via MyAccess |
| Application decommission | Platform team removes the application YAML; Terraform removes permission bindings; the PowerShell process removes the Entra ID groups |

---

## 4. AC3 - Group Structure, Naming, and Ownership

Group design is one of the main control points in this model. The platform depends on consistent naming, clear ownership, and a reliable way to reconcile what should exist with what actually exists in Entra ID and Databricks.

### 4.1 Group Creation and Lifecycle

Entra ID groups are **not** created by Terraform. They are created and managed externally.

- **Creation tool:** PowerShell script in `active-roles-ad-automation`, registered in the corporate Entra ID tenant
- **Authoritative registry:** CSV output from the script, committed to the `neutron-data-platform` repo
- **Terraform interaction:** `data.azuread_group` lookup for pre-existing groups; Terraform may bind permissions to those groups and, for certain platform-owned groups, may automate managed identity or service principal membership where explicitly required

### 4.2 App-Team Group Naming Convention

The platform uses **app-level groups** rather than stamp-level groups. Each application has its own set of groups per environment. The current proposed naming convention is:

```text
ndp-{lob}-{project}-{env}-app{NNN}-{tier}
```

| Segment | Description | Example |
|---|---|---|
| `lob` | Line of business (from application tags) | `banking` |
| `project` | Project / product name | `ethos` |
| `env` | Environment (`dev`, `tst`, `prd`) | `dev` |
| `NNN` | Zero-padded 3-digit application sequence number | `001` |
| `tier` | Role tier (`admin`, `developer`, `reader`) | `admin` |

**Example – application 001, dev environment**

| Tier | Group Name |
|---|---|
| Admin | `ndp-banking-ethos-dev-app001-admin` |
| Developer | `ndp-banking-ethos-dev-app001-developer` |
| Reader | `ndp-banking-ethos-dev-app001-reader` |

> **Note:** The final naming convention is still open for confirmation.

### 4.3 Platform / System Groups

These groups support platform infrastructure operations rather than app-team access. They are managed by the platform team.

| Group | Purpose | Who Is Added |
|---|---|---|
| `ndp-id-management-{env}-directory-reader-azure` | Grants platform UAMIs the Entra ID Directory Reader capability required for Terraform to resolve group names | Platform Write UAMI, Platform Read UAMI |
| `ndp-corporate-dns-admin-azure` | Grants platform UAMIs permission to register private endpoint DNS A records | Platform Write UAMI, Platform Read UAMI |

### 4.4 Databricks Account-Level Groups

| Group | Purpose | Member |
|---|---|---|
| `account-admin` *(Databricks built-in)* | Full Databricks account administration | Platform Write UAMI (registered as SP) |
| `billing-admin` *(Databricks built-in)* | Databricks cost and usage data | Platform Write UAMI (registered as SP) |

### 4.5 Additional SQL Endpoint Access Groups

Beyond the three-tier app groups, individual SQL endpoints can be configured to allow additional Entra ID groups or service principals `CAN_USE` access. This is declared in application configuration and is intended for controlled cross-application or cross-team data-sharing scenarios.

### 4.6 Group Governance Summary

| Group Type | Created By | Managed By | Terraform Action |
|---|---|---|---|
| App team groups (admin/dev/reader) | PowerShell script (`active-roles-ad-automation`) | App data owner via MyAccess | `data` lookup and permission binding only |
| Platform system groups (directory-reader, DNS) | PowerShell script | Platform team | `data` lookup, permission binding, and platform identity membership automation where required |
| Databricks account groups | Databricks platform | Platform team | `data` lookup and SP membership automation where required |
| PIM-eligible platform groups | Platform team / IAM team | IAM team | Out of Terraform scope |

---

## 5. AC4 - UAMI Permissions Model

Managed identities are the backbone of platform automation in this design. They allow CI/CD and runtime workloads to perform the actions they need without long-lived client secrets or certificates.

All CI/CD and runtime identities are **User-Assigned Managed Identities (UAMIs)** created and managed by Terraform in `neutron-data-platform`. GitHub Actions authentication uses **OIDC federated credentials**.

### 5.1 UAMI Summary

| UAMI | OIDC | Purpose |
|---|---|---|
| `{prefix}-uai-w` (Write) | Yes - GitHub Actions environment | Terraform apply - creates and modifies Azure and Databricks infrastructure |
| `{prefix}-uai-r` (Read) | Yes - GitHub Actions environment | Terraform plan - read-only, used for pull request validation |
| `{prefix}-uai-app` (App) | No | Runtime identity for Container Apps / AKS; pulls images and reads secrets at runtime |
| `{prefix}-uai-cmk` (CMK) | No | Customer-managed key encryption identity for ADLS and Databricks managed storage |
| App-scoped UAI | Configurable | Per-application automation identity with app-scoped admin-equivalent permissions |

**OIDC subject claim pattern**

```text
repo:EnterpriseData-and-AI/{repository_name}:environment:{environment}
```

### 5.2 Platform Write UAMI (`uai-w`) - Full Permission Set

| Scope | Role | Justification |
|---|---|---|
| Subscription | Contributor | Create and manage Azure resources |
| Subscription | User Access Administrator | Create RBAC role assignments for groups and app identities |
| Terraform state containers (local, cmk, stamp) | Storage Blob Data Contributor | Read and write Terraform state files |
| Platform Key Vault | Key Vault Crypto Officer | Create and rotate encryption keys |
| Platform Key Vault | Key Vault Secrets Officer | Create and rotate secrets |
| Log Analytics Workspace | Log Analytics Contributor | Create diagnostic settings and configure log forwarding |
| Entra ID - `directory-reader` group | *(group member)* | Resolve Entra ID objects by display name during apply |
| DNS - platform DNS admin group | *(group member)* | Register private endpoint DNS A records |
| Databricks Account | `account-admin` group | Manage Unity Catalog, workspaces, and provisioning |
| Databricks Account | `billing-admin` group | Access cost and usage reporting |

### 5.3 Platform Read UAMI (`uai-r`) - Full Permission Set

| Scope | Role | Justification |
|---|---|---|
| Subscription | Reader | Read Azure resource metadata for Terraform plan |
| Terraform state containers | Storage Blob Data Contributor | Read state and manage lock files during plan |
| Platform Key Vault | Key Vault Crypto Service Encryption User | Read key metadata for validation |
| Platform Key Vault | Key Vault Reader | Read Key Vault configuration |
| Platform Key Vault | Key Vault Secrets User | Read secret values in Terraform data sources |
| Log Analytics Workspace | Log Analytics Contributor | Validate diagnostic settings in plan |
| Entra ID - `directory-reader` group | *(group member)* | Resolve Entra ID objects during plan |
| DNS - platform DNS admin group | *(group member)* | Validate DNS dependencies in plan |

### 5.4 App Runtime UAMI (`uai-app`)

| Scope | Role | Justification |
|---|---|---|
| Application Key Vault | Key Vault Secrets User | Runtime application reads connection strings and API keys |
| Container Registry (ACR) | AcrPull | Pull container images for AKS / Container App workloads |

### 5.5 CMK UAMI (`uai-cmk`)

| Scope | Role | Justification |
|---|---|---|
| CMK Key Vault | Key Vault Crypto Officer | Manage key operations required for encryption setup |
| CMK Key Vault | Key Vault Crypto Service Encryption User | Use the key for encryption/decryption operations at runtime |

### 5.6 App-Scoped UAI (Per Application)

One UAI is created per application. It is registered as a Databricks service principal and acts as the application’s own automation identity. It holds admin-equivalent permissions on app-scoped resources.


**Azure permissions (mirrors Admin group):**
- `Key Vault Secrets Officer` on the application Key Vault
- `Reader` on app resource groups
- `Cognitive Services Usages Reader` at subscription scope

**Databricks permissions:**  
Full admin-equivalent Unity Catalog grants on all app-scoped catalogs, external locations, storage credentials, and service credentials. `CAN_MANAGE` on the application directory, `CAN_USE` on cluster policies, and `CAN_MONITOR` on SQL endpoints.

### 5.7 Global-Tier UAMI Permissions

A global layer manages shared infrastructure with management-group-wide scope.

| UAMI | Scope | Role |
|---|---|---|
| Global Write | Management Group | Contributor + User Access Administrator |
| Global Write | Subscription | Contributor + User Access Administrator |
| Global Read | Management Group | Reader + Resource Provider Contributor |
| Global Read | Subscription | Reader |
| Both | Global Terraform state storage | Storage Blob Data Contributor / Owner |

---

## 6. AC5 - Persona-to-Group Mapping

This section shows how the design becomes operational: application YAML defines the expected groups, Terraform resolves them, and the platform binds the right Azure and Databricks permissions to them. User membership itself remains outside Terraform.

### 6.1 How Groups Flow into Permissions

```text
Step 1 - Application Configuration (neutron-data-platform)
  Application YAML declares:
    identity.admin_group_name     → "ndp-banking-ethos-dev-app001-admin"
    identity.developer_group_name → "ndp-banking-ethos-dev-app001-developer"
    identity.reader_group_name    → "ndp-banking-ethos-dev-app001-reader"

Step 2 - Terraform Data Lookup
  data.azuread_group.group_admin     (display_name lookup - fails if group absent)
  data.azuread_group.group_developer (conditional - skipped if name is empty)
  data.azuread_group.group_reader    (conditional - skipped if name is empty)
  data.databricks_group.*            (resolved at Databricks account level)

Step 3 - Permission Binding
  azurerm_role_assignment          → uses resolved group object_id
  databricks_permission_assignment → uses resolved Databricks group ID
  databricks_grant                 → uses resolved group display_name

Step 4 - Membership Management (outside Terraform for users)
  Users → FIS MyAccess → Entra ID group → Entra native sync → Databricks workspace
```

### 6.2 Master Persona-to-Group Mapping

| Persona | YAML Field | Example Group Name (dev) |
|---|---|---|
| Admin | `identity.admin_group_name` | `ndp-banking-ethos-dev-app001-admin` |
| Developer | `identity.developer_group_name` | `ndp-banking-ethos-dev-app001-developer` |
| Reader | `identity.reader_group_name` | `ndp-banking-ethos-dev-app001-reader` |
| Optional App SPN | `identity.service_principal_name` | *(defined per app if required)* |


### 6.3 Azure RBAC Summary Matrix

| Role / Resource | Admin | Developer | Reader | App UAI |
|---|:---:|:---:|:---:|:---:|
| Reader - Resource Groups | ✔ | ✔ | ✔ | ✔ |
| Key Vault Secrets **Officer** | ✔ | - | - | ✔ |
| Key Vault Secrets **User** | - | ✔ | - | - |
| Databricks Workspace (ARM) Reader | ✔ | ✔ | ✔ | ✔ |
| Cost Management Reader | ✔ | ✔ | ✔ | - |


### 6.4 Databricks Unity Catalog Summary Matrix

| Privilege | Admin | Developer | Reader | App UAI |
|---|:---:|:---:|:---:|:---:|
| `USE_CATALOG`, `USE_SCHEMA`, `BROWSE` | ✔ | ✔ | ✔ | ✔ |
| `SELECT`, `EXECUTE`, `READ_VOLUME` | ✔ | ✔ | ✔ | ✔ |
| `APPLY_TAG` | ✔ | ✔ | - | ✔ |
| `MODIFY`, `WRITE_VOLUME`, `REFRESH` | ✔ | ✔ | - | ✔ |
| `CREATE_*` (schema, table, volume, etc.) | ✔ | ✔ | - | ✔ |
| External Location `WRITE_FILES` + `CREATE_*` | ✔ | ✔ | - | ✔ |
| Storage Credential `WRITE_FILES` + `CREATE_*` | ✔ | ✔ | - | ✔ |
| Service Credential `ACCESS`, `CREATE_CONNECTION` | ✔ | ✔ | - | ✔ |

### 6.5 Databricks Workspace Object Summary Matrix

| Object | Admin | Developer | Reader | App UAI |
|---|:---:|:---:|:---:|:---:|
| Workspace membership (`USER`) | ✔ | ✔ | ✔ | ✔ |
| Application Directory | `CAN_MANAGE` | `CAN_MANAGE` | `CAN_READ` | `CAN_MANAGE` |
| Cluster Policies | `CAN_USE` | - | - | `CAN_USE` |
| SQL Endpoints | `CAN_MONITOR` | `CAN_MONITOR` | `CAN_USE` | `CAN_MONITOR` |
| Secret Scopes | `READ` | `READ` | - | `READ` |
| Budget Policy | ✔ | ✔ | ✔ | ✔ |

### 6.6 Data Provider Mapping

Applications can receive data from external source systems. These are declared in the application configuration and use a separate group or service principal per provider key.

| Principal Type | Privileges on Provider Catalog & External Location |
|---|---|
| Data Provider Service Principal | Full write/create set (admin-equivalent, scoped to provider catalog only) |
| Data Provider Group | Full write/create set (admin-equivalent, scoped to provider catalog only) |

These principals are resolved via Databricks account-level lookups. They do not receive Azure RBAC assignments through this model.

---

## 7. PIM - Privileged Identity Management

PIM exists to reduce standing privileged access for the platform team. The goal is not to slow down normal application work; it is to make sure that high-impact actions at subscription, account, or encryption-key level happen only when genuinely needed and can be audited properly.

### 7.1 Rationale

PIM should be considered for access that grants **highly privileged control for internal platform teams**. App-team groups (Admin, Developer, Reader) are **not** in scope for PIM in the current design.

PIM applies where:
- the role grants subscription-level Contributor or higher
- the role grants Databricks account-admin privileges
- the role grants the ability to modify RBAC assignments (`User Access Administrator`)
- the role grants key-management capability such as `Key Vault Crypto Officer`

### 7.2 Proposed PIM-Eligible Roles

| Role / Group | Scope | PIM Type | Proposed Approval |
|---|---|---|---|
| Contributor | Subscription | Eligible (JIT) | Self-approve with justification |
| User Access Administrator | Subscription | Eligible (JIT) | Manager approval |
| Account Admin | Databricks Account | Eligible (JIT) | Manager approval |
| Key Vault Crypto Officer | Platform Key Vaults | Eligible (JIT) | Self-approve with justification |
| Key Vault Secrets Officer | Platform Key Vaults | Eligible (JIT) | Self-approve with justification |

> **Note:** The exact PIM configuration (activation duration, approval chain, MFA requirements, and audit expectations) still needs alignment with the FIS IAM team.

### 7.3 What PIM Does Not Cover

- App team Admin, Developer, and Reader groups
- Platform Read UAMI (`uai-r`) - CI/CD identity, not human-operated
- Platform Write UAMI (`uai-w`) - CI/CD identity, not human-operated
- App-scoped UAIs - automated identities bound to specific application contexts

---

## 8. Resolved Decisions

The following questions were raised during drafting and have been resolved.

| # | Question | Resolution |
|---|---|---|
| 1 | **Group naming convention** | Confirmed: `ndp-{lob}-{project}-{env}-app{NNN}-{tier}` is the target pattern. This aligns with the per-app model described in the [Identity & Access LLD](../design/lld/02-identity-access.md). We are moving away from stamp-level grouping. The `appNNN` segment provides a stable identifier; friendly names are carried as metadata tags rather than encoded into the group name. |
| 2 | **Persona tiers** | Admin / Developer / Reader are confirmed as the **app-team** tiers — these describe the rights end users are given within their application boundary. Separately, the platform requires **internal-team personas** not yet fully defined in this document (see [Section 9 – Review Items](#9-review-items--stubs)). |
| 3 | **Developer scope** | Admin and Developer grant different levels of permission across an app team's resources (see the Azure RBAC differences in Section 2.2). In Databricks UC, the privilege sets are functionally similar to how they work on the existing platform today. No further separation is planned at this time. |
| 4 | **Entra native sync behaviour** | Confirmed: the platform will use automatic Entra ID identity syncing to Databricks. SCIM is no longer used. Propagation delay is accepted as the trade-off for operational simplicity. |
| 5 | **PIM approval chains** | Break-glass / elevated roles are **self-activated** via PIM — PIM is used for audit trail, not as a gating approval mechanism. Databricks Account Admin is **directly granted** to a small number of named individuals rather than managed through PIM activation. |
| 6 | **Break-glass access** | Break-glass is delivered through PIM self-activation. There is no separate break-glass account. Platform Engineers have PIM eligibility for a "Break Glass Support" role that can be self-activated with justification. See [Section 9.4](#94-break-glass--pim-model). |
| 7 | **Developer and Reader optionality** | All three tiers (Admin, Developer, Reader) should be defined for every application by default. |
| 8 | **Entra sync scope** | Entra automatic identity sync operates at the Databricks **account level**. Workspace-level group membership is then managed via Terraform. No manual workspace-level sync configuration is required. |
| 9 | **Reader scope** | The published/internal distinction no longer applies. The storage architecture has moved to a **Bronze / Silver / Gold / Snowflake** medallion model (see [Storage & Data Access LLD](../design/lld/04-storage-data-access.md) and the [LLM design brief](../design/lld/llm-brief.md)). App-team personas (Admin, Developer, Reader) apply to **all catalogs within their app** — e.g. a Reader gets read grants on all 4 of their app's catalogs. Fine-grained cross-app sharing (e.g. granting another team `SELECT` on a specific schema or table) is delegated to the app teams themselves, since they are closest to the data. This document needs to be updated to reflect the new layer names throughout (see [Section 9.1](#91-catalog-and-storage-layer-alignment-with-medallion-architecture)). |

---

## 9. Review Items / Stubs

> The items below were identified during review. Each needs to be resolved and folded into the main body of this document before it can be treated as final.

### 9.1 Catalog and Storage Layer Alignment with Medallion Architecture

> **Status:** 🔴 Needs update

The current document refers to `published`, `internal`, `provider`, `raw`, `inprogress`, and `workspace` storage containers and catalogs. The storage architecture has been redesigned around a **4-account medallion model**: Bronze, Silver, Gold, and Snowflake (one ADLS Gen2 account per layer per environment, shared across all apps). The catalog structure is now 4 catalogs per app (Bronze, Silver, Gold, Snowflake).

**Key design principles for the update:**

1. **App-team personas apply to all of the app's catalogs.** Admin, Developer, and Reader each get their respective privilege set across all 4 catalogs belonging to their application — not a subset. There is no restriction of Reader to Gold-only at the platform level.
2. **No human app-team persona needs Azure Storage Blob Data roles.** Data access is mediated entirely through Unity Catalog. Storage-level RBAC (`Storage Blob Data Owner/Contributor/Reader`) is granted only to the app's **UAMI** and the **Databricks Access Connector** — not to human groups. This is a significant change from the current document, which assigns storage roles to Admin, Developer, and Reader.
3. **Fine-grained cross-app sharing is delegated to app teams.** The platform only manages the broad-strokes grants (persona → app catalogs). If an app team wants to share a specific schema or table with another team, they manage that grant themselves at schema-level or below within UC. The platform does not define a cross-app persona for this.

**Action required:**
- Replace all references to the old 5-layer container model with the new Bronze/Silver/Gold/Snowflake naming
- **Remove** `Storage Blob Data Owner`, `Storage Blob Data Contributor`, and `Storage Blob Data Reader` from the Admin, Developer, and Reader persona definitions (Sections 2.2, 6.3)
- Confirm that only the App-Scoped UAI and Databricks Access Connector retain Azure storage-level RBAC
- Redefine UC grants for all three personas in terms of the 4-catalog model (each persona applies to all 4 of their app's catalogs)
- Update external location and storage credential grants to match the new layer names
- Update Admin and Developer tables similarly to reflect the new layer names

### 9.2 Internal-Team Personas — Platform, SDC, Snowflake, Metadata Reader

> **Status:** 🔴 Not yet documented

Section 2.3 defines Platform Engineer and Platform Admin but does not cover the full set of internal-team personas expected in the to-be model. The following personas need to be defined with their Azure RBAC and Databricks permission sets:

| Persona | Description |
|---|---|
| **Platform Engineer** | Monitor and provide support across the platform. Standing read access to platform resources. PIM-eligible for elevated "Break Glass Support" role. |
| **SDC Engineer** | Specific role for the SDC team to manage their own infrastructure within the SDC subscription boundary. Permissions TBD. |
| **Snowflake Engineer** | Specific role for the Snowflake team to manage Snowflake-related infrastructure and the Snowflake catalog layer. Permissions TBD. |
| **Metadata Reader** | A group usable by both humans and non-human identities that require `BROWSE` / metadata-level privileges across catalogs. No data read, no write. Permissions TBD. |

**Action required:**
- Define Azure RBAC assignments for each persona
- Define Databricks UC grants for each persona
- Define Databricks workspace object permissions for each persona
- Add persona-to-group mapping rows in Section 6
- Clarify which of these personas are PIM-eligible and for what roles
- Align naming with the conventions in the [Identity & Access LLD](../design/lld/02-identity-access.md) Phase 2 persona model

### 9.3 Cross-Application Data Sharing Model

> **Status:** � Design direction confirmed — needs documentation

Cross-app data sharing is **delegated to app teams**. The platform manages only the broad-strokes grants (persona → all catalogs within their app). When a team needs to share data with another team, the source app team grants access at schema or table level within UC themselves — they are closest to the data and best positioned to manage these decisions.

This means:
- There is **no platform-level cross-app persona**. The platform does not create a "cross-team reader" role.
- App teams with Admin privileges can grant `SELECT` (or other UC privileges) on specific schemas/tables to other teams' groups or service principals.
- Delta Sharing remains the mechanism for **external / cross-tenant** sharing.
- The Snowflake catalog is the explicit opt-in mechanism for Snowflake sync — objects placed there are approved for Snowflake access.

**Action required:**
- Document this delegation model explicitly in the main body of the document (e.g. a new subsection under AC1 or AC5)
- Clarify that Admin's `CAN_MANAGE` + UC catalog ownership is what enables them to issue cross-app grants
- Confirm whether Reader or Developer personas should also be able to grant cross-app access, or only Admin
- Update Section 4.5 (SQL endpoint additional groups) to reference this delegation model

### 9.4 Break-Glass / PIM Model

> **Status:** 🟡 Needs refinement

The resolved decision (Section 8, #5/#6) confirms that break-glass is self-activated via PIM and Account Admin is directly granted by name. The current Section 7 still describes Account Admin as PIM-eligible with manager approval, which contradicts the resolution.

**Action required:**
- Update Section 7.2 to reflect that Databricks Account Admin is **directly granted** to named individuals, not PIM-eligible
- Add a "Break Glass Support" PIM-eligible role for Platform Engineers (self-activate with justification)
- Define what permissions the Break Glass Support role grants (likely: Subscription Contributor + User Access Administrator, time-bound)
- Clarify the Conditional Access / MFA posture for PIM activations (the [Identity & Access LLD](../design/lld/02-identity-access.md) has a placeholder for this — align the two documents)

### 9.5 Workspace Architecture and Isolation

> **Status:** � Design direction confirmed — needs documentation

Each app team gets its own **serverless workspace**, so multi-team isolation within a single workspace is not a concern. However, the platform retains a centralised **"data landing zone" non-serverless workspace** whose associated storage serves out each app team's data. This simplifies networking: serverless workspaces do not each need multiple private endpoints to read data from other app teams they have UC grants on, because all data sits in the same storage accounts (isolated by container).

Storage accounts are split by **environment** and **data layer** (e.g. a Gold dev storage account with one container per application).

**Action required:**
- Document the centralised data landing zone workspace: its purpose, who has access, and what persona permissions apply to it
- Clarify whether app-team personas (Admin/Developer/Reader) receive any grants on the central workspace, or only on their serverless workspace
- Document the storage account topology in the persona tables: per-env, per-layer, one container per app
- Remove or update any references to shared engineering workspaces and multi-app directory isolation — no longer applicable

### 9.6 Removal of ADF, AI Foundry, and Fabric References

> **Status:** � Needs update

The platform is shifting ADF and AI Foundry functionality into Databricks, or otherwise not supporting them. The following items should be removed from the document:

- All `Data Factory Contributor` role assignments (Admin, Developer, App UAI)
- All AI Foundry / AI Services / AI Search / Cognitive Services role assignments
- All Fabric Workspace role assignments
- The corresponding rows in the summary matrices in Section 6.3
- Any references to ADF or AI Foundry managed identities needing Databricks-level grants

**Action required:**
- Remove these from Sections 2.2 (Admin, Developer, Reader Azure Role Assignments), 5.6 (App-Scoped UAI), and 6.3 (Azure RBAC Summary Matrix)
- Confirm whether Microsoft Fabric is also out of scope, or retained

### 9.7 Access Review / Recertification

> **Status:** � Design direction confirmed — needs documentation

Group ownership and access recertification is **delegated to app teams**. Primary and secondary owners of each app-team group's access requests in MyAccess will be delegates from that application team. This places the responsibility for managing joiners, movers, and leavers with the people closest to the team.

**Action required:**
- Document the delegation model: primary and secondary owners per group are app-team delegates, configured in MyAccess
- Clarify what happens for platform system groups (directory-reader, DNS admin) — these are presumably owned by the platform team
- Confirm whether Entra ID Access Reviews will also be configured as a backstop, or whether MyAccess ownership is considered sufficient
- Document any escalation path if an app-team delegate fails to act on a review

### 9.8 Decommission Sequencing

> **Status:** 🟡 Needs clarification

Section 3.3 says Terraform removes permission bindings and then the PowerShell process removes Entra ID groups. If the group is removed from Entra ID *before* Terraform runs, the `data.azuread_group` lookup will fail and the deployment will error.

**Action required:**
- Document the required sequencing: Terraform destroy first, then group removal
- Consider whether Terraform should use `try()` / conditional lookups to be resilient to pre-deleted groups, or whether the process should enforce ordering

---

## Suggested Next Steps

1. **Resolve 9.1** — Update all layer/catalog references to the medallion model (Bronze/Silver/Gold/Snowflake) and remove Storage Blob Data roles from human personas
2. **Resolve 9.6** — Remove ADF, AI Foundry, AI Services, and Fabric references from persona definitions and summary matrices
3. **Resolve 9.2** — Define internal-team personas (Platform Engineer, SDC Engineer, Snowflake Engineer, Metadata Reader)
4. **Resolve 9.4** — Update PIM section to match resolved decisions (Account Admin direct-grant, Break Glass Support role)
5. **Resolve 9.5** — Document the serverless-per-app + centralised data landing zone workspace model
6. Remaining items (9.3, 9.7, 9.8) can be addressed in parallel or as implementation details emerge
5. Remaining items (9.3, 9.5, 9.6, 9.8) can be addressed in parallel or as implementation details emerge
