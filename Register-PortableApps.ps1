param(
    [Parameter(Mandatory = $true, ParameterSetName = "Register")]
    [switch]$Register,

    [Parameter(Mandatory = $true, ParameterSetName = "Unregister")]
    [switch]$Unregister,

    [Parameter(Mandatory = $true, ParameterSetName = "List")]
    [switch]$List,

    [Parameter(Mandatory = $true, ParameterSetName = "Register")]
    [Parameter(Mandatory = $true, ParameterSetName = "Unregister")]
    [string]$Manifest,

    [Parameter(ParameterSetName = "Register")]
    [Parameter(ParameterSetName = "Unregister")]
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$UninstallRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
$AppPathsRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths"
$StartMenuRoot = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$ToolName = "PortableAppRegister"

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return [System.IO.Path]::GetFullPath($expanded)
    }

    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $expanded))
}

function Get-AppValue {
    param(
        [Parameter(Mandatory = $true)]$App,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    $property = $App.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value -and "$($property.Value)" -ne "") {
        return $property.Value
    }

    return $Default
}

function Read-Manifest {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Manifest not found: $fullPath"
    }

    $json = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    if (-not $json.apps) {
        throw "Manifest must contain an 'apps' array."
    }

    return $json.apps
}

function Get-AppId {
    param([Parameter(Mandatory = $true)]$App)

    $id = Get-AppValue -App $App -Name "id"
    if ($id) {
        return [string]$id
    }

    $exe = Get-AppValue -App $App -Name "exe"
    $name = Get-AppValue -App $App -Name "name"
    $source = if ($exe) { [string]$exe } else { [string]$name }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($source)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    $shortHash = -join ($hash[0..5] | ForEach-Object { $_.ToString("x2") })
    return "portable-$shortHash"
}

function Assert-App {
    param([Parameter(Mandatory = $true)]$App)

    foreach ($field in @("name", "exe")) {
        if (-not (Get-AppValue -App $App -Name $field)) {
            throw "Each app must contain '$field'."
        }
    }

    $exePath = Resolve-FullPath ([string](Get-AppValue -App $App -Name "exe"))
    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Executable not found for '$(Get-AppValue -App $App -Name "name")': $exePath"
    }

    return $exePath
}

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Preview
    )

    if ($Preview) {
        Write-Host "[what-if] Ensure folder: $Path"
        return
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Value,
        [string]$Type = "String",
        [switch]$Preview
    )

    if ($Preview) {
        Write-Host "[what-if] Set $Path :: $Name = $Value"
        return
    }

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Remove-RegistryKey {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Preview
    )

    if ($Preview) {
        Write-Host "[what-if] Remove registry key: $Path"
        return
    }

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconPath,
        [switch]$Preview
    )

    if ($Preview) {
        Write-Host "[what-if] Create shortcut: $ShortcutPath -> $TargetPath"
        return
    }

    New-DirectoryIfMissing -Path ([System.IO.Path]::GetDirectoryName($ShortcutPath))

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    if ($Arguments) { $shortcut.Arguments = $Arguments }
    if ($WorkingDirectory) { $shortcut.WorkingDirectory = $WorkingDirectory }
    if ($IconPath) { $shortcut.IconLocation = $IconPath }
    $shortcut.Save()
}

function Remove-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [switch]$Preview
    )

    if ($Preview) {
        Write-Host "[what-if] Remove shortcut: $ShortcutPath"
        return
    }

    if (Test-Path -LiteralPath $ShortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $ShortcutPath -Force
    }
}

function Get-ShortcutPath {
    param([Parameter(Mandatory = $true)]$App)

    $startMenuFolder = Get-AppValue -App $App -Name "startMenuFolder"
    $folder = if ($startMenuFolder) {
        Join-Path $StartMenuRoot ([string]$startMenuFolder)
    }
    else {
        $StartMenuRoot
    }

    $fileName = "$(Get-AppValue -App $App -Name "name").lnk" -replace '[\\/:*?"<>|]', "_"
    return Join-Path $folder $fileName
}

function Register-App {
    param(
        [Parameter(Mandatory = $true)]$App,
        [switch]$Preview
    )

    $exePath = Assert-App $App
    $appId = Get-AppId $App
    $installLocationValue = Get-AppValue -App $App -Name "installLocation"
    $installLocation = if ($installLocationValue) {
        Resolve-FullPath ([string]$installLocationValue)
    }
    else {
        [System.IO.Path]::GetDirectoryName($exePath)
    }

    $iconValue = Get-AppValue -App $App -Name "icon"
    $iconPath = if ($iconValue) { Resolve-FullPath ([string]$iconValue) } else { $exePath }
    $publisher = [string](Get-AppValue -App $App -Name "publisher" -Default "Portable App")
    $version = [string](Get-AppValue -App $App -Name "version" -Default "1.0.0")
    $args = [string](Get-AppValue -App $App -Name "arguments" -Default "")
    $shortcutPath = Get-ShortcutPath $App
    $uninstallKey = Join-Path $UninstallRoot $appId
    $appPathKey = Join-Path $AppPathsRoot ([System.IO.Path]::GetFileName($exePath))

    if ($Preview) {
        Write-Host "[what-if] Register '$(Get-AppValue -App $App -Name "name")'"
    }
    else {
        New-Item -Path $uninstallKey -Force | Out-Null
        New-Item -Path $appPathKey -Force | Out-Null
    }

    $scriptPath = $PSCommandPath
    $uninstallCommand = "powershell.exe -ExecutionPolicy Bypass -File `"$scriptPath`" -Unregister -Manifest `"$Manifest`""

    Set-RegistryValue -Path $uninstallKey -Name "DisplayName" -Value ([string](Get-AppValue -App $App -Name "name")) -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "DisplayVersion" -Value $version -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "Publisher" -Value $publisher -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "InstallLocation" -Value $installLocation -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "DisplayIcon" -Value $iconPath -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "UninstallString" -Value $uninstallCommand -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "NoModify" -Value 1 -Type "DWord" -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "NoRepair" -Value 1 -Type "DWord" -Preview:$Preview
    Set-RegistryValue -Path $uninstallKey -Name "PortableAppRegisterId" -Value $appId -Preview:$Preview

    Set-RegistryValue -Path $appPathKey -Name "(default)" -Value $exePath -Preview:$Preview
    Set-RegistryValue -Path $appPathKey -Name "Path" -Value $installLocation -Preview:$Preview

    New-Shortcut `
        -ShortcutPath $shortcutPath `
        -TargetPath $exePath `
        -Arguments $args `
        -WorkingDirectory $installLocation `
        -IconPath $iconPath `
        -Preview:$Preview

    Write-Host "Registered: $(Get-AppValue -App $App -Name "name")"
}

function Unregister-App {
    param(
        [Parameter(Mandatory = $true)]$App,
        [switch]$Preview
    )

    $appId = Get-AppId $App
    $shortcutPath = Get-ShortcutPath $App
    $uninstallKey = Join-Path $UninstallRoot $appId

    $appPathKey = $null
    $exeValue = Get-AppValue -App $App -Name "exe"
    if ($exeValue) {
        $exePath = Resolve-FullPath ([string]$exeValue)
        $appPathKey = Join-Path $AppPathsRoot ([System.IO.Path]::GetFileName($exePath))
    }

    Remove-Shortcut -ShortcutPath $shortcutPath -Preview:$Preview
    Remove-RegistryKey -Path $uninstallKey -Preview:$Preview
    if ($appPathKey) {
        Remove-RegistryKey -Path $appPathKey -Preview:$Preview
    }

    Write-Host "Unregistered: $(Get-AppValue -App $App -Name "name")"
}

function Show-RegisteredApps {
    $keys = Get-ChildItem -Path $UninstallRoot -ErrorAction SilentlyContinue |
        Where-Object {
            $item = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            $item -and ($item.PSObject.Properties.Name -contains "PortableAppRegisterId")
        }

    if (-not $keys) {
        Write-Host "No apps registered by $ToolName."
        return
    }

    $keys |
        ForEach-Object {
            $item = Get-ItemProperty -LiteralPath $_.PSPath
            [PSCustomObject]@{
                Name = $item.DisplayName
                Version = $item.DisplayVersion
                Publisher = $item.Publisher
                Location = $item.InstallLocation
            }
        } |
        Format-Table -AutoSize
}

if ($List) {
    Show-RegisteredApps
    return
}

$apps = Read-Manifest -Path $Manifest
foreach ($app in $apps) {
    if ($Register) {
        Register-App -App $app -Preview:$WhatIf
    }
    elseif ($Unregister) {
        Unregister-App -App $app -Preview:$WhatIf
    }
}
