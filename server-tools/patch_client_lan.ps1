<#
.SYNOPSIS
    把 LLSIF 客户端改成直连局域网服务端（摆脱 adb / USB 线）。

.DESCRIPTION
    客户端里有**两处**服务端地址，必须同时改：

      1. jav层（classes.dex → smali）里的常量 http://127.0.0.1:8080
         —— ghome SDK 用它打 /v1/*（登录握手、账号等）。
      2. assets/AppAssets.zip 里 config/server_info.json 的 domain
         —— 游戏本体用它拼 /main.php/*（真正的游戏接口）。
         这个文件是 SIF CN **v4 加密**的。
      3. assets/AppAssets.zip 里 config/server_info.json 与
         config/package_info.json 的 server_version
         —— 客户端拿它们当 external_version / install_version 上报。
         两者不等 = 客户端判定自己是旧版本 → 进下载界面等 bootstrap 包
         → 服务端没这种包 → 进度除以 0 → 「下载 NaN%」。

    关键结论（踩了很久才确认）：
      - honoka2 的版本号是写在前缀字母后面的：`-c` = CN v3，`-c4` = CN v4。
        之前用 `-c` 生成的文件是 v3，客户端解不开直接闪退。
      - 用 `-e -c4 -b server_info.json` 加密、`-c4` 解密可以完美往返。

.PARAMETER Ip
    电脑的局域网 IP（服务端跑在这台机器上）。

.PARAMETER Port
    服务端端口，默认 8080。

.EXAMPLE
    .\patch_client_lan.ps1 -Ip 192.168.0.106

.EXAMPLE
    # 只生成 APK 不安装
    .\patch_client_lan.ps1 -Ip 192.168.0.106 -NoInstall
#>
param(
    [Parameter(Mandatory = $true)][string]$Ip,
    [int]$Port = 8080,
    # 必须与服务端 config.PackageVersion 一致，否则客户端会认为自己是旧版本，
    # 停在下载界面等 bootstrap 包（表现为「下载 NaN%」）。
    [string]$PackageVersion = "97.4.6",
    [string]$BaseApk = "d:\LLSIFLocal\temp\installed_base.apk",
    # 原始未改动的 APK，用来取「干净的」加密配置文件。
    # BaseApk 可能是之前打过补丁的包（里面的 config 已被错误的 v3 覆盖），
    # 拿它当模板会解不开。
    [string]$ConfigApk = "d:\LLSIFLocal\LoveLive_9.7.1_patched.apk",
    [string]$WorkDir = "d:\LLSIFLocal\temp\netpatch",
    [string]$Keystore = "d:\LLSIFLocal\askey.keystore",
    [string]$StorePass = "123456",
    [string]$KeyAlias = "askey",
    [string]$KeyPass = "123456",
    [string]$Adb = "d:\LLSIFLocal\android-sdk\platform-tools\adb.exe",
    [string]$Java = "d:\LLSIFLocal\jdk-17.0.14+7\bin\java.exe",
    [string]$Apktool = "d:\LLSIFLocal\工具\apktool.jar",
    [string]$Honoka = "d:\LLSIFLocal\libhonoka\bin\honoka2.exe",
    [string]$Apksigner = "d:\LLSIFLocal\build-tools\android-13\apksigner.bat",
    [string]$Zipalign = "d:\LLSIFLocal\build-tools\android-13\zipalign.exe",
    # 额外注入的 dex（游戏内 GM 面板）。由 temp\gm 下的 Java 源码编译而来。
    [string]$ExtraDex = "d:\LLSIFLocal\temp\gm\dex\classes.dex",
    [switch]$NoInstall,
    [switch]$KeepDecoded
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

$base = "http://${Ip}:$Port"
$decoded = Join-Path $WorkDir "decoded"
$outApk = Join-Path $WorkDir "client_lan_$($Ip -replace '\.','_').apk"

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# honoka2 解不开文件时会往 stderr 输出，而 $ErrorActionPreference=Stop 会把原生 stderr
# 直接当成异常抛出，导致脚本中断在「回退下一个来源」之前。所以统一走这个包装。
function Invoke-Honoka {
    param([string[]]$HonokaArgs)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { return (& $Honoka @HonokaArgs 2>&1 | Out-String).Trim() }
    finally { $ErrorActionPreference = $prev }
}

# ---------------------------------------------------------------- 1. 解码 smali
if (-not (Test-Path (Join-Path $decoded "smali"))) {
    Step "apktool 解码（首次较慢，之后会复用 $decoded）"
    if (Test-Path $decoded) { Remove-Item $decoded -Recurse -Force }
    & $Java -jar $Apktool d -r -f $BaseApk -o $decoded | Out-Null
    if (-not (Test-Path (Join-Path $decoded "smali"))) { throw "apktool 解码失败" }
} else {
    Step "复用已有 smali 目录"
}

# ------------------------------------------------------- 2. 改 Java 层地址常量
Step "替换 smali 里的 http://127.0.0.1:8080 → $base"
$old = "http://127.0.0.1:8080"
# 先把可能已经改成别的 IP 的常量统一回退到旧值，保证可重复执行
$anyHost = 'http://\d{1,3}(\.\d{1,3}){3}:\d+'
$files = Get-ChildItem -Recurse -Path $decoded -Filter *.smali |
    Where-Object { (Get-Content $_.FullName -Raw) -match '127\.0\.0\.1:8080|192\.168\.\d+\.\d+:\d+' }
$changed = 0
foreach ($f in $files) {
    $text = [IO.File]::ReadAllText($f.FullName, [Text.UTF8Encoding]::new($false))
    $new = [regex]::Replace($text, "http://127\.0\.0\.1:8080", $base)
    $new = [regex]::Replace($new, 'http://192\.168\.\d+\.\d+:\d+', $base)
    if ($new -ne $text) {
        [IO.File]::WriteAllText($f.FullName, $new, [Text.UTF8Encoding]::new($false))
        $changed++
    }
}
Write-Host "改动 $changed 个 smali 文件"
$left = (Get-ChildItem -Recurse -Path $decoded -Filter *.smali |
    Select-String -Pattern '127\.0\.0\.1:8080' | Measure-Object).Count
if ($left -gt 0) { Write-Host "警告：仍有 $left 处旧地址" -ForegroundColor Yellow }
else { Write-Host "smali 已全部指向 $base" -ForegroundColor Green }

# ------------------------------------------------------------- 3. 重打包 smali
Step "apktool 重新打包"
$unsigned = Join-Path $WorkDir "out_unsigned.apk"
if (Test-Path $unsigned) { Remove-Item $unsigned -Force }
& $Java -jar $Apktool b $decoded -o $unsigned | Out-Null
if (-not (Test-Path $unsigned)) { throw "apktool 打包失败" }

# ---------------------------- 4. 改 AppAssets.zip 里的配置（server_info / package_info）
# 为什么两个都要改：
#   server_info.json 的 domain    → 游戏本体走哪个服务端
#   server_info.json 的 server_version + package_info.json 的 server_version
#       → 客户端把它当作 external_version / install_version 上报。
#       只改 server_info 会出现 install(97.1.1) != external(97.4.6)，
#       客户端认为自己是旧版本，进入下载界面等 bootstrap 包，
#       而服务端没有对应包 → 进度 total=0 → 「下载 NaN%」。
Step "改写 AppAssets.zip 配置（domain + server_version，SIF CN v4）"
$cfgDir = Join-Path $WorkDir "cfg"
New-Item -ItemType Directory -Force $cfgDir | Out-Null
$assetsSrc = Join-Path $WorkDir "AppAssets_src.zip"
$assetsOut = Join-Path $WorkDir "AppAssets_new.zip"
foreach ($p in @($assetsSrc, $assetsOut)) { if (Test-Path $p) { Remove-Item $p -Force } }

$zip = [System.IO.Compression.ZipFile]::OpenRead($unsigned)
$entry = $zip.Entries | Where-Object { $_.FullName -eq "assets/AppAssets.zip" }
[System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $assetsSrc, $true)
$zip.Dispose()

$replaceBytes = @{}

# 从 $src 取某个配置文件：
#   - .apk  → 先取出嵌套的 assets/AppAssets.zip，再取 config/xxx.json
#   - .zip  → 直接取 config/xxx.json
function Copy-ConfigEntry($src, $entryPath, $dest) {
    $inner = $src
    $tempAa = $null
    if ($src -match '\.apk$') {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($src)
        try {
            $e = $zip.Entries | Where-Object { $_.FullName -eq "assets/AppAssets.zip" }
            if (-not $e) { return $false }
            $tempAa = Join-Path $cfgDir ("aa_" + [IO.Path]::GetFileNameWithoutExtension($src) + ".zip")
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $tempAa, $true)
        } finally { $zip.Dispose() }
        $inner = $tempAa
    }
    $zip = [System.IO.Compression.ZipFile]::OpenRead($inner)
    try {
        $e = $zip.Entries | Where-Object { $_.FullName -eq $entryPath }
        if (-not $e) { return $false }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
        return $true
    } finally {
        $zip.Dispose()
        if ($tempAa -and (Test-Path $tempAa)) { Remove-Item $tempAa -Force }
    }
}

foreach ($item in @(
        @{ Name = "server_info.json"; SetDomain = $true },
        @{ Name = "package_info.json"; SetDomain = $false })) {
    $name = $item.Name
    $entryPath = "config/$name"
    $encPath = Join-Path $cfgDir "$name.enc"
    $plainPath = Join-Path $cfgDir $name

    # 先从目标 APK 的 AppAssets.zip 里取；取不到或解不开就退回原始 APK
    $sources = @($assetsSrc)
    if ($ConfigApk -and (Test-Path $ConfigApk)) { $sources += $ConfigApk }
    $ok = $false
    foreach ($src in $sources) {
        if (-not (Copy-ConfigEntry $src $entryPath $encPath)) { continue }
        if (Test-Path $plainPath) { Remove-Item $plainPath -Force }
        $r = Invoke-Honoka @("-c4", "-b", $name, $encPath, $plainPath)
        if (Test-Path $plainPath) { $ok = $true; break }
        Write-Host "  （$([IO.Path]::GetFileName($src)) 里的 $name 解不开，换下一个来源：$r）" -ForegroundColor Yellow
    }
    if (-not $ok) { throw "所有来源都解不开 $name（需要 v4 加密，文件头第 8 字节为 02）" }

    $text = [IO.File]::ReadAllText($plainPath, [Text.UTF8Encoding]::new($false))
    if ($item.SetDomain) {
        $text = [regex]::Replace($text, 'http://\d{1,3}(\.\d{1,3}){3}(:\d+)?', $base)
        $text = [regex]::Replace($text, 'http://localhost(:\d+)?', $base)
    }
    $text = [regex]::Replace($text, '"server_version"\s*:\s*"[^"]*"', "`"server_version`": `"$PackageVersion`"")
    [IO.File]::WriteAllText($plainPath, $text, [Text.UTF8Encoding]::new($false))
    $domain = [regex]::Match($text, '"domain":\s*"([^"]+)"').Groups[1].Value
    $ver = [regex]::Match($text, '"server_version":\s*"([^"]+)"').Groups[1].Value
    Write-Host ("{0}: domain={1} server_version={2}" -f $name, $domain, $ver)

    $newEnc = Join-Path $cfgDir "$name.new"
    if (Test-Path $newEnc) { Remove-Item $newEnc -Force }
    Invoke-Honoka @("-e", "-c4", "-b", $name, $plainPath, $newEnc) | Out-Null
    if (-not (Test-Path $newEnc)) { throw "$name 加密失败（注意必须是 -c4，不是 -c）" }

    # 往返校验，避免又做出客户端解不开的文件
    $verify = Join-Path $cfgDir "$name.verify"
    if (Test-Path $verify) { Remove-Item $verify -Force }
    Invoke-Honoka @("-c4", "-b", $name, $newEnc, $verify) | Out-Null
    if (-not (Test-Path $verify)) { throw "自检失败：$name 生成的文件解不回来" }
    $ok = (Get-Content $verify -Raw -Encoding UTF8) -eq (Get-Content $plainPath -Raw -Encoding UTF8)
    if (-not $ok) { throw "自检失败：$name 往返内容不一致" }
    Write-Host "$name 加密自检通过（解密回来与明文一致）" -ForegroundColor Green

    $replaceBytes[$entryPath] = [IO.File]::ReadAllBytes($newEnc)
}

$zipIn = [System.IO.Compression.ZipFile]::OpenRead($assetsSrc)
$zipOut = [System.IO.Compression.ZipFile]::Open($assetsOut, 'Create')
foreach ($e in $zipIn.Entries) {
    $ne = $zipOut.CreateEntry($e.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
    $os = $ne.Open()
    if ($replaceBytes.ContainsKey($e.FullName)) {
        $b = $replaceBytes[$e.FullName]
        $os.Write($b, 0, $b.Length)
    } else { $is = $e.Open(); $is.CopyTo($os); $is.Close() }
    $os.Close()
}
$zipOut.Dispose(); $zipIn.Dispose()
Write-Host ("AppAssets.zip 重建完成 " + [math]::Round((Get-Item $assetsOut).Length / 1MB, 1) + " MB")

# --------------------------------------------------------- 5. 重打 APK + 签名
Step "重打 APK（替换 AppAssets.zip 与 assets/version）"
$md5 = (Get-FileHash $assetsOut -Algorithm MD5).Hash.ToLower()
$finalUnsigned = Join-Path $WorkDir "final_unsigned.apk"
if (Test-Path $finalUnsigned) { Remove-Item $finalUnsigned -Force }
$zipIn = [System.IO.Compression.ZipFile]::OpenRead($unsigned)
$zipOut = [System.IO.Compression.ZipFile]::Open($finalUnsigned, 'Create')
foreach ($e in $zipIn.Entries) {
    if ($e.FullName -eq "assets/AppAssets.zip" -or $e.FullName -eq "assets/version") { continue }
    $ne = $zipOut.CreateEntry($e.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
    $os = $ne.Open(); $is = $e.Open(); $is.CopyTo($os); $is.Close(); $os.Close()
}
[System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $zipOut, $assetsOut, "assets/AppAssets.zip",
    [System.IO.Compression.CompressionLevel]::NoCompression) | Out-Null

# 附加 dex：游戏内 GM 面板（com.sifpatch.GmPanel）单独编成 classes3.dex，
# 这样不用手写 smali，改完 Java 重新编译即可。
if ($ExtraDex -and (Test-Path $ExtraDex)) {
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zipOut, $ExtraDex, "classes3.dex",
        [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    Write-Host ("已注入附加 dex：classes3.dex（" + [math]::Round((Get-Item $ExtraDex).Length / 1KB, 1) + " KB）")
}
$ver = $zipOut.CreateEntry("assets/version", [System.IO.Compression.CompressionLevel]::Optimal)
$sw = New-Object System.IO.StreamWriter($ver.Open())
$sw.Write("MD5 (AppAssets.zip) = $md5`n"); $sw.Close()
$zipOut.Dispose(); $zipIn.Dispose()

Step "zipalign + 签名"
# apksigner / zipalign 会往 stderr 打 WARNING，在 $ErrorActionPreference=Stop 下会被
# 当成异常抛出，所以这些外部命令统一压低错误级别再执行。
$prevEap = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$aligned = Join-Path $WorkDir "final_aligned.apk"
& $Zipalign -f 4 $finalUnsigned $aligned | Out-Null
if (Test-Path $outApk) { Remove-Item $outApk -Force }
& $Apksigner sign --ks $Keystore --ks-key-alias $KeyAlias `
    --ks-pass "pass:$StorePass" --key-pass "pass:$KeyPass" `
    --out $outApk $aligned 2>&1 | Out-Null
$ErrorActionPreference = $prevEap
if (-not (Test-Path $outApk)) { throw "签名失败" }
Write-Host ("产物：" + $outApk + "（" + [math]::Round((Get-Item $outApk).Length / 1MB, 1) + " MB）") -ForegroundColor Green

if (-not $KeepDecoded) { Write-Host "提示：$decoded 可以保留，下次换 IP 会快很多（-KeepDecoded）" }

# ------------------------------------------------------------- 6. 安装并验证
if (-not $NoInstall) {
    Step "安装到设备"
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Adb install -r $outApk | Select-Object -Last 1 | Write-Host
    & $Adb reverse --remove-all 2>&1 | Out-Null
    $ErrorActionPreference = $prevEap
    Write-Host "已清除 adb 反向转发（现在只有 wifi 也能连）"
    Write-Host "启动游戏后，检查服务端日志里应出现来自 $Ip 这一网段的请求。"
}
