# Activity Spec — `Queue` and `Orchestrator`

The transaction core of the library. Six public activities replacing seven.

| Activity | File | Replaces |
|---|---|---|
| Get Queue Item | `Activities/Queue/Queue.Item.Get.xaml` | GetQueueItem |
| Resolve Queue Item | `Activities/Queue/Queue.Item.Resolve.xaml` | ResolveQueueItem |
| Retry Queue Item | `Activities/Queue/Queue.Item.Retry.xaml` | MarkItemAsNew **+** UpdateQueueItemProgress |
| Update Queue Item | `Activities/Queue/Queue.Item.Update.xaml` | UpdateQueueItemContent |
| Check Running Jobs | `Activities/Orchestrator/Job.CheckRunning.xaml` | CheckForRunningJob |
| Check For Stop | `Activities/Orchestrator/Stop.Check.xaml` | Check for Stop |

Shared identity: color `#FA4616`, icon `orchestrator.svg`.

---

## 1. One name for the folder

The single most consequential change, and it costs nothing.

| Original activity | Its folder argument | Required? |
|---|---|---|
| GetQueueItem | `in_QueueFolder` | Yes |
| MarkItemAsNew | `in_QueuePath` | Yes |
| ResolveQueueItem | `in_OrchestratorFolder` | Yes |
| UpdateQueueItemContent | `in_OrchestratorFolderPath` | Yes |
| UpdateQueueItemProgress | `in_QueueItemFolder` | Yes |
| CheckForRunningJob | `in_Folder` | **No** — defaults to current |

Six activities, one Orchestrator folder concept, six spellings, and the odd one out is also the only one that got the requiredness right.

**Everywhere in this library: `in_Folder`, optional, empty means the robot's current folder.**

Optional matters as much as the name. A robot already runs in a folder. Making it required means every caller hard-codes a folder string into every queue call, which is the thing that breaks when a process is promoted from dev to prod — a per-environment value baked into a workflow, exactly what config exists to prevent.

---

## 2. `Queue.Item.Get`

**Display name:** Get Queue Item
**Tooltip:** Retrieves one transaction from an Orchestrator queue.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_QueueName` | String | In | TextComposer | — | Yes |
| 2 | `in_Folder` | String | In | TextComposer | — | No |
| 3 | `in_RetrievalOrder` | String | In | Dropdown | Filtering | No |
| 4 | `in_ReferencePrefix` | String | In | TextComposer | Filtering | No |
| 5 | `out_QueueItem` | QueueItem | Out | — | Output | — |
| 6 | `out_Found` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_QueueName` | Queue to pull from. | — |
| `in_Folder` | Orchestrator folder holding the queue. Empty uses the robot's current folder. | current |
| `in_RetrievalOrder` | Order transactions are taken in. | `NewFirst` |
| `in_ReferencePrefix` | Return only items whose Reference starts with this value. Empty matches any. | empty |
| `out_QueueItem` | The transaction. `Nothing` when none matched. | — |
| `out_Found` | True when a transaction was returned. | — |

**`in_RetrievalOrder` DataSourceItems:** `["NewFirst", "NewOnly"]`

### `out_Found`, not `out_NoQueueItems`

The original returns `out_NoQueueItems` — a negatively-named Boolean. In a conditional it reads:

```vb
If out_NoQueueItems Then          ' "if no queue items, then" — then what? exit?
If Not out_NoQueueItems Then      ' double negative: "if not no queue items"
```

Every reader has to invert it mentally, every time, and sooner or later one of them inverts it wrong. The failure is silent: a process that skips its transaction loop whenever there *is* work, or runs it on `Nothing` when there isn't.

Name flags for the true case. `If out_Found Then` needs no decoding.

### Why `InProgressFirst` and `InProgressOnly` are gone

The original offers four retrieval modes: `New First`, `In Progress First`, `New Only`, `In Progress Only`.

An **In Progress** item is a transaction another robot has already taken and is working on right now. Retrieving one hands a second robot the same transaction. Both process it. Depending on what the process does, that is a duplicate payment, a duplicate ticket, or a duplicate email to a customer — and nothing in Orchestrator will flag it, because as far as the queue is concerned both robots did what they were told.

There is a narrow legitimate use: recovering items orphaned by a robot that died mid-transaction. That is a **recovery** operation, not a retrieval order, and it does not belong behind an innocuous Dropdown in the activity every process calls in its main loop. If you need it, write `Queue.Item.Recover` with a name that says what it does and an age threshold so it only touches genuinely abandoned work.

---

## 3. `Queue.Item.Resolve`

**Display name:** Resolve Queue Item
**Tooltip:** Marks a transaction successful or failed, with the failure classified for retry handling.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_QueueItem` | QueueItem | In | — | — | Yes |
| 2 | `in_Successful` | Boolean | In | Toggle | — | Yes |
| 3 | `in_ErrorType` | String | In | **Dropdown** | Failure | No |
| 4 | `in_FailureReason` | String | In | TextComposer | Failure | No |
| 5 | `in_Folder` | String | In | TextComposer | — | No |
| 6 | `in_OutputData` | Dictionary(String, Object) | In | Dictionary | — | No |

| Argument | Description | Default |
|---|---|---|
| `in_QueueItem` | The transaction to close. | — |
| `in_Successful` | True marks Successful. False marks Failed. | — |
| `in_ErrorType` | How Orchestrator should treat the failure. **Required when `in_Successful` is False.** | — |
| `in_FailureReason` | Why it failed. **Required when `in_Successful` is False.** | — |
| `in_Folder` | Empty uses the robot's current folder. | current |
| `in_OutputData` | Data to attach to the transaction for reporting. | empty |

**`in_ErrorType` DataSourceItems:** `["Application", "Business"]`

### `in_ErrorType` must be a Dropdown

The original declares it `Widget: "TextComposer"` — free text — while its own tooltip states there are exactly two values:

> `Application` — Allows automatic retries
> `Business` — Ignores automatic retries

This argument decides **whether Orchestrator retries the transaction**. Typing `Aplication` does not produce a helpful error at design time; it produces a transaction whose retry behaviour is not what the developer intended, discovered later as either an item that never retried or an item that retried forever.

It is the single highest-consequence free-text field in the library, and the two valid values were already written down in the tooltip. Two valid values and no Dropdown is not a style preference — it is a defect with a known failure mode.

Contrast with `in_Importance` in the Outlook activities, which is a `Dropdown` with `DataSourceItems: null` and renders empty. The library contains both halves of the mistake and neither was noticed.

### Conditional requirements have to be enforced in the activity

The original marks `in_FailureReason` as `IsRequired: false` while its tooltip says *"Required if transaction failed."* The contract and the documentation contradict each other, and neither is enforced.

`IsRequired` in the `.xaml.json` descriptor is unconditional — it cannot express "required when another argument has a particular value". So the rule has to live in validation:

```
If Not in_Successful Then
    If String.IsNullOrWhiteSpace(in_FailureReason) Then
        Throw New ArgumentException(
            "in_FailureReason is required when in_Successful is False. " &
            "A failed transaction with no reason cannot be triaged.")
    End If
    If String.IsNullOrWhiteSpace(in_ErrorType) Then
        Throw New ArgumentException(
            "in_ErrorType is required when in_Successful is False. " &
            "Use Application for retryable failures, Business for data failures.")
    End If
End If
```

A design-time tooltip is advice. A runtime throw is a contract. The failed queue item with a blank reason is exactly the one somebody has to triage at 3am with nothing to go on, so this is worth being strict about.

---

## 4. `Queue.Item.Retry` — the merge that fixes the retry loop

**Display name:** Retry Queue Item
**Tooltip:** Returns a transaction to the queue and increments its retry count, failing it permanently once the limit is reached.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_QueueItem` | QueueItem | In | — | — | Yes |
| 2 | `in_MaxRetryCount` | Int32 | In | Number | — | No |
| 3 | `in_PostponeSeconds` | Int32 | In | Number | — | No |
| 4 | `in_Reason` | String | In | TextComposer | — | No |
| 5 | `in_Folder` | String | In | TextComposer | — | No |
| 6 | `out_RetryCount` | Int32 | Out | Number | Output | — |
| 7 | `out_RetryExhausted` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_QueueItem` | The transaction to return to the queue. | — |
| `in_MaxRetryCount` | Attempts allowed before the item is failed permanently. | `3` |
| `in_PostponeSeconds` | Delay before the item becomes eligible again. `0` makes it immediately available. | `0` |
| `in_Reason` | Why it is being retried. Recorded on the item and logged. | empty |
| `in_Folder` | Empty uses the robot's current folder. | current |
| `out_RetryCount` | Attempt number after this call. | — |
| `out_RetryExhausted` | True when the limit was reached and the item was failed instead of re-queued. | — |

### Why two activities become one

The original splits this across `MarkItemAsNew` (re-queue) and `UpdateQueueItemProgress` (increment the counter, behind an optional toggle).

So re-queueing a transaction and recording that you re-queued it are separate calls, and the increment is opt-in. The path of least resistance — call `MarkItemAsNew`, move on — produces an item with no attempt history. An item that fails for a permanent reason (malformed data, a deleted record, a field the upstream system stopped sending) then cycles through the queue indefinitely. Every cycle logs an error, burns a robot slot, and delays real work. Nothing stops it, because nothing is counting.

Re-queueing without incrementing is always a bug. An API that makes the bug the default should not have that shape.

```
1. Validate
     in_QueueItem Nothing      -> ArgumentException
     in_MaxRetryCount < 1      -> ArgumentException
     in_PostponeSeconds < 0    -> ArgumentException

2. int_Current = current retry count on the item
   out_RetryCount = int_Current + 1

3. If out_RetryCount > in_MaxRetryCount
     Resolve the item as Failed
       ErrorType     = "Business"       ' exhausted retries are not retryable
       FailureReason = "Retry limit reached (" & in_MaxRetryCount & " attempts). " &
                       "Last reason: " & in_Reason
     out_RetryExhausted = True
     Log Error: "Transaction " & reference & " exhausted " & in_MaxRetryCount &
                " retries and was failed. Last reason: " & in_Reason
     exit

4. Re-queue the item
     postpone until DateTime.UtcNow.AddSeconds(in_PostponeSeconds) when > 0
     increment the retry counter in the same call
   out_RetryExhausted = False
   Log Warn: "Transaction " & reference & " re-queued, attempt " &
             out_RetryCount & " of " & in_MaxRetryCount & ". Reason: " & in_Reason
```

**The exhausted item is failed as `Business`, not `Application`.** It has already been retried the allowed number of times. Classifying it as Application would hand it back to Orchestrator's own retry mechanism and restart the loop one level up.

**Retry logs at Warn, exhaustion at Error.** A retry is expected and recoverable. Exhaustion is a transaction that will never complete without a human. Those belong at different levels so an alert on Error means something.

### One shape for postpone

The original expresses postpone two ways: `in_PostponeDelayMS` (relative milliseconds) in `MarkItemAsNew`, `in_PostponeTimeUTC` (absolute `DateTime`) in `UpdateQueueItemContent`. Same operation, two mental models, and no way to know which an activity wants without opening it.

This library uses **relative seconds**, everywhere. Retry backoff is inherently relative — "try again in 30 seconds" — and relative values carry no timezone or clock-skew ambiguity. A caller who genuinely needs an absolute time writes one expression:

```vb
CInt((targetUtc - DateTime.UtcNow).TotalSeconds)
```

### `in_CustomValue` is not carried forward

The original's `UpdateQueueItemProgress` has `in_CustomValue`, documented in full as: *"Overwrites the other options."*

No format, no precedence, no statement of what it overwrites them with, no description of what happens when it is set alongside the toggles. An undocumented escape hatch that mutates queue state cannot be used safely and cannot be reviewed. If a case exists that the typed arguments do not cover, it gets its own named argument with its own documentation.

---

## 5. `Queue.Item.Update`

**Display name:** Update Queue Item
**Tooltip:** Merges values into a transaction's specific content.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_QueueItem` | QueueItem | In | — | — | Yes |
| 2 | `in_Values` | Dictionary(String, Object) | In | Dictionary | — | Yes |
| 3 | `in_Replace` | Boolean | In | Toggle | Advanced | No |
| 4 | `in_Folder` | String | In | TextComposer | — | No |
| 5 | `out_Success` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Values` | Keys to set on the transaction's specific content. | — |
| `in_Replace` | Replace the entire content instead of merging. Destructive — anything not in `in_Values` is lost. | `False` |
| `out_Success` | True when the update was accepted. | — |

### Merge by default, replace by choice

The original requires the complete `in_SpecificContent` dictionary on every call. To change one field you must supply all of them, which means read the item, hold its content, write it back — and anything another process changed in between is silently overwritten. A read-modify-write race, forced by the contract rather than chosen by the caller.

Merging updates only the keys supplied. `in_Replace` is there for the rare caller who genuinely wants to blank the rest, with a description that says what it costs.

### `out_Success`, not `out_StatusCode`

The original returns `out_StatusCode` — a raw HTTP status code as a `Number`, `Tooltip: null`, `IsPrincipal: false`.

Three problems. It leaks the transport into the contract: the caller has to know 200 means success, and if the implementation moves from REST to a UiPath activity the contract breaks. It is undocumented, so nobody knows which codes to treat as success. And it is the **only output in the entire original library** — and it is hidden on the collapsed card while `in_TimeoutMS`, which is optional, is shown.

A library activity returns whether it worked, not what the wire said.

---

## 6. `Orchestrator.Job.CheckRunning`

**Display name:** Check Running Jobs
**Tooltip:** Reports how many of the named processes are currently running or pending, for use as a concurrency gate.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_ProcessNames` | String[] | In | StringArray | — | Yes |
| 2 | `in_MaxConcurrent` | Int32 | In | Number | — | No |
| 3 | `in_ExcludeSelf` | Boolean | In | Toggle | Advanced | No |
| 4 | `in_Folder` | String | In | TextComposer | — | No |
| 5 | `out_LimitReached` | Boolean | Out | Toggle | Output | — |
| 6 | `out_RunningCount` | Int32 | Out | Number | Output | — |
| 7 | `out_RunningProcesses` | String[] | Out | StringArray | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_ProcessNames` | Release names to check. | — |
| `in_MaxConcurrent` | Running jobs allowed before `out_LimitReached` is True. | `1` |
| `in_ExcludeSelf` | Ignore the job making this call. | `True` |
| `out_LimitReached` | True when the count has reached `in_MaxConcurrent`. | — |
| `out_RunningCount` | How many matched. | — |
| `out_RunningProcesses` | Which ones. | — |

### `in_ExcludeSelf` fixes a trap

The original has no equivalent. A process that includes its own release name in `in_ProcessNames` — which is the obvious thing to do when the point is "don't run two of me at once" — always finds itself running. `out_IsRunning` comes back True on the first and only instance, and the process exits immediately, every time, forever. It looks like the gate is working.

Default `True`, because excluding yourself is what the caller almost always means.

### Returning the names, not just a flag

The original returns a bare `out_IsRunning` Boolean. So when a process declines to start, the log says it was blocked and nothing more. `out_RunningProcesses` lets the caller log *which* process held the lock, which is the difference between "blocked again" and "blocked by the nightly reconciliation that has been running for six hours."

### The name says what it does

`in_MaxJobCount` — "max number of jobs that can run at a time" — makes this a **concurrency gate**, not a check. Keeping a name that undersells it means developers write their own gate rather than finding this one.

---

## 7. `Orchestrator.Stop.Check`

**Display name:** Check For Stop
**Tooltip:** Returns True when a stop has been requested for this job from Orchestrator.

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `out_StopRequested` | Boolean | Out | Toggle | Output | — |

One output, no inputs.

### `in_ShouldFault` is dropped

The original takes a required `in_ShouldFault` toggle that makes the activity throw instead of returning. So it has two mechanisms for one piece of information, and the caller picks which at design time.

Returning a Boolean is strictly more capable. A caller who wants an exception writes one `If` — and gets to choose the message, which the activity cannot do as well as the caller can. A caller who wants to finish the current transaction before stopping cleanly, which is the correct behaviour in a queue loop, can do that too. The throwing version cannot.

The standards say it directly: an activity that always throws cannot be used inside a loop that needs to continue past it.

Also fixed from the original: the header `Tooltip` was `null`, and "Recieved" was misspelled in both the DisplayName and the tooltip — both visible in every consumer's Properties panel. And `out_Stop` was `IsPrincipal: false`, hiding the activity's only output on the collapsed card while the optional flag was shown.

---

## 8. Test cases

### Queue.Item.Get
| Case | Expected |
|---|---|
| Item available | `out_Found` true, `out_QueueItem` populated |
| Queue empty | `out_Found` false, `out_QueueItem` Nothing, no exception |
| `in_Folder` empty | resolves against the current folder |
| `in_ReferencePrefix` set | only matching references returned |
| Queue does not exist | throws, message names the queue and folder |

### Queue.Item.Resolve
| Case | Expected |
|---|---|
| Successful | item Successful |
| Failed, Application | item Failed, Orchestrator retry allowed |
| Failed, Business | item Failed, no retry |
| Failed, no reason | `ArgumentException` before anything is written |
| Failed, no ErrorType | `ArgumentException` before anything is written |
| Successful, no reason | accepted — the rule is conditional |

### Queue.Item.Retry
| Case | Expected |
|---|---|
| First retry | re-queued, `out_RetryCount` 1, Warn logged |
| At the limit | failed as Business, `out_RetryExhausted` true, Error logged |
| Postpone 60s | not eligible for 60 seconds |
| Postpone 0 | immediately eligible |
| `in_MaxRetryCount` 0 | `ArgumentException` |
| Same item retried past the limit in a loop | terminates — the regression test for the infinite-requeue bug |

### Queue.Item.Update
| Case | Expected |
|---|---|
| Merge one key | other keys untouched |
| `in_Replace` true | content replaced wholesale |
| Empty dictionary | `ArgumentException` |

### Orchestrator
| Case | Expected |
|---|---|
| Self in the list, `in_ExcludeSelf` true | not counted |
| Self in the list, `in_ExcludeSelf` false | counted |
| Two of three running, max 3 | `out_LimitReached` false, count 2, names returned |
| Nothing running | count 0, empty array |
| No stop requested | `out_StopRequested` false |
| Stop requested | `out_StopRequested` true, nothing thrown |
