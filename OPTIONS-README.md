# Detailed Menu Options Guide
## Choose Firefox profile
Use the **Profile** dropdown at the top of the window. It lists initialized profiles registered in profiles.ini and found in Firefox's standard Profiles folder. For custom locations, Browse custom... selects the Root Directory containing prefs.js, not Firefox's Local Directory. The selection is validated and remembered for the current Windows account. For multiple profiles, select each and back it up separately.

## Open profile / Saved Logs
Open the selected root folder or toolkit logs in Explorer. Opening folders changes no profile files. Do not manually delete unfamiliar data. Logs may include personal paths.

## Save a backup
Close Firefox completely. Select Bookmarks, Passwords, Extensions and their data, Settings, or Select all. The chosen profile is already filled from the main toolkit. Choose a destination outside the live profile. Timestamped output includes copied files, a copy log, category metadata and SHA-256 hashes. Missing or changed files fail verification. Hashes are not tamper-proof authentication. A failure leaves an incomplete folder without a completion marker. Bookmarks use the latest automatic snapshot and may omit recent changes. Password backup copies the login and key files together when present. Primary Password remains required. Extensions include supporting prefs.js and can therefore restore unrelated preferences.

Extension storage coverage is limited to the locations supported by this tool; export important extension data independently when needed. Settings copies only prefs.js. All does not mean a full profile.

## Restore a backup
Close Firefox completely. Select the completed backup folder. New-format backups are verified first; format 1 requires a warning confirmation because hashes are absent. Restore stages the current profile, overlays backed-up files, removes extension startup metadata caches, then preserves the original profile before swapping. If the final swap fails, it attempts to put the original back. Staging folders may remain on failure. Restore applies the included categories, without a second selection picker. Passwords and preferences overwrite current files. Additional extensions may remain. Keep a compatible Firefox version and prefer the original profile path.

Import bookmarks separately with Ctrl+Shift+O > Import and Backup > Restore > Choose File. This replaces current bookmarks. A bookmarks-only backup displays instructions without swapping the profile. Verify the result before removing the recovery folder.

## Diagnostics Center — Green button
Quick health check inspects the selected profile, essential file presence and size, password/key pairing, Firefox processes, latest bookmark snapshot and disk space. Full scan adds JSON parsing and root-file counts/size; no secret fields are printed. These checks are read-only with respect to Firefox; toolkit session logging still occurs. Results do not prove database integrity. Export the last report as TXT or Markdown to a location you select; cancel leaves no export.

## Troubleshoot Mode
Close Firefox. Launch the selected profile with Firefox's -safe-mode command. In the Firefox prompt choose Open in Troubleshoot Mode, not Refresh. Use this temporary mode to compare behavior with extensions and certain other features disabled. This is a launch, so Firefox may write normal profile data. The toolkit does not force-close Firefox.

## Clear startup cache
Close Firefox. If the profile root contains startupCache, confirm the repair to move it to a timestamped recovery location. Firefox can regenerate it. Linked cache folders are rejected. If no root startupCache is found, use Firefox about:support > Clear startup cache. The tool does not guess or delete the Local Directory's caches. Do not copy an old cache back unless you have a specific reason and Firefox is closed.

## Refresh Firefox (guided)
First save a backup. Confirm the dialog to launch about:support for the selected profile. Initiate Refresh Firefox there only after reviewing Firefox's warning. Refresh removes extensions and custom preferences while retaining certain essential information. The toolkit does not automate the refresh or claim that opening the page completed a repair. Availability depends on Firefox/profile/policy configuration.

## Profile Manager / clean test profile
Close Firefox. Open Firefox Profile Manager. Create a new test profile there and retain the original. If the issue disappears with the new profile, the existing profile is a useful troubleshooting lead, not proof of one particular cause. No profile is deleted by this toolkit.

## about:support
Close Firefox first. Opens Firefox's troubleshooting page for the selected profile. Use its built-in tools as appropriate. The Places Database Verify Integrity tool, if present, is separate from toolkit diagnostics.

## Verify a backup
Select a completed backup; checks integrity without restoring files. Shows date, format and included categories. Legacy format 1 lacks hash verification and requires confirmation. Cancellation is not successful verification.

## Feedback / Mozilla guidance
The Feedback action displays GitHub instructions without an assumed repository URL. Mozilla guidance opens the official Mozilla troubleshooting webpage in your default browser. The full web address is also in README.md for users who prefer to open it manually.

## Detailed Options Guide (H) — Yellow button
Directly below Other Tools. Click this button or press H to open this guide with your default Markdown app, falling back to Notepad.

## Optional Support — Blue button

## Exit Toolkit — Red button
Click the red button with white text to close the toolkit. It is separate from repair actions and is disabled while an operation runs. Exiting does not close Firefox if a tool launched it.

## Finding Exit
**Exit Toolkit** is highlighted at the bottom left. **Detailed Options Guide** is directly below **Other Tools**, and **Optional Support** sits between the guide and Exit with equal spacer rows above and below. The standard window Close button is also available. Click **Exit Toolkit** to close the main toolkit. Exit is disabled while an operation is running; wait for the operation to return.

## Section sidebar interface
Click a section on the left to display its actions on the right. Diagnostic findings and action messages appear in the results area below the buttons. Backup and restore keep their category-selection dialogs. Numbered documentation sections still identify the tools, but you now click buttons instead of entering menu numbers. Repair and support-link confirmations use dialogs. The interface can pause while an operation runs; background progress and cancellation are not implemented. Do not force-close it while files are being copied.

## Hidden-console launcher
Double-click **Firefox Diagnostic and Repair Toolkit.bat** or **Launch-Toolkit.vbs**. Both use Windows Script Host to launch PowerShell hidden; only the graphical toolkit stays visible. Keep the VBS, BAT and both PS1 files together. Do not run the PS1 directly if you want the console hidden. Windows Script Host must be available; if organizational policy disables it, contact your administrator.

## Button order and colors
The left-side buttons appear in this order:
1. **Profile and Folders**
2. **Backup & Restore**
3. **Diagnostics** — green
4. **Repair & Troubleshoot**
5. **Other Tools**
6. **Detailed Options Guide (H)** — yellow
7. **Optional Support** — blue
8. **Exit Toolkit** — red with white text

The guide is directly below Other Tools. Optional Support remains evenly positioned between the guide and Exit. These button colors remain in place when switching sections. The toolkit starts on Profile and Folders. Version remains **1.0.0**.

## Optional Ko-fi support

Optional Support asks before opening [https://ko-fi.com/rebeltortuga](https://ko-fi.com/rebeltortuga) in your browser. All features remain free, and no payment information is collected by the toolkit.
