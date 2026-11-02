# Activity Spec — `Integration/Outlook`

Outlook 365 mail actions over the UiPath Integration Service connection.

| Activity | File | Visibility |
|---|---|---|
| Reply To Email | `Activities/Integration/Outlook/Mail.Reply.xaml` | Public |
| Forward Email | `Activities/Integration/Outlook/Mail.Forward.xaml` | Public |
| *(shared)* Compose Body | `Snippets/Mail.Body.Compose.xaml` | **Private** |

Shared identity: color `#0078D4`, icon `outlook.svg`.

Replaces a Forward / Reply pair of 11 and 13 arguments. Both drop to 9, the duplicated body-composition block becomes one private snippet, and the hard-coded team mailbox moves to config.

---

## 1. The duplication problem this fixes

The original Forward and Reply activities are roughly 85% the same: identical connection argument, identical `Body Options` block (`IncludeDisclaimer`, `IncludeContactInfo`, `ContactEmail`), identical `Optional Email` block (`Attachments`, `NewSubject`, `CC`, `BCC`).

Duplicated logic in two published activities rots asymmetrically. Observed in the original:

- `in_Attachments` has the tooltip "An Enumerable of attachment paths." in Forward and `null` in Reply.
- Reply's argument tooltips still say "forward" — `in_EmailToReplyTo` is documented as "The email **to forward**", and `in_AddRecipients` / `in_AddCC` / `in_AddBCC` all describe "the **forwarded** email".
- Both carry the header tooltip "Uses o365 activities to **retrieve** emails from a mailbox", which describes neither activity. It belongs to Get Emails.

None of these are runtime failures. They are worse than that: they are wrong documentation shipped to every consumer, in the one place a developer looks before using an activity they have not used before.

**Fix:** the shared body composition lives in one private snippet. Each public activity documents only what is genuinely its own.

---

## 2. Body composition moves to config

Three arguments in the original control what gets appended to the body:

```
in_IncludeDisclaimer   Boolean  Toggle   (tooltip: null)
in_IncludeContactInfo  Boolean  Toggle   "Whether or not to include automation@example.com"
in_ContactEmail        String            "Contact email to use in the body."
```

Three problems:

1. **A specific mailbox is hard-coded into a shared library's tooltip.** Any team adopting the library inherits another team's address as the documented default.
2. **`in_IncludeDisclaimer` has a null tooltip.** It is a compliance control — it decides whether legal text is appended to outbound mail — and there is no indication anywhere in the contract of what text that is. Nobody can audit it from the activity.
3. **`IncludeContactInfo` + `ContactEmail` is a coupled pair.** If the toggle is on and the email is empty, behaviour is undefined, and the caller finds out in production.

**Replacement — config keys, zero arguments:**

```
Constants sheet:
  Mail.DisclaimerText  = This message was sent by an automated process. Replies are not monitored.
  Mail.ContactEmail    = automation-support@example.com
  Mail.ContactLine     = Questions about this message: {ContactEmail}
```

`Mail.Body.Compose` appends the disclaimer when `Mail.DisclaimerText` is non-empty, and the contact line when `Mail.ContactEmail` is non-empty. Empty means absent. One mechanism, no toggles, no coupled pairs, no undefined state — and changing the disclaimer is a spreadsheet edit rather than a library republish.

---

## 3. `Mail.Reply`

**Display name:** Reply To Email
**Tooltip:** Replies to an Outlook 365 message, optionally to all recipients.

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_Connection` | Connection | In | Connection (`ArgumentType: 1`) | — | Yes |
| 2 | `in_Message` | Message | In | — | — | Yes |
| 3 | `in_Body` | String | In | TextComposer | — | Yes |
| 4 | `in_ReplyAll` | Boolean | In | Toggle | — | No |
| 5 | `in_CC` | String[] | In | StringArray | Recipients | No |
| 6 | `in_BCC` | String[] | In | StringArray | Recipients | No |
| 7 | `in_Attachments` | String[] | In | StringArray | Optional | No |
| 8 | `in_Importance` | String | In | Dropdown | Optional | No |
| 9 | `out_Success` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Connection` | Outlook 365 connection from Integration Service. | — |
| `in_Message` | The message being replied to, as returned by Get Emails. | — |
| `in_Body` | Reply body. HTML is accepted. | — |
| `in_ReplyAll` | Reply to every recipient of the original rather than the sender alone. | `False` |
| `in_CC` | Additional CC recipients beyond those carried over. | empty |
| `in_BCC` | BCC recipients. | empty |
| `in_Attachments` | Full paths of files to attach. | empty |
| `in_Importance` | Message importance. | `Normal` |
| `out_Success` | True when Graph accepted the reply. | — |

**`in_Importance` DataSourceItems:** `["Low", "Normal", "High"]`

> The original declares `in_Importance` as `Widget: "Dropdown"` with `DataSourceItems: null`. That renders an empty dropdown — the consumer opens it and there is nothing to pick. A Dropdown without DataSourceItems is always a defect.

---

## 4. `Mail.Forward`

**Display name:** Forward Email
**Tooltip:** Forwards an Outlook 365 message to one or more recipients.

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_Connection` | Connection | In | Connection (`ArgumentType: 1`) | — | Yes |
| 2 | `in_Message` | Message | In | — | — | Yes |
| 3 | `in_To` | String[] | In | StringArray | — | Yes |
| 4 | `in_Comment` | String | In | TextComposer | — | No |
| 5 | `in_CC` | String[] | In | StringArray | Recipients | No |
| 6 | `in_BCC` | String[] | In | StringArray | Recipients | No |
| 7 | `in_Attachments` | String[] | In | StringArray | Optional | No |
| 8 | `in_Importance` | String | In | Dropdown | Optional | No |
| 9 | `out_Success` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Connection` | Outlook 365 connection from Integration Service. | — |
| `in_Message` | The message being forwarded, as returned by Get Emails. | — |
| `in_To` | Recipients of the forward. At least one is required. | — |
| `in_Comment` | Text placed above the forwarded content. | empty |
| `in_CC` | CC recipients. | empty |
| `in_BCC` | BCC recipients. | empty |
| `in_Attachments` | Additional files to attach beyond those already on the message. | empty |
| `in_Importance` | Message importance. | `Normal` |
| `out_Success` | True when Graph accepted the forward. | — |

**Subject is deliberately not an argument.** A forward carries `FW:` and a reply carries `RE:` — that is what the verbs mean, and mail clients thread on it. An activity that lets a caller replace the subject of a reply produces mail that breaks threading. A caller who genuinely needs an arbitrary subject is composing a new message, which is a different activity.

---

## 5. `Snippets/Mail.Body.Compose` (private)

| Argument | Type | Direction |
|---|---|---|
| `in_Body` | String | In |
| `in_Config` | Dictionary(String, Object) | In |
| `out_Body` | String | Out |

```
1. out_Body = in_Body

2. If Config has "Mail.ContactLine" and "Mail.ContactEmail", both non-empty
     line = Config("Mail.ContactLine").Replace("{ContactEmail}", Config("Mail.ContactEmail"))
     out_Body = out_Body & "<br/><br/>" & line

3. If Config has "Mail.DisclaimerText", non-empty
     out_Body = out_Body & "<br/><br/><hr/><i>" & Config("Mail.DisclaimerText") & "</i>"
```

Private, so it never appears in a consumer's activity panel. One implementation, so Reply and Forward cannot drift.

---

## 6. Logic — both activities

```
Try
  1. Validate
       in_Connection null        -> ArgumentException
       in_Message null           -> ArgumentException
       Forward: in_To empty      -> ArgumentException("At least one recipient is required.")
       Reply:   in_Body empty    -> ArgumentException("Reply body cannot be empty.")

  2. Verify attachments
       For each path in in_Attachments
         Not File.Exists -> throw FileNotFoundException naming the path
       (Fail before sending. A half-sent message with missing attachments cannot be recalled.)

  3. str_Body = Invoke Mail.Body.Compose(in_Body / in_Comment, in_Config)

  4. Reply:   Reply To Mail Message   (ReplyAll = in_ReplyAll)
     Forward: Forward Mail Message
       Connection  = in_Connection
       Message     = in_Message
       Body        = str_Body
       CC / BCC    = in_CC / in_BCC
       Attachments = in_Attachments
       Importance  = in_Importance

  5. out_Success = True
     Log Info: "<Reply|Forward> sent for message " & in_Message.Id &
               " to " & recipient count & " recipient(s)"

Catch ex As Exception
  out_Success = False
  Log Error: "<Reply|Forward> failed for message " & in_Message.Id & " - " & ex.Message
  Rethrow
```

**Why `out_Success` exists at all.** The original pair has no output of any kind. A process that forwards a message has no way to record that it happened — not in a ticket, not in a log field, not in a queue item. When someone asks three weeks later whether the notification went out, the answer is a shrug. One Boolean removes that.

**Why attachments are checked before sending.** Sending is irreversible. Validating paths first turns a partially-correct outbound email into a clean exception.

---

## 7. Test cases

| Case | Expected |
|---|---|
| Reply, minimal | sent, `out_Success` true |
| Reply all | every original recipient addressed |
| Reply, empty body | `ArgumentException` |
| Forward, no recipients | `ArgumentException` |
| Forward with attachments | all files attached |
| Attachment path missing | `FileNotFoundException` before anything is sent |
| Importance = High | header set on the delivered message |
| Disclaimer configured | appended once, not twice |
| Disclaimer key absent | body unchanged, no error |
| Contact line configured | `{ContactEmail}` substituted |
| Connection expired | exception naming the connection |
| Body contains HTML | rendered, not escaped |
