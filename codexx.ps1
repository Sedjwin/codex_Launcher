[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$PassThruArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve the real Codex launcher
$CodexPath = (Get-Command codex -ErrorAction Stop).Source

# Settings store
$CfgDir  = Join-Path $env:APPDATA 'codexx'
$CfgFile = Join-Path $CfgDir 'settings.json'
New-Item -ItemType Directory -Force -Path $CfgDir | Out-Null

# Defaults
$defaults = [ordered]@{
  model     = 'gpt-5-codex'
  sandbox   = 'workspace-write'     # read-only | workspace-write | danger-full-access
  approval  = 'on-request'          # untrusted | on-request | on-failure
  webSearch = $false                 # adds --search
}

# Load saved settings
$saved = $null
if (Test-Path $CfgFile) { try { $saved = Get-Content $CfgFile -Raw | ConvertFrom-Json } catch {} }
$cfg = [ordered]@{}
foreach ($k in $defaults.Keys) { $cfg[$k] = if ($saved -and $saved.PSObject.Properties[$k]) { $saved.$k } else { $defaults[$k] } }

# Menu items
$items = @(
  @{ key='continue';  label='[ Save & Continue ]'; kind='action' },
  @{ key='model';     label='Model';   kind='pick';  values=@('gpt-5-codex','gpt-5','o4-mini') },
  @{ key='sandbox';   label='Sandbox'; kind='pick';  values=@('read-only','workspace-write','danger-full-access') },
  @{ key='approval';  label='Approval';kind='pick';  values=@('untrusted','on-request','on-failure') },
  @{ key='webSearch'; label='Web Search tool (--search)'; kind='bool' }
)
$index = 0

function Get-FlagPreview {
  $parts = @()
  $parts += "--sandbox $($cfg.sandbox)"
  $parts += "--ask-for-approval $($cfg.approval)"
  if ($cfg.model)     { $parts += "--model $($cfg.model)" }
  if ($cfg.webSearch) { $parts += "--search" }
  $parts -join ' '
}

function Draw {
  Clear-Host
  Write-Host "codexx - OpenAI Codex launcher" -ForegroundColor Cyan
  Write-Host "Use Up/Down to move, Left/Right to change, Enter to select, Esc to quit."
  Write-Host ""
  for ($i = 0; $i -lt $items.Count; $i++) {
    $it = $items[$i]; $isSel = ($i -eq $index)
    $prefix = if ($isSel) { '>' } else { ' ' }
    switch ($it.kind) {
      'action' { $line = "$prefix $($it.label)" }
      'pick'   { $line = "$prefix $($it.label): $($cfg[$it.key])" }
      'bool'   {
        $state = if ($cfg[$it.key]) { 'On' } else { 'Off' }  # <- fixed
        $line  = "$prefix $($it.label): $state"
      }
    }
    if ($isSel) { Write-Host $line -ForegroundColor Black -BackgroundColor Gray } else { Write-Host $line }
  }
  Write-Host ""
  Write-Host ("Current flags preview: " + (Get-FlagPreview)) -ForegroundColor DarkGray
  Write-Host ""
}

function CycleValue([string]$key, [int]$delta) {
  $it = $items | Where-Object { $_.key -eq $key }
  if ($it.kind -eq 'pick') {
    $vals = $it.values
    $cur = [array]::IndexOf($vals, [string]$cfg[$key])
    if ($cur -lt 0) { $cur = 0 }
    $cur = $cur + $delta
    if ($cur -ge $vals.Count) { $cur = 0 }
    if ($cur -lt 0) { $cur = $vals.Count - 1 }
    $cfg[$key] = $vals[$cur]
  } elseif ($it.kind -eq 'bool') {
    $cfg[$key] = -not [bool]$cfg[$key]
  }
}

function Save-Settings {
  ($cfg | ConvertTo-Json -Depth 4) | Set-Content -Path $CfgFile -Encoding UTF8
}

function Launch-Codex {
  Save-Settings
  $launchArgs = @('--sandbox', $cfg.sandbox, '--ask-for-approval', $cfg.approval)
  if ($cfg.model)     { $launchArgs += @('--model', $cfg.model) }
  if ($cfg.webSearch) { $launchArgs += '--search' }
  if ($PassThruArgs)  { $launchArgs += $PassThruArgs }

  Write-Host ""
  Write-Host ("Launching: codex " + ($launchArgs -join ' ')) -ForegroundColor Green
  Write-Host ""
  & $CodexPath @launchArgs
}

# Main loop
[Console]::TreatControlCAsInput = $true
Draw
while ($true) {
  $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
  switch ($key.VirtualKeyCode) {
    13 { if ($items[$index].key -eq 'continue') { Launch-Codex; break } else { CycleValue $items[$index].key +1; Draw } }
    27 { break }                                   # Esc
    38 { if ($index -gt 0) { $index-- }; Draw }    # Up
    40 { if ($index -lt ($items.Count-1)) { $index++ }; Draw } # Down
    37 { $k = $items[$index].key; if ($items[$index].kind -ne 'action') { CycleValue $k -1; Draw } } # Left
    39 { $k = $items[$index].key; if ($items[$index].kind -ne 'action') { CycleValue $k +1; Draw } } # Right
    default { }
  }
}
