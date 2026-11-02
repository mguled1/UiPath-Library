# UiPath Library — a reusable activity library, and the standard behind it

A UiPath **Library** project plus the written design standard it was built from: 26 activities,
171 documented arguments, a composition map of how the activities chain together, and a
per-activity specification covering arguments, logic, validation rules and test cases.

This repository is as much about **how to design a library** as it is about the library itself.

---

## Why this exists

Most RPA teams accumulate a shared library rather than design one. It starts clean, then a
few years of delivery pressure later you find things like these — each one drawn from
auditing a real production library in daily use by a large team:

| What you find | Why it costs you |
|---|---|
| Seven different argument names for one Orchestrator folder concept | Nobody can learn the convention, because there isn't one |
| Several environment switches under three vocabularies | Environment is being treated as a code path instead of configuration |
| Bearer tokens returned as plain `String` | `excludedLoggedData` patterns don't match them, so they reach the logs |
| Test cases shipping inside the published API | A consumer eventually drags the wrong one |
| Requeue and retry-count split across two activities | The default path never increments, so a permanently failing item cycles forever |
| A `Dropdown` with no `DataSourceItems` | Renders empty; nothing to select |
| Tooltips describing a type the argument doesn't have | Documentation that drifted from the thing it documents |

None of these are failures of knowledge. Everything needed to avoid them was already known
somewhere in that library. They are failures of **consistency** — nothing held the good
decisions in place as the library grew, so each new activity re-decided, and the decisions
drifted.

That is what a written standard is for. Not because the team doesn't know better, but so
they don't have to re-decide, activity by activity, for four years.

---

## What's here

```
00_STANDARDS.md        The coding standard: naming, error handling, logging,
                       config, versioning, testing, and ten non-negotiables
BUILD.md               How to build custom UiPath activities, end to end —
                       project setup, the .xaml.json descriptor, public/private
                       boundary, colour system, publishing, versioning
COMPOSITION.md         How the activities chain: five canonical pipelines,
                       20 typed handoffs, and the rules for designing an
                       activity that composes
BUILD_ORDER.md         Build checklist, ordered easiest-first

specs/                 One spec per activity group — arguments, descriptions,
                       logic, validation, test cases, and the reasoning behind
                       each design decision

build/
  activities.json      All 26 activities defined as data
  generate.ps1         Generates every .xaml.json descriptor and .svg icon

Intellika.Automation/  The Library project itself
  project.json         outputType: Library
  Activities/          26 activity descriptors + icons, 2 workflows built
  Assets/              Config.xlsx template
```

---

## The standard, in brief

Full version in [`00_STANDARDS.md`](00_STANDARDS.md).

**Naming** — `Noun.Verb.xaml`, no spaces. Arguments are `in_` / `out_` / `io_` plus
PascalCase, never abbreviated. One name per concept, library-wide.

**Error handling** — business exceptions and system exceptions are different things.
A bad record is failed and moved past; a transient fault is retried with exponential
backoff. One is never treated as the other.

**Retry shape follows the failure** — exponential backoff for transient faults; a steady
cadence for resource contention, where the resource frees at a time unrelated to how often
you ask.

**Credentials are typed, not named** — `SecureString`, not a `String` you hope a glob will
catch. `excludedLoggedData` lives in the *executing project*, so a hardened list inside a
library protects none of its consumers. Treat it as a second layer, never the first.

**Config over code paths** — the same published package promotes dev → test → prod with no
code change. No activity in a library takes an environment flag.

**Closed sets are Dropdowns** with `DataSourceItems` populated. A Dropdown without them is
always a defect.

**Report absence** — `out_Found`, `out_NotFound`, `out_EmptyGroups`. A caller comparing
input count to output count will not notice the gap, because nobody diffs arrays.

**"Nothing to do" is a value, not an exception** — empty queue, missing file, no matching
record. These are normal outcomes in a loop, and the loop needs to continue past them.

---

## Status

**Honest about where this is.**

| | |
|---|---|
| Activity contracts | **26 of 26** — arguments, descriptions, widgets, categories, icons |
| Specifications | **26 of 26** — logic, validation rules, test cases |
| Workflows implemented | **2 of 26** — `Stop.Check`, `Folder.Create` |
| Published as a package | Yes — builds and installs from a NuGet feed |

The descriptor pipeline is proven end to end: build a workflow with the matching filename,
and its Activity Layout is already populated — display name, tooltip, colour, icon,
per-argument categories and widgets. The remaining 24 need their logic built in Studio from
the specs in [`specs/`](specs/).

See [`BUILD_ORDER.md`](BUILD_ORDER.md) for the checklist.

---

## Using it

**Open the library**

```
Studio → Open → Intellika.Automation/project.json
```

**Add an activity**

1. Right-click the folder → Add → Sequence, named exactly as in `BUILD_ORDER.md`
2. Add the arguments from the matching file in `specs/`
3. Build the logic from that spec's Logic section
4. Save — the descriptor attaches automatically

**Regenerate descriptors and icons** after editing `build/activities.json`:

```powershell
powershell -ExecutionPolicy Bypass -File build/generate.ps1
```

It only writes `.xaml.json` and `.xaml.svg`. Workflow logic is never touched.

**Publish**

```
Design → Publish → Custom → <your feed>
```

Then add that feed under Studio → Settings → Package Sources, and install it in any process
through Manage Packages.

---

## Notes

Built against **UiPath Studio 26.0**, targeting `net8.0-windows`, VisualBasic expressions.
Switching to C# is one field in `project.json` — do it before writing workflows, because
changing it afterwards doesn't convert existing expressions, it breaks them.

The activity count, argument names and icons are all generated from `build/activities.json`,
so adding an activity is a data edit rather than hand-written JSON.

---

## License

MIT — see [LICENSE](LICENSE).

---

Built by [Mohamed Guled](https://mohdguled.vercel.app).
