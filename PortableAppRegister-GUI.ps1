param(
    [switch]$RemoveRegisteredApp,
    [string]$Id,
    [string]$ExeName,
    [string]$ShortcutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ToolName = "PortableAppRegister"
$DefaultStartMenuFolder = "Portable Apps"
$UninstallRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall"
$AppPathsRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths"
$StartMenuRoot = [Environment]::GetFolderPath("Programs")
$DataRoot = Join-Path ([Environment]::GetFolderPath("ApplicationData")) $ToolName
$DatabasePath = Join-Path $DataRoot "apps.json"

function Test-SupportedLaunchFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return $extension -in @(".exe", ".bat", ".cmd")
}

function Test-AppPathsSupported {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [System.IO.Path]::GetExtension($Path).ToLowerInvariant() -eq ".exe"
}

function Get-StableId {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalized)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    $shortHash = -join ($hash[0..7] | ForEach-Object { $_.ToString("x2") })
    return "portable-$shortHash"
}

function Get-VersionInfoValue {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [string]$Fallback = ""
    )

    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) {
        return $Fallback
    }

    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath)
        $value = $versionInfo.$PropertyName
    }
    catch {
        return $Fallback
    }
    if ($value -and $value.Trim()) {
        return $value.Trim()
    }

    return $Fallback
}

function Get-InitialDisplayName {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    $suggestions = @(Get-NameSuggestions -ExePath $ExePath -IncludeOnline:$false)
    if ($suggestions.Count -gt 0) {
        return $suggestions[0]
    }

    return Get-VersionInfoValue `
        -ExePath $ExePath `
        -PropertyName "ProductName" `
        -Fallback ([System.IO.Path]::GetFileNameWithoutExtension($ExePath))
}

function Get-KnownAppName {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    $parent = Split-Path -Path (Split-Path -Path $ExePath -Parent) -Leaf
    $text = "$fileName $parent".ToLowerInvariant()
    $compact = ($text -replace '[^a-z0-9]+', '')
    $spaced = ($text -replace '[^a-z0-9]+', ' ').Trim()
    $yearMatch = [regex]::Match($text, '(20[0-3][0-9])')
    $year = if ($yearMatch.Success) { " $($yearMatch.Groups[1].Value)" } else { "" }

    $rules = @(
        @{ Pattern = '(^|[^a-z])ps([^a-z]|$)|photoshop'; Name = "Adobe Photoshop" },
        @{ Pattern = '(^|[^a-z])ai([^a-z]|$)|illustrator'; Name = "Adobe Illustrator" },
        @{ Pattern = '(^|[^a-z])pr([^a-z]|$)|premiere|premierepro'; Name = "Adobe Premiere Pro" },
        @{ Pattern = '(^|[^a-z])ae([^a-z]|$)|aftereffects'; Name = "Adobe After Effects" },
        @{ Pattern = '(^|[^a-z])au([^a-z]|$)|audition'; Name = "Adobe Audition" },
        @{ Pattern = '(^|[^a-z])id([^a-z]|$)|indesign'; Name = "Adobe InDesign" },
        @{ Pattern = 'lightroom|(^|[^a-z])lr([^a-z]|$)'; Name = "Adobe Lightroom" },
        @{ Pattern = 'acrobat|(^|[^a-z])dc([^a-z]|$)'; Name = "Adobe Acrobat" },
        @{ Pattern = 'notepad\+\+|notepadpp|npp'; Name = "Notepad++" },
        @{ Pattern = 'everything'; Name = "Everything" },
        @{ Pattern = 'obs|obsstudio'; Name = "OBS Studio" },
        @{ Pattern = 'vscode|codeoss|visualstudiocode'; Name = "Visual Studio Code" },
        @{ Pattern = 'chrome|googlechrome'; Name = "Google Chrome" },
        @{ Pattern = 'firefox|mozilla'; Name = "Mozilla Firefox" },
        @{ Pattern = 'telegram'; Name = "Telegram" },
        @{ Pattern = 'potplayer'; Name = "PotPlayer" },
        @{ Pattern = 'foobar2000'; Name = "foobar2000" },
        @{ Pattern = '7zip|7zfm'; Name = "7-Zip" },
        @{ Pattern = 'winrar'; Name = "WinRAR" },
        @{ Pattern = 'qbittorrent'; Name = "qBittorrent" },
        @{ Pattern = 'filezilla'; Name = "FileZilla" },
        @{ Pattern = 'winscp'; Name = "WinSCP" },
        @{ Pattern = 'rufus'; Name = "Rufus" },
        @{ Pattern = 'sumatrapdf|sumatra'; Name = "SumatraPDF" },
        @{ Pattern = 'krita'; Name = "Krita" },
        @{ Pattern = 'blender'; Name = "Blender" },
        @{ Pattern = 'inkscape'; Name = "Inkscape" },
        @{ Pattern = 'xnview'; Name = "XnView" },
        @{ Pattern = 'gtavc|gta vc|vicecity|vice city'; Name = "Grand Theft Auto: Vice City" },
        @{ Pattern = 'gtasa|gta sa|sanandreas|san andreas'; Name = "Grand Theft Auto: San Andreas" },
        @{ Pattern = 'gta3|gta iii|grandtheftauto3'; Name = "Grand Theft Auto III" },
        @{ Pattern = 'gtaiv|gta 4|gta4|grandtheftautoiv'; Name = "Grand Theft Auto IV" },
        @{ Pattern = 'gtav|gta 5|gta5|grandtheftautov'; Name = "Grand Theft Auto V" },
        @{ Pattern = 'rdr2|reddeadredemption2|red dead redemption 2'; Name = "Red Dead Redemption 2" },
        @{ Pattern = 'csgo|counterstrikeglobaloffensive|counter strike global offensive'; Name = "Counter-Strike: Global Offensive" },
        @{ Pattern = 'cs2|counterstrike2|counter strike 2'; Name = "Counter-Strike 2" },
        @{ Pattern = 'hl2|halflife2|half life 2'; Name = "Half-Life 2" },
        @{ Pattern = 'portal2|portal 2'; Name = "Portal 2" },
        @{ Pattern = 'nfsu2|needforspeedunderground2|need for speed underground 2'; Name = "Need for Speed: Underground 2" },
        @{ Pattern = 'nfsmw|needforspeedmostwanted|need for speed most wanted'; Name = "Need for Speed: Most Wanted" },
        @{ Pattern = 'aoe2|ageofempires2|age of empires 2'; Name = "Age of Empires II" },
        @{ Pattern = 'war3|warcraft3|warcraft iii'; Name = "Warcraft III" },
        @{ Pattern = 'sc2|starcraft2|starcraft ii'; Name = "StarCraft II" },
        @{ Pattern = 'yurisrevenge|yuri revenge|yuri|gamemd|ra2md|redalert2yuri|red alert 2 yuri'; Name = "Command & Conquer: Yuri's Revenge" },
        @{ Pattern = 'ra2|redalert2|red alert 2'; Name = "Command & Conquer: Red Alert 2" },
        @{ Pattern = 'generals|zerohour|zero hour'; Name = "Command & Conquer: Generals - Zero Hour" },
        @{ Pattern = 'tiberiansun|tiberian sun|sun'; Name = "Command & Conquer: Tiberian Sun" },
        @{ Pattern = 'minecraft'; Name = "Minecraft" },
        @{ Pattern = 'terraria'; Name = "Terraria" },
        @{ Pattern = 'stardewvalley|stardew valley'; Name = "Stardew Valley" }
    )

    foreach ($rule in $rules) {
        if ($text -match $rule.Pattern -or $compact -match $rule.Pattern -or $spaced -match $rule.Pattern) {
            return "$($rule.Name)$year"
        }
    }

    return $null
}

function Add-NameSuggestion {
    param(
        [Parameter(Mandatory = $true)]$List,
        $Name
    )

    if (-not $Name) {
        return
    }

    if ($Name -is [array]) {
        foreach ($item in $Name) {
            Add-NameSuggestion -List $List -Name $item
        }
        return
    }

    $cleanName = ([string]$Name -replace '\s+', ' ').Trim()
    if (-not $cleanName -or $cleanName.Length -lt 2 -or $cleanName.Length -gt 100) {
        return
    }

    foreach ($item in $List) {
        if ($item.ToLowerInvariant() -eq $cleanName.ToLowerInvariant()) {
            return
        }
    }

    [void]$List.Add($cleanName)
}

function Get-NameSuggestions {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [switch]$IncludeOnline,
        [string]$CurrentName = ""
    )

    $suggestions = New-Object System.Collections.Generic.List[string]
    $knownName = Get-KnownAppName -ExePath $ExePath
    Add-NameSuggestion -List $suggestions -Name $knownName

    $productName = Get-VersionInfoValue -ExePath $ExePath -PropertyName "ProductName" -Fallback ""
    $fileDescription = Get-VersionInfoValue -ExePath $ExePath -PropertyName "FileDescription" -Fallback ""
    $internalName = Get-VersionInfoValue -ExePath $ExePath -PropertyName "InternalName" -Fallback ""
    $originalFileName = Get-VersionInfoValue -ExePath $ExePath -PropertyName "OriginalFilename" -Fallback ""
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    $parent = Split-Path -Path (Split-Path -Path $ExePath -Parent) -Leaf

    Add-NameSuggestion -List $suggestions -Name $productName
    Add-NameSuggestion -List $suggestions -Name $fileDescription
    Add-NameSuggestion -List $suggestions -Name $internalName
    Add-NameSuggestion -List $suggestions -Name ([System.IO.Path]::GetFileNameWithoutExtension($originalFileName))
    Add-NameSuggestion -List $suggestions -Name $parent
    Add-NameSuggestion -List $suggestions -Name $fileName
    Add-NameSuggestion -List $suggestions -Name $CurrentName

    if ($IncludeOnline) {
        foreach ($name in @(Search-OfficialNames -ExePath $ExePath -CurrentName $CurrentName)) {
            Add-NameSuggestion -List $suggestions -Name $name
        }
    }

    return $suggestions
}

function Get-Publisher {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    return Get-VersionInfoValue -ExePath $ExePath -PropertyName "CompanyName" -Fallback "Portable App"
}

function Get-Version {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    return Get-VersionInfoValue -ExePath $ExePath -PropertyName "ProductVersion" -Fallback "1.0.0"
}

function Get-SafeFileName {
    param([Parameter(Mandatory = $true)][string]$Name)

    return ($Name -replace '[\\/:*?"<>|]', "_")
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Default = $null
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value -and "$($property.Value)" -ne "") {
        return $property.Value
    }

    return $Default
}

function Ensure-DataRoot {
    if (-not (Test-Path -LiteralPath $DataRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $DataRoot -Force | Out-Null
    }
}

function Read-AppDatabase {
    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        return @()
    }

    try {
        $json = Get-Content -LiteralPath $DatabasePath -Raw | ConvertFrom-Json
        if ($json.apps) {
            return @($json.apps)
        }
    }
    catch {
        return @()
    }

    return @()
}

function Write-AppDatabase {
    param([Parameter(Mandatory = $true)]$Apps)

    Ensure-DataRoot
    $plainApps = @($Apps)
    $payload = [PSCustomObject]@{
        version = 1
        apps = $plainApps
    }
    $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $DatabasePath -Encoding UTF8
}

function Save-AppRecord {
    param([Parameter(Mandatory = $true)]$Record)

    $apps = @()
    foreach ($app in @(Read-AppDatabase)) {
        if ([string](Get-PropertyValue -Object $app -Name "id" -Default "") -ne $Record.id) {
            $apps += $app
        }
    }
    $apps += $Record
    Write-AppDatabase -Apps $apps
}

function Remove-AppRecord {
    param([Parameter(Mandatory = $true)][string]$AppId)

    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) {
        return
    }

    try {
        $apps = @()
        foreach ($app in @(Read-AppDatabase)) {
            if ([string](Get-PropertyValue -Object $app -Name "id" -Default "") -ne $AppId) {
                $apps += $app
            }
        }
        Write-AppDatabase -Apps $apps
    }
    catch {
        Write-ErrorLog -Context "Remove app data record $AppId" -ErrorRecord $_
    }
}

function Write-ErrorLog {
    param(
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)]$ErrorRecord
    )

    try {
        Ensure-DataRoot
        $message = @(
            "[$((Get-Date).ToString("o"))] $Context",
            $ErrorRecord.Exception.Message,
            $ErrorRecord.ScriptStackTrace,
            ""
        ) -join [Environment]::NewLine
        Add-Content -LiteralPath (Join-Path $DataRoot "errors.log") -Value $message -Encoding UTF8
    }
    catch {
        # Logging must never break registration.
    }
}

function ConvertTo-UiText {
    param($Value)

    if ($null -eq $Value) {
        return ""
    }

    return [string]$Value
}

function Get-AppDisplayName {
    param([Parameter(Mandatory = $true)]$App)

    $name = ConvertTo-UiText $App.Name
    if ($name.Trim()) {
        return $name
    }

    $shortcutPath = ConvertTo-UiText $App.ShortcutPath
    if ($shortcutPath.Trim()) {
        return [System.IO.Path]::GetFileNameWithoutExtension($shortcutPath)
    }

    $targetPath = ConvertTo-UiText $App.TargetPath
    if ($targetPath.Trim()) {
        return [System.IO.Path]::GetFileNameWithoutExtension($targetPath)
    }

    $exeName = ConvertTo-UiText $App.ExeName
    if ($exeName.Trim()) {
        return [System.IO.Path]::GetFileNameWithoutExtension($exeName)
    }

    return ConvertTo-UiText $App.Id
}

function Get-AppTargetText {
    param([Parameter(Mandatory = $true)]$App)

    $targetPath = ConvertTo-UiText $App.TargetPath
    if ($targetPath.Trim()) {
        return $targetPath
    }

    $shortcutPath = ConvertTo-UiText $App.ShortcutPath
    if ($shortcutPath.Trim()) {
        return $shortcutPath
    }

    return ConvertTo-UiText $App.ExeName
}

function New-Shortcut {
    param(
        [Parameter(Mandatory = $true)][string]$ShortcutPath,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    $folder = [System.IO.Path]::GetDirectoryName($ShortcutPath)
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = $TargetPath
    $shortcut.Save()
}

function Get-ShortcutTarget {
    param([Parameter(Mandatory = $true)][string]$ShortcutPath)

    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        return [string]$shortcut.TargetPath
    }
    catch {
        Write-ErrorLog -Context "Read shortcut $ShortcutPath" -ErrorRecord $_
        return ""
    }
}

function Set-StringValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    if ($Name -eq "(default)") {
        Set-Item -Path $Path -Value ([string]$Value)
        return
    }

    New-ItemProperty -Path $Path -Name $Name -Value ([string]$Value) -PropertyType String -Force | Out-Null
}

function Set-DwordValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Value
    )

    New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType DWord -Force | Out-Null
}

function Remove-RegisteredPortableApp {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [string]$ApplicationExeName,
        [string]$ApplicationShortcutPath
    )

    $uninstallKey = Join-Path $UninstallRoot $AppId
    if (Test-Path -LiteralPath $uninstallKey) {
        $item = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
        if (-not $ApplicationExeName) {
            $ApplicationExeName = Get-PropertyValue -Object $item -Name "PortableAppExeName" -Default ""
        }
        if (-not $ApplicationShortcutPath) {
            $ApplicationShortcutPath = Get-PropertyValue -Object $item -Name "PortableAppShortcutPath" -Default ""
        }

        Remove-Item -LiteralPath $uninstallKey -Recurse -Force
    }

    if ($ApplicationExeName) {
        $appPathKey = Join-Path $AppPathsRoot $ApplicationExeName
        if (Test-Path -LiteralPath $appPathKey) {
            Remove-Item -LiteralPath $appPathKey -Recurse -Force
        }
    }

    if ($ApplicationShortcutPath -and (Test-Path -LiteralPath $ApplicationShortcutPath -PathType Leaf)) {
        Remove-Item -LiteralPath $ApplicationShortcutPath -Force
    }

    Remove-AppRecord -AppId $AppId
}

function Search-OfficialNames {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [Parameter(Mandatory = $true)][string]$CurrentName
    )

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($ExePath)
    $parent = Split-Path -Path (Split-Path -Path $ExePath -Parent) -Leaf
    $publisher = Get-Publisher -ExePath $ExePath
    $knownName = Get-KnownAppName -ExePath $ExePath
    $queryBase = if ($knownName) { $knownName } else { $CurrentName }
    $query = "$queryBase $fileName $parent $publisher official software name"
    $url = "https://duckduckgo.com/html/?q=$([uri]::EscapeDataString($query))"

    $names = New-Object System.Collections.Generic.List[string]

    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 8
        $html = [System.Net.WebUtility]::HtmlDecode($response.Content)
        $matches = [regex]::Matches($html, '<a[^>]+class="result__a"[^>]*>(.*?)</a>', 'IgnoreCase')
        foreach ($match in $matches) {
            $title = [regex]::Replace($match.Groups[1].Value, '<.*?>', '')
            $title = ($title -replace '\s+', ' ').Trim()
            $title = ($title -replace '\s*[-|].*$', '').Trim()
            if ($title -and $title.Length -ge 2 -and $title.Length -le 80) {
                Add-NameSuggestion -List $names -Name $title
            }
            if ($names.Count -ge 6) { break }
        }
    }
    catch {
        return @()
    }

    return $names
}

function Show-NameDialog {
    param([Parameter(Mandatory = $true)][string]$ExePath)

    $initialSuggestions = @(Get-NameSuggestions -ExePath $ExePath -IncludeOnline:$false)
    $initialName = if ($initialSuggestions.Count -gt 0) { $initialSuggestions[0] } else { Get-InitialDisplayName -ExePath $ExePath }

    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "Name this app"
    $dialog.Size = New-Object System.Drawing.Size(600, 420)
    $dialog.MinimumSize = New-Object System.Drawing.Size(560, 380)
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

    $pathLabel = New-Object System.Windows.Forms.Label
    $pathLabel.Text = $ExePath
    $pathLabel.AutoEllipsis = $true
    $pathLabel.Left = 16
    $pathLabel.Top = 16
    $pathLabel.Width = 550
    $pathLabel.Height = 24
    $dialog.Controls.Add($pathLabel)

    $suggestionLabel = New-Object System.Windows.Forms.Label
    $suggestionLabel.Text = "Suggestions"
    $suggestionLabel.Left = 16
    $suggestionLabel.Top = 48
    $suggestionLabel.Width = 160
    $suggestionLabel.Height = 24
    $dialog.Controls.Add($suggestionLabel)

    $suggestionList = New-Object System.Windows.Forms.ListBox
    $suggestionList.Left = 16
    $suggestionList.Top = 76
    $suggestionList.Width = 550
    $suggestionList.Height = 150
    $dialog.Controls.Add($suggestionList)

    $nameLabel = New-Object System.Windows.Forms.Label
    $nameLabel.Text = "Start menu name"
    $nameLabel.Left = 16
    $nameLabel.Top = 240
    $nameLabel.Width = 160
    $nameLabel.Height = 24
    $dialog.Controls.Add($nameLabel)

    $nameBox = New-Object System.Windows.Forms.TextBox
    $nameBox.Text = $initialName
    $nameBox.Left = 16
    $nameBox.Top = 268
    $nameBox.Width = 550
    $dialog.Controls.Add($nameBox)

    $searchButton = New-Object System.Windows.Forms.Button
    $searchButton.Text = "Find more online"
    $searchButton.Left = 16
    $searchButton.Top = 312
    $searchButton.Width = 150
    $searchButton.Height = 32
    $dialog.Controls.Add($searchButton)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "Add"
    $okButton.Left = 390
    $okButton.Top = 312
    $okButton.Width = 84
    $okButton.Height = 32
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dialog.Controls.Add($okButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Left = 482
    $cancelButton.Top = 312
    $cancelButton.Width = 84
    $cancelButton.Height = 32
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.Add($cancelButton)

    $message = New-Object System.Windows.Forms.Label
    $message.Text = "Click a suggestion, search online, or type your own name."
    $message.Left = 16
    $message.Top = 354
    $message.Width = 550
    $message.Height = 24
    $dialog.Controls.Add($message)

    $dialog.AcceptButton = $okButton
    $dialog.CancelButton = $cancelButton

    foreach ($suggestion in $initialSuggestions) {
        [void]$suggestionList.Items.Add($suggestion)
    }
    if ($suggestionList.Items.Count -gt 0) {
        $suggestionList.SelectedIndex = 0
    }

    $suggestionList.Add_SelectedIndexChanged({
        if ($suggestionList.SelectedItem) {
            $nameBox.Text = [string]$suggestionList.SelectedItem
        }
    })

    $searchButton.Add_Click({
        $oldText = $searchButton.Text
        try {
            $searchButton.Enabled = $false
            $searchButton.Text = "Searching..."
            $message.Text = "Searching online..."
            [System.Windows.Forms.Application]::DoEvents()
            $foundNames = @(Get-NameSuggestions -ExePath $ExePath -IncludeOnline -CurrentName $nameBox.Text)
            $added = 0
            foreach ($foundName in $foundNames) {
                $exists = $false
                foreach ($item in $suggestionList.Items) {
                    if ([string]$item -eq $foundName) {
                        $exists = $true
                        break
                    }
                }
                if (-not $exists) {
                    [void]$suggestionList.Items.Add($foundName)
                    $added++
                }
            }
            if ($suggestionList.Items.Count -gt 0 -and $suggestionList.SelectedIndex -lt 0) {
                $suggestionList.SelectedIndex = 0
            }
            if ($added -gt 0) {
                $message.Text = "Added $added online suggestion(s). Pick one or edit manually."
            }
            else {
                $message.Text = "No new online suggestions found. Please enter it manually."
            }
        }
        finally {
            $searchButton.Text = $oldText
            $searchButton.Enabled = $true
        }
    })

    $result = $dialog.ShowDialog()
    if ($result -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $name = $nameBox.Text.Trim()
    if (-not $name) {
        return $null
    }

    return $name
}

function Register-PortableExe {
    param(
        [Parameter(Mandatory = $true)][string]$ExePath,
        [Parameter(Mandatory = $true)][string]$DisplayName
    )

    $fullPath = [System.IO.Path]::GetFullPath($ExePath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "File not found: $fullPath"
    }

    if (-not (Test-SupportedLaunchFile -Path $fullPath)) {
        throw "Only .exe, .bat, and .cmd files are supported."
    }

    $step = "read app metadata"
    try {
        $publisher = Get-Publisher -ExePath $fullPath
        $version = Get-Version -ExePath $fullPath
        $appId = Get-StableId -Path $fullPath
        $installLocation = [System.IO.Path]::GetDirectoryName($fullPath)
        $exeName = [System.IO.Path]::GetFileName($fullPath)
        $shortcutFolder = Join-Path $StartMenuRoot $DefaultStartMenuFolder
        $shortcutPath = Join-Path $shortcutFolder "$(Get-SafeFileName -Name $DisplayName).lnk"
        $scriptPath = $PSCommandPath
        $uninstallKey = Join-Path $UninstallRoot $appId
        $uninstallCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -RemoveRegisteredApp -Id `"$appId`" -ExeName `"$exeName`" -ShortcutPath `"$shortcutPath`""

        $record = [PSCustomObject]@{
            id = $appId
            name = $DisplayName
            publisher = $publisher
            version = $version
            targetPath = $fullPath
            installLocation = $installLocation
            exeName = $exeName
            shortcutPath = $shortcutPath
            startMenuFolder = $DefaultStartMenuFolder
            registeredAt = (Get-Date).ToString("o")
        }

        $recordSaved = $true
        $step = "save app data record"
        try {
            Save-AppRecord -Record $record
        }
        catch {
            $recordSaved = $false
            Write-ErrorLog -Context "$step for $fullPath" -ErrorRecord $_
        }

        $step = "write installed-app registry"
        New-Item -Path $uninstallKey -Force | Out-Null
        Set-StringValue -Path $uninstallKey -Name "DisplayName" -Value $DisplayName
        Set-StringValue -Path $uninstallKey -Name "DisplayVersion" -Value $version
        Set-StringValue -Path $uninstallKey -Name "Publisher" -Value $publisher
        Set-StringValue -Path $uninstallKey -Name "InstallLocation" -Value $installLocation
        Set-StringValue -Path $uninstallKey -Name "DisplayIcon" -Value $fullPath
        Set-StringValue -Path $uninstallKey -Name "UninstallString" -Value $uninstallCommand
        Set-StringValue -Path $uninstallKey -Name "PortableAppRegisterId" -Value $appId
        Set-StringValue -Path $uninstallKey -Name "PortableAppExeName" -Value $exeName
        Set-StringValue -Path $uninstallKey -Name "PortableAppTargetPath" -Value $fullPath
        Set-StringValue -Path $uninstallKey -Name "PortableAppShortcutPath" -Value $shortcutPath
        Set-DwordValue -Path $uninstallKey -Name "NoModify" -Value 1
        Set-DwordValue -Path $uninstallKey -Name "NoRepair" -Value 1

        if (Test-AppPathsSupported -Path $fullPath) {
            $step = "write App Paths registry"
            $appPathKey = Join-Path $AppPathsRoot $exeName
            New-Item -Path $appPathKey -Force | Out-Null
            Set-StringValue -Path $appPathKey -Name "(default)" -Value $fullPath
            Set-StringValue -Path $appPathKey -Name "Path" -Value $installLocation
        }

        $step = "remove old shortcut"
        if (Test-Path -LiteralPath $uninstallKey) {
            $existing = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
            $oldShortcutPath = Get-PropertyValue -Object $existing -Name "PortableAppShortcutPath" -Default ""
            if ($oldShortcutPath -and $oldShortcutPath -ne $shortcutPath -and (Test-Path -LiteralPath $oldShortcutPath -PathType Leaf)) {
                Remove-Item -LiteralPath $oldShortcutPath -Force
            }
        }

        $step = "create Start menu shortcut"
        try {
            New-Shortcut -ShortcutPath $shortcutPath -TargetPath $fullPath -WorkingDirectory $installLocation
        }
        catch {
            Write-ErrorLog -Context "$step for $fullPath" -ErrorRecord $_
        }
    }
    catch {
        throw "Failed to $step. $($_.Exception.Message)"
    }

    return [PSCustomObject]@{
        Id = $appId
        Name = $DisplayName
        Publisher = $publisher
        ShortcutPath = $shortcutPath
        TargetPath = $fullPath
        ExeName = $exeName
        RecordSaved = $recordSaved
    }
}

function Get-RegisteredPortableApps {
    $itemsById = @{}

    foreach ($app in @(Read-AppDatabase)) {
        $id = [string](Get-PropertyValue -Object $app -Name "id" -Default "")
        if (-not $id) {
            continue
        }

        $itemsById[$id] = [PSCustomObject]@{
            Id = $id
            Name = [string](Get-PropertyValue -Object $app -Name "name" -Default "")
            Publisher = [string](Get-PropertyValue -Object $app -Name "publisher" -Default "")
            TargetPath = [string](Get-PropertyValue -Object $app -Name "targetPath" -Default "")
            ShortcutPath = [string](Get-PropertyValue -Object $app -Name "shortcutPath" -Default "")
            ExeName = [string](Get-PropertyValue -Object $app -Name "exeName" -Default "")
        }
    }

    $keys = Get-ChildItem -Path $UninstallRoot -ErrorAction SilentlyContinue
    foreach ($key in $keys) {
        $item = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if (-not $item) {
            continue
        }
        if (-not ($item.PSObject.Properties.Name -contains "PortableAppRegisterId")) {
            continue
        }

        $id = [string]$item.PortableAppRegisterId
        $itemsById[$id] = [PSCustomObject]@{
            Id = $id
            Name = [string](Get-PropertyValue -Object $item -Name "DisplayName" -Default "")
            Publisher = [string](Get-PropertyValue -Object $item -Name "Publisher" -Default "")
            TargetPath = [string](Get-PropertyValue -Object $item -Name "PortableAppTargetPath" -Default "")
            ShortcutPath = [string](Get-PropertyValue -Object $item -Name "PortableAppShortcutPath" -Default "")
            ExeName = [string](Get-PropertyValue -Object $item -Name "PortableAppExeName" -Default "")
        }
    }

    $shortcutFolder = Join-Path $StartMenuRoot $DefaultStartMenuFolder
    if (Test-Path -LiteralPath $shortcutFolder -PathType Container) {
        $shortcuts = Get-ChildItem -LiteralPath $shortcutFolder -Filter "*.lnk" -File -ErrorAction SilentlyContinue
        foreach ($shortcut in $shortcuts) {
            $shortcutPath = $shortcut.FullName
            $targetPath = Get-ShortcutTarget -ShortcutPath $shortcutPath
            $id = if ($targetPath) { Get-StableId -Path $targetPath } else { Get-StableId -Path $shortcutPath }

            if ($itemsById.ContainsKey($id)) {
                continue
            }

            $itemsById[$id] = [PSCustomObject]@{
                Id = $id
                Name = [System.IO.Path]::GetFileNameWithoutExtension($shortcut.Name)
                Publisher = "Portable App"
                TargetPath = $targetPath
                ShortcutPath = $shortcutPath
                ExeName = if ($targetPath) { [System.IO.Path]::GetFileName($targetPath) } else { "" }
            }
        }
    }

    return $itemsById.Values | Sort-Object Name
}

if ($RemoveRegisteredApp) {
    Remove-RegisteredPortableApp -AppId $Id -ApplicationExeName $ExeName -ApplicationShortcutPath $ShortcutPath
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "Portable App Register"
$form.Size = New-Object System.Drawing.Size(780, 520)
$form.MinimumSize = New-Object System.Drawing.Size(700, 460)
$form.StartPosition = "CenterScreen"
$form.AllowDrop = $true
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = "Fill"
$listView.View = [System.Windows.Forms.View]::Details
$listView.FullRowSelect = $true
$listView.MultiSelect = $true
$listView.GridLines = $true
$listView.AllowDrop = $true
$listView.HideSelection = $false
[void]$listView.Columns.Add("Name", 240)
[void]$listView.Columns.Add("Publisher", 160)
[void]$listView.Columns.Add("Executable / Shortcut", 340)
$form.Controls.Add($listView)

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = "Top"
$topPanel.Height = 126
$form.Controls.Add($topPanel)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Drop portable .exe, .bat, or .cmd files here"
$title.AutoSize = $false
$title.TextAlign = "MiddleCenter"
$title.Dock = "Top"
$title.Height = 58
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 18, [System.Drawing.FontStyle]::Bold)
$topPanel.Controls.Add($title)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = "After dropping, choose an online name lookup or type the Start menu name manually."
$hint.AutoSize = $false
$hint.TextAlign = "MiddleCenter"
$hint.Dock = "Top"
$hint.Height = 36
$topPanel.Controls.Add($hint)

$status = New-Object System.Windows.Forms.Label
$status.Text = "Waiting for launch files"
$status.AutoSize = $false
$status.TextAlign = "MiddleLeft"
$status.Dock = "Bottom"
$status.Height = 32
$status.Padding = New-Object System.Windows.Forms.Padding(12, 0, 0, 0)
$topPanel.Controls.Add($status)

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Dock = "Bottom"
$buttonPanel.Height = 48
$form.Controls.Add($buttonPanel)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "Refresh"
$refreshButton.Left = 12
$refreshButton.Top = 8
$refreshButton.Width = 96
$refreshButton.Height = 32
$buttonPanel.Controls.Add($refreshButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = "Remove selected"
$deleteButton.Left = 116
$deleteButton.Top = 8
$deleteButton.Width = 140
$deleteButton.Height = 32
$buttonPanel.Controls.Add($deleteButton)

$openFolderButton = New-Object System.Windows.Forms.Button
$openFolderButton.Text = "Open Start menu folder"
$openFolderButton.Left = 264
$openFolderButton.Top = 8
$openFolderButton.Width = 170
$openFolderButton.Height = 32
$buttonPanel.Controls.Add($openFolderButton)

$openDataButton = New-Object System.Windows.Forms.Button
$openDataButton.Text = "Open app data"
$openDataButton.Left = 442
$openDataButton.Top = 8
$openDataButton.Width = 130
$openDataButton.Height = 32
$buttonPanel.Controls.Add($openDataButton)

function Refresh-AppList {
    try {
        $listView.Items.Clear()
        $apps = @(Get-RegisteredPortableApps)
        foreach ($app in $apps) {
            try {
                $item = New-Object System.Windows.Forms.ListViewItem
                $item.Text = Get-AppDisplayName -App $app
                [void]$item.SubItems.Add((ConvertTo-UiText $app.Publisher))
                [void]$item.SubItems.Add((Get-AppTargetText -App $app))
                $item.Tag = $app
                [void]$listView.Items.Add($item)
            }
            catch {
                Write-ErrorLog -Context "Add list item" -ErrorRecord $_
            }
        }

        $status.Text = "Registered apps: $($apps.Count), visible rows: $($listView.Items.Count)"
    }
    catch {
        Write-ErrorLog -Context "Refresh app list" -ErrorRecord $_
        $status.Text = "Could not refresh list. See errors.log in app data."
    }
}

function Upsert-AppListItem {
    param([Parameter(Mandatory = $true)]$App)

    foreach ($existingItem in @($listView.Items)) {
        if ($existingItem.Tag -and $existingItem.Tag.Id -eq $App.Id) {
            $existingItem.Text = Get-AppDisplayName -App $App
            $existingItem.SubItems[1].Text = ConvertTo-UiText $App.Publisher
            $existingItem.SubItems[2].Text = Get-AppTargetText -App $App
            $existingItem.Tag = $App
            return
        }
    }

    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = Get-AppDisplayName -App $App
    [void]$item.SubItems.Add((ConvertTo-UiText $App.Publisher))
    [void]$item.SubItems.Add((Get-AppTargetText -App $App))
    $item.Tag = $App
    [void]$listView.Items.Add($item)
}

function Add-ExeFiles {
    param([Parameter(Mandatory = $true)]$Files)

    $exeFiles = @($Files | Where-Object { Test-SupportedLaunchFile -Path $_ })
    if ($exeFiles.Count -eq 0) {
        $status.Text = "No supported .exe, .bat, or .cmd files found"
        return
    }

    $registeredNames = New-Object System.Collections.Generic.List[string]
    $registeredApps = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($exe in $exeFiles) {
        try {
            $name = Show-NameDialog -ExePath $exe
            if (-not $name) {
                continue
            }

            $result = Register-PortableExe -ExePath $exe -DisplayName $name
            $registeredApps.Add($result)
            $registeredNames.Add($result.Name)
            if (-not $result.RecordSaved) {
                $warnings.Add("$($result.Name): app data record was not saved")
            }
        }
        catch {
            Write-ErrorLog -Context "Register $exe" -ErrorRecord $_
            $errors.Add("$([System.IO.Path]::GetFileName($exe)): $($_.Exception.Message)")
        }
    }

    try {
        Refresh-AppList
    }
    catch {
        Write-ErrorLog -Context "Refresh after add" -ErrorRecord $_
    }

    foreach ($app in $registeredApps) {
        Upsert-AppListItem -App $app
    }
    if ($registeredNames.Count -gt 0 -and ($errors.Count -gt 0 -or $warnings.Count -gt 0)) {
        $details = @($warnings) + @($errors)
        $status.Text = "Added with warning: " + ($registeredNames -join ", ") + " | " + ($details -join " | ")
    }
    elseif ($registeredNames.Count -gt 0) {
        $status.Text = "Added: " + ($registeredNames -join ", ")
    }
    elseif ($errors.Count -gt 0) {
        $status.Text = "Registration failed: " + ($errors -join " | ")
    }
    else {
        $status.Text = "No apps added"
    }
}

$handleDrop = {
    param($sender, $eventArgs)

    try {
        $files = $eventArgs.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
        Add-ExeFiles -Files $files
    }
    catch {
        Write-ErrorLog -Context "Drop handler" -ErrorRecord $_
        Refresh-AppList
        $status.Text = "Registration failed: $($_.Exception.Message)"
    }
}

$handleDragEnter = {
    param($sender, $eventArgs)

    if ($eventArgs.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
        $eventArgs.Effect = [System.Windows.Forms.DragDropEffects]::Copy
    }
    else {
        $eventArgs.Effect = [System.Windows.Forms.DragDropEffects]::None
    }
}

$refreshButton.Add_Click({ Refresh-AppList })

$deleteButton.Add_Click({
    if ($listView.SelectedItems.Count -eq 0) {
        $status.Text = "Select one or more apps to remove"
        return
    }

    $count = $listView.SelectedItems.Count
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Remove $count selected app registration(s)? This only removes Start menu shortcuts and registry entries.",
        "Confirm removal",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        return
    }

    foreach ($item in @($listView.SelectedItems)) {
        $app = $item.Tag
        Remove-RegisteredPortableApp `
            -AppId $app.Id `
            -ApplicationExeName $app.ExeName `
            -ApplicationShortcutPath $app.ShortcutPath
    }

    Refresh-AppList
    $status.Text = "Removed $count app registration(s)"
})

$openFolderButton.Add_Click({
    $folder = Join-Path $StartMenuRoot $DefaultStartMenuFolder
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList "`"$folder`""
})

$openDataButton.Add_Click({
    Ensure-DataRoot
    Start-Process explorer.exe -ArgumentList "`"$DataRoot`""
})

$form.Add_DragEnter($handleDragEnter)
$form.Add_DragDrop($handleDrop)
$listView.Add_DragEnter($handleDragEnter)
$listView.Add_DragDrop($handleDrop)

Refresh-AppList
[void]$form.ShowDialog()
