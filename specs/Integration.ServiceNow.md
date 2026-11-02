# Activity Spec — `Integration/ServiceNow`

| Activity | File | Replaces |
|---|---|---|
| Create Record | `Activities/Integration/ServiceNow/Record.Create.xaml` | Create Ticket |
| Get Record | `Activities/Integration/ServiceNow/Record.Get.xaml` | Get Ticket (sys_id path) |
| Query Records | `Activities/Integration/ServiceNow/Record.Query.xaml` | Get Ticket (search path) |
| Update Record | `Activities/Integration/ServiceNow/Record.Update.xaml` | Update Ticket |
| Get Related Tasks | `Activities/Integration/ServiceNow/Task.GetRelated.xaml` | Get Related Tasks |
| Get User Emails | `Activities/Integration/ServiceNow/User.GetEmails.xaml` | Get Emails from SNOW |
| Get Group Members | `Activities/Integration/ServiceNow/Group.GetUsers.xaml` | Get Users in Group |

Shared identity: color `#7AAC99`, icon `servicenow.svg`.

Six activities become seven, because one of them was two activities wearing one name.

---

## 1. The unbounded query, and why Get splits in two

`Get Ticket` takes `in_TicketSysId` and `in_SearchQuery`, both `IsRequired: false`. The rule lives in one tooltip — *"Required if no SysId is provided"* — on one of the two arguments, and is enforced on neither.

Call it with neither and you issue `GET /api/now/table/incident` with no `sysparm_query`. ServiceNow applies its default `sysparm_limit` of **10,000** rather than returning the entire table, so it does not hang forever — it returns up to ten thousand incident records over REST, blows the 15-second timeout, and loads the instance while it does. The caller sees a timeout and goes looking for a network problem.

`in_Limit`, the one guardrail, is optional, undocumented and has no default.

**A validation check would catch it. A split makes it unrepresentable.**

```
Record.Get     in_SysId  REQUIRED   — one record, by identity
Record.Query   in_Query  REQUIRED   — many records, by filter
               in_Limit  REQUIRED   — bounded, always
```

Neither activity can be called in a way that produces an unfiltered query. The caller also picks the right one by name rather than by remembering which arguments to fill, and each gets an honest return type: `Record.Get` returns one record and a `Boolean`; `Record.Query` returns a collection and a count.

This is the general principle worth taking: when two modes of one activity have different required arguments, they are two activities. A single activity with mutually-conditional optional arguments cannot express its own contract.

---

## 2. One tri-state, not two booleans

`in_DisplayIDs` and `in_DisplayValues` are two `Boolean` toggles. They map to **one** ServiceNow parameter:

> `sysparm_display_value` — `true` returns display values, `false` returns database values, `all` returns both. Default `false`.

Two booleans give four combinations for three valid states. Nothing documents which combination means `all`, both tooltips are `null`, and the metadata contradicts itself across the library:

| | `Category` | `IsRequired` |
|---|---|---|
| Create Ticket | `"Optional"` | **true** |
| Get Ticket | `"Optional Query Parameters"` | false |
| Update Ticket | `"Optional"` | false |

Required in one activity, optional in two, under two category names. One of those is wrong and nothing says which.

**Replacement:** one argument, `in_DisplayValues As String`, `Dropdown`, items `["false", "true", "all"]`, default `"false"` — matching the API exactly. Three states, three values, no invalid combinations.

> Display values are slower: ServiceNow resolves them rather than reading straight from the database. Worth a line in the description so nobody turns it on by default.

---

## 3. Arguments

### `Record.Create`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_Table` | String | In | Dropdown | — | Yes |
| 3 | `in_Payload` | Dictionary(String, Object) | In | Dictionary | — | Yes |
| 4 | `in_DisplayValues` | String | In | Dropdown | Advanced | No |
| 5 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 6 | `out_SysId` | String | Out | TextComposer | Output | — |
| 7 | `out_Number` | String | Out | TextComposer | Output | — |
| 8 | `out_Record` | JObject | Out | — | Output | — |

### `Record.Get`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_Table` | String | In | Dropdown | — | Yes |
| 3 | `in_SysId` | String | In | TextComposer | — | **Yes** |
| 4 | `in_Fields` | String[] | In | StringArray | Advanced | No |
| 5 | `in_DisplayValues` | String | In | Dropdown | Advanced | No |
| 6 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 7 | `out_Record` | JObject | Out | — | Output | — |
| 8 | `out_Found` | Boolean | Out | Toggle | Output | — |

### `Record.Query`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_Table` | String | In | Dropdown | — | Yes |
| 3 | `in_Query` | String | In | TextComposer | — | **Yes** |
| 4 | `in_Limit` | Int32 | In | Number | — | **Yes** |
| 5 | `in_Fields` | String[] | In | StringArray | Advanced | No |
| 6 | `in_OrderBy` | String | In | TextComposer | Advanced | No |
| 7 | `in_DisplayValues` | String | In | Dropdown | Advanced | No |
| 8 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 9 | `out_Records` | JArray | Out | — | Output | — |
| 10 | `out_Count` | Int32 | Out | Number | Output | — |

### `Record.Update`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_Table` | String | In | Dropdown | — | Yes |
| 3 | `in_SysId` | String | In | TextComposer | — | Yes |
| 4 | `in_Payload` | Dictionary(String, Object) | In | Dictionary | — | Yes |
| 5 | `in_DisplayValues` | String | In | Dropdown | Advanced | No |
| 6 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 7 | `out_Record` | JObject | Out | — | Output | — |
| 8 | `out_Success` | Boolean | Out | Toggle | Output | — |

### `Task.GetRelated`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_SysId` | String | In | TextComposer | — | Yes |
| 3 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 4 | `out_Tasks` | JArray | Out | — | Output | — |
| 5 | `out_Count` | Int32 | Out | Number | Output | — |

### `User.GetEmails`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_UserIds` | String[] | In | StringArray | — | Yes |
| 3 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 4 | `out_Emails` | Dictionary(String, String) | Out | Dictionary | Output | — |
| 5 | `out_NotFound` | String[] | Out | StringArray | Output | — |

### `Group.GetUsers`

| # | Name | Type | Dir | Widget | Category | Req |
|---|---|---|---|---|---|---|
| 1 | `in_Instance` | String | In | Dropdown | — | Yes |
| 2 | `in_GroupIds` | String[] | In | StringArray | — | Yes |
| 3 | `in_ActiveOnly` | Boolean | In | Toggle | Advanced | No |
| 4 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 5 | `out_UserIds` | String[] | Out | StringArray | Output | — |
| 6 | `out_EmptyGroups` | String[] | Out | StringArray | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_GroupIds` | `sys_user_group` sys_ids to expand. | — |
| `in_ActiveOnly` | Exclude inactive users from the result. | `True` |
| `out_UserIds` | Distinct `sys_user` sys_ids across all groups. Deduplicated — a user in two groups appears once. | — |
| `out_EmptyGroups` | Groups that resolved to no members, so an empty notification list is distinguishable from a mistyped group. | — |

**Why `in_ActiveOnly` defaults to True.** The usual reason to expand a group is to notify or assign to its members. Including deactivated users means paging people who have left, and the failure is silent — the message goes nowhere and nobody is told it didn't arrive.

**Why `out_EmptyGroups` exists.** The original returns only a user list. An empty result could mean the group has no members, the group sys_id was wrong, or every member is inactive. All three produce the same empty array, and the process carries on notifying nobody.

**Shared values**

- `in_Instance` DataSourceItems: `["dev", "uat", "prod"]`
- `in_Table` DataSourceItems: `["incident", "task", "incident_task", "change_request", "change_task", "sc_req_item", "sys_user", "sys_user_group"]`
- `in_DisplayValues` DataSourceItems: `["false", "true", "all"]`, default `"false"`
- `in_TimeoutSeconds` default `30`

---

## 4. Descriptions

| Argument | Description |
|---|---|
| `in_Instance` | ServiceNow instance for the REST call. The credentials for each are resolved from config. |
| `in_Table` | Table to act on. |
| `in_SysId` | The record's 32-character `sys_id`. **Not** the display number — `INC0012345` is a `number`, not a `sys_id`. |
| `in_Payload` | Field name to value. Common incident fields: `short_description`, `description`, `assignment_group`, `caller_id`, `urgency`, `impact`, `category`, `state`, `work_notes`, `close_notes`, `close_code`. Reference fields take a `sys_id`, not a display name. |
| `in_Query` | Encoded query, e.g. `active=true^assignment_group=<sys_id>^ORDERBYDESCsys_created_on`. |
| `in_Limit` | Maximum records to return. Required — an unbounded query against a production instance is never intended. |
| `in_Fields` | `sysparm_fields`. Restricting returned fields is the single biggest win on a large table. |
| `in_OrderBy` | Field to sort by. Prefix with `-` for descending. |
| `in_DisplayValues` | `false` returns database values, `true` display values, `all` both. Display values are slower — ServiceNow resolves them rather than reading them directly. |
| `in_UserIds` | `sys_user` sys_ids to resolve. |
| `out_SysId` | `sys_id` of the created record. |
| `out_Number` | Display number of the created record, e.g. `INC0012345`. |
| `out_Record` | The full record. Empty JObject when not found. |
| `out_Found` | False when no record has that `sys_id`. |
| `out_Count` | Number of records returned. Equal to `in_Limit` means results were truncated. |
| `out_Emails` | sys_id to email address. Users without an email are absent. |
| `out_NotFound` | sys_ids that did not resolve. |

### `out_Number` is the point of Create

The original's `Create Ticket` returns `out_Results` — `Tooltip: null`, `Widget: null`, `IsPrincipal: false`. Something comes back and the contract does not say what.

The display number is what a Create activity exists to produce. It goes in the notification email, the queue item reference, the log line, the chat message to the on-call engineer. Returning it as a named `String` instead of burying it in an undocumented blob removes a `JObject` parse from every single caller.

`out_SysId` is separate because that is what the *next* activity needs — `Record.Get`, `Record.Update` and `Task.GetRelated` all key on `sys_id`. The original left both ends of that chain undocumented: `Create Ticket` does not say what it returns and `Get Related Tasks` does not say what format it wants. Naming both outputs closes it.

### `out_NotFound` instead of a silent gap

`User.GetEmails` returns a dictionary. A caller iterating 50 users and getting 47 entries back has no way to know which three are missing without diffing the input against the output — so nobody does, and three people silently stop receiving notifications. Returning the gap explicitly costs one argument.

---

## 5. Logic — common shape

```
Try
  1. Validate
       in_Instance not in {dev, uat, prod}   -> ArgumentException
       in_Table empty                        -> ArgumentException
       Record.Get / Update: in_SysId empty   -> ArgumentException
       Record.Query: in_Query empty          -> ArgumentException("A query is required.
                                                An unfiltered request would return up to
                                                10,000 records.")
       Record.Query: in_Limit < 1            -> ArgumentException
       Create / Update: in_Payload empty     -> ArgumentException

  2. Resolve instance from config
       ServiceNow.<instance>.BaseUrl
       ServiceNow.<instance>.CredentialAsset

  3. Call the Table API
       Create : POST   /api/now/table/{table}
       Get    : GET    /api/now/table/{table}/{sysId}
       Query  : GET    /api/now/table/{table}?sysparm_query=...&sysparm_limit=...
       Update : PATCH  /api/now/table/{table}/{sysId}
       Related: GET    /api/now/table/task?sysparm_query=parent={sysId}

       sysparm_display_value = in_DisplayValues
       sysparm_fields        = String.Join(",", in_Fields) when supplied
       Timeout               = in_TimeoutSeconds

  4. Branch on status
       200/201 -> parse result, populate outputs
       404     -> Record.Get: out_Found = False, no throw
                  others: throw naming the table and sys_id
       401/403 -> throw naming the instance and the credential asset
       429     -> honour Retry-After, retry once, then throw
       else    -> throw with status and the ServiceNow error detail from the body

  5. Record.Query only
       If out_Count = in_Limit
         Log Warn: "Query returned exactly in_Limit records; results may be truncated."

Catch ex As Exception
  Log Error: "<Operation> failed on " & in_Table & " @ " & in_Instance & " - " & ex.Message
  Rethrow
```

**Why the truncation warning.** A query that returns exactly the limit almost always means there was more. Silent truncation reads as a complete result set, and a reconciliation process that silently sees 500 of 900 records produces a confidently wrong answer. One Warn makes it visible.

**Why 404 only soft-fails on Get.** "That record does not exist" is a normal answer to a lookup and a caller may well loop past it. It is not a normal answer to an update — if you are updating a record that is not there, something upstream is wrong and you want to know now.

---

## 6. Config

```
Settings sheet:
  ServiceNow.dev.BaseUrl           = https://devNNNNN.service-now.com
  ServiceNow.dev.CredentialAsset   = ServiceNow_Dev_ApiCredential
  ServiceNow.uat.BaseUrl           = https://company-uat.service-now.com
  ServiceNow.uat.CredentialAsset   = ServiceNow_Uat_ApiCredential
  ServiceNow.prod.BaseUrl          = https://company.service-now.com
  ServiceNow.prod.CredentialAsset  = ServiceNow_Prod_ApiCredential
```

`in_Instance` stays as an argument rather than moving to config, unlike every other environment switch in this library. The reason is that it is **not** an environment switch: a production robot legitimately writes to the dev instance — seeding test data, validating a change before it goes to prod. The instance is a genuine per-call choice. `in_UseDev`, `in_UseUAT` and the rest were not; they selected which credentials to use for the same logical target, which is config's job.

---

## 7. What was dropped or changed

### `in_ServiceNowInstance` → `in_Instance`

The activity lives in `Integration/ServiceNow/`. Repeating the namespace in the argument name makes the Properties panel read `ServiceNow > ServiceNowInstance`.

Worth noting this is the one argument the original got right across all five activities — byte-identical Dropdown, identical items, identical tooltip, everywhere it appears. After seven names for the Orchestrator folder, that consistency is the exception in the library and it is the thing to copy.

### `in_DisplayIDs` + `in_DisplayValues` → one `in_DisplayValues`

Section 2.

### `in_TimeoutMS` → `in_TimeoutSeconds`

Four ServiceNow activities default to `15000`, `Get Emails from SNOW` defaults to `30000`, and `IsPrincipal` flips to `true` on that one. Five activities, three sets of timeout metadata, in a library where `Get Mainframe Bot ID` also documents the same `in_TimeoutMS` name as *"In Seconds"*.

One name, one unit, one default, library-wide.

### `out_Results` → named outputs

Four activities, one argument name, four different metadata combinations:

| | `Category` | `IsRequired` | `IsPrincipal` |
|---|---|---|---|
| Create Ticket | `"Output"` | true | false |
| Get Ticket | `null` | true | **true** |
| Get Related Tasks | `null` | true | true |
| Update Ticket | `"Output"` | **false** | false |

All four `Tooltip: null`, all four `Widget: null`. `IsRequired` has no meaning on an Out argument, and the fact that it varies is the tell: the field was filled in by copy-paste rather than decided.

### `in_UserList` and `out_EmailList` → typed

Both `Widget: null`, both `Tooltip: null`, in an activity whose only job is resolving users to emails. A consumer cannot tell whether to pass sys_ids, usernames or email addresses, or whether a `String[]`, `List(Of String)` or `DataTable` comes back — they have to open the implementation, which `includeOriginalXaml: false` is specifically meant to make unnecessary.

---

## 8. Test cases

| Case | Expected |
|---|---|
| Create, valid payload | `out_SysId` and `out_Number` populated |
| Create, empty payload | `ArgumentException`, nothing sent |
| Get, exists | `out_Found` true, record populated |
| Get, missing sys_id | `out_Found` false, no exception |
| Get, a `number` passed as `in_SysId` | `out_Found` false — the description warns about this |
| **Query, empty `in_Query`** | **`ArgumentException` — the unbounded-query regression test** |
| Query, `in_Limit` 0 | `ArgumentException` |
| Query returning exactly `in_Limit` | Warn logged about possible truncation |
| Query with `in_Fields` | only those fields returned |
| Update, exists | `out_Success` true |
| Update, missing sys_id | throws, message names table and sys_id |
| `in_DisplayValues = "all"` | both value forms returned |
| `in_DisplayValues = "maybe"` | rejected at design time — not in the Dropdown |
| Bad credentials | throws naming instance and credential asset |
| 429 | Retry-After honoured, one retry |
| GetEmails, one user missing | present in `out_NotFound`, others resolved |
| Related tasks, none | empty array, `out_Count` 0, no exception |

---

Sources for the API behaviour cited above: [ServiceNow Table API — Washington DC](https://www.servicenow.com/docs/r/washingtondc/api-reference/rest-apis/c_TableAPI.html) · [Xanadu](https://www.servicenow.com/docs/r/xanadu/api-reference/rest-apis/c_TableAPI.html)
