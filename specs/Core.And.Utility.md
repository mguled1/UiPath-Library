# Activity Spec — `Core`, `Http`, `File`, `Security`

The primitives everything else is built on.

| Activity | File | Replaces |
|---|---|---|
| Set Log Context | `Activities/Core/Log.Context.Set.xaml` | *(new)* |
| Write Log | `Activities/Core/Log.Write.xaml` | Write to Log **+** Create Splunk Log |
| Send Request | `Activities/Http/Http.Request.xaml` | HTTP GET oAuth2 Request |
| Create Folder | `Activities/File/Folder.Create.xaml` | CreateFolder |
| Delete Files | `Activities/File/Files.Delete.xaml` | Delete All Files |
| Generate Password | `Activities/Security/Password.Generate.xaml` | GetNewPassword |
| *(private)* Retry | `Snippets/Retry.xaml` | General Retry, REST API Retry |

---

## 1. Logging: context once, event per call

`Create Splunk Log` takes ten arguments. **Six of them never change within a run:**

```
in_OrchFolder   in_Environment   in_ProjectName
in_ClientName   in_BotType       in_Path
```

Three carry the tooltip *"Once the automation is LIVE, this should NOT be changed"* — because Splunk dashboards key on them. So they must be byte-identical across every call, and the design requires retyping them at every call site. Call the activity in forty places and one typo in `in_ClientName` silently splits a dashboard in two, with nothing failing and nothing to notice.

That is what a **log context** is for.

### `Log.Context.Set` — called once, at init

| # | Name | Type | Dir | Widget | Req |
|---|---|---|---|---|---|
| 1 | `in_Config` | Dictionary(String, Object) | In | Dictionary | Yes |
| 2 | `in_TransactionId` | String | In | TextComposer | No |

Reads `ProcessName`, `ClientName`, `BotType` and `Environment` from config and registers them as UiPath log fields. Every subsequent log line in the job carries them automatically. Change `ClientName` by editing one cell in `Config.xlsx`, not forty workflows.

```
Add Log Fields:
  ProcessName   = Config("ProcessName")
  ClientName    = Config("ClientName")
  BotType       = Config("BotType")
  Environment   = Config("Environment")
  TransactionId = in_TransactionId   ' when supplied
```

Call it again per transaction with a new `in_TransactionId` to tag a whole transaction's logs.

### `Log.Write` — called everywhere

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Message` | String | In | TextComposer | — | Yes |
| 2 | `in_Level` | String | In | Dropdown | — | No |
| 3 | `in_Stage` | String | In | TextComposer | Advanced | No |
| 4 | `in_Data` | Dictionary(String, Object) | In | Dictionary | Advanced | No |

**`in_Level` DataSourceItems:** `["Trace", "Info", "Warn", "Error", "Fatal"]`, default `"Info"`

| Argument | Description |
|---|---|
| `in_Message` | Human-readable message. Name the record and the system — "Ticket.Create failed for invoice INV-4471", not "Error occurred". |
| `in_Level` | See the levels table in `00_STANDARDS.md` §6. |
| `in_Stage` | Where in the process this happened, e.g. `ServiceNow.Ticket.Create`. Becomes a queryable field, so `Stage="..." AND level=ERROR` is one Splunk search rather than a regex over free text. |
| `in_Data` | Extra fields for this event only. |

Four arguments, three optional, no identity fields. Everything the dashboards key on comes from the context.

### Both original activities write files

Worth stating plainly, because the names hide it:

- **`Write to Log`** appends a string to a file on disk. Not Orchestrator, not Splunk. In a library that also contains `Create Splunk Log`, a developer looking for "how do I log" reaches for this one and their output lands in a local file nothing monitors.
- **`Create Splunk Log`** writes files to `D:\UiPath\Logs\<project>\<robot>\splunk\` for a forwarder to collect.

Neither has a log level. Neither states whether a timestamp is added. Neither is concurrency-safe — several unattended robots appending to one file on a shared drive interleave or lose writes, which is exactly how robots are run. Neither rotates, so they append until the disk fills. And `Create Splunk Log`'s header tooltip carries `Write to Log`'s sentence verbatim, typo included: *"If the file does not exist. it will be created."*

`Log.Write` goes through UiPath's own logging pipeline, which already has levels, timestamps, structured fields, concurrency safety, and an existing route to Splunk. The file-writing is the part to delete, not reimplement.

**If a file sink is genuinely required** — a forwarder that only reads a directory — it belongs in the robot's NLog configuration, not in an activity every developer has to remember to call.

---

## 2. `Http.Request`

**Display name:** Send Request
**Tooltip:** Issues an HTTP request with retry, timeout and optional bearer authentication.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Method` | String | In | Dropdown | — | Yes |
| 2 | `in_Url` | String | In | TextComposer | — | **Yes** |
| 3 | `in_Private_Token` | SecureString | In | — | Auth | No |
| 4 | `in_Headers` | Dictionary(String, String) | In | Dictionary | — | No |
| 5 | `in_Body` | String | In | TextComposer | — | No |
| 6 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 7 | `in_MaxRetryCount` | Int32 | In | Number | Advanced | No |
| 8 | `out_StatusCode` | Int32 | Out | Number | Output | — |
| 9 | `out_Body` | String | Out | TextComposer | Output | — |
| 10 | `out_Success` | Boolean | Out | Toggle | Output | — |

**`in_Method` DataSourceItems:** `["GET", "POST", "PUT", "PATCH", "DELETE"]`
**Defaults:** `in_TimeoutSeconds` 30, `in_MaxRetryCount` 3

### Four fixes

**The URL is required.** The original's `in_Endpoint` is `IsRequired: false` — an HTTP activity that can be called with no URL. Same shape as `CreateFolder`'s optional `in_Path`.

**There is a timeout.** The original has none. Every other activity in that library carries `in_TimeoutMS`, including ones that only talk to Orchestrator; the single activity making raw outbound calls — the only one that can actually hang on a dead endpoint — has no timeout argument at all. A robot blocked on a half-open socket stays blocked.

**Retry lives here.** This is the primitive every API call goes through, so handling 429 and transient 5xx here covers the whole library at once. The original leaves it to `Snippets/REST API Retry.xaml`, which callers have to know to wrap it in.

```
Retry on: 408, 429, 500, 502, 503, 504, and transport-level timeouts
Never retry: 4xx other than 408/429 — the request is wrong and will stay wrong
429: honour Retry-After when present, otherwise exponential backoff
Backoff: 2s, 4s, 8s — never a fixed delay against a service already under load
```

**The token is a `SecureString` named `in_Private_Token`.** The original takes `in_AuthToken` as a plain `String`, and the library's exclusion list is `["Private:*", "*password*"]` — which matches **neither**. This is the shared HTTP primitive, so every Graph call, every ServiceNow call and every API call in the portfolio passes a live bearer token through that argument. Raise the log level to Verbose while debugging and it is written out.

Two protections, because one is not enough: `SecureString` so the log serializer will not render it regardless of what the consuming process configured, and a name matching both `Private:*` and `*token*` so pattern exclusion catches it too. See `Integration.Graph.md` §3 for why the library's own `excludedLoggedData` protects nothing on its own.

**One output, not three.** The original returns `out_StatusCode`, `out_Response` and `out_StringResponse`, all `Tooltip: null`, with no indication which to use. `out_Body` is the raw string; the caller parses it. `out_Success` is `true` for 2xx.

**All verbs.** The original bakes `GET` into the name, so `POST`, `PUT`, `PATCH` and `DELETE` need separate activities or inline HTTP — which is presumably why `Snippets/HTTP Request.xaml` exists alongside it.

---

## 3. `Folder.Create`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Path` | String | In | TextComposer | — | **Yes** |
| 2 | `out_Path` | String | Out | TextComposer | Output | — |
| 3 | `out_Created` | Boolean | Out | Toggle | Output | — |

| Argument | Description |
|---|---|
| `in_Path` | Folder to create. Parent folders are created as needed. |
| `out_Path` | Full resolved path, so callers holding a relative path do not rebuild it. |
| `out_Created` | True if created, false if it already existed. |

The original has one argument, `in_Path`, and it is **`IsRequired: false`** — a create-folder activity callable with no path. No tooltips, no colour, no icon, no output. It also appears **twice** in `privateWorkflows`, as `Snippets/CreateFolder.xaml` and `Workflows/Utility/CreateFolder.xaml`.

`out_Created` distinguishes "I made this" from "it was already there" — which matters when the folder's existence is what you were checking for.

---

## 4. `Files.Delete`

**Display name:** Delete Files
**Tooltip:** Deletes files matching a pattern in a folder. Destructive — the pattern is required.
**Colour:** `#E44949` · **Icon:** `delete.svg`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Path` | String | In | TextComposer | — | Yes |
| 2 | `in_Pattern` | String | In | TextComposer | — | **Yes** |
| 3 | `in_OlderThanDays` | Int32 | In | Number | Filter | No |
| 4 | `in_Recursive` | Boolean | In | Toggle | Advanced | No |
| 5 | `out_DeletedCount` | Int32 | Out | Number | Output | — |
| 6 | `out_DeletedPaths` | String[] | Out | StringArray | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Path` | Folder to delete from. Must exist. | — |
| `in_Pattern` | Glob pattern, e.g. `*.tmp`. **Required.** Pass `*` explicitly to delete everything. | — |
| `in_OlderThanDays` | Only delete files last modified more than this many days ago. `0` means no age filter. | `0` |
| `in_Recursive` | Include subfolders. | `False` |
| `out_DeletedCount` | How many files were deleted. | — |
| `out_DeletedPaths` | Which ones. | — |

### Credit, then the fix

`Delete All Files` is in several respects the best-built activity in that library. `Color: "#E44949"`, a recycle-bin icon, and a tooltip stating the consequence plainly — the only place anyone used colour as a warning. Somebody thought about this one.

And `in_Filter` is still `IsRequired: false`, which makes **the default behaviour of a destructive activity "delete every file in the directory."** There is no output, no recursion statement, and no record of what was removed. Point it at the wrong path and there is nothing to reconstruct afterwards.

**Making the pattern required is the whole fix.** `*` still deletes everything — but somebody typed it, which means somebody meant it. A required argument that can be filled with a dangerous value is safer than an optional one that defaults to it.

`out_DeletedPaths` is the other half. A cleanup that removed 10,000 files instead of 10 is only discoverable if the activity says what it touched.

---

## 5. `Password.Generate`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Length` | Int32 | In | Number | — | No |
| 2 | `in_SpecialChars` | String | In | TextComposer | — | No |
| 3 | `in_RequireEachClass` | Boolean | In | Toggle | Advanced | No |
| 4 | `in_UserName` | String | In | TextComposer | Masking | No |
| 5 | `in_MaskMode` | String | In | Dropdown | Masking | No |
| 6 | `out_Private_Password` | SecureString | Out | — | Output | — |
| 7 | `out_MaskedUserName` | String | Out | TextComposer | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Length` | Password length. | **`20`** |
| `in_SpecialChars` | Characters allowed in addition to letters and digits. | `@#$%^&*` |
| `in_RequireEachClass` | Guarantee at least one upper, lower, digit and special. | `True` |
| `in_UserName` | Username to mask for inclusion in a notification. | empty |
| `in_MaskMode` | Which part of the username to obscure. | `HEAD` |
| `out_Private_Password` | The generated password. Never a `String`. | — |
| `out_MaskedUserName` | Masked form, safe to put in an email. | — |

**`in_MaskMode` DataSourceItems:** `["HEAD", "TAIL", "ENDS", "MIDDLE"]`
`HEAD` masks the first four characters, `TAIL` the last four, `ENDS` both, `MIDDLE` the centre.

### Three changes

**Length defaults to 20, not 8.** `GetNewPassword` and `a terminal login activity` both document `8`, the latter explicitly — *"Default length is 8"* — for a CyberArk-managed privileged service account. It is a placeholder, so it is also the value anyone copies.

**There is no plaintext output.** `GetNewPassword` returns two passwords:

```
out_ss_NewPassword    Widget: null          ← ss_ = SecureString. Correct.
out_TempPwd           Widget: TextComposer  ← plaintext String.
```

Same activity. The author knew to protect one and returned the other in the clear — and the exclusion pattern they rely on is `*password*`, which **does not match `TempPwd`**. The one plaintext password in the library is precisely the one their own log scrubbing misses. It appears again in `TC-UpdatePassword`, so it crosses the boundary in both the generator and the CyberArk rotation path.

If a caller genuinely needs a temporary password in a notification, they need the **masked** form, which is `out_MaskedUserName` plus a secure delivery channel — not the password as a `String`.

**`in_MaskMode` is a Dropdown with its values documented.** The same argument exists three times in the original library:

| Activity | Widget | Tooltip |
|---|---|---|
| a terminal login activity | `Dropdown`, `["HEAD","TAIL","ENDS","MIDDLE"]` | each value explained |
| GetNewPassword | `TextComposer` | `null` |
| TC-UpdatePassword | `null` | `null` |

The correct version was written once and never propagated. That is the drift pattern in a single argument, and it is why this library's shared behaviour lives in one place.

---

## 6. `Snippets/Retry` (private)

| Argument | Type | Dir |
|---|---|---|
| `in_WorkflowPath` | String | In |
| `in_Arguments` | Dictionary(String, Object) | In |
| `in_MaxRetryCount` | Int32 | In |
| `in_InitialDelaySeconds` | Int32 | In |
| `in_RetryOn` | String[] | In |
| `out_Result` | Dictionary(String, Object) | Out |
| `out_AttemptCount` | Int32 | Out |

```
For attempt = 1 to in_MaxRetryCount
  Try
    Invoke in_WorkflowPath with in_Arguments
    out_AttemptCount = attempt
    exit

  Catch ex As BusinessRuleException
    Rethrow immediately          ' business exceptions are never retried

  Catch ex As Exception
    If Not retryable(ex, in_RetryOn) Then Rethrow
    If attempt = in_MaxRetryCount Then
      Log Error: "All " & in_MaxRetryCount & " attempts failed. Last: " & ex.Message
      Rethrow
    End If
    delay = in_InitialDelaySeconds * (2 ^ (attempt - 1))    ' 2s, 4s, 8s
    Log Warn: "Attempt " & attempt & " of " & in_MaxRetryCount &
              " failed: " & ex.Message & ". Retrying in " & delay & "s."
    Delay(delay)
```

**Business exceptions rethrow immediately.** A retry on bad data fails identically three times, burns the retry budget and delays the real work. This is the single most important line in the snippet.

**Exponential backoff for transient failures.** A fixed interval against a service that is already struggling is the same request rate that caused the failure, repeated.

**But not for resource contention.** Waiting for a locked record, a free licence or an account to return to a pool is a different problem: the resource frees at a time unrelated to how often you ask, so backing off only makes you wait longer after it becomes available. Poll at a steady cadence there, and cap the total wait rather than the attempt count.

Two different situations, two different shapes. Choose by what you are waiting on, not by habit.

**Every attempt is logged with its number.** `"Attempt 2 of 3 failed: …"` is the difference between diagnosing a flaky dependency in one Splunk query and not knowing retries were happening at all.

Private, so it never appears in a consumer's activity panel — and one implementation, so `Retry.General` and `Retry.RestApi` cannot drift the way Forward and Reply did.

---

## 7. Test cases

### Log
| Case | Expected |
|---|---|
| Context set, then write | identity fields present on the line |
| Write without context | still logs, identity fields absent, no exception |
| `in_Data` supplied | fields queryable in Splunk |
| Level = Error | arrives at Error, not Info |

### Http
| Case | Expected |
|---|---|
| 200 | `out_Success` true, body returned |
| 404 | `out_Success` false, `out_StatusCode` 404, **no retry** |
| 500 then 200 | retried, `out_Success` true |
| 429 with Retry-After | header honoured |
| 3 × 503 | throws after `in_MaxRetryCount` |
| Dead endpoint | times out at `in_TimeoutSeconds`, does not hang |
| Empty `in_Url` | `ArgumentException` |
| Token supplied | header correct, **token absent from every log line** |

### File
| Case | Expected |
|---|---|
| Create new | `out_Created` true |
| Create existing | `out_Created` false, no exception |
| Create nested path | parents created |
| Empty `in_Path` | `ArgumentException` |
| **Delete, empty pattern** | **`ArgumentException` — the "deleted everything" regression test** |
| Delete `*.tmp` | only `.tmp` removed, count correct |
| Delete with `in_OlderThanDays` | recent files untouched |
| Delete recursive | subfolders included |
| Delete, no matches | count 0, no exception |

### Password
| Case | Expected |
|---|---|
| Default | 20 characters |
| `in_RequireEachClass` | every class present |
| Mask HEAD | first four obscured |
| Mask MIDDLE | centre obscured |
| **Log inspection after a run** | **no password value in any log line** |
| Type check on `out_Private_Password` | `SecureString`, not `String` |
