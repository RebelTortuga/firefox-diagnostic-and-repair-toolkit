# Firefox Diagnostic and Repair Toolkit | RebelTortuga | Version 1.0.0
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
# Add the confirmed public Ko-fi URL here and to README.md before enabling support links.
$script:KoFiUrl = 'https://ko-fi.com/rebeltortuga'
$script:Profile = $null
$script:Report = @()
$state = Join-Path $env:LOCALAPPDATA 'RebelTortuga\Firefox-Toolkit'
$logs = Join-Path $state 'Logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$script:LogFile = Join-Path $logs ("Firefox-" + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff') + '.txt')
$settings = Join-Path $state 'settings.json'
function Log($text) { Add-Content -LiteralPath $script:LogFile -Value "[$(Get-Date -Format o)] $text" -Encoding UTF8 }
function Closed {
    if (Get-Process firefox -ErrorAction SilentlyContinue) { throw 'Completely exit Firefox, including background processes, before continuing. The toolkit does not terminate Firefox.' }
}
function GetFirefoxProfiles {
    $base = Join-Path $env:APPDATA 'Mozilla\Firefox'
    $found = @{}
    $ini = Join-Path $base 'profiles.ini'
    if (Test-Path -LiteralPath $ini -PathType Leaf) {
        $entries = @(); $entry = $null
        foreach ($line in (Get-Content -LiteralPath $ini)) {
            if ($line -match '^\[(.+)\]$') {
                if ($entry) { $entries += $entry }
                $entry = if ($matches[1] -match '^Profile\d+$') { @{} } else { $null }
            } elseif ($null -ne $entry -and $line -match '^([^=]+)=(.*)$') {
                $entry[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
        if ($entry) { $entries += $entry }
        foreach ($entry in $entries) {
            if (!$entry.Path) { continue }
            try {
                $path = if ($entry.IsRelative -eq '1') { Join-Path $base $entry.Path.Replace('/','\') } else { $entry.Path }
                $path = [IO.Path]::GetFullPath($path)
                if (Test-Path -LiteralPath (Join-Path $path 'prefs.js') -PathType Leaf) {
                    $name = if ($entry.Name) { $entry.Name } else { Split-Path $path -Leaf }
                    $found[$path] = [pscustomobject]@{ Name=$name; Path=$path; Display="$name - $path" }
                }
            } catch { Log 'Skipped an invalid profile registration.' }
        }
    }
    $standard = Join-Path $base 'Profiles'
    if (Test-Path -LiteralPath $standard -PathType Container) {
        foreach ($folder in (Get-ChildItem -LiteralPath $standard -Directory)) {
            if (!$found.ContainsKey($folder.FullName) -and (Test-Path -LiteralPath (Join-Path $folder.FullName 'prefs.js') -PathType Leaf)) {
                $found[$folder.FullName] = [pscustomobject]@{ Name=$folder.Name; Path=$folder.FullName; Display="$($folder.Name) - $($folder.FullName)" }
            }
        }
    }
    return @($found.Values | Sort-Object Name,Path)
}
function SetProfile([string]$path) {
    if (!(Test-Path -LiteralPath (Join-Path $path 'prefs.js') -PathType Leaf)) { throw 'This folder is not an initialized Firefox profile. Open Firefox once, then try again.' }
    $script:Profile = [IO.Path]::GetFullPath($path)
    @{Profile=$script:Profile} | ConvertTo-Json | Set-Content -LiteralPath $settings -Encoding UTF8
    Log 'Profile selection saved.'
}
function ChooseProfile {
    if ($script:ProfilePicker) {
        $script:ProfilePicker.Focus()
        $script:ProfilePicker.DroppedDown = $true
        return
    }
    throw 'Choose your Firefox profile using the Profile list at the top of the window.'
}
function BrowseProfile {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Custom profile: select the ROOT folder containing prefs.js. Firefox about:profiles shows Root Directory.'
    $dialog.SelectedPath = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    try {
        if ($dialog.ShowDialog() -ne 'OK') { return }
        SetProfile $dialog.SelectedPath
        $record = [pscustomobject]@{ Name=(Split-Path $script:Profile -Leaf); Path=$script:Profile; Display=$script:Profile }
        $index = $script:ProfilePicker.Items.Add($record)
        $script:ProfilePicker.SelectedIndex = $index
    } finally { $dialog.Dispose() }
}
function RequireProfile {
    if (!$script:Profile -or !(Test-Path -LiteralPath (Join-Path $script:Profile 'prefs.js') -PathType Leaf)) {
        throw 'Choose a Firefox profile from the Profile list at the top. If none are listed, open Firefox once, restart the toolkit, or use Browse for a custom profile.'
    }
}
function FirefoxExe {
    $candidates = @()
    foreach ($root in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA)) {
        if ($root) { $candidates += Join-Path $root 'Mozilla Firefox\firefox.exe' }
    }
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe')) {
        if (Test-Path $key) { $candidates += (Get-Item $key).GetValue('') }
    }
    foreach ($path in $candidates) { if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) { return $path } }
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select your Firefox executable'
    $dialog.Filter = 'Firefox executable (firefox.exe)|firefox.exe'
    try { if ($dialog.ShowDialog() -eq 'OK') { return $dialog.FileName } } finally { $dialog.Dispose() }
    throw 'Firefox executable was not selected.'
}
function Finding($status,$text) {
    $script:Report += "[$status] $text"
    $color = switch ($status) { 'PASS' {'Green'} 'WARN' {'Yellow'} 'FAIL' {'Red'} default {'Cyan'} }
    Write-Host "[$status] $text" -ForegroundColor $color
}
function Diagnose([bool]$full) {
    RequireProfile
    $script:Report = @('Firefox Diagnostic and Repair Toolkit - RebelTortuga',"Scan time: $(Get-Date -Format o)","Profile: $script:Profile",'Findings are indicators, not proof of corruption or a guaranteed diagnosis.','')
    Finding 'PASS' 'Selected profile exists and contains prefs.js.'
    $running = @(Get-Process firefox -ErrorAction SilentlyContinue)
    Finding 'INFO' "Firefox processes: $($running.Count). Close all before backup or repairs."
    foreach ($name in @('prefs.js','places.sqlite','logins.json','key4.db','extensions.json')) {
        $path = Join-Path $script:Profile $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $file = Get-Item -LiteralPath $path
            if (!$file.Length) { Finding 'WARN' "$name is empty. Review before restoring or replacing anything." }
            else { Finding 'PASS' "$name present ($($file.Length) bytes). Presence does not establish integrity." }
        } else { Finding 'INFO' "$name absent; some files are optional or created only after use." }
    }
    if ((Test-Path -LiteralPath (Join-Path $script:Profile 'logins.json')) -and !(Test-Path -LiteralPath (Join-Path $script:Profile 'key4.db'))) { Finding 'FAIL' 'Saved login file exists but its key database is missing.' }
    $snapshots = @(Get-ChildItem -LiteralPath (Join-Path $script:Profile 'bookmarkbackups') -File -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    if ($snapshots.Count) { Finding 'INFO' "Latest automatic bookmark snapshot: $($snapshots[0].Name). May not contain recent edits." }
    else { Finding 'WARN' 'No automatic bookmark snapshot found. Export bookmarks from Firefox.' }
    try {
        $root = [IO.Path]::GetPathRoot($script:Profile)
        $drive = New-Object IO.DriveInfo($root)
        if ($drive.AvailableFreeSpace -lt 1GB) { Finding 'WARN' 'Profile drive has less than 1 GB available.' }
        else { Finding 'INFO' "Profile drive free space: $([math]::Round($drive.AvailableFreeSpace/1GB,2)) GB." }
    } catch { Finding 'UNKNOWN' 'Could not determine profile drive space.' }
    if ($full) {
        foreach ($name in @('extensions.json','logins.json')) {
            $path = Join-Path $script:Profile $name
            if (Test-Path -LiteralPath $path) {
                try { $null = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json; Finding 'PASS' "$name parses as JSON; contents were not printed." }
                catch { Finding 'WARN' "$name could not be parsed. A running Firefox can affect scan results." }
            }
        }
        $items = @(Get-ChildItem -LiteralPath $script:Profile -File -ErrorAction Stop)
        Finding 'INFO' "Root profile files: $($items.Count). Root-file size: $([math]::Round(($items | Measure-Object Length -Sum).Sum/1MB,2)) MB; subfolders excluded."
        Finding 'INFO' 'SQLite databases were not opened or checked for corruption. Use Firefox about:support > Places Database > Verify Integrity if available.'
    }
    Log "Diagnostics completed. Full scan: $full"
}
function ExportReport {
    if (!$script:Report.Count) { throw 'Run a diagnostic scan first.' }
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Filter = 'Text report (*.txt)|*.txt|Markdown report (*.md)|*.md'
    $dialog.FileName = 'Firefox Diagnostic Report ' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss') + '.txt'
    try {
        if ($dialog.ShowDialog() -eq 'OK') {
            $script:Report | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
            Write-Host "Report saved: $($dialog.FileName). Review and redact identifying paths before sharing." -ForegroundColor Green
            Log 'Diagnostic report exported.'
        }
    } finally { $dialog.Dispose() }
}
function RunBackupEngine([string]$action, [string]$profilePath) {
    $engine = Join-Path $PSScriptRoot 'FirefoxBackup.ps1'
    if (!(Test-Path -LiteralPath $engine -PathType Leaf)) { throw 'FirefoxBackup.ps1 is missing. Extract all toolkit files into one folder.' }
    $arguments = "-NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$engine`" -Action $action"
    if ($profilePath) { $arguments += " -ProfilePath `"$profilePath`"" }
    $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $process = Start-Process -FilePath $powershellPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) { throw "$action did not complete. Review the message from the backup dialog." }
}
function BackupAction($action) {
    RequireProfile
    Closed
    Write-Host 'Backup/restore dialogs will open. The main toolkit stays open; the PowerShell console remains hidden.'
    RunBackupEngine $action $script:Profile
    Log "$action window closed. Check its completion message; cancellation is not a completed operation."
}
function OpenFirefoxPage($page) {
    RequireProfile
    Closed
    $exe = FirefoxExe
    Start-Process -FilePath $exe -ArgumentList "-no-remote -profile `"$script:Profile`" $page"
    Log "Opened Firefox page $page."
}
function ClearStartupCache {
    RequireProfile
    Closed
    $cache = Join-Path $script:Profile 'startupCache'
    if (!(Test-Path -LiteralPath $cache -PathType Container)) { Write-Host 'No startupCache folder was found in this profile. Use about:support > Clear startup cache instead.'; return }
    $item = Get-Item -LiteralPath $cache -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Cache is a linked folder; use Firefox built-in cache clearing instead.' }
    Write-Host 'Moves startupCache into a recovery folder outside the profile. Firefox can regenerate the cache. It does not reset bookmarks or passwords.' -ForegroundColor Yellow
    if ([System.Windows.Forms.MessageBox]::Show('Move startupCache to a recovery folder? Firefox must remain closed.', 'Confirm cache repair', 'YesNo', 'Warning') -ne 'Yes') { return }
    $dest = Join-Path $state ('Recovery\Startup Cache ' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'))
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Closed
    Move-Item -LiteralPath $cache -Destination (Join-Path $dest 'startupCache')
    Write-Host "Cache moved. Recovery copy: $dest" -ForegroundColor Green
    Log "Startup cache moved to $dest"
}
function OpenGuide {
    $guide = Join-Path $PSScriptRoot 'OPTIONS-README.md'
    try { Start-Process -FilePath $guide } catch { Start-Process notepad.exe -ArgumentList "`"$guide`"" }
}
function OptionalSupport {
    Write-Host "`nOPTIONAL TACO TIP - RebelTortuga" -ForegroundColor Cyan
    Write-Host 'The toolkit is free. Tips are completely optional and do not unlock features.'
    Write-Host 'Bug reports, suggestions and sharing the project are welcome too.'
    if ([string]::IsNullOrWhiteSpace($script:KoFiUrl)) {
        Write-Host 'A Ko-fi support link may be added in a future release. No payment link is configured yet.'
        Write-Host 'When available, the same full link will be printed in README.md so you can open it yourself.'
        return
    }
    $uri = $null
    if (![Uri]::TryCreate($script:KoFiUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'ko-fi.com' -or $uri.UserInfo) {
        throw 'Support link is invalid. The release author must configure a confirmed HTTPS ko-fi.com URL.'
    }
    Write-Host "Ko-fi: $script:KoFiUrl"
    Write-Host 'Opening this link takes you to Ko-fi in your default browser. No payment is made by the toolkit.'
    if ([System.Windows.Forms.MessageBox]::Show("Open this optional support page?`n$script:KoFiUrl", 'Optional support', 'YesNo', 'Question') -eq 'Yes') {
        Start-Process -FilePath $script:KoFiUrl
        Log 'Optional Ko-fi page opened at user request.'
    }
}

function Confirm($message,$title) {
    return [System.Windows.Forms.MessageBox]::Show($message,$title,'YesNo','Warning') -eq 'Yes'
}
function RunAction([scriptblock]$work) {
    $script:Form.UseWaitCursor = $true
    $script:ActionPanel.Enabled = $false
    $script:Nav.Enabled = $false
    $script:ProfilePanel.Enabled = $false
    $script:ExitButton.Enabled = $false
    $script:Busy = $true
    try {
        $script:Results.AppendText("`r`n[$(Get-Date -Format 'HH:mm:ss')] Started.`r`n")
        $output = @(& $work 6>&1 | ForEach-Object { $_.ToString() })
        if ($output.Count) { $script:Results.AppendText(($output -join "`r`n") + "`r`n") }
        $script:Results.AppendText("Action window closed / command returned. Check the reported outcome; cancellation does not mean completion.`r`n")
    } catch {
        $script:Results.AppendText("ERROR: $($_.Exception.Message)`r`n")
        Log "Action error: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Firefox Toolkit','OK','Error') | Out-Null
    } finally {
        $script:Form.UseWaitCursor = $false
        $script:ActionPanel.Enabled = $true
        $script:Nav.Enabled = $true
        $script:ProfilePanel.Enabled = $true
        $script:ExitButton.Enabled = $true
        $script:Busy = $false

    }
}
function InvokeAction([string]$id) {
    switch ($id) {
        'quick' { Diagnose $false }
        'full' { Diagnose $true }
        'export' { ExportReport }
        '2' { BackupAction 'Backup' }
        '3' { BackupAction 'Restore' }
        '4' { ChooseProfile }
        '5' { RequireProfile; Start-Process explorer.exe -ArgumentList "`"$script:Profile`"" }
        '6' { Start-Process explorer.exe -ArgumentList "`"$logs`"" }
        '7' { if (Confirm 'Close Firefox completely. In its prompt choose Open in Troubleshoot Mode, not Refresh. Launch now?' 'Troubleshoot Mode') { OpenFirefoxPage '-safe-mode' } }
        '8' { ClearStartupCache }
        '9' { if (Confirm 'Refresh removes extensions and custom preferences. Back up first. Open about:support? You must initiate and confirm Refresh inside Firefox.' 'Guided Firefox Refresh') { OpenFirefoxPage 'about:support' } }
        '10' { Closed; Write-Host 'Create a new test profile in Profile Manager. Retain your original profile.'; Start-Process -FilePath (FirefoxExe) -ArgumentList '-no-remote -ProfileManager' }
        '11' { OpenFirefoxPage 'about:support' }
        '12' { RunBackupEngine 'Verify' $null }
        '13' { Write-Host 'Author: RebelTortuga. Use this repository Issues tab for feedback. Include versions, steps and error text; never upload passwords or profiles. Repository URL will be added when confirmed.' }
        '14' { Start-Process 'https://support.mozilla.org/en-US/kb/troubleshoot-and-diagnose-firefox-problems' }
        '15' { OptionalSupport }
    }
}
function ShowSection([string]$name) {
    $script:ActionPanel.Controls.Clear()
    $script:SectionTitle.Text = $name
    $items = @(switch ($name) {
        'Diagnostics' { [pscustomobject]@{ Id='quick'; Text='Quick health check' }; [pscustomobject]@{ Id='full'; Text='Full local scan' }; [pscustomobject]@{ Id='export'; Text='Export last report' } }
        'Backup & Restore' { [pscustomobject]@{ Id='2'; Text='Save a backup - choose categories' }; [pscustomobject]@{ Id='3'; Text='Restore a backup' } }
        'Profile and Folders' { [pscustomobject]@{ Id='5'; Text='Open profile folder' }; [pscustomobject]@{ Id='6'; Text='Saved Logs' } }
        'Repair & Troubleshoot' { [pscustomobject]@{ Id='7'; Text='Troubleshoot Mode' }; [pscustomobject]@{ Id='8'; Text='Clear startup cache' }; [pscustomobject]@{ Id='9'; Text='Refresh Firefox - guided' }; [pscustomobject]@{ Id='10'; Text='Profile Manager / clean test profile' } }
        'Other Tools' { [pscustomobject]@{ Id='11'; Text='Open about:support' }; [pscustomobject]@{ Id='12'; Text='Verify a backup' }; [pscustomobject]@{ Id='13'; Text='Feedback and GitHub information' }; [pscustomobject]@{ Id='14'; Text='Mozilla troubleshooting guidance' } }
        'Optional Support' { [pscustomobject]@{ Id='15'; Text='Optional Ko-fi support' } }
    })
    foreach ($item in $items) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $item.Text
        $button.Tag = $item.Id
        $button.Size = New-Object System.Drawing.Size(470,42)
        $button.Margin = New-Object System.Windows.Forms.Padding(0,0,0,10)
        $button.TextAlign = 'MiddleLeft'
        $button.Add_Click({ $id = [string]$this.Tag; RunAction { InvokeAction $id } })
        $script:ActionPanel.Controls.Add($button)
    }
    foreach ($button in $script:NavButtons) {
        if ($button.Tag -eq 'Optional Support') {
            $button.BackColor = [Drawing.Color]::RoyalBlue
            $button.ForeColor = [Drawing.Color]::White
        } elseif ($button.Tag -eq 'Diagnostics') {
            $button.BackColor = [Drawing.Color]::ForestGreen
            $button.ForeColor = [Drawing.Color]::White
        } else {
            $button.BackColor = if ($button.Tag -eq $name) { [Drawing.Color]::LightSteelBlue } else { [Drawing.SystemColors]::Control }
        }
    }
}
try {
    if (Test-Path -LiteralPath $settings) {
        try {
            $saved = (Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).Profile
            if ($saved -and (Test-Path -LiteralPath (Join-Path $saved 'prefs.js'))) { $script:Profile = $saved }
        } catch { Log 'Saved profile selection could not be loaded.' }
    }
    Log 'Sidebar toolkit started.'
    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = 'Firefox Diagnostic and Repair Toolkit - Version 1.0.0 - RebelTortuga'
    $script:Form.Size = New-Object Drawing.Size(1050,900)
    $script:Form.MinimumSize = New-Object Drawing.Size(920,850)
    $script:Form.StartPosition = 'CenterScreen'
    $script:Form.Font = New-Object Drawing.Font('Segoe UI',10)
    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = 'Fill'
    $layout.ColumnCount = 2
    $layout.RowCount = 5
    $layout.Padding = New-Object System.Windows.Forms.Padding(18)
    $null = $layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',230)))
    $null = $layout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    foreach ($height in @(110,90,250)) { $null = $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',$height))) }
    $null = $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $null = $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',40)))
    $script:Form.Controls.Add($layout)
    $title = New-Object System.Windows.Forms.Label
    $title.Text = 'Firefox Diagnostic and Repair Toolkit' + "`r`n" + 'Version 1.0.0 | RebelTortuga | Free to use' + "`r`n`r`n" + 'Close Firefox completely before backups or repairs.'
    $title.Dock = 'Fill'
    $layout.Controls.Add($title,0,0)
    $layout.SetColumnSpan($title,2)
    $script:ProfilePanel = New-Object System.Windows.Forms.TableLayoutPanel
    $script:ProfilePanel.Dock = 'Fill'
    $script:ProfilePanel.ColumnCount = 3
    $script:ProfilePanel.RowCount = 2
    $null = $script:ProfilePanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',65)))
    $null = $script:ProfilePanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Percent',100)))
    $null = $script:ProfilePanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle('Absolute',160)))
    $null = $script:ProfilePanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',38)))
    $null = $script:ProfilePanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $profileCaption = New-Object System.Windows.Forms.Label
    $profileCaption.Text = 'Profile:'
    $profileCaption.Dock = 'Fill'
    $profileCaption.TextAlign = 'MiddleLeft'
    $script:ProfilePanel.Controls.Add($profileCaption,0,0)
    $script:ProfilePicker = New-Object System.Windows.Forms.ComboBox
    $script:ProfilePicker.Dock = 'Fill'
    $script:ProfilePicker.DropDownStyle = 'DropDownList'
    $script:ProfilePicker.DisplayMember = 'Display'
    $script:ProfilePicker.DropDownWidth = 650
    $placeholder = [pscustomobject]@{ Display='Choose your Firefox profile here'; Path=$null }
    $null = $script:ProfilePicker.Items.Add($placeholder)
    foreach ($record in @(GetFirefoxProfiles)) { $null = $script:ProfilePicker.Items.Add($record) }
    if ($script:Profile) {
        $exists = $false
        foreach ($record in $script:ProfilePicker.Items) { if ($record.Path -eq $script:Profile) { $exists = $true } }
        if (!$exists) { $null = $script:ProfilePicker.Items.Add([pscustomobject]@{Display=$script:Profile; Path=$script:Profile}) }
    }
    $script:ProfilePicker.SelectedIndex = 0
    for ($i=1; $i -lt $script:ProfilePicker.Items.Count; $i++) {
        if ($script:ProfilePicker.Items[$i].Path -eq $script:Profile) { $script:ProfilePicker.SelectedIndex = $i; break }
    }
    $script:ProfilePicker.Add_SelectedIndexChanged({
        if ($this.SelectedItem.Path) {
            try { SetProfile $this.SelectedItem.Path; $script:Results.AppendText("Selected Firefox profile: $script:Profile`r`n") }
            catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Profile selection','OK','Error') | Out-Null }
        } else { $script:Profile = $null }
    })
    $script:ProfilePanel.Controls.Add($script:ProfilePicker,1,0)
    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Browse custom...'
    $browse.Dock = 'Fill'
    $browse.Add_Click({ RunAction { BrowseProfile } })
    $script:ProfilePanel.Controls.Add($browse,2,0)
    $profileHelp = New-Object System.Windows.Forms.Label
    $profileHelp.Text = 'A profile holds your bookmarks, passwords and settings. Choose the one you normally use. If unsure, Firefox about:profiles identifies the profile in use.'
    $profileHelp.Dock = 'Fill'
    $script:ProfilePanel.Controls.Add($profileHelp,0,1)
    $script:ProfilePanel.SetColumnSpan($profileHelp,3)
    $layout.Controls.Add($script:ProfilePanel,0,1)
    $layout.SetColumnSpan($script:ProfilePanel,2)
    $script:Nav = New-Object System.Windows.Forms.TableLayoutPanel
    $script:Nav.Dock = 'Fill'
    $script:Nav.ColumnCount = 1
    $script:Nav.RowCount = 10
    foreach ($height in @(50,50,50,50,50,50)) { $null = $script:Nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',$height))) }
    $null = $script:Nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',50)))
    $null = $script:Nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',50)))
    $null = $script:Nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',50)))
    $null = $script:Nav.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',50)))
    $layout.Controls.Add($script:Nav,0,2)
    $layout.SetRowSpan($script:Nav,3)
    $script:NavButtons = @()
    $row = 0
    foreach ($name in @('Profile and Folders','Backup && Restore','Diagnostics','Repair && Troubleshoot','Other Tools')) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $name
        $button.Tag = $name.Replace('&&','&')
        if ($button.Tag -eq 'Diagnostics') {
            $button.UseVisualStyleBackColor = $false
            $button.BackColor = [Drawing.Color]::ForestGreen
            $button.ForeColor = [Drawing.Color]::White
        }
        $button.Dock = 'Fill'
        $button.Margin = New-Object System.Windows.Forms.Padding(0,0,12,8)
        $button.Add_Click({ ShowSection $this.Tag })
        $script:Nav.Controls.Add($button,0,$row)
        $script:NavButtons += $button
        $row++
    }
    $help = New-Object System.Windows.Forms.Button
    $help.Text = 'Detailed Options Guide (H)'
    $help.UseVisualStyleBackColor = $false
    $help.BackColor = [Drawing.Color]::Khaki
    $help.ForeColor = [Drawing.Color]::Black
    $help.Dock = 'Fill'
    $help.Margin = New-Object System.Windows.Forms.Padding(0,0,12,8)
    $help.Add_Click({ RunAction { OpenGuide } })
    $script:Nav.Controls.Add($help,0,5)
    $support = New-Object System.Windows.Forms.Button
    $support.Text = 'Optional Support'
    $support.UseVisualStyleBackColor = $false
    $support.BackColor = [Drawing.Color]::RoyalBlue
    $support.ForeColor = [Drawing.Color]::White
    $support.Tag = 'Optional Support'
    $support.Dock = 'Fill'
    $support.Margin = New-Object System.Windows.Forms.Padding(0,0,12,8)
    $support.Add_Click({ ShowSection 'Optional Support' })
    $script:Nav.Controls.Add($support,0,7)
    $script:NavButtons += $support
    $script:ExitButton = New-Object System.Windows.Forms.Button
    $script:ExitButton.Text = 'Exit Toolkit'
    $script:ExitButton.Dock = 'Fill'
    $script:ExitButton.Margin = New-Object System.Windows.Forms.Padding(0,0,12,0)
    $script:ExitButton.UseVisualStyleBackColor = $false
    $script:ExitButton.BackColor = [Drawing.Color]::Firebrick
    $script:ExitButton.ForeColor = [Drawing.Color]::White
    $script:ExitButton.Font = New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
    $script:ExitButton.Add_Click({ $script:Form.Close() })
    $script:Nav.Controls.Add($script:ExitButton,0,9)
    $content = New-Object System.Windows.Forms.TableLayoutPanel
    $content.Dock = 'Fill'
    $content.RowCount = 2
    $null = $content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',35)))
    $null = $content.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $layout.Controls.Add($content,1,2)
    $script:SectionTitle = New-Object System.Windows.Forms.Label
    $script:SectionTitle.Dock = 'Fill'
    $script:SectionTitle.Font = New-Object Drawing.Font('Segoe UI',12,[Drawing.FontStyle]::Bold)
    $content.Controls.Add($script:SectionTitle,0,0)
    $script:ActionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
    $script:ActionPanel.Dock = 'Fill'
    $script:ActionPanel.FlowDirection = 'TopDown'
    $script:ActionPanel.WrapContents = $false
    $script:ActionPanel.AutoScroll = $true
    $content.Controls.Add($script:ActionPanel,0,1)
    $resultsPanel = New-Object System.Windows.Forms.TableLayoutPanel
    $resultsPanel.Dock = 'Fill'
    $resultsPanel.RowCount = 2
    $null = $resultsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Absolute',30)))
    $null = $resultsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle('Percent',100)))
    $resultsCaption = New-Object System.Windows.Forms.Label
    $resultsCaption.Text = 'Results and messages appear here'
    $resultsCaption.Dock = 'Fill'
    $resultsPanel.Controls.Add($resultsCaption,0,0)
    $script:Results = New-Object System.Windows.Forms.TextBox
    $script:Results.Multiline = $true
    $script:Results.ReadOnly = $true
    $script:Results.ScrollBars = 'Vertical'
    $script:Results.Dock = 'Fill'
    $script:Results.Font = New-Object Drawing.Font('Consolas',10)
    $script:Results.Text = ''
    $resultsPanel.Controls.Add($script:Results,0,1)
    $layout.Controls.Add($resultsPanel,1,3)
    $logCaption = New-Object System.Windows.Forms.Label
    $logCaption.Text = "Saved Log Path: $script:LogFile"
    $logCaption.Dock = 'Fill'
    $logCaption.AutoEllipsis = $true
    $layout.Controls.Add($logCaption,1,4)
    $script:Form.KeyPreview = $true
    $script:Form.Add_KeyDown({ if (!$script:Busy -and $_.KeyCode -eq 'H' -and !($_.Control -or $_.Alt)) { RunAction { OpenGuide }; $_.Handled = $true } })
    $script:Form.Add_FormClosing({ if ($script:Busy) { $_.Cancel = $true } })
    $script:Form.Add_FormClosed({ Log 'Toolkit exited.' })
    ShowSection 'Profile and Folders'
    [void]$script:Form.ShowDialog()
    $script:Form.Dispose()
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Firefox Toolkit - Startup Failed','OK','Error') | Out-Null
    exit 1
}
