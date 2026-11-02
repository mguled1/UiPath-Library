# Intellika.Automation

Reusable UiPath activities for queue-based automation: config, structured logging, retry, HTTP, Orchestrator, and integrations for Microsoft Graph, Outlook, SharePoint and ServiceNow.

**26 activities · 171 documented arguments · VB · Windows**

---

## Install

**Manage Packages → your feed → `Intellika.Automation` → Install**

Activities appear in the panel grouped by folder, colour-coded by family.

### One required step in the consuming process

Merge this into your process's `project.json` under `runtimeOptions`:

```json
"excludedLoggedData": [
  "Private:*", "*password*", "*secret*", "*token*",
  "*bearer*", "*apikey*", "*credential*", "*assertion*", "Authorization*"
]
```

`excludedLoggedData` is read from the **executing project**, not from a library. The list inside this package governs nothing in your process. Credentials here are typed `SecureString` so they are protected regardless — this is the second layer, for the variables *you* name.

---

## Activities

### Core — `#11AAAA`
| Activity | Does |
|---|---|
| **Load Config** | Config workbook → dictionary, from disk or an Orchestrator storage bucket |
| **Set Log Context** | Registers identity fields once; every later log line carries them |
| **Write Log** | Structured log entry with level and stage |

### Orchestrator — `#FA4616`
| Activity | Does |
|---|---|
| **Check Running Jobs** | Concurrency gate; excludes the calling job by default |
| **Check For Stop** | Returns whether a stop was requested, so the loop can finish cleanly |

### Queue — `#FA4616`
| Activity | Does |
|---|---|
| **Get Queue Item** | One transaction, with `Found` so the loop can end |
| **Resolve Queue Item** | Closes it; failure reason and error type enforced at runtime |
| **Retry Queue Item** | Re-queues **and** increments the counter; fails permanently at the limit |
| **Update Queue Item** | Merges into specific content without clobbering the rest |

### HTTP — `#5B6CFF`
| Activity | Does |
|---|---|
| **Send Request** | All verbs, timeout, retry on transient failures, `SecureString` bearer token |

### File — `#8A8F98` / `#E44949`
| Activity | Does |
|---|---|
| **Create Folder** | Creates with parents; says whether it already existed |
| **Delete Files** | Pattern **required**; returns count and paths |

### Security — `#6B4FBB`
| Activity | Does |
|---|---|
| **Generate Password** | 20 chars by default, `SecureString` only, plus a masked username |

### Microsoft — `#0078D4`
| Activity | Does |
|---|---|
| **Get Graph Token** | Client credentials, cached in-process until shortly before expiry |
| **Get Graph User** | Entra lookup by email; `Found` instead of throwing on 404 |
| **Send Email** | Outlook 365 with optional SMTP fallback; reports which channel delivered |
| **Reply To Email** / **Forward Email** | Shared body composition, attachments verified before sending |
| **Download SharePoint File** | Takes the URL you're already looking at; returns the real local path |

### ServiceNow — `#7AAC99`
| Activity | Does |
|---|---|
| **Create Record** | Returns `SysId` **and** `Number` — one for the next activity, one for humans |
| **Get Record** | By sys_id, required |
| **Query Records** | Query **and** limit both required |
| **Update Record** | Partial update by sys_id |
| **Get Related Tasks** | Child tasks of a record |
| **Get User Emails** | sys_ids → emails, with `NotFound` |
| **Get Group Members** | Groups → distinct members, with `EmptyGroups` |

---

## Quick start

```
Load Config          → Config, AssetNames
Set Log Context      ← Config
Check Running Jobs   → LimitReached     [exit if true]

while True:
    Check For Stop   → StopRequested    [exit if true]
    Get Queue Item   → QueueItem, Found [exit if not Found]
    Set Log Context  ← TransactionId = QueueItem.Reference

    try:
        ... your business logic ...
        Resolve Queue Item  (Successful = true)

    catch BusinessRuleException:
        Resolve Queue Item  (Successful = false, ErrorType = "Business")

    catch Exception:
        Retry Queue Item    → RetryCount, RetryExhausted
```

`Retry Queue Item` closes the item itself when retries are exhausted — do not also call Resolve.

Full chain maps: [`../COMPOSITION.md`](../COMPOSITION.md)

---

## Config

`Assets/Config.template.csv` → save as `Config.xlsx` with sheets `Settings`, `Constants`, `Assets`.

Nothing environment-specific is hard-coded anywhere in this library. The same published package promotes dev → test → prod with **zero code changes**.

---

## Conventions

| | |
|---|---|
| Arguments | `in_` / `out_` / `io_` + PascalCase, never abbreviated |
| Credentials | `in_Private_*` / `out_Private_*`, always `SecureString` |
| Timeouts | `in_TimeoutSeconds` — one name, one unit, everywhere |
| Orchestrator folder | `in_Folder` — one name, optional, defaults to current |
| Closed value sets | `Dropdown` with `DataSourceItems` populated, always |
| Absence | reported (`out_Found`, `out_NotFound`, `out_EmptyGroups`), never a short list |
| Destructive ops | `#E44949`, and they return what they destroyed |

Full standard: [`../00_STANDARDS.md`](../00_STANDARDS.md)

---

## Repo layout

```
project.json                 manifest — outputType: Library
Activities/                  PUBLIC — each .xaml becomes a draggable activity
  <Family>/
    Name.xaml                logic           ← you build this in Studio
    Name.xaml.json           Activity Layout ← generated
    Name.xaml.svg            icon            ← generated
Snippets/                    PRIVATE — listed in privateWorkflows
CodedWorkflows/              C# — the Graph token cache
Tests/                       TC-*.xaml
.variations/                 JSON test data
Assets/                      config template
```

**Regenerate descriptors and icons** after editing `build/activities.json`:

```powershell
powershell -ExecutionPolicy Bypass -File ..\build\generate.ps1
```

It overwrites `.xaml.json` and `.xaml.svg` only. Your `.xaml` logic is never touched.

---

## Building the activities

Descriptors, icons and the manifest are generated. The `.xaml` logic is built in Studio — see [`../BUILD.md`](../BUILD.md) for the full procedure, and `../specs/` for each activity's logic, validation rules and test cases.

---

## Versioning

| Change | Bump |
|---|---|
| New activity, or new optional argument | Minor |
| Bug fix, no contract change | Patch |
| Renamed/removed argument, changed type, new required argument | **Major** |

A major bump means every consuming process must be opened, updated, retested and redeployed.
