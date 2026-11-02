# Activity Spec — `Integration/Outlook/Mail.Send`

**Package path:** `Activities/Integration/Outlook/Mail.Send.xaml`
**Visibility:** Public
**Display name:** Send Email
**Tooltip:** Sends an email through Outlook 365, falling back to SMTP if the primary channel fails.
**Color:** `#0078D4` · **Icon:** `outlook.svg`

Replaces a 15-argument `Send Email v2`. Keeps its best idea — the SMTP fallback — and fixes how it is wired.

---

## 1. The fallback is the point

The original's header tooltip reads: *"If unable to send mail via O365 then it will send mail via SMTP."*

That is good engineering. Outlook 365 has outages, connections expire, Graph throttles. An automation that only notifies by O365 goes silent exactly when something has gone wrong — which is when the notification matters most. A second, independent channel is real resilience, and it is the only place in that library where anyone designed for degraded conditions.

Two things about the original's implementation defeat it.

### Both connections are required

```
Send_Email__Send_365_Mail        Connection  IsRequired: true
Send_SMTP_Email__Send_SMTP_Mail  Connection  IsRequired: true
```

A caller who wants O365 and has no SMTP relay cannot use the activity at all. The fallback is mandatory, which is a contradiction in terms — a fallback that must be configured is just a second dependency.

**Fix:** primary required, fallback optional. Empty fallback means no fallback, and a primary failure throws as it would anywhere else.

### Nothing reports which channel was used

The original returns nothing at all. So when the fallback fires, nobody finds out.

That is the most useful signal the activity can produce. The fallback firing means **O365 is degraded right now**. If three processes quietly fell back to SMTP this morning, somebody should know before the fourth one fails outright. Without an output, the first anyone hears of it is a different, worse incident.

**Fix:** `out_Channel` returns `Primary` or `Fallback`, and the fallback path logs at **Warn** — not Info. The mail went out; something is still wrong.

---

## 2. Arguments

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_Connection` | Connection | In | Connection (`ArgumentType: 1`) | — | Yes |
| 2 | `in_To` | String[] | In | StringArray | — | Yes |
| 3 | `in_Subject` | String | In | TextComposer | — | Yes |
| 4 | `in_Body` | String | In | TextComposer | — | Yes |
| 5 | `in_CC` | String[] | In | StringArray | Recipients | No |
| 6 | `in_BCC` | String[] | In | StringArray | Recipients | No |
| 7 | `in_Attachments` | String[] | In | StringArray | Optional | No |
| 8 | `in_Importance` | String | In | Dropdown | Optional | No |
| 9 | `in_FallbackConnection` | Connection | In | Connection (`ArgumentType: 1`) | Fallback | No |
| 10 | `out_Success` | Boolean | Out | Toggle | Output | — |
| 11 | `out_Channel` | String | Out | TextComposer | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Connection` | Outlook 365 connection from Integration Service. The primary send channel. | — |
| `in_To` | Recipients. At least one is required. | — |
| `in_Subject` | Subject line. | — |
| `in_Body` | Message body. HTML is accepted. | — |
| `in_CC` | CC recipients. | empty |
| `in_BCC` | BCC recipients. | empty |
| `in_Attachments` | Full paths of files to attach. | empty |
| `in_Importance` | Message importance. | `Normal` |
| `in_FallbackConnection` | SMTP connection used only when the primary send fails. Leave empty to disable the fallback — the primary failure then throws. | empty |
| `out_Success` | True when the message was accepted by either channel. | — |
| `out_Channel` | `Primary` or `Fallback`. Which channel actually delivered. | — |

**`in_Importance` DataSourceItems:** `["Low", "Normal", "High"]`

> The original declares `in_Importance` as a `Dropdown` with `DataSourceItems: null` — here and in `Reply To Email`. The consumer opens the dropdown and it is empty. A Dropdown without DataSourceItems is always a defect, and this one was copied before it was ever noticed.

### On the argument count

Nine inputs is above the seven in the standards. That rule is about **cohesion**, not arithmetic: an activity is too big when its arguments serve more than one job. All nine here describe one message being sent once. Splitting them would mean a builder object, which is worse ergonomics in a Properties panel than one more optional field.

What was removed below was removed because it belonged elsewhere, not to hit a number.

---

## 3. Config keys

```
Constants sheet:
  Mail.DisclaimerText   = This message was sent by an automated process. Replies are not monitored.
  Mail.ContactEmail     = automation-support@example.com
  Mail.ContactLine      = Questions about this message: {ContactEmail}

Settings sheet:
  Mail.FromName         = Automation Service
  Mail.FromAddress      = no-reply@example.com
  Mail.TimeoutSeconds   = 30
```

`Mail.FromName` and `Mail.FromAddress` apply to the SMTP path only. O365 sends as the connected mailbox and ignores both.

---

## 4. Logic

```
Try
  1. Validate
       in_Connection null  -> ArgumentException
       in_To empty         -> ArgumentException("At least one recipient is required.")
       in_Subject empty    -> ArgumentException("Subject cannot be empty.")

  2. Verify attachments BEFORE sending
       For each path in in_Attachments
         Not File.Exists -> throw FileNotFoundException naming the path

  3. str_Body = Invoke Snippets/Mail.Body.Compose(in_Body, in_Config)

  4. Primary
       Try
         Send Mail (O365)
           Connection = in_Connection
           To / CC / BCC / Subject / Body / Attachments / Importance
           Timeout    = Config("Mail.TimeoutSeconds")
         out_Channel = "Primary"
         out_Success = True
         Log Info: "Mail sent via O365 to " & in_To.Length & " recipient(s). Subject: " & in_Subject

       Catch ex_Primary As Exception
         If in_FallbackConnection Is Nothing
           Log Error: "O365 send failed and no fallback is configured - " & ex_Primary.Message
           Rethrow

         Log Warn: "O365 send FAILED, falling back to SMTP - " & ex_Primary.Message

         Try
           Send SMTP Mail
             Connection = in_FallbackConnection
             From       = Config("Mail.FromAddress"), display Config("Mail.FromName")
             To / CC / BCC / Subject / Body / Attachments
           out_Channel = "Fallback"
           out_Success = True
           Log Warn: "Mail sent via SMTP FALLBACK. Subject: " & in_Subject &
                     " | primary failure: " & ex_Primary.Message

         Catch ex_Fallback As Exception
           Log Error: "BOTH channels failed. O365: " & ex_Primary.Message &
                      " | SMTP: " & ex_Fallback.Message
           Throw new Exception(
             "Send failed on both channels. O365: " & ex_Primary.Message &
             " | SMTP: " & ex_Fallback.Message, ex_Fallback)

Catch ex As Exception
  out_Success = False
  out_Channel = ""
  Rethrow
```

### Why these specifics

- **Attachments verified before the first send attempt.** Otherwise a missing file fails the primary, triggers the fallback, and fails that too — producing a log that reads like an O365 outage when the real cause is a typo in a path.
- **The fallback logs at Warn, not Info.** The mail went out, so it is not an error. But a degraded primary is something a human should see. Alert on `Stage="Mail.Send" AND level=WARN` and you get told the first time it happens instead of the tenth.
- **The primary exception is carried into the final message.** When both channels fail, the O365 error is the one that explains what started it. Losing it leaves only "SMTP relay refused", which is the symptom, not the cause.
- **No fallback configured means rethrow.** Silence is not a safe default for a notification that did not send.

---

## 5. What was dropped, and why

### `in_FromName`, `in_FromAddress` — arguments that silently do nothing

Both apply only to the SMTP path. O365 sends as the connected mailbox. Nothing in the original's contract says so — both have `Tooltip: null` — so a developer sets them, tests against O365, sees no effect, and has no way to find out why.

**Replacement:** `Mail.FromName` / `Mail.FromAddress` in config. The SMTP identity is an environment property, not a per-call decision. One place, set once, documented.

### `in_IncludeDisclaimer`, `in_IncludeContactInfo`, `in_ContactEmail`

Same treatment as the Reply and Forward activities — see `Integration.Outlook.md` section 2. Three arguments become three config keys, and `automation@example.com` stops being baked into a shared library. Note it appears in this activity **twice**: once in a tooltip and once as a Placeholder.

### `in_TimeoutMS` — milliseconds, with a null tooltip

Moves to `Mail.TimeoutSeconds` in config, in seconds, to match every other timeout in the library.

### `v2` in the activity name

Version belongs in the package version, not the activity name. `Send Email v2` implies `Send Email` still exists and is still published, leaving consumers to guess which is current — and leaving whoever maintains it to fix bugs in two places. Semantic versioning on the package, one activity name.

---

## 6. Test cases

| Case | Expected |
|---|---|
| Primary succeeds | `out_Channel = "Primary"`, no Warn logged |
| Primary fails, fallback configured | `out_Channel = "Fallback"`, Warn logged carrying the primary error |
| Primary fails, no fallback | throws, error names the absent fallback |
| Both fail | throws, message carries **both** errors |
| No recipients | `ArgumentException`, nothing sent |
| Empty subject | `ArgumentException`, nothing sent |
| Attachment path missing | `FileNotFoundException` before the primary is attempted |
| Importance = High | header present on the delivered message |
| Disclaimer configured | appended once |
| SMTP path | From name and address taken from config |
| O365 path | config From values correctly ignored |
| Log inspection after fallback | a Warn exists naming the primary failure |
