# Composition — How the Activities Connect

The specs define each activity in isolation. This defines the **seams**: what flows out of one activity and into the next, which activities are meaningless alone, and where the original library broke its own chains.

A library is not a bag of activities. It is a set of activities that compose. Most of the design decisions in `specs/` only make sense once you see what sits on either side.

---

## 1. The handoff contract

Every arrow below is a type contract. Both ends must agree on the type **and** on the meaning, and both ends must be documented — an undocumented output feeding an undocumented input is a guess on both sides.

| Producer | Output | Consumer | Input | Type |
|---|---|---|---|---|
| `Config.Load` | `out_Config` | `Log.Context.Set` | `in_Config` | `Dictionary(String, Object)` |
| `Config.Load` | `out_Config` | *everything* | `in_Config` | `Dictionary(String, Object)` |
| `Config.Load` | `out_AssetNames` | Orchestrator asset reads | asset name | `Dictionary(String, String)` |
| `Queue.Item.Get` | `out_QueueItem` | `Queue.Item.Resolve` | `in_QueueItem` | `QueueItem` |
| `Queue.Item.Get` | `out_QueueItem` | `Queue.Item.Retry` | `in_QueueItem` | `QueueItem` |
| `Queue.Item.Get` | `out_QueueItem` | `Queue.Item.Update` | `in_QueueItem` | `QueueItem` |
| `Graph.Token.Get` | `out_Private_GraphToken` | `Graph.User.Get` | `in_Token` | `SecureString` |
| `Graph.Token.Get` | `out_Private_GraphToken` | `Http.Request` | `in_Private_Token` | `SecureString` |
| `Record.Create` | `out_SysId` | `Record.Update` | `in_SysId` | `String` (32 hex) |
| `Record.Create` | `out_SysId` | `Task.GetRelated` | `in_SysId` | `String` (32 hex) |
| `Record.Create` | `out_Number` | `Mail.Send` | `in_Body` | `String` (`INC0012345`) |
| `Record.Query` | `out_Records[i].sys_id` | `Record.Update` | `in_SysId` | `String` (32 hex) |
| `Group.GetUsers` | `out_UserIds` | `User.GetEmails` | `in_UserIds` | `String[]` |
| `User.GetEmails` | `out_Emails.Values` | `Mail.Send` | `in_To` | `String[]` |
| `Password.Generate` | `out_Private_Password` | CyberArk rotation | `in_Private_NewPassword` | `SecureString` |
| `Password.Generate` | `out_MaskedUserName` | `Mail.Send` | `in_Body` | `String` |
| `File.Download` | `out_FilePath` | `Config.Load` | `in_ConfigPath` | `String` |
| `File.Download` | `out_FilePath` | `Files.Delete` | `in_Path` | `String` |
| `Mail.Send` | `out_Channel` | `Log.Write` | `in_Message` | `String` |

**The two sys_id rows are the ones to watch.** `sys_id` is a 32-character identifier; `number` is `INC0012345`. They are both strings, so nothing catches the mistake at design time — pass a `number` where a `sys_id` belongs and you get an empty result, not an error. That is why `Record.Create` returns **both**, named for what they are: `out_SysId` feeds the next activity, `out_Number` goes to humans.

---

## 2. Chain A — the transaction loop

The spine of every queue-based process. Nine activities, one shape.

```
┌─ Initialization (once per job) ─────────────────────────────────┐
│                                                                 │
│  Config.Load                                                    │
│    in_Source, in_ConfigPath         → out_Config                │
│                                     → out_AssetNames            │
│                                                                 │
│  Log.Context.Set                                                │
│    in_Config = out_Config                                       │
│    ↳ every later log line carries ProcessName, ClientName,      │
│      BotType, Environment — nothing passes them again           │
│                                                                 │
│  Orchestrator.Job.CheckRunning                                  │
│    in_ProcessNames, in_MaxConcurrent, in_ExcludeSelf = True     │
│                                     → out_LimitReached          │
│    if out_LimitReached → log Info, exit cleanly                 │
└─────────────────────────────────────────────────────────────────┘

┌─ Transaction loop ──────────────────────────────────────────────┐
│  While True:                                                    │
│                                                                 │
│   1. Orchestrator.Stop.Check      → out_StopRequested           │
│         if True → finish current work, exit loop                │
│                                                                 │
│   2. Queue.Item.Get               → out_QueueItem, out_Found    │
│         if Not out_Found → exit loop                            │
│                                                                 │
│   3. Log.Context.Set                                            │
│         in_TransactionId = out_QueueItem.Reference              │
│         ↳ every log line in this iteration is now tagged        │
│                                                                 │
│   4. Try: process the transaction                               │
│                                                                 │
│      ├─ Success ──────────────────────────────────────────      │
│      │   Queue.Item.Resolve                                     │
│      │     in_QueueItem  = out_QueueItem                        │
│      │     in_Successful = True                                 │
│      │     in_OutputData = results for reporting                │
│      │                                                          │
│      ├─ BusinessRuleException ────────────────────────────      │
│      │   Queue.Item.Resolve                                     │
│      │     in_Successful   = False                              │
│      │     in_ErrorType    = "Business"   ← no retry, ever      │
│      │     in_FailureReason = ex.Message  ← enforced, not        │
│      │                                      a tooltip           │
│      │                                                          │
│      └─ System exception ─────────────────────────────────      │
│          Queue.Item.Retry                                       │
│            in_QueueItem       = out_QueueItem                   │
│            in_MaxRetryCount   = Config("MaxRetryCount")         │
│            in_PostponeSeconds = backoff                         │
│            in_Reason          = ex.Message                      │
│                               → out_RetryCount                  │
│                               → out_RetryExhausted              │
│                                                                 │
│            ↳ if out_RetryExhausted, Retry has ALREADY resolved  │
│              the item as Failed/Business. Do not also call      │
│              Resolve — it is closed.                            │
└─────────────────────────────────────────────────────────────────┘
```

### What the chain explains about the API

Three design decisions in `specs/Queue.And.Orchestrator.md` only make sense from here:

- **`out_Found` exists so the loop can terminate.** A queue activity that throws on an empty queue forces every caller to wrap it in a Try/Catch and inspect the exception message to decide whether to exit normally. That is not an error path; it is the normal end of the work.
- **`out_RetryExhausted` exists so the caller knows the item is already closed.** Without it, a caller who retries and then also resolves double-closes the transaction. `Queue.Item.Retry` owns the whole decision — re-queue or fail permanently — because splitting it is what produced the infinite-requeue bug in the original.
- **`Orchestrator.Stop.Check` returns a Boolean instead of throwing** because the loop needs to *finish the current transaction* before exiting. The throwing version cannot do that: the exception arrives mid-transaction and the item is left In Progress for an hour until Orchestrator reclaims it.

### The original's break

`MarkItemAsNew` re-queues. `UpdateQueueItemProgress` increments the retry count. They are **two separate activities**, and the increment is behind an optional toggle in the one you are less likely to call.

So the chain is: get the item, fail, re-queue — and recording that you re-queued is a second call the developer has to remember. The path of least resistance produces an item with no attempt history, which cycles through the queue forever. The library makes the broken chain the default one.

---

## 3. Chain B — incident response

This is the shape of an on-call notification automation: raise a ticket, work out who to page, page them, record what happened.

```
Graph.Token.Get
  in_AppRegistration = "Graph_DirectoryRead"
                                     → out_Private_GraphToken
                                     → out_ExpiresOn
        │
        ├──────────────────────────────────────────┐
        ▼                                          ▼
Record.Create                              Group.GetUsers
  in_Instance = "prod"                       in_Instance  = "prod"
  in_Table    = "incident"                   in_GroupIds  = on-call group
  in_Payload  = { short_description,         in_ActiveOnly = True
                  assignment_group,                        → out_UserIds
                  urgency, caller_id }                     → out_EmptyGroups
                → out_SysId                        │
                → out_Number                       ▼
                → out_Record               User.GetEmails
        │                                    in_UserIds = out_UserIds
        │                                              → out_Emails
        │                                              → out_NotFound
        │                                          │
        └──────────────┬───────────────────────────┘
                       ▼
                 Mail.Send
                   in_To      = out_Emails.Values.ToArray()
                   in_Subject = "[" & out_Number & "] " & summary
                   in_Body    = detail + link built from out_SysId
                   in_FallbackConnection = SMTP
                             → out_Success
                             → out_Channel
                       │
        ┌──────────────┴──────────────┐
        ▼                             ▼
  out_Channel = "Fallback"      Record.Update
  Log.Write(Warn)                 in_SysId   = out_SysId
    "O365 degraded —              in_Payload = { work_notes:
     SMTP fallback used"                        "Paged N responders at ..." }
                                              → out_Success
                       │
                       ▼
               Task.GetRelated
                 in_SysId = out_SysId
                          → out_Tasks
                          → out_Count
```

### Four handoffs, four reasons the outputs are shaped as they are

- **`out_SysId` and `out_Number` are separate** because they go to different places. `out_Number` goes in the subject line a human reads. `out_SysId` goes into `Record.Update` and `Task.GetRelated`. Returning one undocumented blob forces every caller to parse a `JObject` and guess which field is which.
- **`out_EmptyGroups` and `out_NotFound` exist so the gap is visible.** Expand a group of 50, get 47 emails back, and without those two arrays nobody ever learns that three people silently stopped being paged. The notification succeeds. The people do not get it.
- **`out_Channel` feeds a Warn, not an Info.** The fallback firing means Outlook 365 is degraded right now. It is the most useful operational signal in the chain and the original returns nothing at all, so three processes can quietly fall back all morning.
- **`Record.Update` comes after `Mail.Send`** on purpose — the work note records what actually happened, including which channel delivered it.

### The original's break

`Create Ticket` returns `out_Results` with `Tooltip: null` and `Widget: null`. `Get Related Tasks` requires `in_TicketSysId` with `Tooltip: null`.

Same folder, obviously meant to chain, **neither end of the handoff documented**. A developer has to open the XAML of one activity to work out what to feed the other — which is exactly what `includeOriginalXaml: false` is meant to make unnecessary.

---

## 4. Chain C — authenticated API calls

```
Config.Load → out_Config
    Graph.ReadOnly.TenantId
    Graph.ReadOnly.ClientId
    Graph.ReadOnly.CredentialAsset
        │
        ▼
Graph.Token.Get
  in_AppRegistration = "Graph_ReadOnly"
  in_ForceRefresh    = False
                            → out_Private_GraphToken  (SecureString)
                            → out_ExpiresOn
        │
        ├────────────────┬────────────────┐
        ▼                ▼                ▼
  Graph.User.Get   Http.Request     File.Download
    in_Token         in_Private_Token   (resolves its own)
        │                │
        └────────┬───────┘
                 ▼
        401 Unauthorized?
                 │
                 ▼
        Graph.Token.Get(in_ForceRefresh = True)
          ↳ invalidates the cache, mints fresh, retry the call once
```

### Why the cache is in the chain, not the activity

`Graph.Token.Get` is called once per API call *in the code* but hits the network roughly once per hour, because the token is cached in a process-wide `ConcurrentDictionary` keyed by registration and scope.

That matters precisely because of this chain's shape. A process that calls `Graph.User.Get` for 500 queue items calls `Graph.Token.Get` 500 times. Without caching that is 500 token requests, throttling from the identity endpoint, and a process that fails for a reason unrelated to its actual work.

`in_ForceRefresh` exists for one caller: the one that just got a 401 on a call that should have worked. It is the only recovery path that does not require restarting the robot.

**`out_ExpiresOn` is informational.** Callers should not branch on it — that is the cache's job, and a caller checking expiry itself will get the five-minute renewal window wrong.

---

## 5. Chain D — credential rotation

The shortest chain and the one with the sharpest type contract.

```
Password.Generate
  in_Length            = 20
  in_RequireEachClass  = True
  in_UserName          = "svc_automation"
  in_MaskMode          = "HEAD"
                            → out_Private_Password   (SecureString)
                            → out_MaskedUserName     (String)
        │                                    │
        ▼                                    │
CyberArk rotation                            │
  in_Private_NewPassword = out_Private_Password
  in_SafeName            = Config("CyberArk.SafeName")
  in_CyberArkHost        = Config("CyberArk.Host")
                            → out_Success     ← rotation is two-sided;
                              without this you cannot know it worked
        │                                    │
        ▼                                    ▼
      Log.Write                         Mail.Send
        in_Level = Info                   in_Body contains out_MaskedUserName
        "Rotated svc_automation"          ↳ NEVER out_Private_Password
```

**The SecureString never becomes a String anywhere in this chain.** It is generated as one, passed as one, and consumed as one. The only thing that reaches an email is the *masked username* — never the password, in any form.

### What the original gets right, and the one thing it does not

The handoff itself is sound. Both ends are genuinely `SecureString`:

```csharp
public (System.Security.SecureString out_ss_NewPassword, string out_UserNameCensored,
        string out_TempPwd) GetNewPassword(…)

public void UpdatePassword(string in_SafeName, string in_UserName,
                           System.Security.SecureString in_NewPassword, …)
```

Only the **naming** drifts — the producer marks the type with an `ss_` prefix and the consumer does not. That is a readability cost, not a security one: a developer reading `in_NewPassword` in the Properties panel has no signal that this argument is typed, and may reach for a `String` variable and get a compile error rather than guidance.

**The actual gap is the third return value.** `out_TempPwd` is a plain `string`, in the same tuple as the SecureString, under a name their `*password*` exclusion pattern does not match. One of three credentials in that method is unprotected, and it is the one nobody looked at twice.

---

## 6. Chain E — file lifecycle

```
File.Download (SharePoint)
  in_SiteUrl, in_FileName, in_SavePath
                            → out_FilePath
                            → out_Found
        │
        ├─ out_Found = False → Log.Write(Info), skip or wait
        │
        ▼
Config.Load / Excel read
  in_ConfigPath = out_FilePath
        │
        ▼
     [ process ]
        │
        ▼  ← Finally block, always
Files.Delete
  in_Path    = Path.GetDirectoryName(out_FilePath)
  in_Pattern = "*"          ← typed explicitly, because it is required
                            → out_DeletedCount
                            → out_DeletedPaths
```

**`out_FilePath` is the whole reason the chain works.** Without it every caller rebuilds `Path.Combine(in_SavePath, in_FileName)` by hand — which is wrong whenever `in_SavePath` was already a full path, or SharePoint returns a name differing in case. The download activity knows where the file landed; it should say so.

**Cleanup belongs in Finally, not at the end of Try.** A failure mid-processing must not leave the temp copy behind. See `00_STANDARDS.md` §5.

---

## 7. The reference process

All five chains in one skeleton. This is what a new process starts from.

```
Main.xaml
│
├─ Initialization
│    Config.Load            → Config, AssetNames
│    Log.Context.Set(Config)
│    Graph.Token.Get        → token          [if the process uses Graph]
│    Job.CheckRunning       → LimitReached   [exit if gated]
│
├─ Get Transaction Data
│    Stop.Check             → StopRequested  [exit if True]
│    Queue.Item.Get         → QueueItem, Found
│
├─ Process Transaction
│    Log.Context.Set(TransactionId = QueueItem.Reference)
│    [ business logic — the only part that differs per process ]
│    Record.Create / Mail.Send / File.Download / Http.Request
│
├─ End Transaction
│    success  → Queue.Item.Resolve(Successful = True)
│    business → Queue.Item.Resolve(Successful = False, ErrorType = "Business")
│    system   → Queue.Item.Retry → RetryExhausted
│
└─ End Process  (Finally)
     Files.Delete(temp)
     Log.Write(Info, "Processed N transactions, M failed")
     close applications, release sessions
```

Everything outside "Process Transaction" is identical in every process. That is the point of the library: the ninety percent that is the same stops being rewritten, and the business logic is all that is left to think about.

---

## 8. Rules for designing an activity that composes

Derived from the four broken chains above. Each one is a rule because a specific break produced it.

**1. Return what the next activity needs, named for what it is.**
`Record.Create` returns `out_SysId` because `Record.Update` and `Task.GetRelated` both key on it. An undocumented `out_Results` makes every caller parse and guess. *(Break: §3)*

**2. Return what a human needs, separately.**
`out_Number` and `out_SysId` are both identifiers and they go to different audiences. One name for both forces the caller to know which field of a blob is which.

**3. Document both ends of every handoff.**
An undocumented output feeding an undocumented input is two guesses that have to agree. Being in the same folder is not documentation. *(Break: §3)*

**4. Keep the type marking through the whole chain.**
If the producer marks a credential as `SecureString`, the consumer's argument is `SecureString` too, with a matching name. A convention applied at one end only is worse than none, because it reads as a guarantee. *(Break: §5)*

**5. Operations that are only correct together are one activity.**
Re-queueing without incrementing the retry count is always a bug. Splitting them across two activities with the second one optional makes the bug the default. *(Break: §2)*

**6. Report absence, don't return a short list.**
`out_NotFound`, `out_EmptyGroups`, `out_Found`. A caller comparing input count to output count will not notice the gap — nobody diffs arrays.

**7. Make "nothing to do" a value, not an exception.**
Empty queue, missing file, no matching record. These are normal outcomes in a loop and the loop needs to continue past them. Reserve exceptions for conditions the caller genuinely cannot proceed through.

**8. State who owns cleanup.**
`Queue.Item.Retry` resolves the item when retries are exhausted — so the caller must not. Write that down in the description, because the caller cannot infer it.

---

## 9. The composition map, in one view

```
                    ┌──────────────┐
                    │ Config.Load  │  ← everything starts here
                    └──────┬───────┘
                           │ out_Config
          ┌────────────────┼────────────────┬──────────────────┐
          ▼                ▼                ▼                  ▼
   Log.Context.Set   Graph.Token.Get   Job.CheckRunning   (all activities)
          │                │
          │                │ out_Private_GraphToken
          │       ┌────────┼────────┬──────────────┐
          │       ▼        ▼        ▼              ▼
          │  Graph.User  Http.Req  File.Download  SharePoint
          │                                   │ out_FilePath
          │                                   ▼
          │                              Files.Delete (Finally)
          │
          │   ┌─────────────────────────────────────────┐
          │   │           TRANSACTION LOOP              │
          │   │                                         │
          │   │  Stop.Check → Queue.Item.Get            │
          │   │                  │ out_QueueItem        │
          │   │                  ▼                      │
          │   │            [ business logic ]           │
          │   │             │      │       │            │
          │   │   Record.Create  Mail.Send  Http.Request│
          │   │     │ out_SysId    │ out_Channel        │
          │   │     ├──────────────┼────────┐           │
          │   │     ▼              ▼        ▼           │
          └───┼ Record.Update  Log.Write  Task.GetRelated
              │                  (Warn)                 │
              │                  │                      │
              │                  ▼                      │
              │  Queue.Item.Resolve ◄── Queue.Item.Retry│
              │      (success/business)   (system)      │
              └─────────────────────────────────────────┘

        Password.Generate ──SecureString──► CyberArk rotation
                │ out_MaskedUserName                │ out_Success
                └──────────► Mail.Send ◄────────────┘

        Group.GetUsers ──out_UserIds──► User.GetEmails ──out_Emails──► Mail.Send
```
