<#
.SYNOPSIS
  Builds a signed, verified release APK of the commissioning APP.

.DESCRIPTION
  -Env local : flutter build apk --release --dart-define=LOCAL_DEVELOPMENT=true
               (HTTP allowed for the private-LAN test backend), signed with
               the Android debug keystore (<user home>/.android/debug.keystore,
               alias androiddebugkey) - the same certificate as the field-test
               APKs of rounds 19/20 (SHA-256 bea4c874...), so `adb install -r`
               updates the installed APP without an uninstall.
  -Env prodtest : TRANSITIONAL. Like local's signing (debug keystore, so it
               installs over the field-test APP) but WITHOUT LOCAL_DEVELOPMENT
               (HTTPS only), for end-to-end tests against the production
               server while it has only an IP and a self-signed certificate
               (.secrets\prodtest.env sets API_BASE and API_CERT_SHA256).
               Not a release: the real production APK still needs -Env prod
               and the release keystore.
  -Env prod  : flutter build apk --release (no LOCAL_DEVELOPMENT: HTTPS only),
               signed with the release keystore from android\key.properties
               (storeFile / storePassword / keyAlias / keyPassword; a relative
               storeFile is resolved against android\app) or the environment
               variables GIOS_KEYSTORE / GIOS_KEYSTORE_PASS / GIOS_KEY_ALIAS /
               GIOS_KEY_PASS. Without one the script stops before building:
               it never produces an unsigned APK, nor a prod APK signed with
               the debug key.

  Backend credential (09-28: field staff never type a backend password):
  .secrets\<env>.env (git-ignored) must hold a line APP_BACKEND_KEY=<value>,
  the backend's APP_API_KEY for that environment. It reaches flutter as
  --dart-define APP_BACKEND_KEY through a temporary --dart-define-from-file
  JSON under build\ (deleted right after the build), so the value is never
  on the command line nor in this script's output. Missing -> the script
  stops before building.
  Optional lines in the same file: API_BASE=<https url> (production API
  base, --dart-define API_BASE) and API_CERT_SHA256=<64 hex digits, colons
  allowed> (pin the production server certificate, --dart-define
  API_CERT_SHA256). Absent -> not passed (defaults: https://46.250.255.172,
  system trust).
  API_CA_FILE=<path to a PEM CA certificate> (absolute, or relative to the
  repo): the file is read, base64-encoded and passed as --dart-define
  API_CA_PEM_B64; the APP then verifies the production host with the
  normal chain check against the system roots plus this CA (IP SAN
  included). 09-28: the production nginx is signed by IoTGateway-CA
  (MariaDb_Contabo_Server_Master\mosquitto\certs\ca.crt). With a CA,
  API_CERT_SHA256 is an optional extra pin on the leaf; without one it is
  the old pinning that only works for a single self-signed certificate.

  Gradle's release output stays unsigned (android/app/build.gradle.kts has
  signingConfig = null); this script signs it with apksigner, runs
  `apksigner verify --print-certs` and exits non-zero on any failure.
  Output: <OutDir>\app_<git short hash>_<env>.apk, its SHA-256 printed.
  With -BuildNumber N, overrides only this Android APK's versionCode and
  names it app_<git short hash>_b<N>_<env>.apk. The shared pubspec version
  and iOS project are not changed. Omit it to use pubspec.yaml as before.
  -BuildName X.Y.Z similarly overrides only this Android APK's versionName.
  Neither option writes the shared pubspec version or iOS build settings.
  A dirty working tree is refused (the name would not match the source)
  unless -AllowDirty, which adds -dirty after the source hash in the name.

.PARAMETER BuildNumber
  Optional Android versionCode (integer 1 through 2100000000). Passed to
  flutter build apk --build-number. Use the same source and signing key
  with 20 and 21 to prepare a baseline APK and its update APK.

.PARAMETER BuildName
  Optional Android versionName, exactly three dot-separated numeric parts.
  Passed to flutter build apk --build-name; omitted means use pubspec.yaml.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env local -OutDir C:\temp\apk

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env prod -BuildNumber 20

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\build_apk.ps1 -Env prod -BuildNumber 21 -BuildName 1.0.1

.EXAMPLE
  pwsh -NoProfile -File tools/build_apk.ps1 -Env local
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('local', 'prodtest', 'prod')]
    [string]$Env,

    [string]$OutDir = '',

    [ValidatePattern('^[1-9][0-9]*$')]
    [ValidateScript({ [long]$_ -le 2100000000 })]
    [string]$BuildNumber,

    [ValidatePattern('\A[0-9]+\.[0-9]+\.[0-9]+\z')]
    [string]$BuildName,

    [switch]$AllowDirty
)

# Keep every executable string ASCII (Windows PowerShell 5.1 reads a UTF-8
# file without BOM as the ANSI code page).
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# Do not use $IsWindows: it is not defined in Windows PowerShell 5.1.
$RunningOnWindows = [System.IO.Path]::DirectorySeparatorChar -eq '\'
$ApkSignerName = if ($RunningOnWindows) { 'apksigner.bat' } else { 'apksigner' }
$ZipAlignName = if ($RunningOnWindows) { 'zipalign.exe' } else { 'zipalign' }
$BuildUserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
if (-not $BuildUserProfile) {
    $BuildUserProfile = if ($RunningOnWindows) { $env:USERPROFILE } else { $env:HOME }
}

# Temporary --dart-define-from-file JSON holding the backend credential.
$DefineFile = $null

# Certificate of the round 19/20 field-test APKs (debug.keystore).
$FieldTestCertSha256 = 'bea4c874f88d713ecf3893e4a73235c495b296a79804a538719174222a2325ef'

function Fail([string]$Message) {
    Remove-Item Env:\GIOS_BUILD_KS_PASS -ErrorAction SilentlyContinue
    Remove-Item Env:\GIOS_BUILD_KEY_PASS -ErrorAction SilentlyContinue
    if ($script:DefineFile) { Remove-Item -LiteralPath $script:DefineFile -Force -ErrorAction SilentlyContinue }
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
        & $Exe @Arguments 2>&1 | ForEach-Object {
            # Flutter passes encoded credentials to Gradle. Never echo them.
            "$_" -replace '(?i)((?:-P|--)dart-defines?=)\S+', '$1[REDACTED]'
        }
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

function Convert-BuildPath([string]$Path) {
    if ($RunningOnWindows) { return $Path }
    # Accept repo-relative paths copied from the Windows build settings.
    return $Path.Replace('\', '/')
}

function Write-PrivateUtf8File([string]$Path, [string]$Content) {
    try {
        # Create an empty, unique file first; restrict access before writing
        # credentials. CreateNew also refuses to follow an existing symlink.
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $stream.Dispose()
        if (-not $RunningOnWindows) {
            $chmod = Get-Command chmod -CommandType Application -ErrorAction SilentlyContinue
            if (-not $chmod) { Fail 'chmod not found; cannot protect the temporary backend credential.' }
            Invoke-Native $chmod.Source @('600', $Path) | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail 'Cannot protect the temporary backend credential (chmod 600 failed).' }
        }
        [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    } catch {
        # Do not print exception details that could contain credential data.
        Fail 'Cannot write the protected temporary backend credential.'
    }
}

function Find-AndroidSdk([string]$Root) {
    $candidates = @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT)
    $localProps = Join-Path $Root 'android/local.properties'
    if (Test-Path -LiteralPath $localProps) {
        $p = Read-Properties $localProps
        if ($p.ContainsKey('sdk.dir')) {
            $candidates += (Convert-BuildPath ($p['sdk.dir'] -replace '\\\\', '\' -replace '\\:', ':'))
        }
    }
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Android/Sdk') }
    if ($BuildUserProfile) {
        $candidates += (Join-Path $BuildUserProfile 'Library/Android/sdk')
        $candidates += (Join-Path $BuildUserProfile 'Android/Sdk')
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'build-tools'))) { return $c }
    }
    return $null
}

function Find-BuildTools([string]$Sdk) {
    $best = $null
    $bestVersion = $null
    foreach ($d in (Get-ChildItem -LiteralPath (Join-Path $Sdk 'build-tools') -Directory)) {
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName $ApkSignerName))) { continue }
        if (-not (Test-Path -LiteralPath (Join-Path $d.FullName $ZipAlignName))) { continue }
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
$buildSuffix = if ($PSBoundParameters.ContainsKey('BuildNumber')) { "_b$BuildNumber" } else { '' }
$Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
if (-not $OutDir) { $OutDir = Join-Path $Root 'build/dist' }
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
        Fail "working tree has uncommitted changes; commit first (or pass -AllowDirty for a test build named app_${hash}-dirty${buildSuffix}_$Env.apk)."
    }
    Write-Warning 'Building from a dirty working tree (-AllowDirty).'
    $hash = "$hash-dirty"
}

$sdk = Find-AndroidSdk $Root
if (-not $sdk) { Fail 'Android SDK not found (ANDROID_HOME / android\local.properties sdk.dir).' }
$bt = Find-BuildTools $sdk
if (-not $bt) { Fail "no build-tools with $ApkSignerName and $ZipAlignName under $sdk/build-tools." }
$apksigner = Join-Path $bt $ApkSignerName
$zipalign = Join-Path $bt $ZipAlignName
Write-Host "build-tools: $bt"

$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutter) { Fail 'flutter not found on PATH.' }

# ---------------------------------------------------------------- signing
# Resolved before building: a missing key fails fast, never an unsigned APK.
if ($Env -eq 'local' -or $Env -eq 'prodtest') {
    if (-not $BuildUserProfile) { Fail 'User home directory not found (needed for the debug keystore).' }
    $ks = Join-Path $BuildUserProfile '.android/debug.keystore'
    if (-not (Test-Path -LiteralPath $ks)) {
        Fail ("debug keystore not found: $ks. Copy the field-test debug.keystore " +
            "(cert SHA-256 $($FieldTestCertSha256.Substring(0, 8))...) there; a new one " +
            "would not install over the field-test APP.")
    }
    $alias = 'androiddebugkey'
    $ksPass = 'android'
    $keyPass = 'android'
} else {
    $keyProps = Join-Path $Root 'android/key.properties'
    $ks = $env:GIOS_KEYSTORE
    $alias = $env:GIOS_KEY_ALIAS
    $ksPass = $env:GIOS_KEYSTORE_PASS
    $keyPass = $env:GIOS_KEY_PASS
    if (-not $ks -and (Test-Path -LiteralPath $keyProps)) {
        $p = Read-Properties $keyProps
        foreach ($k in 'storeFile', 'storePassword', 'keyAlias', 'keyPassword') {
            if (-not $p.ContainsKey($k) -or -not $p[$k]) { Fail "android\key.properties lacks $k." }
        }
        $ks = Convert-BuildPath $p['storeFile']
        if (-not [System.IO.Path]::IsPathRooted($ks)) { $ks = Join-Path (Join-Path $Root 'android/app') $ks }
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
# ---------------------------------------------------------------- backend credential
# Resolved before building too: an APK without it would ask nobody for a
# password and just say it lacks the credential.
$secretsFile = Join-Path $Root ".secrets/$Env.env"
if (-not (Test-Path -LiteralPath $secretsFile)) {
    Fail (".secrets\$Env.env not found. Create it (git-ignored) with one line " +
        "APP_BACKEND_KEY=<the backend APP_API_KEY for $Env>; see README.")
}
$secrets = Read-Properties $secretsFile
if (-not $secrets.ContainsKey('APP_BACKEND_KEY') -or -not $secrets['APP_BACKEND_KEY']) {
    Fail ".secrets\$Env.env has no APP_BACKEND_KEY value."
}
$backendKey = $secrets['APP_BACKEND_KEY']
if ($backendKey -match '\s') { Fail 'APP_BACKEND_KEY must not contain spaces.' }
Write-Host "backend credential: .secrets\$Env.env ($($backendKey.Length) chars, value not shown)"
$defines = @{ APP_BACKEND_KEY = $backendKey }
if ($secrets.ContainsKey('API_BASE') -and $secrets['API_BASE']) {
    if ($secrets['API_BASE'] -notmatch '^https://[^\s/]+/?$') { Fail 'API_BASE must be https://<host>[:port].' }
    $defines['API_BASE'] = $secrets['API_BASE'].TrimEnd('/')
    Write-Host "API_BASE: $($defines['API_BASE'])"
}
if ($secrets.ContainsKey('API_CERT_SHA256') -and $secrets['API_CERT_SHA256']) {
    $pin = ($secrets['API_CERT_SHA256'] -replace ':', '').ToLower()
    if ($pin -notmatch '^[0-9a-f]{64}$') { Fail 'API_CERT_SHA256 must be 64 hex digits.' }
    $defines['API_CERT_SHA256'] = $pin
    Write-Host "API_CERT_SHA256: $pin"
}
if ($secrets.ContainsKey('API_CA_FILE') -and $secrets['API_CA_FILE']) {
    $caFile = Convert-BuildPath $secrets['API_CA_FILE']
    if (-not [System.IO.Path]::IsPathRooted($caFile)) { $caFile = Join-Path $Root $caFile }
    if (-not (Test-Path -LiteralPath $caFile)) { Fail "API_CA_FILE not found: $caFile" }
    $caBytes = [System.IO.File]::ReadAllBytes($caFile)
    $caText = [System.Text.Encoding]::ASCII.GetString($caBytes)
    if ($caText -notmatch '-----BEGIN CERTIFICATE-----') { Fail "API_CA_FILE is not a PEM certificate: $caFile" }
    $defines['API_CA_PEM_B64'] = [System.Convert]::ToBase64String($caBytes)
    Write-Host "API_CA_FILE: $caFile ($($caBytes.Length) bytes, production host verified against this CA)"
}
if ($Env -eq 'prodtest' -and -not $defines.ContainsKey('API_BASE')) {
    Fail '.secrets\prodtest.env has no API_BASE.'
}

# Passwords reach apksigner through the environment, not the command line.
$env:GIOS_BUILD_KS_PASS = $ksPass
$env:GIOS_BUILD_KEY_PASS = $keyPass
Write-Host "keystore: $ks (alias $alias)"

# ---------------------------------------------------------------- build
$flutterArgs = @('build', 'apk', '--release')
if ($PSBoundParameters.ContainsKey('BuildNumber')) { $flutterArgs += @('--build-number', $BuildNumber) }
if ($PSBoundParameters.ContainsKey('BuildName')) { $flutterArgs += @('--build-name', $BuildName) }
# Field rescue v1: the build the back office sees in every report (app.build).
$flutterArgs += "--dart-define=APP_BUILD=$hash"
if ($Env -eq 'local') { $flutterArgs += '--dart-define=LOCAL_DEVELOPMENT=true' }
# The credential goes through a file (UTF-8 without BOM), never argv.
$buildDir = Join-Path $Root 'build'
if (-not (Test-Path -LiteralPath $buildDir)) { New-Item -ItemType Directory -Path $buildDir | Out-Null }
$DefineFile = Join-Path $buildDir ('.app_backend_key_{0}_{1}.json' -f $PID, [Guid]::NewGuid().ToString('N'))
$defineJson = ($defines | ConvertTo-Json -Compress)
Write-PrivateUtf8File $DefineFile $defineJson
$flutterArgs += "--dart-define-from-file=$DefineFile"
$gradleOut = Join-Path $Root 'build/app/outputs/flutter-apk/app-release.apk'
# Never sign a leftover from an earlier build.
if (Test-Path -LiteralPath $gradleOut) { Remove-Item -LiteralPath $gradleOut -Force }

Step ('flutter ' + ($flutterArgs -join ' '))
$inheritedDebug = $env:DEBUG
# gradlew.bat enables command echo when DEBUG is set, exposing dart-defines.
Remove-Item Env:\DEBUG -ErrorAction SilentlyContinue
Push-Location $Root
try {
    Invoke-Native $flutter.Source $flutterArgs | ForEach-Object { Write-Host $_ }
    $buildExit = $LASTEXITCODE
} finally {
    Pop-Location
    if ($null -eq $inheritedDebug) {
        Remove-Item Env:\DEBUG -ErrorAction SilentlyContinue
    } else {
        $env:DEBUG = $inheritedDebug
    }
    Remove-Item -LiteralPath $DefineFile -Force -ErrorAction SilentlyContinue
    $DefineFile = $null
}
if ($buildExit -ne 0) { Fail "flutter build exited with $buildExit." }
if (-not (Test-Path -LiteralPath $gradleOut)) { Fail "build output missing: $gradleOut" }

# ---------------------------------------------------------------- align + sign
$work = Join-Path $OutDir ".build_apk_$PID"
New-Item -ItemType Directory -Path $work -Force | Out-Null
$final = Join-Path $OutDir "app_${hash}${buildSuffix}_$Env.apk"
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
$envNote = if ($Env -eq 'local') { 'LOCAL_DEVELOPMENT=true' } elseif ($Env -eq 'prodtest') { 'HTTPS only, debug-signed, NOT a release' } else { 'HTTPS only' }
Step 'Done'
Write-Host "APK    : $final"
Write-Host "env    : $Env ($envNote)"
Write-Host "key    : APP_BACKEND_KEY from .secrets\$Env.env"
Write-Host "cert   : $cert"
Write-Host "sha256 : $sha"
exit 0
