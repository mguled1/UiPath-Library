<#
    Intellika.Automation — library scaffold generator

    Reads build/activities.json and emits a complete UiPath Library project:
      project.json              the manifest, with privateWorkflows populated
      Activities/**.xaml.json   one Activity Layout descriptor per activity
      Activities/**.xaml.svg    one icon per activity, coloured by family
      Snippets/ Tests/ Assets/  folder structure

    Re-run it any time. It overwrites generated files and leaves .xaml alone,
    so your workflow logic is never touched.

    Usage:  powershell -ExecutionPolicy Bypass -File build\generate.ps1
#>

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$defPath = Join-Path $PSScriptRoot 'activities.json'
$def     = Get-Content $defPath -Raw | ConvertFrom-Json
$outRoot = Join-Path $root $def.package

# UTF-8 without BOM — Studio and git both prefer it
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-TextFile($path, $content) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($path, $content, $utf8)
}

function Get-Prop($obj, $name, $default) {
    if ($obj.PSObject.Properties.Name -contains $name) {
        $v = $obj.$name
        if ($null -ne $v) { return $v }
    }
    return $default
}

# ---------------------------------------------------------------- icons

$iconPaths = @{
    'gear'   = 'M12 15.5a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.6 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.6a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z'
    'robot'  = 'M12 2v4 M5 8h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-8a2 2 0 0 1 2-2z M9 13h.01 M15 13h.01 M9.5 17h5'
    'queue'  = 'M3 6h18 M3 12h18 M3 18h12 M19 16l2 2-2 2'
    'globe'  = 'M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z M3.6 9h16.8 M3.6 15h16.8 M12 3a14 14 0 0 1 0 18 14 14 0 0 1 0-18z'
    'folder' = 'M4 5h5l2 2.5h9a1.5 1.5 0 0 1 1.5 1.5v9a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 18V6.5A1.5 1.5 0 0 1 4 5z'
    'trash'  = 'M3 6h18 M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2 M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6 M10 11v6 M14 11v6'
    'key'    = 'M14.5 9.5a4.5 4.5 0 1 1-1.9-3.68L21 14l-2.5 2.5-2-2-2 2-2-2 1.1-1.1a4.5 4.5 0 0 0 .9-3.9z'
    'cloud'  = 'M17.5 19a4.5 4.5 0 0 0 .5-8.97A6 6 0 0 0 6.1 11.2 3.5 3.5 0 0 0 6.5 19h11z'
    'mail'   = 'M3 6.5A1.5 1.5 0 0 1 4.5 5h15A1.5 1.5 0 0 1 21 6.5v11a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 17.5v-11z M3.5 6.8 12 13l8.5-6.2'
    'ticket' = 'M4 7.5A1.5 1.5 0 0 1 5.5 6h13A1.5 1.5 0 0 1 20 7.5v2a2.5 2.5 0 0 0 0 5v2a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 16.5v-2a2.5 2.5 0 0 0 0-5v-2z M9.5 6v12'
}

function New-Svg($iconKey, $color) {
    $d = $iconPaths[$iconKey]
    $paths = ($d -split ' M' | ForEach-Object {
        $seg = $_.TrimStart('M').Trim()
        if ($seg) { "  <path d=`"M$seg`" />" }
    }) -join "`n"
@"
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"
     fill="none" stroke="$color" stroke-width="1.6"
     stroke-linecap="round" stroke-linejoin="round">
$paths
</svg>
"@
}

# ---------------------------------------------------------------- descriptors

$made    = 0
$argCount = 0

foreach ($a in $def.activities) {

    $fam   = $def.families.($a.family)
    $dir   = Join-Path $outRoot $a.path
    $svgNm = "$($a.file).xaml.svg"

    $arguments = @()
    foreach ($g in $a.args) {
        $arguments += [ordered]@{
            Name            = $g.n
            DisplayName     = (Get-Prop $g 'd'     $g.n)
            Category        = (Get-Prop $g 'c'     $null)
            Tooltip         = (Get-Prop $g 't'     $null)
            Placeholder     = (Get-Prop $g 'ph'    $null)
            Widget          = (Get-Prop $g 'w'     $null)
            IsRequired      = [bool](Get-Prop $g 'req'   $false)
            IsPrincipal     = [bool](Get-Prop $g 'pri'   $false)
            ArgumentType    = [int](Get-Prop  $g 'atype' 0)
            DataSourceItems = (Get-Prop $g 'items' $null)
        }
        $argCount++
    }

    $descriptor = [ordered]@{
        DisplayName          = $a.display
        Tooltip              = $a.tooltip
        HelpLink             = $null
        Color                = $fam.color
        OriginalIconFileName = $svgNm
        Arguments            = $arguments
    }

    Write-TextFile (Join-Path $dir "$($a.file).xaml.json") (($descriptor | ConvertTo-Json -Depth 8) + "`n")
    Write-TextFile (Join-Path $dir $svgNm)                 (New-Svg $fam.icon $fam.color)
    $made++
}

# ---------------------------------------------------------------- project.json

# Everything that must NOT appear in a consumer's Activities panel.
# Add every Tests/TC-*.xaml here as you write them: registering a workflow as a
# test case in fileInfoCollection does NOT hide it. the legacy library ships two test
# cases as public activities because that distinction was assumed rather than set.
$privateWorkflows = @(
    'Snippets/Retry.xaml',
    'Snippets/Http.Core.xaml',
    'Snippets/Mail.Body.Compose.xaml',
    'Snippets/Config.ReadSheet.xaml',
    'Snippets/Credential.Resolve.xaml',
    'Snippets/ServiceNow.Call.xaml'
)

$project = [ordered]@{
    name        = $def.package
    description = 'Reusable automation components - config, logging, retry, HTTP, queue, Orchestrator and integration activities.'
    main        = 'Activities/Core/Config.Load.xaml'
    # Only the one package every library needs is pinned. Excel, Mail, WebAPI and
    # Testing are added through Manage Packages as you build the activities that
    # need them — pinning versions that are not in your feed fails the restore on
    # first open, and the right version is whatever your Studio offers.
    # Square brackets are NuGet exact-version notation — the Strict runtime rule.
    # Bare '25.10.3' would mean "that version or higher", which lets an untested
    # package version run in production. Studio writes brackets; so do we.
    dependencies = [ordered]@{
        'UiPath.System.Activities' = '[25.10.3]'
    }
    webServices    = @()
    entitiesStores = @()
    schemaVersion  = '4.0'
    studioVersion  = '26.0.180.0'
    projectVersion = '1.0.0'
    runtimeOptions = [ordered]@{
        autoDispose             = $true
        netFrameworkLazyLoading = $false
        isPausable              = $false
        isAttended              = $false
        requiresUserInteraction = $false
        supportsPersistence     = $false
        workflowSerialization   = 'DataContract'
        excludedLoggedData      = @(
            'Private:*', '*password*', '*secret*', '*token*',
            '*bearer*', '*apikey*', '*credential*', '*assertion*', 'Authorization*'
        )
        executionType           = 'Workflow'
        readyForPiP             = $false
        startsInPiP             = $false
        mustRestoreAllDependencies = $false
        pipType                 = 'ChildSession'
    }
    designOptions = [ordered]@{
        # NOT a typo. 'Developement' is the literal value of UiPath's
        # ProjectProfile enum — the misspelling ships in the product.
        # Writing 'Development' makes Studio refuse to open the project.
        projectProfile = 'Developement'
        outputType     = 'Library'
        libraryOptions = [ordered]@{
            includeOriginalXaml = $false
            privateWorkflows    = $privateWorkflows
        }
        processOptions     = [ordered]@{ ignoredFiles = @() }
        fileInfoCollection = @()
        saveToCloud        = $false
    }
    # VisualBasic: Studio's default, and the language this library's author
    # works in daily. Change to 'CSharp' only if you want coded workflows,
    # which are C#-only. Flip BEFORE writing workflows — switching afterwards
    # does not convert existing expressions, it breaks them one by one.
    expressionLanguage  = 'VisualBasic'
    isTemplate          = $false
    templateProjectData = [ordered]@{}
    publishData         = [ordered]@{}
    # 'Windows' matches the robots this will actually run on and keeps every
    # activity package available. Change to 'Portable' for cross-platform /
    # Linux robots — it is a one-line flip, at the cost of some packages.
    targetFramework     = 'Windows'
}

Write-TextFile (Join-Path $outRoot 'project.json') (($project | ConvertTo-Json -Depth 8) + "`n")

# ---------------------------------------------------------------- folders

foreach ($d in @('Snippets', 'Tests', '.variations', 'Assets', 'CodedWorkflows')) {
    $p = Join-Path $outRoot $d
    if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
}

Write-Output "Package    : $($def.package)"
Write-Output "Activities : $made"
Write-Output "Arguments  : $argCount"
Write-Output "Output     : $outRoot"
