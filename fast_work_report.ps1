param(
  [string]$Date,
  [string]$Content,
  [string]$ConfigPath = (Join-Path $PSScriptRoot "report-config.local.json")
)

$ErrorActionPreference = "Stop"
$Started = Get-Date

function Write-Step([string]$Message) {
  Write-Host "[fast-report] $Message"
}

function Read-Config([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Config not found: $Path. Copy report-config.example.json to report-config.local.json and fill it first."
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Get-OpenCliPath {
  # npm global bins are different on Windows and Unix-like systems.
  # Keep this small and explicit so failures are easy to diagnose.
  if ($IsWindows -or $env:OS -eq "Windows_NT") {
    $ps1 = Join-Path $env:APPDATA "npm\opencli.ps1"
    if (Test-Path -LiteralPath $ps1) { return $ps1 }
    $cmd = Join-Path $env:APPDATA "npm\opencli.cmd"
    if (Test-Path -LiteralPath $cmd) { return $cmd }
  }
  return "opencli"
}

function Invoke-OpenCli([string[]]$ArgsList) {
  $out = & $script:OpenCli @ArgsList
  if ($LASTEXITCODE -ne 0) {
    throw ($out -join "`n")
  }
  return $out
}

function Invoke-TapeEval([string]$Code) {
  # OpenCLI eval expects a single argument. Collapsing whitespace avoids shell
  # argument splitting problems while keeping the JavaScript readable in source.
  $singleLine = $Code -replace "\r?\n", " "
  return Invoke-OpenCli @("browser", $script:Config.opencliSession, "eval", $singleLine)
}

function Convert-OpenCliJson($Output) {
  $line = @($Output) | Where-Object { $_ -match "^\s*[\{\[]" } | Select-Object -First 1
  if (-not $line) { return $null }
  return $line | ConvertFrom-Json
}

function To-JsonLiteral($Value) {
  return ConvertTo-Json $Value -Compress
}

function Ensure-MainPage {
  Invoke-OpenCli @("browser", $script:Config.opencliSession, "bind") | Out-Null
  $state = Convert-OpenCliJson (Invoke-TapeEval "JSON.stringify({url:location.href,title:document.title})")
  if (-not $state -or -not ([string]$state.url).Contains([string]$script:Config.targetUrl)) {
    Write-Step "opening main page"
    $url = To-JsonLiteral $script:Config.targetUrl
    Invoke-TapeEval "location.href=$url; 'navigating'" | Out-Null
    Start-Sleep -Seconds 5
  }
}

function Open-Worklog {
  $home = To-JsonLiteral $script:Config.frameIds.home
  $worklog = To-JsonLiteral $script:Config.frameIds.worklog
  $menu = To-JsonLiteral $script:Config.selectors.worklogMenuId
  $code = @"
(() => {
  var existing = document.getElementById($worklog);
  if (existing) return 'already';
  var home = document.getElementById($home);
  if (!home) return 'no-home-frame';
  var doc = home.contentDocument || home.contentWindow.document;
  var menu = doc.getElementById($menu);
  if (!menu) return 'no-worklog-menu';
  menu.click();
  return 'opened';
})()
"@
  $result = Invoke-TapeEval $code
  Write-Step ("worklog tab: " + (@($result)[0]))
  Start-Sleep -Milliseconds 2500
}

function Read-ListState([string]$TargetDate, [string]$TargetContent) {
  $worklog = To-JsonLiteral $script:Config.frameIds.worklog
  $dateJson = To-JsonLiteral $TargetDate
  $contentJson = To-JsonLiteral $TargetContent
  $recordCountSelector = To-JsonLiteral $script:Config.verification.recordCountSelector
  $code = @"
(() => {
  var frame = document.getElementById($worklog);
  if (!frame) return JSON.stringify({ready:false});
  var doc = frame.contentDocument || frame.contentWindow.document;
  var text = doc.body ? doc.body.innerText : '';
  var info = doc.querySelector($recordCountSelector);
  var idx = text.indexOf($dateJson);
  var fragment = '';
  if (idx > -1) fragment = text.slice(idx, idx + 240);
  return JSON.stringify({
    ready: true,
    info: info ? info.textContent.trim() : '',
    hasDate: idx > -1,
    hasContent: text.indexOf($contentJson) > -1,
    fragment: fragment
  });
})()
"@
  return Convert-OpenCliJson (Invoke-TapeEval $code)
}

function Click-New {
  $worklog = To-JsonLiteral $script:Config.frameIds.worklog
  $button = To-JsonLiteral $script:Config.selectors.newButtonId
  $code = @"
(() => {
  var frame = document.getElementById($worklog);
  var doc = frame.contentDocument || frame.contentWindow.document;
  var btn = doc.getElementById($button);
  if (!btn) return 'missing-new-button';
  btn.click();
  return 'new-clicked';
})()
"@
  $result = Invoke-TapeEval $code
  Write-Step (@($result)[0])
  Start-Sleep -Milliseconds 1600
}

function Fill-Dialog([string]$TargetDate, [decimal]$Hours, [string]$TargetContent) {
  $payload = @{
    date = $TargetDate
    hours = $Hours
    content = $TargetContent
    frameId = $script:Config.frameIds.worklog
    selectors = $script:Config.selectors
    lookups = $script:Config.lookups
    model = $script:Config.model
  } | ConvertTo-Json -Depth 8 -Compress

  $code = @"
(() => {
  var cfg = $payload;
  var frame = document.getElementById(cfg.frameId);
  var doc = frame.contentDocument || frame.contentWindow.document;
  var win = doc.defaultView || doc.parentWindow;

  // Visible lookup values keep the user-facing form readable.
  function setLookup(item) {
    var q = win.jQuery('#' + item.controlId);
    q.lookupbox('setValue', item.value);
    q.lookupbox('setText', item.text);
  }
  Object.keys(cfg.lookups).forEach(function(key) {
    setLookup(cfg.lookups[key]);
  });

  var manager = doc.getElementById(cfg.selectors.managerInputId);
  if (manager) manager.value = cfg.model.managerName || '';

  // Date widgets often have both a visible value and a hidden canonical value.
  doc.getElementById(cfg.selectors.dateInputId).value = cfg.date;
  doc.getElementById(cfg.selectors.hiddenDateInputId).value = cfg.date;

  // EasyUI numberbox ignores plain DOM value writes in many systems.
  win.jQuery('#' + cfg.selectors.hoursInputId).numberbox('setValue', cfg.hours);

  var content = doc.getElementById(cfg.selectors.contentInputId);
  content.focus();
  content.value = cfg.content;
  content.dispatchEvent(new Event('input', {bubbles:true}));
  content.dispatchEvent(new Event('change', {bubbles:true}));
  doc.getElementById(cfg.selectors.dateInputId).dispatchEvent(new Event('blur', {bubbles:true}));
  doc.getElementById(cfg.selectors.hoursInputId).dispatchEvent(new Event('blur', {bubbles:true}));
  content.dispatchEvent(new Event('blur', {bubbles:true}));

  // Some enterprise forms validate the Knockout/currentItem model instead of
  // the DOM controls. Keep model synchronization explicit and config-driven.
  var root = doc.getElementById(cfg.selectors.formRootId);
  var viewInstance = win.jQuery.data(root).viewInstance;
  var controller = viewInstance.context.controllers.OmsWorklogInputController;
  var item = controller.dataSourceHelper.getCurrentItem(controller.cardInstance());

  Object.keys(cfg.model.fields).forEach(function(fieldName) {
    if (item[fieldName]) item[fieldName](cfg.model.fields[fieldName]);
  });
  if (item.WorkDate) item.WorkDate(cfg.date);
  if (item.WorkHour) item.WorkHour(cfg.hours);
  if (item.Content) item.Content(cfg.content);

  return 'filled';
})()
"@
  $result = Invoke-TapeEval $code
  Write-Step (@($result)[0])
}

function Verify-Dialog([string]$TargetDate, [string]$TargetContent) {
  $worklog = To-JsonLiteral $script:Config.frameIds.worklog
  $selectors = $script:Config.selectors | ConvertTo-Json -Depth 4 -Compress
  $code = @"
(() => {
  var selectors = $selectors;
  var frame = document.getElementById($worklog);
  var doc = frame.contentDocument || frame.contentWindow.document;
  var win = doc.defaultView || doc.parentWindow;
  var root = doc.getElementById(selectors.formRootId);
  var viewInstance = win.jQuery.data(root).viewInstance;
  var controller = viewInstance.context.controllers.OmsWorklogInputController;
  var item = controller.dataSourceHelper.getCurrentItem(controller.cardInstance());
  return JSON.stringify({
    date: doc.getElementById(selectors.dateInputId).value,
    hiddenDate: doc.getElementById(selectors.hiddenDateInputId).value,
    hours: win.jQuery('#' + selectors.hoursInputId).numberbox('getValue'),
    content: doc.getElementById(selectors.contentInputId).value,
    modelDate: item.WorkDate ? item.WorkDate() : '',
    modelContent: item.Content ? item.Content() : ''
  });
})()
"@
  $dialog = Convert-OpenCliJson (Invoke-TapeEval $code)
  if (-not $dialog -or $dialog.date -ne $TargetDate -or $dialog.hiddenDate -ne $TargetDate -or $dialog.content -ne $TargetContent) {
    throw "dialog verification failed: $($dialog | ConvertTo-Json -Compress)"
  }
  Write-Step ("dialog: " + ($dialog | ConvertTo-Json -Compress))
}

function Save-AndClose {
  $worklog = To-JsonLiteral $script:Config.frameIds.worklog
  $saveText = To-JsonLiteral $script:Config.selectors.saveAndCloseText
  $code = @"
(() => {
  var frame = document.getElementById($worklog);
  var doc = frame.contentDocument || frame.contentWindow.document;
  var btns = Array.prototype.slice.call(doc.querySelectorAll('a.l-btn'));
  var btn = btns.filter(function (b) {
    return b.offsetParent !== null && b.textContent.trim() === $saveText;
  })[0];
  if (!btn) return 'missing-save-close';
  btn.dispatchEvent(new MouseEvent('mousedown', {bubbles:true, view:window}));
  btn.dispatchEvent(new MouseEvent('mouseup', {bubbles:true, view:window}));
  btn.dispatchEvent(new MouseEvent('click', {bubbles:true, view:window}));
  return 'save-clicked';
})()
"@
  $result = Invoke-TapeEval $code
  Write-Step (@($result)[0])
  Start-Sleep -Seconds 4
}

$script:Config = Read-Config $ConfigPath
$script:OpenCli = Get-OpenCliPath

if (-not $Date) {
  throw "Missing -Date. Example: -Date 2026-07-04"
}
if (-not $Content) {
  $Content = $script:Config.defaults.content
}

Write-Step "target $Date"
Ensure-MainPage
Open-Worklog

$before = Read-ListState $Date $Content
Write-Step ("before: " + $before.info)
if ($before.hasDate) {
  throw "$Date already exists; refusing to duplicate"
}

Click-New
Fill-Dialog $Date ([decimal]$script:Config.defaults.hours) $Content
Verify-Dialog $Date $Content
Save-AndClose

$after = Read-ListState $Date $Content
Write-Step ("after: " + $after.info)
if (-not $after.hasDate -or -not $after.hasContent) {
  throw "save verification failed: $($after | ConvertTo-Json -Compress)"
}

$elapsed = [int]((Get-Date) - $Started).TotalSeconds
Write-Step "saved in ${elapsed}s"
Write-Host $after.fragment
