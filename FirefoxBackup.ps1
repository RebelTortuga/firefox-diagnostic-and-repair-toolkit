param([ValidateSet('Choose','Backup','Restore','Verify')][string]$Action='Choose', [string]$ProfilePath)
# Firefox Backup and Restore | RebelTortuga
# Windows PowerShell 5.1 or later; no administrator privileges required.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
function Closed {
    if (Get-Process firefox -ErrorAction SilentlyContinue) { throw 'Close Firefox, including background processes, and try again.' }
}
function Folder($title, $initial) {
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    $d.Description = $title
    if ($initial -and (Test-Path -LiteralPath $initial)) { $d.SelectedPath = $initial }
    try {
        if ($d.ShowDialog() -eq 'OK') { return $d.SelectedPath }
        return $null
    } finally { $d.Dispose() }
}
function CopyTree($from,$to,$log) {
    & robocopy.exe $from $to /E /XJ /R:1 /W:1 /COPY:DAT /DCOPY:DAT /NP "/LOG+:$log" | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copy failed. See $log" }
}
function Selected($from,$to,$log,$choices) {
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    $names = @()
    if ('Passwords' -in $choices) {
        $hasLogins = Test-Path -LiteralPath (Join-Path $from 'logins.json') -PathType Leaf
        $hasKey = Test-Path -LiteralPath (Join-Path $from 'key4.db') -PathType Leaf
        if ($hasLogins -and !$hasKey) { throw 'Saved logins exist but key4.db is missing. Password backup cannot be completed safely.' }
        $names += @('logins.json','logins-backup.json','key4.db')
    }
    if ('Settings' -in $choices -or 'Extensions' -in $choices) { $names += 'prefs.js' }
    if ('Extensions' -in $choices) { $names += @('extensions.json','extension-preferences.json','extension-settings.json') }
    foreach ($name in $names) {
        $f = Join-Path $from $name
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            Copy-Item -LiteralPath $f -Destination $to -Force
            Add-Content -LiteralPath $log -Value "Copied: $name" -Encoding UTF8
        }
    }
    $bookmarkFolder = Join-Path $from 'bookmarkbackups'
    if ('Bookmarks' -in $choices -and (Test-Path -LiteralPath $bookmarkFolder)) {
        $latest = Get-ChildItem -LiteralPath $bookmarkFolder -File | Where-Object { $_.Extension -in @('.jsonlz4','.json') } | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $dest = Join-Path $to 'bookmarkbackups'
            New-Item -ItemType Directory -Path $dest -Force | Out-Null
            Copy-Item -LiteralPath $latest.FullName -Destination $dest -Force
            Add-Content -LiteralPath $log -Value "Copied bookmarks: $($latest.Name). Modified: $($latest.LastWriteTime)" -Encoding UTF8
        }
    }
    if ('Extensions' -notin $choices) { return }
    $addonsPath = Join-Path $from 'extensions.json'
    if (!(Test-Path -LiteralPath $addonsPath)) { throw 'extensions.json is missing. Select the Firefox profile ROOT folder from about:profiles.' }
    $addons = (Get-Content -LiteralPath $addonsPath -Raw -Encoding UTF8 | ConvertFrom-Json).addons
    $selected = @($addons | Where-Object { $_.type -eq 'extension' -and $_.location -eq 'app-profile' -and !$_.isBuiltin -and !$_.foreignInstall })
    $prefs = Get-Content -LiteralPath (Join-Path $from 'prefs.js') -Raw -Encoding UTF8
    $uuidMap = $null
    $match = [regex]::Match($prefs, 'user_pref\("extensions.webextensions.uuids",\s*("(?:\\.|[^"\\])*")\);')
    if ($match.Success) { $uuidMap = ($match.Groups[1].Value | ConvertFrom-Json) | ConvertFrom-Json }
    foreach ($addon in $selected) {
        $id = [string]$addon.id
        if ($id.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $id -in @('.', '..')) { throw 'Invalid extension ID.' }
        $extRoot = Join-Path $from 'extensions'
        $destRoot = Join-Path $to 'extensions'
        foreach ($file in @((Join-Path $extRoot ($id + '.xpi')), (Join-Path $extRoot $id))) {
            if (Test-Path -LiteralPath $file) {
                New-Item -ItemType Directory -Path $destRoot -Force | Out-Null
                if (Test-Path -LiteralPath $file -PathType Container) { CopyTree $file (Join-Path $destRoot $id) $log }
                else { Copy-Item -LiteralPath $file -Destination $destRoot -Force; Add-Content -LiteralPath $log -Value "Copied extension: $id" -Encoding UTF8 }
            }
        }
        $data = Join-Path (Join-Path $from 'browser-extension-data') $id
        if (Test-Path -LiteralPath $data) { CopyTree $data (Join-Path (Join-Path $to 'browser-extension-data') $id) $log }
        if ($uuidMap) {
            $entry = $uuidMap.PSObject.Properties[$id]
            if ($entry) {
                $uuid = [string]$entry.Value
                if ($uuid -match '^[a-fA-F0-9-]+$') {
                    foreach ($area in @('default','permanent')) {
                        $store = Join-Path $from "storage\$area"
                        if (Test-Path -LiteralPath $store) {
                            foreach ($dir in (Get-ChildItem -LiteralPath $store -Directory)) {
                                if ($dir.Name -eq "moz-extension+++$uuid" -or $dir.Name.StartsWith("moz-extension+++$uuid^")) {
                                    CopyTree $dir.FullName (Join-Path (Join-Path $to "storage\$area") $dir.Name) $log
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    $selected | Select-Object id,defaultLocale,version | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $to 'Installed Extensions.json') -Encoding UTF8
}
function ChooseMode {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Firefox Backup and Restore - RebelTortuga'
    $form.Size = New-Object System.Drawing.Size(520,220)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Back up bookmarks, saved passwords and installed extensions.`r`nClose Firefox completely before continuing."
    $label.SetBounds(20,20,470,60)
    $form.Controls.Add($label)
    foreach ($item in @(@('Back up','Yes',20),@('Restore','No',180),@('Exit','Cancel',340))) {
        $button = New-Object System.Windows.Forms.Button
        $button.Text = $item[0]
        $button.DialogResult = [System.Windows.Forms.DialogResult]$item[1]
        $button.SetBounds([int]$item[2],100,140,38)
        $form.Controls.Add($button)
    }
    try { return $form.ShowDialog() } finally { $form.Dispose() }
}
function ChooseCategories {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Choose what to back up'
    $form.Size = New-Object System.Drawing.Size(600,360)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $checks = @()
    $labels = @('Bookmarks (latest automatic snapshot)', 'Saved passwords', 'Installed extensions and their data', 'Browser settings')
    $keys = @('Bookmarks','Passwords','Extensions','Settings')
    for ($i=0; $i -lt $keys.Count; $i++) {
        $check = New-Object System.Windows.Forms.CheckBox
        $check.Text = $labels[$i]
        $check.Tag = $keys[$i]
        $check.Checked = $true
        $check.SetBounds(20,(20+$i*32),540,28)
        $form.Controls.Add($check)
        $checks += $check
    }
    $note = New-Object System.Windows.Forms.Label
    $note.Text = "All means all four choices, not a full Firefox profile.`r`nExtensions also require prefs.js and restore its browser preferences.`r`nHistory, cookies, website data and open tabs are excluded."
    $note.SetBounds(20,155,550,65)
    $form.Controls.Add($note)
    $all = New-Object System.Windows.Forms.Button
    $all.Text = 'Select all'
    $all.SetBounds(20,235,120,35)
    $all.Add_Click({ foreach ($check in $checks) { $check.Checked = $true } })
    $form.Controls.Add($all)
    $none = New-Object System.Windows.Forms.Button
    $none.Text = 'Clear all'
    $none.SetBounds(150,235,120,35)
    $none.Add_Click({ foreach ($check in $checks) { $check.Checked = $false } })
    $form.Controls.Add($none)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'Continue'
    $ok.SetBounds(300,235,120,35)
    $ok.Add_Click({
        if (@($checks | Where-Object { $_.Checked }).Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('Choose at least one item.','Backup selection') | Out-Null
        } else { $form.DialogResult = 'OK'; $form.Close() }
    })
    $form.Controls.Add($ok)
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    $cancel.SetBounds(430,235,120,35)
    $form.Controls.Add($cancel)
    try {
        if ($form.ShowDialog() -eq 'OK') { return @($checks | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Tag }) }
        return @()
    } finally { $form.Dispose() }
}
function ValidateBackup($root) {
    $metaPath = Join-Path $root 'Backup Complete.json'
    if (!(Test-Path -LiteralPath $metaPath -PathType Leaf)) { throw 'This backup is incomplete or the wrong folder was selected.' }
    $meta = Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($meta.Format -notin @('FirefoxEssentials1','FirefoxEssentials2','FirefoxEssentials3')) { throw 'Unrecognized backup format.' }
    $data = Join-Path $root 'Profile'
    if ($meta.Format -ne 'FirefoxEssentials3' -and !(Test-Path -LiteralPath (Join-Path $data 'prefs.js') -PathType Leaf)) { throw 'The backup profile is missing prefs.js.' }
    if ($meta.Format -in @('FirefoxEssentials2','FirefoxEssentials3')) {
        $manifest = @(Get-Content -LiteralPath (Join-Path $root 'File Integrity.json') -Raw -Encoding UTF8 | ConvertFrom-Json)
        if (!$manifest.Count) { throw 'The integrity manifest is empty.' }
        $seen = @{}
        foreach ($entry in $manifest) {
            $path = [IO.Path]::GetFullPath((Join-Path $data $entry.Path))
            $prefix = [IO.Path]::GetFullPath($data).TrimEnd('\') + '\'
            if (!$path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid path in backup manifest.' }
            if ($seen.ContainsKey($path)) { throw 'Duplicate path in backup manifest.' }
            $seen[$path] = $true
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Backup file missing: $($entry.Path)" }
            if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $entry.SHA256) { throw "Backup file damaged or changed: $($entry.Path)" }
        }
        foreach ($file in (Get-ChildItem -LiteralPath $data -File -Recurse -Force)) {
            if (!$seen.ContainsKey($file.FullName)) { throw "Unexpected file in backup: $($file.Name)" }
        }
    } else {
        if ([System.Windows.Forms.MessageBox]::Show('This older backup has no integrity manifest. Continue without hash verification?', 'Legacy Backup','YesNo','Warning') -ne 'Yes') { throw 'Restore cancelled.' }
    }
    return $meta
}
try {
    if ($Action -eq 'Verify') {
        $folder = Folder 'Select a completed Firefox backup folder to verify' $null
        if (!$folder) { exit }
        $metadata = ValidateBackup $folder
        $items = if ($metadata.Format -eq 'FirefoxEssentials3') { @($metadata.Categories) -join ', ' } else { 'Legacy essentials' }
        [System.Windows.Forms.MessageBox]::Show("Backup check completed.`nCreated: $($metadata.Created)`nItems: $items`nFormat: $($metadata.Format)", 'Backup Verification') | Out-Null
        exit
    }
    $base = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    $mode = if ($Action -eq 'Backup') { 'Yes' } elseif ($Action -eq 'Restore') { 'No' } else { ChooseMode }
    if ($mode -notin @('Yes','No')) { exit }
    Closed
    $stamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss-fff'
    if ($mode -eq 'Yes') {
        $choices = @(ChooseCategories)
        if (!$choices.Count) { exit }
        $profile = if ($ProfilePath) { $ProfilePath } else { Folder 'Select your Firefox profile ROOT folder (see about:profiles if unsure)' $base }
        if (!$profile) { exit }
        if (!(Test-Path -LiteralPath (Join-Path $profile 'prefs.js'))) { throw 'Select the profile folder containing prefs.js.' }
        $parent = Folder 'Choose where to save the backup' ([Environment]::GetFolderPath('MyDocuments'))
        if (!$parent) { exit }
        $srcFull = [IO.Path]::GetFullPath($profile).TrimEnd('\')
        $dstFull = [IO.Path]::GetFullPath($parent).TrimEnd('\')
        if ($dstFull -eq $srcFull -or $dstFull.StartsWith($srcFull+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Choose a destination outside the profile.' }
        $backup = Join-Path $parent "Firefox Backup $stamp"
        New-Item -ItemType Directory -Path $backup | Out-Null
        Closed
        Selected $profile (Join-Path $backup 'Profile') (Join-Path $backup 'Copy Log.txt') $choices
        Closed
         $dataRoot = Join-Path $backup 'Profile'
        $integrity = @(Get-ChildItem -LiteralPath $dataRoot -File -Recurse -Force | ForEach-Object {
            @{Path=$_.FullName.Substring($dataRoot.Length+1); SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
        })
        if (!$integrity.Count) { throw 'No files were found for the selected items. No completed backup was created.' }
        ConvertTo-Json -InputObject $integrity -Depth 4 | Set-Content -LiteralPath (Join-Path $backup 'File Integrity.json') -Encoding UTF8
        @{Format='FirefoxEssentials3';Categories=$choices;Created=(Get-Date).ToString('o');Profile=(Split-Path $profile -Leaf)} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'Backup Complete.json') -Encoding UTF8
        $bookmarks = @(Get-ChildItem -LiteralPath (Join-Path $backup 'Profile\bookmarkbackups') -File -ErrorAction SilentlyContinue)
        $bookmarkNote = 'No automatic bookmark backup found. Export bookmarks separately from Firefox.'
        if ($bookmarks.Count -gt 0) { $bookmarkNote = "Bookmark snapshot: $($bookmarks[0].Name). Changes since that snapshot require a fresh Firefox bookmark export." }
        if ('Bookmarks' -notin $choices) { $bookmarkNote = 'Bookmarks were not selected.' }
        [System.Windows.Forms.MessageBox]::Show("Backup completed. Items: $($choices -join ', ').`n`n$backup`n`n$bookmarkNote",'Firefox Backup') | Out-Null
    } else {
        $backup = Folder 'Select a completed Firefox Backup folder' $null
        if (!$backup) { exit }
        $meta = ValidateBackup $backup
        $restoreItems = 'Legacy essentials (passwords, extensions and supporting settings)'
        if ($meta.Format -eq 'FirefoxEssentials3') { $restoreItems = @($meta.Categories) -join ', ' }
        if ($meta.Format -eq 'FirefoxEssentials3' -and @($meta.Categories).Count -eq 1 -and $meta.Categories[0] -eq 'Bookmarks') {
            [System.Windows.Forms.MessageBox]::Show("Bookmarks-only backup verified. Open Firefox and press Ctrl+Shift+O > Import and Backup > Restore > Choose File. Choose the snapshot in $backup\Profile\bookmarkbackups. This replaces current bookmarks; export them first if needed.", 'Restore Bookmarks') | Out-Null
            exit
        }
        $target = if ($ProfilePath) { $ProfilePath } else { Folder 'Select the existing Firefox profile ROOT folder to restore into' $base }
        if (!$target) { exit }
        if (!(Test-Path -LiteralPath (Join-Path $target 'prefs.js'))) { throw 'Select an existing Firefox profile.' }
        if ([System.Windows.Forms.MessageBox]::Show("Restore backed-up items: $($restoreItems)? Current profile will be kept in a recovery folder. Bookmarks, if backed up, must be imported afterward in Firefox.", 'Confirm Restore','YesNo','Warning') -ne 'Yes') { exit }
         $targetFull = [IO.Path]::GetFullPath($target).TrimEnd('\')
        $backupFull = [IO.Path]::GetFullPath($backup).TrimEnd('\')
        if ($backupFull -eq $targetFull -or $backupFull.StartsWith($targetFull+'\',[StringComparison]::OrdinalIgnoreCase) -or $targetFull.StartsWith($backupFull+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'The backup and target profile must be separate folders.' }
        Closed
        $parent = Split-Path $target -Parent
        $stage = Join-Path $parent "Restore Staging $stamp"
        $log = Join-Path $parent "Firefox Restore $stamp.txt"
        CopyTree $target $stage $log
        CopyTree (Join-Path $backup 'Profile') $stage $log
        # Firefox regenerates these caches using the restored extension records.
        foreach ($name in @('addonStartup.json.lz4','extensions.ini')) {
            $f = Join-Path $stage $name
            if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
        }
        Closed
        $recovery = Join-Path $parent "$(Split-Path $target -Leaf) before restore $stamp"
        Move-Item -LiteralPath $target -Destination $recovery
        try { Move-Item -LiteralPath $stage -Destination $target }
        catch { if (!(Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $recovery -Destination $target }; throw }
        [System.Windows.Forms.MessageBox]::Show("Backed-up profile files restored ($restoreItems). Open Firefox. If bookmarks were backed up, restore them with: Ctrl+Shift+O > Import and Backup > Restore > Choose File; select the snapshot in $backup\Profile\bookmarkbackups. This replaces current bookmarks.`n`nOriginal profile: $recovery",'Firefox Backup') | Out-Null
    }
} catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Firefox Backup - Failed','OK','Error') | Out-Null
    exit 1
}
