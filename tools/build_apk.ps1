<#
.SYNOPSIS
  Builds a signed, verified release APK of the commissioning APP.

.DESCRIPTION
  -Env local : flutter build apk --release --dart-define=LOCAL_DEVELOPMENT=true
               (HTTP allowed for the private-LAN test backend), signed with
               the Android debug keystore (%USERPROFILE%\.android\debug.keystore,
               alias androiddebugkey) - the same certificate as the field-test
               APKs of rounds 19/20 (SHA-256 bea4c874...), so `adb install -r`
               updates the installed APP without an uninstall.
  -Env prod  : flutter build apk --release (no LOCAL_DEVELOPMENT: HTTPS only),
               signed with the release keystore from android\key.properties
               (storeFile / storePassword / keyAlias / keyPassword; a relative
               storeFile is resolved against android\app) or the environment
               variables GIOS_KEYSTORE / GIOS_KEYSTORE_PASS / GIOS_KEY_ALIAS /
               GIOS_KEY_PASS. Without one the script stops before building:
               it never produces an unsigned APK, nor a prod APK signed with
               the debug key.

  Gradle's release output stays unsigned (android/app/build.gradle.kts has
  signingConfig = null); this script signs it with apksigner, runs
  `apksigner verify --print-certs` and exits non-zero on any failure.
  Output: <OutDir>\app_<git short hash>_<env>.apk, its SHA-256 printed.
  A dirty working tree is refused (the name would not match the source)
  unless -AllowDirty, which names the file app_<hash>-dirty_<env>.apk.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env local -OutDir C:\temp\apk
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'prod')]
    [string]$Env,

    [string]$OutDir = '',

    [switch]$AllowDirty
)

# Keep every executable string ASCII (Windows PowerShell 5.1 reads a UTF-8
# file without BOM as the ANSI code page).
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Certificate of the round 19/20 field-test APKs (debug.keystore).
$FieldTestCertSha256 = 'bea4c874f88d713ecf3893e4a73235c495b296a79804a538719174222a2325ef'

function Fail([string]$Message) {
    Remove-Item Env:\GIOS_BUILD_KS_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:\GIOS_BUILD_KEY_PASS -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "BUILD FAILED: $Message" -ForegroundColor Red
    exit 1
}

# Runs a native tool with its stderr folded into the output as text: under
# Windows PowerShell 5.1 a redirected host turns native stderr lines into
# error records, which $ErrorActionPreference = 'Stop' would make fatal.
# Success is judged by $LASTEXITCODE only.
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $old
    }
}

function Step([string]$Message) {
    Write-Host ''
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Read-Properties([string]$Path) {
    $props = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#') -or $t.StartsWith('!')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        $props[$t.Substring(0, $i).Trim()] = $t.Substring($i + 1).Trim()
    }
    return $props
}

function Find-AndroidSdk([string]$Root) {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    $localProps = Join-Path $Root 'android\local.properties'
    if (Test-Path -LiteralPath $localProps) {
        $p = Read-Properties $localProps
        if ($p.ContainsKey('sdk.dir')) { $candidates += ($p['sdk.dir'] -replace '\\\\', '\') }
    }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'build-tools'))) { return $c }
    }
    return $null
}

function Find-BuildTools([string]$Sdk) {
    $best = $null
    $bestVersion = $null
    foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'apksigner.bat'))) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName 'zipalign.exe'))) { continue }
        $v = $null
        if (-not [version]::TryParse(($d.Name -replace '[^0-9.].*$', ''), [ref]$v)) { continue }
        if ($null -eq $bestVersion -or $v -gt $bestVersion) {
            $best = $d.FullName
            $bestVersion = $v
        }
    }
    return $best
}

# ---------------------------------------------------------------- inputs
$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutDir) { $OutDir = Join-Path $Root 'build\dist' }
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).Path

Step "Environment: $Env (repo $Root)"

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git not found on PATH (needed for the file name).' }
$hash = @(Invoke-Native 'git' @('-C', $Root, 'rev-parse', '--short', 'HEAD')) | Select-Object -Last 1
if ($LASTEXITCODE -ne 0 -or -not $hash) { Fail 'git rev-parse failed.' }
$hash = "$hash".Trim()
$dirty = @(Invoke-Native 'git' @('-C', $Root, 'status', '--porcelain', '--untracked-files=no'))
if ($LASTEXITCODE -ne 0) { Fail 'git status failed.' }
if ($dirty.Count -gt 0) {
    if (-not $AllowDirty) {
        $dirty | ForEach-Object { Write-Host "  $_" }
        Fail "working tree has uncommitted changes; commit first (or pass -AllowDirty for a test build named app_$hash-dirty_$Env.apk)."
    }
    Write-Warning 'Building from a dirty working tree (-AllowDirty).'
    $hash = "$hash-dirty"
}

$sdk = Find-AndroidSdk $Root
if (-not $sdk) { Fail 'Android SDK not found (ANDROID_HOME / android\local.properties sdk.dir).' }
$bt = Find-BuildTools $sdk
if (-not $bt) { Fail "no build-tools with apksigner.bat and zipalign.exe under $sdk\build-tools." }
$apksigner = Join-Path $bt 'apksigner.bat'
$zipalign = Join-Path $bt 'zipalign.exe'
Write-Host "build-tools: $bt"

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { Fail 'flutter not found on PATH.' }

# ---------------------------------------------------------------- signing
# Resolved before building: a missing key fails fast, never an unsigned APK.
if ($Env -eq 'local') {
    $ks = Join-Path $env:USERPROFILE '.android\debug.keystore'
    if (-not (Test-Path -LiteralPath $ks)) {
        Fail ("debug keystore not found: $ks. Copy the field-test debug.keystore " +
            "(cert SHA-256 $($FieldTestCertSha256.Substring(0, 8))...) there; a new one " +
            "would not install over the field-test APP.")
    }
    $alias = 'androiddebugkey'
    $ksPass = 'android'
    $keyPass = 'android'
} else {
    $keyProps = Join-Path $Root 'android\key.properties'
    $ks = $env:GIOS_KEYSTORE
    $alias = $env:GIOS_KEY_ALIAS
    $ksPass = $env:GIOS_KEYSTORE_PASS
    $keyPass = $env:GIOS_KEY_PASS
    if (-not $ks -and (Test-Path -LiteralPath $keyProps)) {
        $p = Read-Properties $keyProps
        foreach ($k in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
            if (-not $p.ContainsKey($k) -or -not $p[$k]) { Fail "android\key.properties lacks $k." }
        }
        $ks = $p['storeFile']
        if (-not [System.IO.Path]::IsPathRooted($ks)) { $ks = Join-Path $Root "android\app\$ks" }
        $alias = $p['keyAlias']
        $ksPass = $p['storePassword']
        $keyPass = $p['keyPassword']
    }
    if (-not $ks) {
        Fail ("no release keystore configured - refusing to build an unsigned prod APK. " +
            "Create android\key.properties (storeFile, storePassword, keyAlias, keyPassword; " +
            "git-ignored) or set GIOS_KEYSTORE, GIOS_KEYSTORE_PASS, GIOS_KEY_ALIAS, GIOS_KEY_PASS.")
    }
    if (-not (Test-Path -LiteralPath $ks)) { Fail "release keystore not found: $ks" }
    if (-not $alias -or -not $ksPass) { Fail 'release keystore alias / password missing.' }
    if (-not $keyPass) { $keyPass = $ksPass }
    if ((Split-Path -Leaf $ks) -ieq 'debug.keystore') { Fail 'prod must not be signed with debug.keystore.' }
    $ks = (Resolve-Path -LiteralPath $ks).Path
}
# Passwords reach apksigner through the environment, not the command line.
$env:GIOS_BUILD_KS_PASS = $ksPass
$env:GIOS_BUILD_KEY_PASS = $keyPass
Write-Host "keystore: $ks (alias $alias)"

# ---------------------------------------------------------------- build
$flutterArgs = @('build', 'apk', '--release')
if ($Env -eq 'local') { $flutterArgs += '--dart-define=LOCAL_DEVELOPMENT=true' }
$gradleOut = Join-Path $Root 'build\app\outputs\flutter-apk\app-release.apk'
# Never sign a leftover from an earlier build.
if (Test-Path -LiteralPath $gradleOut) { Remove-Item -LiteralPath $gradleOut -Force }

Step ('flutter ' + ($flutterArgs -join ' '))
Push-Location $Root
try {
    Invoke-Native $flutter.Source $flutterArgs | ForEach-Object { Write-Host $_ }
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExit -ne 0) { Fail "flutter build exited with $buildExit." }
if (-not (Test-Path -LiteralPath $gradleOut)) { Fail "build output missing: $gradleOut" }

# ---------------------------------------------------------------- align + sign
$work = Join-Path $OutDir ".build_apk_$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$final = Join-Path $OutDir "app_$($hash)_$Env.apk"
$cert = ''
try {
    $toSign = $gradleOut
    Invoke-Native $zipalign @('-c', '-P', '16', '4', $gradleOut) | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Step 'zipalign -P 16 4'
        $toSign = Join-Path $work 'aligned.apk'
        Invoke-Native $zipalign @('-f', '-P', '16', '4', $gradleOut, $toSign) | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { Fail "zipalign exited with $LASTEXITCODE." }
    }

    Step 'apksigner sign'
    $signed = Join-Path $work 'signed.apk'
    Invoke-Native $apksigner @('sign', '--ks', $ks, '--ks-key-alias', $alias,
        '--ks-pass', 'env:GIOS_BUILD_KS_PASS', '--key-pass', 'env:GIOS_BUILD_KEY_PASS',
        '--v4-signing-enabled', 'false', '--out', $signed, $toSign) | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { Fail "apksigner sign exited with $LASTEXITCODE." }

    Step 'apksigner verify --print-certs'
    $verify = @(Invoke-Native $apksigner @('verify', '--print-certs', '-v', $signed))
    $verifyExit = $LASTEXITCODE
    $verify | ForEach-Object { Write-Host "  $_" }
    if ($verifyExit -ne 0) { Fail "apksigner verify exited with $verifyExit." }
    if (-not ($verify | Where-Object { $_ -eq 'Verifies' })) { Fail 'apksigner verify did not report Verifies.' }
    $certLine = $verify | Where-Object { $_ -match '^Signer #1 certificate SHA-256 digest: ' } | Select-Object -First 1
    $dnLine = $verify | Where-Object { $_ -match '^Signer #1 certificate DN: ' } | Select-Object -First 1
    if (-not $certLine) { Fail 'apksigner verify printed no signer certificate.' }
    $cert = ($certLine -replace '^Signer #1 certificate SHA-256 digest: ', '').Trim()
    if ($Env -eq 'prod' -and "$dnLine" -match 'CN=Android Debug') {
        Fail 'prod APK is signed with an Android Debug certificate.'
    }
    if ($Env -eq 'local' -and $cert -ne $FieldTestCertSha256) {
        Write-Warning ("debug.keystore certificate $cert differs from the field-test certificate " +
            "$FieldTestCertSha256 - adb install -r over the field-test APP will fail (uninstall first).")
    }

    Move-Item -LiteralPath $signed -Destination $final -Force
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\GIOS_BUILD_KS_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:\GIOS_BUILD_KEY_PASS -ErrorAction SilentlyContinue
}

$sha = (Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash.ToLower()
$envNote = if ($Env -eq 'local') { 'LOCAL_DEVELOPMENT=true' } else { 'HTTPS only' }
Step 'Done'
Write-Host "APK    : $final"
Write-Host "env    : $Env ($envNote)"
Write-Host "cert   : $cert"
Write-Host "sha256 : $sha"
exit 0
