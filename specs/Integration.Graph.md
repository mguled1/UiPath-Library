# Activity Spec — `Integration/Graph`

Microsoft Graph authentication and user lookup.

| Activity | File | Visibility |
|---|---|---|
| Get Graph Token | `Activities/Integration/Graph/Graph.Token.Get.xaml` | Public |
| Get Graph User | `Activities/Integration/Graph/Graph.User.Get.xaml` | Public |

Shared visual identity: color `#0078D4`, icon `graph.svg`. Every activity in this folder uses both, so the family reads as one group in the Activities panel.

Replaces a `GetToken` / `GetUserDetails` pair. The substantive changes are token caching, no environment toggle, and getting the token out of the log stream.

---

## 1. `Graph.Token.Get`

**Display name:** Get Graph Token
**Tooltip:** Acquires a Microsoft Graph access token using client credentials, cached until shortly before expiry.

### Arguments

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_AppRegistration` | String | In | TextComposer | — | Yes |
| 2 | `in_Scope` | String | In | TextComposer | Advanced | No |
| 3 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 4 | `in_ForceRefresh` | Boolean | In | Toggle | Advanced | No |
| 5 | `out_Private_GraphToken` | SecureString | Out | TextComposer | Output | — |
| 6 | `out_ExpiresOn` | DateTime | Out | TextComposer | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_AppRegistration` | Logical name of the app registration, resolved through config to a tenant id, client id and credential asset. For example `Graph_ReadOnly`. | — |
| `in_Scope` | OAuth2 scope requested. | `https://graph.microsoft.com/.default` |
| `in_TimeoutSeconds` | Timeout for the token request. | `30` |
| `in_ForceRefresh` | Bypass the cache and request a new token. Use only after a 401 on a call that should have succeeded. | `False` |
| `out_Token` | Bearer token. Pass as `"Bearer " + out_Token` in the Authorization header. | — |
| `out_ExpiresOn` | UTC expiry of the returned token. | — |

### Config keys this reads

```
Settings sheet:
  Graph.ReadOnly.TenantId        = 00000000-0000-0000-0000-000000000000
  Graph.ReadOnly.ClientId        = 00000000-0000-0000-0000-000000000000
  Graph.ReadOnly.CredentialAsset = Graph_ReadOnly_ClientSecret
```

Pattern: `Graph.<AppRegistration>.<Setting>`. Adding a second app registration is three config rows, not a code change and a republish.

---

## 2. Token caching

The single most important behavioural change. Without it, a process that calls Graph in a loop requests a fresh token on every iteration — 500 transactions, 500 token requests, and eventually HTTP 429 from the identity endpoint.

A Graph client-credentials token lives about 60 minutes. One token covers a whole run.

XAML workflows cannot hold state between invocations, so the cache has to be a **coded workflow** — a C# class whose static field survives for the life of the robot process. This is the right use of `.codedworkflows`.

```csharp
using System;
using System.Collections.Concurrent;

namespace Guled.Automation.Integration.Graph
{
    /// <summary>
    /// Process-wide cache of Graph access tokens, keyed by app registration and scope.
    /// A token is served from cache until it is within RenewalWindow of expiry.
    /// </summary>
    internal static class TokenCache
    {
        private sealed class Entry
        {
            public string Token;
            public DateTime ExpiresOnUtc;
        }

        private static readonly ConcurrentDictionary<string, Entry> Cache =
            new ConcurrentDictionary<string, Entry>(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        /// Renew this far ahead of the real expiry so a token cannot expire
        /// between being handed out and being used.
        /// </summary>
        private static readonly TimeSpan RenewalWindow = TimeSpan.FromMinutes(5);

        private static string KeyFor(string appRegistration, string scope)
        {
            return appRegistration + "|" + scope;
        }

        /// <summary>
        /// Returns a cached token, or null when there is no usable one.
        /// </summary>
        public static string TryGet(string appRegistration, string scope, out DateTime expiresOnUtc)
        {
            expiresOnUtc = DateTime.MinValue;

            Entry entry;
            if (!Cache.TryGetValue(KeyFor(appRegistration, scope), out entry))
                return null;

            if (DateTime.UtcNow.Add(RenewalWindow) >= entry.ExpiresOnUtc)
                return null;

            expiresOnUtc = entry.ExpiresOnUtc;
            return entry.Token;
        }

        public static void Set(string appRegistration, string scope, string token, int expiresInSeconds)
        {
            Cache[KeyFor(appRegistration, scope)] = new Entry
            {
                Token = token,
                ExpiresOnUtc = DateTime.UtcNow.AddSeconds(expiresInSeconds)
            };
        }

        public static void Invalidate(string appRegistration, string scope)
        {
            Entry discarded;
            Cache.TryRemove(KeyFor(appRegistration, scope), out discarded);
        }
    }
}
```

### Why these specifics

- **`ConcurrentDictionary`** — several robots can share a process; two jobs requesting a token at once must not corrupt the cache.
- **Five-minute renewal window** — a token handed out with thirty seconds left will expire mid-request. Renewing early costs one extra token call an hour and removes the whole failure mode.
- **Keyed by registration *and* scope** — a read-only token must never be served to a caller that asked for a write scope.
- **`Invalidate`** — what `in_ForceRefresh` calls, so a 401 is recoverable without restarting the robot.

The `CodedWorkflow` wrapper that exposes this as an activity varies by Studio version; confirm the base class and attribute against your Studio's generated template when you create the coded workflow. The cache above is the part that matters and is version-independent.

---

## 3. Keeping the token out of the logs

A bearer token is a credential. Anyone holding it can call Graph as the app registration until it expires — roughly an hour.

### `excludedLoggedData` in a library does not protect its consumers

This is the trap, and it is worth stating plainly because the opposite is the intuitive assumption.

`excludedLoggedData` lives in `runtimeOptions` of **the project being executed**. A library is a dependency, not an executing project. When a process consumes `Graph.Token.Get`, the robot's logging pipeline reads the **consuming process's** `project.json` — not the library's.

So a hardened list shipped inside the library governs nothing at the point where it matters. Worse, the token lands in a variable the caller named: `token`, `strToken`, `authHeader`. The library author never sees that name and cannot pattern-match it.

A control that is documented, believed, and inert is more dangerous than no control, because nobody looks again.

### What actually protects the token

**1. Type the output `SecureString`.** UiPath's log serializer does not render SecureString values, and the Studio Locals panel shows the type rather than the contents. This holds regardless of what the consuming process configured, which is the whole point — it does not depend on the caller doing anything.

**2. Name it so pattern exclusion catches it too.** `out_Private_GraphToken` matches `Private:*`-style conventions and any `*token*` rule a consumer has set. Belt and braces, with the belt doing the real work.

**3. Convert to String only inside the activity.** Building the `Authorization` header needs a plain string. Do it in the activity that makes the call, in a tightly scoped variable that never becomes a workflow argument. Activity-scoped and short-lived is acceptable; crossing the library boundary as a String is not.

**4. Ship the consumer snippet anyway.** `README.md` carries the `excludedLoggedData` block for consuming processes to merge, and the sample process has it pre-set. State explicitly that a consumer who has not merged it is relying on SecureString alone.

```json
"excludedLoggedData": [
  "Private:*", "*password*", "*secret*", "*token*",
  "*bearer*", "*apikey*", "*credential*", "*assertion*", "Authorization*"
]
```

### Exception text is never filtered

`excludedLoggedData` masks **argument and variable values**. It does not touch exception messages, inner exceptions or stack traces, and UiPath logs those at Error unconditionally.

The token request POSTs `client_id` and `client_secret` as form data. When the secret has just been rotated or the tenant throttles, the HTTP activity throws — and some HTTP wrappers put the request body in the message, while Entra's own 400 response echoes request parameters in `error_description`. That message reaches the Global Exception Handler, gets logged at Error, and ships to Splunk.

What is sitting in the log store at that point is not a 60-minute token. It is the **long-lived client secret** of a production app registration, valid until somebody notices.

**So the token request is wrapped in Try/Catch inside the activity**, and what comes out is a sanitised exception carrying only what is safe and useful:

```
GraphAuthException:
  HTTP status, Entra error code, error_codes, correlation_id / trace_id,
  app registration logical name, environment
```

Never the request body. Never the raw response text. A test forces 400, 401 and timeout and asserts the thrown message does not contain the secret.

### Remediation, if a token or secret was ever logged

Rotate the credential. Deleting log lines is not remediation — the value has already been read, indexed, replicated to any log forwarder, and retained by whatever downstream system consumes Splunk.

---

## 4. `Graph.User.Get`

**Display name:** Get Graph User
**Tooltip:** Looks up an Entra ID user by email and returns their profile.

### Arguments

| # | Name | Type | Direction | Widget | Category | Required |
|---|---|---|---|---|---|---|
| 1 | `in_Token` | String | In | TextComposer | — | Yes |
| 2 | `in_UserEmail` | String | In | TextComposer | — | Yes |
| 3 | `in_Fields` | String[] | In | StringArray | Advanced | No |
| 4 | `in_TimeoutSeconds` | Int32 | In | Number | Advanced | No |
| 5 | `out_User` | JObject | Out | — | Output | — |
| 6 | `out_Found` | Boolean | Out | Toggle | Output | — |

| Argument | Description | Default |
|---|---|---|
| `in_Token` | Bearer token from Get Graph Token. | — |
| `in_UserEmail` | User principal name or mail address. | — |
| `in_Fields` | Graph `$select` fields. | `{"displayName","givenName","surname","jobTitle","mail","mobilePhone","businessPhones","officeLocation","department","accountEnabled"}` |
| `in_TimeoutSeconds` | Request timeout. | `30` |
| `out_User` | The Graph user object. Empty JObject when not found. | — |
| `out_Found` | False when Graph returned 404. | — |

### Why `out_Found` instead of throwing

"This email does not exist in Entra" is a **business** outcome, not a system failure. A process reconciling a thousand addresses will hit missing users as a matter of course, and it must keep going. Throwing on 404 forces every caller to wrap the activity in a Try/Catch and inspect the message — which they will get wrong.

A 403, a 500 or a timeout *is* a system failure and still throws.

### Logic

```
1. Validate
     in_Token empty      -> ArgumentException
     in_UserEmail empty  -> ArgumentException

2. GET https://graph.microsoft.com/v1.0/users/{Uri.EscapeDataString(in_UserEmail)}
        ?$select={String.Join(",", in_Fields)}
   Header: Authorization = "Bearer " + in_Token
   Timeout: in_TimeoutSeconds

3. Branch on status
     200 -> out_User = JObject.Parse(body);  out_Found = True
     404 -> out_User = new JObject();        out_Found = False
            Log Info: "No Graph user for " & in_UserEmail
     401 -> throw with a message naming ForceRefresh as the remedy
     429 -> honour Retry-After, retry once, then throw
     else-> throw, message carries status code and the Graph error code from the body
```

`Uri.EscapeDataString` on the email matters: an address containing `#` or `+` builds a malformed URL and returns a confusing 400.

---

## 5. What was dropped from the original pair, and why

### `in_UseDev` — the environment toggle, again

A `Boolean` switching between PROD and UAT credentials. The same anti-pattern as `in_DevMode` and `in_Environment` in `Initialize` — this is the **third** independent environment switch in one library, and the three do not even share vocabulary: `PROD`/`UAT` here, `DEV`/`UAT`/`PROD` in one tooltip, `PROD_Cloud`/`DEV_Cloud` in the actual options.

Nobody can reason about a library where the same concept has three names and three mechanisms.

**Replacement:** none. `in_AppRegistration` names a logical registration; config supplies the credentials for whichever environment the robot is running in. The UAT robot reads UAT config. No argument, no branch, no toggle.

### `in_Application` as a hard-coded dropdown

`["APP_A", "APP_B"]` baked into the published contract. A third app registration means editing the library, bumping the version, republishing, and updating every consumer.

**Replacement:** a free-text logical name resolved through config.

### `IsRequired: true` on outputs

`out_Token` and `out_UserDetails` are both marked required. The field has no meaning on an Out argument — an output is produced, not supplied. Harmless at runtime, but it signals the descriptor was filled in by copy-paste, which is also where the wrong tooltips come from.

### `in_TimeoutMS` — milliseconds

Not wrong, but the library should pick one unit. Seconds reads better in a Properties panel (`30` beats `15000`) and matches `in_TimeoutSeconds` everywhere else. Consistency across a library beats local preference.

---

## 6. Test cases

`Tests/TC-Graph.Token.Get.xaml`, `Tests/TC-Graph.User.Get.xaml`.

| Case | Expected |
|---|---|
| First call | token returned, `out_ExpiresOn` roughly one hour ahead |
| Second call inside the window | identical token, no HTTP request made |
| Call with `in_ForceRefresh` | new token, cache replaced |
| Cached token inside the renewal window | new token fetched, not the stale one |
| Unknown app registration | exception naming the missing config key |
| Bad client secret | exception carrying the Entra error code, secret not in the message |
| User lookup, exists | `out_Found` true, `out_User` populated |
| User lookup, missing | `out_Found` false, no exception, Info logged |
| User lookup, expired token | 401 surfaced with ForceRefresh named as the remedy |
| Email containing `+` | correctly escaped, resolves |
| Log inspection after a full run | no token value present in any log line |
