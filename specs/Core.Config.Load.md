# Activity Spec — `Core/Config.Load`

**Package path:** `Activities/Core/Config.Load.xaml`
**Visibility:** Public
**Display name:** Load Config
**Tooltip:** Loads a configuration workbook into a dictionary, from a local file or an Orchestrator storage bucket.
**Icon color:** `#11AAAA`

Replaces the `Initialize` pattern. 15 arguments down to 7, with every removal justified in section 5.

---

## 1. Arguments

| # | Name | Type | Direction | Widget | Category | Required | Principal |
|---|---|---|---|---|---|---|---|
| 1 | `in_Source` | String | In | RadioGroup | — | Yes | Yes |
| 2 | `in_ConfigPath` | String | In | TextComposer | — | Yes | Yes |
| 3 | `in_SheetNames` | String[] | In | StringArray | Advanced | No | No |
| 4 | `in_BucketName` | String | In | TextComposer | Storage Bucket | No | No |
| 5 | `in_BucketFolder` | String | In | TextComposer | Storage Bucket | No | No |
| 6 | `out_Config` | Dictionary(String, Object) | Out | Dictionary | Output | — | Yes |
| 7 | `out_AssetNames` | Dictionary(String, String) | Out | Dictionary | Output | — | No |

### Descriptions

| Argument | Description (becomes the Properties tooltip) |
|---|---|
| `in_Source` | Where the config workbook lives. `LocalFile` reads from disk. `StorageBucket` downloads it from an Orchestrator storage bucket first. |
| `in_ConfigPath` | Path to the config workbook. A full local path when Source is LocalFile; the file name inside the bucket when Source is StorageBucket. |
| `in_SheetNames` | Sheets to load as key/value settings. Defaults to `{"Settings", "Constants"}`. The sheet named `Assets` is always read separately into `out_AssetNames`. |
| `in_BucketName` | Orchestrator storage bucket holding the config workbook. Required when Source is StorageBucket. |
| `in_BucketFolder` | Orchestrator folder the storage bucket belongs to, e.g. `Finance/Production`. Leave empty to use the robot's current folder. |
| `out_Config` | All key/value pairs from the settings sheets, merged into one dictionary. |
| `out_AssetNames` | Logical name to Orchestrator asset name mapping, read from the `Assets` sheet. |

**Default for `in_SheetNames`:** `new String[] { "Settings", "Constants" }`

**`in_Source` DataSourceItems:** `["LocalFile", "StorageBucket"]`

---

## 2. Config workbook structure

Three sheets. Column A is the key, column B is the value, column C is a comment column the activity ignores.

| Sheet | Purpose |
|---|---|
| `Settings` | Anything that differs per environment — URLs, paths, timeouts, retry counts, recipients |
| `Constants` | Values identical in every environment |
| `Assets` | Logical name to Orchestrator asset name |

`Settings` and `Constants` merge into `out_Config`. On a duplicate key, `Settings` wins and the activity logs a Warn naming the key.

### Keys every process should define

| Key | Sheet | Example |
|---|---|---|
| `ProcessName` | Constants | `InvoiceProcessing` |
| `TempPath` | Settings | `%TEMP%\InvoiceProcessing` |
| `LogPath` | Settings | `%TEMP%\InvoiceProcessing\Logs` |
| `MaxRetryCount` | Settings | `3` |
| `RetryDelaySeconds` | Settings | `2` |
| `TimeoutSeconds` | Settings | `30` |

`TempPath` and `LogPath` are config keys, not activity outputs. See section 5.

---

## 3. Logic

```
Try
  1. Validate
       in_ConfigPath empty                      -> throw ArgumentException
       in_Source = "StorageBucket" and
         in_BucketName empty                    -> throw ArgumentException

  2. Resolve the workbook
       If in_Source = "StorageBucket"
         str_LocalPath = Path.Combine(Path.GetTempPath(),
                                      Guid.NewGuid().ToString("N"),
                                      Path.GetFileName(in_ConfigPath))
         Download Storage File
           BucketName = in_BucketName
           Folder     = in_BucketFolder  (empty -> current folder)
           BucketPath = in_ConfigPath
           LocalPath  = str_LocalPath
         bool_IsTempCopy = True
       Else
         If Not File.Exists(in_ConfigPath) -> throw FileNotFoundException
         str_LocalPath   = in_ConfigPath
         bool_IsTempCopy = False

  3. Read the settings sheets
       out_Config = new Dictionary(Of String, Object)(StringComparer.OrdinalIgnoreCase)
       For Each str_Sheet In in_SheetNames
         Read Range -> dt_Sheet (AddHeaders = False)
         For Each row In dt_Sheet
           skip when column A is blank
           when the key already exists -> Log Warn, overwrite
           out_Config(A) = B
       Log Info: out_Config.Count & " settings loaded from " &
                 String.Join(", ", in_SheetNames)

  4. Read the Assets sheet
       out_AssetNames = new Dictionary(Of String, String)(StringComparer.OrdinalIgnoreCase)
       If the workbook contains a sheet named "Assets"
         same key/value loop
       Else
         Log Info: "No Assets sheet found; out_AssetNames is empty."

Catch ex As Exception
  Log Error: "Config.Load failed for " & in_ConfigPath & " - " & ex.Message
  Rethrow

Finally
  If bool_IsTempCopy AndAlso File.Exists(str_LocalPath)
    delete str_LocalPath and its temp directory
```

### Why these specifics

- **`StringComparer.OrdinalIgnoreCase`** — `Config("timeoutseconds")` and `Config("TimeoutSeconds")` resolve to the same entry. Removes an entire class of silent lookup failures.
- **`AddHeaders = False`** — the first row is data, not a header. A config sheet has no header row.
- **GUID temp directory** — two robots loading config on the same machine never collide.
- **Cleanup in Finally** — the downloaded copy is removed even when parsing throws.
- **Rethrow, not swallow** — a process that cannot read its config must not continue with an empty dictionary.

---

## 4. `Config.Load.xaml.json` sidecar

```json
{
  "DisplayName": "Load Config",
  "Tooltip": "Loads a configuration workbook into a dictionary, from a local file or an Orchestrator storage bucket.",
  "HelpLink": null,
  "Color": "#11AAAA",
  "OriginalIconFileName": "Config.Load.xaml.svg",
  "Arguments": [
    {
      "Name": "in_Source",
      "DisplayName": "Source",
      "Category": null,
      "Tooltip": "Where the config workbook lives. LocalFile reads from disk. StorageBucket downloads it from an Orchestrator storage bucket first.",
      "Placeholder": null,
      "Widget": "RadioGroup",
      "IsRequired": true,
      "IsPrincipal": true,
      "ArgumentType": 0,
      "DataSourceItems": ["LocalFile", "StorageBucket"]
    },
    {
      "Name": "in_ConfigPath",
      "DisplayName": "Config Path",
      "Category": null,
      "Tooltip": "Path to the config workbook. A full local path when Source is LocalFile; the file name inside the bucket when Source is StorageBucket.",
      "Placeholder": null,
      "Widget": "TextComposer",
      "IsRequired": true,
      "IsPrincipal": true,
      "ArgumentType": 0,
      "DataSourceItems": null
    },
    {
      "Name": "in_SheetNames",
      "DisplayName": "Sheet Names",
      "Category": "Advanced",
      "Tooltip": "Sheets to load as key/value settings. Defaults to Settings and Constants. The sheet named Assets is always read separately into Asset Names.",
      "Placeholder": null,
      "Widget": "StringArray",
      "IsRequired": false,
      "IsPrincipal": false,
      "ArgumentType": 0,
      "DataSourceItems": null
    },
    {
      "Name": "in_BucketName",
      "DisplayName": "Bucket Name",
      "Category": "Storage Bucket",
      "Tooltip": "Orchestrator storage bucket holding the config workbook. Required when Source is StorageBucket.",
      "Placeholder": null,
      "Widget": "TextComposer",
      "IsRequired": false,
      "IsPrincipal": false,
      "ArgumentType": 0,
      "DataSourceItems": null
    },
    {
      "Name": "in_BucketFolder",
      "DisplayName": "Bucket Folder",
      "Category": "Storage Bucket",
      "Tooltip": "Orchestrator folder the storage bucket belongs to, e.g. Finance/Production. Leave empty to use the robot's current folder.",
      "Placeholder": null,
      "Widget": "TextComposer",
      "IsRequired": false,
      "IsPrincipal": false,
      "ArgumentType": 0,
      "DataSourceItems": null
    },
    {
      "Name": "out_Config",
      "DisplayName": "Config",
      "Category": "Output",
      "Tooltip": "All key/value pairs from the settings sheets, merged into one dictionary.",
      "Placeholder": null,
      "Widget": "Dictionary",
      "IsRequired": false,
      "IsPrincipal": true,
      "ArgumentType": 0,
      "DataSourceItems": null
    },
    {
      "Name": "out_AssetNames",
      "DisplayName": "Asset Names",
      "Category": "Output",
      "Tooltip": "Logical name to Orchestrator asset name mapping, read from the Assets sheet.",
      "Placeholder": null,
      "Widget": "Dictionary",
      "IsRequired": false,
      "IsPrincipal": false,
      "ArgumentType": 0,
      "DataSourceItems": null
    }
  ]
}
```

Save it next to the workflow as `Config.Load.xaml.json`, with a 24×24 SVG named `Config.Load.xaml.svg`.

---

## 5. What was dropped, and why

Eight arguments removed. Each one for a reason, not for brevity.

### `in_Environment`, `in_DevMode`, `in_UseLocalConfig` — three switches over one decision

These are three independent controls over the same thing, and nothing stops them contradicting each other. `Environment = PROD_Cloud` with `DevMode = True` has no defined behavior — you would have to read the implementation to find out what wins, and whoever wrote it probably never decided.

Two further problems in the original:

- The `in_Environment` tooltip says `(DEV, UAT, PROD)` while the actual options are `PROD_Cloud` and `DEV_Cloud`. A consumer reads the tooltip, looks for UAT, and does not find it.
- `in_UseLocalConfig` has a null tooltip, no category, no widget, and a display name identical to the argument name. It was added late and never finished — which is how a third switch over the same decision comes to exist in the first place.

**Replacement:** one `in_Source` with two values. Environment is not a code path — it is determined by which Orchestrator folder the robot runs in and which config workbook sits in that folder. The same package runs in dev and prod with no argument change. That is the whole point of config-driven design.

### `in_ProjectName` — path construction does not belong in a library

The original derives paths in the shape `D:\UiPath\...`. A library that assumes a `D:` drive exists works until the first machine that does not have one. Path layout is the caller's decision; the library takes a path and reads it.

### `io_ConfigPath` — In/Out with no reason to be

In/Out means the activity writes back into the caller's variable. A consumer reading `Config Path` in the Properties panel has no reason to expect their variable to change. If a resolved path needs returning, that is a separate Out argument with its own name.

### `out_TempPath`, `out_LogPath` — outputs that should be config keys

A config loader returning paths means the paths are computed inside the library, so changing the convention means republishing it and updating every consumer. Put `TempPath` and `LogPath` in the `Settings` sheet and they are `Config("TempPath")` — changeable by editing a spreadsheet.

### `in_AssetSheet` — convention over configuration

An argument that exists so the Assets sheet can be called something other than `Assets`. Nobody uses it. The sheet is called `Assets`.

### `out_AssetFolders` — mapping that belongs with the asset

Two parallel dictionaries keyed the same way drift apart the moment someone updates one and not the other. If an asset needs a folder, qualify it in the `Assets` sheet value: `Finance/Production:InvoiceApiCredential`.

---

## 6. Test cases

`Tests/TC-Config.Load.xaml`, data-driven from `.variations/Config.Load.json`.

| Case | Input | Expected |
|---|---|---|
| Local, happy path | valid path, both sheets | `out_Config` populated, no exception |
| Missing file | path to nothing | `FileNotFoundException`, message names the path |
| Empty path | `""` | `ArgumentException` |
| Bucket without name | Source=StorageBucket, no bucket | `ArgumentException` |
| No Assets sheet | workbook with Settings only | empty `out_AssetNames`, Info logged, no throw |
| Duplicate key | same key in both sheets | Settings value wins, Warn logged naming the key |
| Blank rows | sheet with gaps | blanks skipped, count correct |
| Case-insensitive read | `Config("timeoutseconds")` | resolves |
| Temp cleanup | bucket download then parse failure | temp file deleted |
