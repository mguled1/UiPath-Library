# UiPath Library Standards

**Owner:** Mohamed Guled
**Purpose:** The coding standard for every automation and reusable component I build.
**Status:** Living document.

---

## 1. What a Library actually is

A UiPath **Library** and a UiPath **Process** are the same project type. One field separates them:

```json
"designOptions": {
  "outputType": "Library"
}
```

Set that, publish, and every workflow in the project becomes a drag-and-drop activity in anyone's Activities panel. That is the entire mechanism.

Two consequences follow, and they drive everything else in this document:

1. **Every public workflow is a published API.** Once someone drops your activity into a production process, you cannot rename an argument without breaking them. Design the argument contract as if it is permanent, because it is.
2. **Visibility is opt-out, not opt-in.** Every workflow is public *unless* you list it as private. Forget to mark an internal helper private and it appears in the activity panel of every consumer.

### The public / private boundary

```json
"libraryOptions": {
  "includeOriginalXaml": false,
  "privateWorkflows": [
    "Snippets/Retry.General.xaml",
    "Snippets/Retry.RestApi.xaml",
    "Snippets/Http.Request.xaml"
  ]
}
```

**Rule:** anything in `Snippets\` is private. Anything in `Activities\` is public. No exceptions — the folder tells you the visibility, so nobody has to open project.json to find out.

`includeOriginalXaml: false` ships compiled workflows only. Consumers can use the activity but cannot read or copy the implementation. Keep it false.

---

## 2. Folder structure

```
MyLibrary/
├── Activities/              PUBLIC — each file becomes a draggable activity
│   ├── Core/                Logging, config, initialization
│   ├── Orchestrator/        Jobs, assets, triggers
│   ├── Queue/               Queue item lifecycle
│   ├── Http/                REST, auth, tokens
│   ├── Data/                Excel, CSV, DataTable, SQL
│   ├── File/                Filesystem operations
│   ├── Mail/                Send, read, attachments
│   └── Integration/         One subfolder per external system
├── Snippets/                PRIVATE — internal helpers, never exposed
├── Tests/                   TC-*.xaml test cases
├── .variations/             JSON test data for data-driven tests
├── Assets/                  Templates, schemas, sample config
└── project.json
```

**Rules**

- A folder with one file is premature. Create the folder at three.
- `Integration\` holds anything tied to a specific vendor system. Everything outside `Integration\` must be portable to any client.
- Never nest deeper than three levels. `Activities\Integration\ServiceNow\` is the floor.

---

## 3. Naming

### 3.1 Workflows

`Noun.Verb.xaml` — noun first, so files sort into related groups.

| Good | Bad | Why |
|---|---|---|
| `Ticket.Create.xaml` | `CreateTicket.xaml` | all `Ticket.*` files sort together |
| `Queue.Item.Get.xaml` | `GetQueueItem.xaml` | reads as a hierarchy |
| `Token.OAuth2.Get.xaml` | `HTTP GET oAuth2 Request.xaml` | no spaces, no protocol noise |

- **No spaces in filenames.** Ever. Spaces break command-line tooling, CI scripts and Git workflows, and they force quoting in every `Invoke Workflow File` path.
- PascalCase each segment.
- Test cases get a `TC-` prefix: `TC-Ticket.Create.xaml`.

### 3.2 Arguments

`direction_PascalCaseName`

| Prefix | Direction | Use |
|---|---|---|
| `in_` | In | Input. Default to this. |
| `out_` | Out | Output. |
| `io_` | In/Out | Only when genuinely mutating a passed-in object. Rare — justify it. |

```
in_TicketNumber        String
in_Config              Dictionary(Of String, Object)
in_TimeoutSeconds      Int32
out_SysId              String
out_Success            Boolean
out_Exception          Exception
```

**Rules**

- Never abbreviate. `in_Num` is worthless in an Arguments panel six months from now; `in_TicketNumber` explains itself.
- Booleans read as assertions: `in_ThrowOnError`, `out_Success`. Never `in_Flag`, never `in_Check`.
- Name the unit when a number has one: `in_TimeoutSeconds`, `in_MaxRetryCount`, `in_DelayMilliseconds`.
- **Every argument gets a Description.** It becomes the tooltip in the Properties panel of every consumer. An argument without one is unfinished work.

### 3.3 Variables

`prefix_PascalCaseName`

| Prefix | Type |
|---|---|
| `str_` | String |
| `int_` | Int32 / Int64 |
| `bool_` | Boolean |
| `dt_` | DataTable |
| `dict_` | Dictionary |
| `list_` | List |
| `arr_` | Array |
| `obj_` | Object / custom type |
| `ex_` | Exception |
| `date_` | DateTime |
| `jo_` | JObject |
| `ja_` | JArray |

Scope every variable as tightly as it will go. A variable scoped to the whole Main sequence when it is used inside one If block is a defect waiting to happen.

### 3.4 Orchestrator resources

| Resource | Pattern | Example |
|---|---|---|
| Asset | `System_Purpose` | `ServiceNow_BaseUrl` |
| Credential asset | `System_Credential` | `ServiceNow_ApiCredential` |
| Queue | `Process_Purpose` | `InvoiceProcessing_Transactions` |
| Process | `Dept_Process_Env` | `Finance_InvoiceProcessing_PROD` |
| Trigger | `Process_Cadence` | `InvoiceProcessing_Daily0600` |

---

## 4. Argument design

### Keep the surface small

If an activity takes more than seven arguments, it is doing more than one thing. Split it, or accept a config object.

### Required before optional

Order arguments in the panel: required inputs, then optional inputs, then outputs. Consumers read top to bottom.

### Never take a credential as a String

```
WRONG:   in_Password        String
RIGHT:   in_Credential      SecureString
BETTER:  in_CredentialAsset String   ' the asset NAME; the activity retrieves it
```

Passing the asset name rather than the secret means the secret never appears in a variable, a log, or a `.xaml` file on disk.

### Always expose a timeout

Anything that touches a network, a file share or a UI gets `in_TimeoutSeconds` with a sensible default. An activity that can hang forever will eventually hang forever.

### Prefer returning status over throwing

```
out_Success      Boolean
out_Message      String
out_Exception    Exception
in_ThrowOnError  Boolean   ' default False
```

Let the caller decide whether a failure is fatal. An activity that always throws cannot be used inside a loop that needs to continue past a bad record.

---

## 5. Error handling

### Business vs system exceptions

This distinction is the single most important design decision in production automation.

| | Business Exception | System Exception |
|---|---|---|
| **Means** | The data is wrong | The environment is wrong |
| **Example** | Invoice has no PO number | ServiceNow returned 503 |
| **Retry?** | Never — it will fail identically | Yes — it may succeed next time |
| **Queue status** | Failed / Business Exception | Failed / Application Exception, then retried |
| **Who fixes it** | The business | Support |

Retrying a business exception burns the retry budget and delays the real work. Not retrying a system exception fails a transaction that would have succeeded on attempt two.

```vb
Throw New BusinessRuleException("Invoice " & in_InvoiceId & " has no PO number.")
```

### Retry

- **Only system exceptions.** Never a business exception.
- Exponential backoff, not fixed delay: 2s, 4s, 8s. A fixed 5-second retry against a service under load is three requests that all fail.
- Cap attempts. Three is the default. Configure it; never hard-code it.
- Log every attempt with its number: `"Attempt 2 of 3 failed: " & ex.Message`.

### Never swallow

```
WRONG:   Try / Catch / (empty)
RIGHT:   Try / Catch -> log it, set out_Success = False, set out_Exception = ex
```

An empty catch block converts a loud failure into a silent wrong answer. Silent wrong answers in production are the expensive kind.

### Always clean up

Close applications, release file handles and log out of sessions in the **Finally** block, not the Try. A failure mid-process must not leave an orphaned browser or a locked file behind.

---

## 6. Logging

### Levels

| Level | Use | Frequency |
|---|---|---|
| `Trace` | Step-by-step debugging | Dev only, off in prod |
| `Info` | Transaction start/end, key milestones | A few per transaction |
| `Warn` | Recovered — retry succeeded, fallback used | Rare |
| `Error` | Transaction failed | Once per failed transaction |
| `Fatal` | Process cannot continue | Almost never |

### Structured, not prose

Add log fields so the log is queryable in Splunk instead of grep-able:

```
Add Log Fields:
  TransactionId  = in_TransactionId
  ProcessName    = Config("ProcessName")
  Stage          = "ServiceNow.Ticket.Create"
```

Then `Stage="ServiceNow.Ticket.Create" AND level=ERROR` is one Splunk query instead of a regex against free text.

### Never log a secret

In project.json:

```json
"excludedLoggedData": ["Private:*", "*password*", "*secret*", "*token*", "*apikey*"]
```

Variables matching those patterns are stripped before anything reaches the log. This is cheap, and it protects you from the one day someone logs the whole config dictionary.

### Log what helps a 3 a.m. diagnosis

Bad: `"Error occurred"`

Good: `"Ticket.Create failed for invoice INV-4471 — ServiceNow returned 403 Forbidden. Asset: ServiceNow_ApiCredential"`

The second one tells support what broke, for which record, and what to look at. The first costs an hour.

---

## 7. Configuration

**Nothing environment-specific is ever hard-coded.** No URLs, paths, timeouts, email addresses, thresholds or retry counts in a workflow.

All of it lives in `Config.xlsx`, loaded once at init into `Dictionary(Of String, Object)`:

| Sheet | Holds |
|---|---|
| `Settings` | URLs, paths, timeouts, retry counts |
| `Constants` | Values that never change per environment |
| `Assets` | Orchestrator asset names (the names, not the values) |

The same published package must promote dev → test → prod with **zero code changes**. If promoting requires editing a workflow, the design is wrong.

```vb
' Read with a default so a missing key degrades instead of crashing
If in_Config.ContainsKey("TimeoutSeconds") Then
    int_Timeout = CInt(in_Config("TimeoutSeconds"))
Else
    int_Timeout = 30
End If
```

---

## 8. Versioning and publishing

Semantic versioning, strictly:

| Change | Bump | Example |
|---|---|---|
| New activity, or new **optional** argument | Minor | 1.3.0 → 1.4.0 |
| Bug fix, no contract change | Patch | 1.3.0 → 1.3.1 |
| Renamed/removed argument, changed type, new **required** argument | **Major** | 1.3.0 → **2.0.0** |

A major bump means every consuming process must be opened, updated, retested and redeployed. Design the contract properly the first time and you will rarely pay that cost.

**Pre-release tags** (`2.11.2-alpha.7`) for anything not production-ready. Never let a consumer pin to an alpha in production — set the dependency Runtime Rule to **Strict** so the exact tested version is what runs.

**Every publish gets release notes.** A consumer deciding whether to take an update needs to know what changed.

---

## 9. Testing

Library activities are consumed by processes you will never see. Test them properly.

- One `TC-*.xaml` per public activity, in `Tests\`.
- Data-driven via a JSON variation file in `.variations\` — same test, many inputs, no copy-paste.
- Cover: happy path, empty/null input, malformed input, downstream failure, timeout.
- Run the full suite before every publish.

An untested library activity is a defect distributed to every process that uses it.

---

## 10. Non-negotiables

1. No hard-coded environment values. Config only.
2. No spaces in file or folder names.
3. Every argument has a Description.
4. Business exceptions are never retried.
5. No empty catch blocks.
6. Cleanup in Finally, not Try.
7. Secrets never become Strings and never reach logs.
8. Every network call has a timeout.
9. Breaking the argument contract means a major version bump.
10. Every public activity has a test case.
