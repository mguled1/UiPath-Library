# Build Order

Tick these off as you build each `.xaml`. The descriptor, icon, tooltips,
categories and colour already exist for every one — you are writing logic only.

| # | Done | Activity | Folder | Args | Spec |
|---|---|---|---|---|---|
| 1 | [ ] | `Folder.Create` | `File` | 3 | Core.And.Utility.md |
| 2 | [ ] | `Log.Write` | `Core` | 4 | Core.Config.Load.md / Core.And.Utility.md |
| 3 | [ ] | `Log.Context.Set` | `Core` | 2 | Core.Config.Load.md / Core.And.Utility.md |
| 4 | [ ] | `Config.Load` | `Core` | 7 | Core.Config.Load.md / Core.And.Utility.md |
| 5 | [x] | `Stop.Check` | `Orchestrator` | 1 | Queue.And.Orchestrator.md |
| 6 | [ ] | `Job.CheckRunning` | `Orchestrator` | 7 | Queue.And.Orchestrator.md |
| 7 | [ ] | `Queue.Item.Get` | `Queue` | 6 | Queue.And.Orchestrator.md |
| 8 | [ ] | `Queue.Item.Resolve` | `Queue` | 6 | Queue.And.Orchestrator.md |
| 9 | [ ] | `Queue.Item.Retry` | `Queue` | 7 | Queue.And.Orchestrator.md |
| 10 | [ ] | `Queue.Item.Update` | `Queue` | 5 | Queue.And.Orchestrator.md |
| 11 | [ ] | `Files.Delete` | `File` | 6 | Core.And.Utility.md |
| 12 | [ ] | `Http.Request` | `Http` | 10 | Core.And.Utility.md |
| 13 | [ ] | `Password.Generate` | `Security` | 7 | Core.And.Utility.md |
| 14 | [ ] | `Graph.Token.Get` | `Integration/Graph` | 6 | Integration.Graph.md |
| 15 | [ ] | `Graph.User.Get` | `Integration/Graph` | 6 | Integration.Graph.md |
| 16 | [ ] | `File.Download` | `Integration/SharePoint` | 9 | Integration.SharePoint.md |
| 17 | [ ] | `Mail.Send` | `Integration/Outlook` | 11 | Integration.Outlook.md / .Send.md |
| 18 | [ ] | `Mail.Reply` | `Integration/Outlook` | 9 | Integration.Outlook.md / .Send.md |
| 19 | [ ] | `Mail.Forward` | `Integration/Outlook` | 9 | Integration.Outlook.md / .Send.md |
| 20 | [ ] | `Record.Create` | `Integration/ServiceNow` | 8 | Integration.ServiceNow.md |
| 21 | [ ] | `Record.Get` | `Integration/ServiceNow` | 8 | Integration.ServiceNow.md |
| 22 | [ ] | `Record.Query` | `Integration/ServiceNow` | 10 | Integration.ServiceNow.md |
| 23 | [ ] | `Record.Update` | `Integration/ServiceNow` | 8 | Integration.ServiceNow.md |
| 24 | [ ] | `Task.GetRelated` | `Integration/ServiceNow` | 5 | Integration.ServiceNow.md |
| 25 | [ ] | `User.GetEmails` | `Integration/ServiceNow` | 5 | Integration.ServiceNow.md |
| 26 | [ ] | `Group.GetUsers` | `Integration/ServiceNow` | 6 | Integration.ServiceNow.md |

## How

1. Right-click the folder in the Project panel -> Add -> Sequence
2. Name it **exactly** as the Activity column shows (the dots matter)
3. Open the Arguments tab, add the arguments from the spec
4. Build the logic from the spec's Logic section
5. Ctrl+S

When you have a batch done: Publish -> bump the version -> republish to
`C:\Users\kasgu\UiPathPackages`, then Update the package in any consuming project.
