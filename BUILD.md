# How to Build Custom Activities

The complete process, from empty folder to a package other people install — the same mechanism `the legacy library` uses.

---

## 1. The whole secret is one field

A UiPath **Library** and a UiPath **Process** are the same project type. One setting separates them:

```json
"designOptions": {
  "outputType": "Library"
}
```

Set that, and every workflow in the project becomes a drag-and-drop activity in anyone's Activities panel when they install your package. That is the entire mechanism. There is no SDK, no C# project, no Visual Studio, no `CodeActivity` class to inherit from.

> There *is* a separate C#/.NET route — the UiPath Activity Creator SDK — for activities that need custom design-time UI or wizards. You do not need it. Everything in `the legacy library` is the Library route.

---

## 2. Create the project

**Studio → New Project → Library**

| Field | Value |
|---|---|
| Name | `Intellika.Automation` |
| Location | your repo folder |
| Language | C# |
| Compatibility | Windows (or Cross-platform, if your robots are Linux) |

Studio creates `project.json` with `"outputType": "Library"` already set.

**Name it like a NuGet package**, because that is what it becomes. `Company.Area` — `Intellika.Automation`, `Intellika.ServiceNow`. Not `MyLibrary`, not `Utils`. The name appears in every consumer's dependency list forever.

---

## 3. Build an activity

Each activity is one `.xaml` file.

1. **Right-click the project → Add → Sequence.** Name it `Record.Create.xaml`.
2. **Open the Arguments panel** (bottom of the designer) and define the contract: name, direction, type, default, **description**.
3. **Build the logic** on the canvas.
4. **Save.**

That is it. On publish, this becomes an activity called "Record.Create" that anyone can drag into their workflow.

The argument names you type here are the argument names every consumer sees forever. Get them right the first time — see `00_STANDARDS.md` §3.

---

## 4. Make it look professional

This is what separates a library people like using from one they tolerate. Two mechanisms.

### 4a. Activity Layout (the UI)

**Right-click the `.xaml` file → Activity Layout.**

That dialog sets:

| Setting | Effect |
|---|---|
| **Display Name** | What appears in the Activities panel |
| **Tooltip** | Hover text on the activity |
| **Color** | The activity's accent colour |
| **Icon** | A 24×24 SVG |
| **Per-argument: Category** | Groups properties into collapsible sections |
| **Per-argument: Tooltip** | Hover text in the Properties panel |
| **Per-argument: Widget** | The editor control — Toggle, Dropdown, Number, Dictionary… |
| **Per-argument: Is Principal** | Shows the argument on the collapsed activity card |

When you save, Studio writes a **`<workflow>.xaml.json`** sidecar next to the workflow.

### 4b. Editing the sidecar directly

The dialog is slow for 10 arguments. The `.xaml.json` is plain JSON and you can edit it in VS Code — which is why the files in this repo already exist, fully filled in.

```
Activities/ServiceNow/Record.Create.xaml        ← logic (you build this)
Activities/ServiceNow/Record.Create.xaml.json   ← appearance (already written)
Activities/ServiceNow/Record.Create.xaml.svg    ← icon (already written)
```

**The sidecar's shape:**

```json
{
  "DisplayName": "Create Record",
  "Tooltip": "Creates a record in a ServiceNow table.",
  "HelpLink": null,
  "Color": "#7AAC99",
  "OriginalIconFileName": "Record.Create.xaml.svg",
  "Arguments": [
    {
      "Name": "in_Table",
      "DisplayName": "Table",
      "Category": null,
      "Tooltip": "The ServiceNow table to act on.",
      "Placeholder": null,
      "Widget": "Dropdown",
      "IsRequired": true,
      "IsPrincipal": true,
      "ArgumentType": 0,
      "DataSourceItems": ["incident", "task", "change_request"]
    }
  ]
}
```

**Field reference:**

| Field | Notes |
|---|---|
| `DisplayName` | Activity name in the panel. Never leave an argument's `DisplayName` as its raw `in_Foo` name. |
| `Tooltip` | Never `null` on a public activity. This is the only documentation most consumers read. |
| `Color` | Hex. Use one per family — see §6. |
| `OriginalIconFileName` | Filename of the SVG sitting beside the workflow. |
| `Widget` | `TextComposer`, `Toggle`, `Number`, `Dropdown`, `RadioGroup`, `StringArray`, `Dictionary`, `Datetime`, `Connection` |
| `IsRequired` | Studio flags the activity as unconfigured if empty. **Meaningless on Out arguments** — leave `false`. |
| `IsPrincipal` | `true` shows it on the collapsed card. Reserve for the 2–3 that matter, **including the main output**. |
| `ArgumentType` | `0` for normal arguments. `1` for an Integration Service `Connection`. |
| `DataSourceItems` | The list for `Dropdown`/`RadioGroup`. **A Dropdown with `null` here renders empty — always a defect.** |

> `Widget` and `Tooltip` behaviour is documented in the community thread linked at the bottom; `Color` and `OriginalIconFileName` are not in official docs but are used throughout `the legacy library` and work. If a field misbehaves on your Studio version, open Activity Layout once and let Studio rewrite the file.

**Caution:** Studio rewrites the sidecar when you use Activity Layout. Edit by hand *or* through the dialog on any given activity — mixing them loses hand edits.

---

## 5. Public vs private

**Everything is public unless you say otherwise.** Forget this and your internal helpers appear in every consumer's Activities panel.

```json
"libraryOptions": {
  "includeOriginalXaml": false,
  "privateWorkflows": [
    "Snippets/Retry.xaml",
    "Snippets/Http.Core.xaml",
    "Snippets/Mail.Body.Compose.xaml"
  ]
}
```

**Convention in this library:** anything under `Snippets/` is private, anything under `Activities/` is public. The folder tells you the visibility, so nobody opens `project.json` to find out.

`includeOriginalXaml: false` is commonly described as shipping compiled workflows only. **Verify that claim against your own package before relying on it.** Inspecting a `.nupkg` published with it set to `false` showed the compiled assemblies in `lib/net8.0-windows7.0/` *and* the source `.xaml` still present under `content/Activities/`. A `.nupkg` is a zip — open yours and look:

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("path\to\Your.Package.1.0.0.nupkg")
$zip.Entries | Select-Object FullName, Length
$zip.Dispose()
```

Treat the published package as readable by anyone who can install it, and keep secrets out of workflows and descriptors on that basis — not on the basis of a flag.

---

## 6. Colour and icon

Colour carries information. Pick per family and keep it:

| Family | Colour |
|---|---|
| Core (config, logging) | `#11AAAA` |
| Orchestrator & Queue | `#FA4616` |
| Microsoft (Graph, Outlook, SharePoint) | `#0078D4` |
| ServiceNow | `#7AAC99` |
| HTTP | `#5B6CFF` |
| File | `#8A8F98` |
| **Destructive** | **`#E44949`** |
| Security | `#6B4FBB` |

One reserved colour for destructive operations is the highest-value convention here. `the legacy library` got that right with `Delete All Files` and then used seven other colours, four activities with none, and two near-identical yellows for unrelated things.

Icons are 24×24 SVG. Keep `viewBox="0 0 24 24"`, use `currentColor` for strokes so the icon inherits the accent.

---

## 7. Test

```
Tests/TC-Record.Create.xaml
.variations/Record.Create.json
```

A library activity is consumed by processes you will never see. Install `UiPath.Testing.Activities`, write one `TC-` test case per public activity, drive it from a JSON variation file, and run the suite before every publish.

Register test cases in `project.json`:

```json
"fileInfoCollection": [
  {
    "editorId": "TestCaseEditor",
    "fileName": "Tests/TC-Record.Create.xaml",
    "testCaseId": "...",
    "testCaseType": "TestCase"
  }
]
```

An untested library activity is a defect distributed to every process that uses it.

---

## 8. Publish

**Design → Publish**

| Target | When |
|---|---|
| Orchestrator Libraries feed | normal |
| Custom NuGet feed (Artifactory, Azure Artifacts) | enterprise |
| Local folder | testing |

Version strictly — this is a published API:

| Change | Bump |
|---|---|
| New activity, or new **optional** argument | Minor · 1.3.0 → 1.4.0 |
| Bug fix, no contract change | Patch · 1.3.0 → 1.3.1 |
| Renamed/removed argument, changed type, new **required** argument | **Major · 1.3.0 → 2.0.0** |

A major bump means every consuming process must be opened, updated, retested, redeployed. Design the contract properly and you rarely pay it.

**Pre-release tags** (`1.1.0-alpha.1`) for anything not production-ready. Never let a consumer pin an alpha in production — set the dependency **Runtime Rule: Strict** so the exact tested version runs.

**Write release notes every time.**

---

## 9. Consume

In a process: **Manage Packages → your feed → install `Intellika.Automation`.**

Your activities appear in the Activities panel under the package name, grouped by folder.

**Updating:** Manage Packages shows available versions. Installed `1.0.0`, available `1.2.0` → Update → **retest**. A library update changes code running in production; it is a release, not a refresh.

---

## 10. The checklist before every publish

1. Every public activity has a non-null header `Tooltip`
2. Every argument has a non-null `Tooltip`
3. No argument's `DisplayName` is still `in_Foo`
4. Every `Dropdown` has `DataSourceItems`
5. Every private helper is listed in `privateWorkflows` — **including every `TC-` test case.** Registering a workflow as a test case in `fileInfoCollection` does not hide it; `the legacy library` ships two test cases as public activities because of exactly this.
6. No hard-coded URLs, paths, hostnames, mailboxes, safe names or tenants — anywhere, **including tooltips and placeholders**
7. No placeholder contains a real credential location or a test value like `"This is a test"`
8. Credentials are `SecureString`, never `String`
9. Every network call has a timeout
10. All test cases pass
11. Version bumped correctly; release notes written

Numbers 6 and 7 exist because `the legacy library` ships a CyberArk safe name, two vault hostnames, a SharePoint tenant, two service-account addresses and the string `"This is a test - testing"` in its published contracts.

---

Sources: [UiPath Community — `.xaml.json` for custom libraries](https://forum.uipath.com/t/regarding-activity-name-xaml-json-files-for-custom-library-projects/5708863) · [UiPath SDK — Customizing Properties](https://docs.uipath.com/sdk/other/latest/developer-guide/customizing-properties)
