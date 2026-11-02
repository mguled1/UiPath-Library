# Activity Spec — `Integration/SharePoint/File.Download`

**Package path:** `Activities/Integration/SharePoint/File.Download.xaml`
**Visibility:** Public
**Display name:** Download SharePoint File
**Tooltip:** Finds a file in a SharePoint site or Teams document library and downloads it.
**Color:** `#0078D4` · **Icon:** `sharepoint.svg`

Replaces a 7-argument `DownloadFile` that returns nothing.

---

## 1. Arguments

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_SiteUrl` | String | In | TextComposer | — | Yes |
| 2 | `in_FileName` | String | In | TextComposer | — | Yes |
| 3 | `in_SavePath` | String | In | TextComposer | — | Yes |
| 4 | `in_FolderPath` | String | In | TextComposer | Location | No |
| 5 | `in_DriveName` | String | In | TextComposer | Location | No |
| 6 | `in_Overwrite` | Boolean | In | Toggle | Options | No |
| 7 | `in_TimeoutSeconds` | Int32 | In | Number | Options | No |
| 8 | `out_FilePath` | String | Out | TextComposer | Output | — |
| 9 | `out_Found` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_SiteUrl` | Full SharePoint URL of the site or team, copied from the browser. For example `https://contoso.sharepoint.com/teams/FinanceAutomation`. | — |
| `in_FileName` | Exact file name including extension. | — |
| `in_SavePath` | Local folder or full file path to download to. A folder keeps the original name. | — |
| `in_FolderPath` | Folder within the document library. Leave empty for the root. | root |
| `in_DriveName` | Document library name when the file is not in the default library. | default |
| `in_Overwrite` | Replace an existing local file. When false, an existing file causes an exception. | `False` |
| `in_TimeoutSeconds` | Timeout for the download. | `120` |
| `out_FilePath` | Full local path of the downloaded file. Empty when not found. | — |
| `out_Found` | False when no matching file exists at that location. | — |

---

## 2. One URL instead of two arguments

The original takes `in_TeamName` plus `in_TeamsOrSites` (a Dropdown of `Sites` / `Teams`), and both tooltips tell the user to go and read the SharePoint URL:

> `in_TeamName`: "Should match the name in the SharePoint URL. Example: `https://…/teams/YourTeam`"
> `in_TeamsOrSites`: "Check the URL, e.g. `https://…/teams/YourTeam`"

So the user opens SharePoint, copies nothing, reads the URL, mentally splits it into two parts, and types both into separate boxes — where the activity reassembles them into the URL they were looking at.

**Replacement:** take the URL. Paste what is in the address bar. `/sites/` versus `/teams/` is already in the string, so the Dropdown has nothing left to decide.

This also removes a failure mode the original cannot report: pick the wrong Dropdown value and you get a 404 against a path that was never checked, with no indication which of the two arguments was wrong.

> In fairness, `in_TeamsOrSites` is the only Dropdown in that library with populated `DataSourceItems`. `in_Importance` in both `Reply To Email` and `Send Email v2` declares `Widget: "Dropdown"` with `DataSourceItems: null` and renders empty. Whoever wrote this one knew how it was supposed to work.

---

## 3. Outputs, because the activity searches

The original returns nothing. Its own tooltip says it *"searches for a file"* — and a search can come back empty. The caller has no way to learn that it did.

What that costs in practice: a process downloads a config workbook from SharePoint, the file was renamed last week, the activity finds nothing, the process carries on and reads a stale local copy — or no copy — and either way reports success. The failure surfaces days later as wrong data, with nothing in the logs pointing at the download.

```
out_Found     False when nothing matched. The caller decides whether that is fatal.
out_FilePath  Where the file actually landed, so the next activity does not
              have to rebuild the path from in_SavePath and in_FileName.
```

`out_FilePath` matters more than it looks. Without it, every caller reconstructs `Path.Combine(in_SavePath, in_FileName)` by hand — which is wrong the moment `in_SavePath` is already a full file path, or SharePoint returns a name differing in case.

**Not found is not an exception.** "The file is not there yet" is a normal state for a process polling a drop folder. Returning `out_Found = False` lets the caller loop and wait. A permissions failure or a bad URL *does* throw.

---

## 4. Logic

```
Try
  1. Validate
       in_SiteUrl empty   -> ArgumentException
       in_FileName empty  -> ArgumentException
       in_SavePath empty  -> ArgumentException
       in_SiteUrl is not a well-formed absolute URI -> ArgumentException naming the value

  2. Resolve the drive
       Graph: /sites/{hostname}:{site-path}
       in_DriveName empty -> default document library
       else               -> match the named library, case-insensitive
       no match           -> throw, message lists the libraries that do exist

  3. Locate the file
       path = in_FolderPath empty ? "/" : in_FolderPath
       List children at path, match in_FileName case-insensitively
       no match ->
         out_Found    = False
         out_FilePath = ""
         Log Info: "No file named " & in_FileName & " at " & in_SiteUrl & path
         exit without throwing

  4. Resolve the destination
       in_SavePath is an existing directory
         -> destination = Path.Combine(in_SavePath, actual name from SharePoint)
       else
         -> destination = in_SavePath
       create the parent directory when absent

       destination exists AndAlso Not in_Overwrite
         -> throw IOException naming the file and pointing at in_Overwrite

  5. Download to destination with in_TimeoutSeconds
       out_FilePath = destination
       out_Found    = True
       Log Info: "Downloaded " & name & " (" & size & " bytes) to " & destination

Catch ex As Exception
  out_Found    = False
  out_FilePath = ""
  Log Error: "SharePoint download failed for " & in_FileName &
             " at " & in_SiteUrl & " - " & ex.Message
  Rethrow
```

### Why these specifics

- **Use the name SharePoint returns, not `in_FileName`.** SharePoint preserves the stored casing. Matching case-insensitively but saving under the user's spelling produces a local file whose name differs from the source, which breaks the next step that looks for it.
- **The "wrong library" error lists the real ones.** `Drive 'Documents2' not found. Available: Documents, Shared Documents, Archive` turns a ten-minute hunt into a one-second fix.
- **Overwrite is explicit.** The original does not say what happens when the file already exists locally, so the answer is whatever the underlying activity happens to do — silently replacing a file one run and failing the next.
- **Log the byte count.** A zero-byte download that technically succeeded is a real failure mode, and the size in the log is how anyone notices.

---

## 5. What was dropped, and why

### `in_UseUAT` — the environment toggle, for the fifth time

`"Set True to use AzureApp Token UAT"`.

Counting across the library:

| Activity | Argument | Vocabulary |
|---|---|---|
| Initialize | `in_Environment` | `PROD_Cloud` / `DEV_Cloud` (tooltip says `DEV`/`UAT`/`PROD`) |
| Initialize | `in_DevMode` | Dev / not-Dev |
| Initialize | `in_UseLocalConfig` | undocumented |
| GetToken | `in_UseDev` | PROD / UAT |
| DownloadFile | `in_UseUAT` | UAT |

Five arguments, five names, three vocabularies, one concept — and no two activities agree on what the environments are called. A developer wiring a process that uses all three has to get five unrelated switches consistent by hand, with nothing checking that they are.

**Replacement:** none, in any activity. The robot runs in an Orchestrator folder; that folder's config says which Entra app registration to use; `Graph.Token.Get` resolves it. Dev robots read dev config. Nothing to toggle, nothing to keep in sync, nothing to get wrong.

### `in_TeamName`, `in_TeamsOrSites`

Collapsed into `in_SiteUrl`. See section 2.

### The hard-coded tenant

`https://contoso.sharepoint.com/teams/YourTeam` appears in two tooltips. Examples in a shared library use a placeholder tenant — `contoso.sharepoint.com` — so nobody adopting the library inherits another organisation's URL as the documented default.

---

## 6. Test cases

| Case | Expected |
|---|---|
| File in root | downloaded, `out_Found` true, `out_FilePath` set |
| File in a subfolder | found via `in_FolderPath` |
| Named document library | found via `in_DriveName` |
| File absent | `out_Found` false, no exception, Info logged |
| Library name wrong | exception listing the libraries that exist |
| Malformed `in_SiteUrl` | `ArgumentException` naming the value |
| `in_SavePath` is a directory | saved under SharePoint's own file name |
| `in_SavePath` is a file path | saved exactly there |
| Destination exists, Overwrite false | `IOException` pointing at `in_Overwrite` |
| Destination exists, Overwrite true | replaced |
| Parent directory missing | created |
| Casing differs from SharePoint | matched, saved under SharePoint's casing |
| No permission on the site | throws, message names the site |
