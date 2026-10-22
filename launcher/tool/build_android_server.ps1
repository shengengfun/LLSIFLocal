<#
.SYNOPSIS
    把 honoka-chan 交叉编译成 Android 可执行的 native lib，塞进启动器 APK。

.DESCRIPTION
    为什么打成 `lib/arm64-v8a/libhonoka_chan.so` 而不是普通二进制：

      Android 10+ 禁止 app 执行自己可写目录（app_data_file）里的文件，
      `execve` 会直接 EACCES。但 APK 的 native lib 目录
      （/data/app/~~xxx/<pkg>/lib/arm64/）属于 apk_data_file，允许执行。
      所以把服务端伪装成一个 .so 放进 jniLibs，由 Gradle 打进 APK，
      安装时解压到 lib 目录，Dart 侧直接 Process.start 这个路径即可。

    配套要求（已在本仓库改好）：
      * AndroidManifest 里 android:extractNativeLibs="true"
      * build.gradle.kts 里 packaging { jniLibs { useLegacyPackaging = true } }
        —— 否则 lib 会被压缩进 APK 而不解压，路径不存在
      * packaging { jniLibs { keepDebugSymbols += "**/libhonoka_chan.so" } }
        —— 别让 Flutter 的 strip 步骤动它

    honoka-chan 是纯 Go（SQLite 用 modernc.org/sqlite，无 CGO），
    所以直接 `GOOS=android GOARCH=arm64 CGO_ENABLED=0` 就能出 Android 可执行文件，
    不需要 NDK。

    两个必须踩对的点（脚本会自检）：
      * **必须是 PIE**（ELF type=3/DYN）。Android 5+ 拒绝执行非 PIE 的 ELF，
        用 `GOOS=linux` 编出来的是 ET_EXEC，装上就 "only position independent
        executables are supported"。
      * **PT_INTERP 必须是 /system/bin/linker64**。`GOOS=linux` 会写成
        `/lib/ld-linux-aarch64.so.1`，Android 上没这个路径，execve 直接 ENOENT。

.EXAMPLE
    .\build_android_server.ps1
    .\build_android_server.ps1 -Abis arm64-v8a,armeabi-v7a
#>
param(
    [string[]]$Abis = @("arm64-v8a"),
    [string]$ServerSrc = "d:\LLSIFLocal\honoka-chan-dev",
    [string]$JniLibs = "d:\LLSIFLocal\srvapp\android\app\src\main\jniLibs",
    [string]$GoBin = "d:\LLSIFLocal\Go\Go\bin\go.exe",
    [string]$LibName = "libhonoka_chan.so"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GoBin)) {
    $found = Get-Command go -ErrorAction SilentlyContinue
    if ($found) { $GoBin = $found.Source } else { throw "找不到 go：$GoBin" }
}

# 校验产物确实能跑在 Android 上：PIE(ET_DYN) + 正确的 PT_INTERP。
function Assert-AndroidExecutable {
    param([string]$Path, [string]$Goarch)

    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes[0] -ne 0x7F -or $bytes[1] -ne 0x45 -or $bytes[2] -ne 0x4C -or $bytes[3] -ne 0x46) {
        throw "$Path 不是 ELF"
    }
    $machine = [BitConverter]::ToUInt16($bytes, 18)
    $want = if ($Goarch -eq "arm64") { 183 } else { 40 }
    if ($machine -ne $want) { throw "$Path 的 machine=$machine，期望 $want" }

    $etype = [BitConverter]::ToUInt16($bytes, 16)
    if ($etype -ne 3) {
        throw ("$Path 不是 PIE（e_type={0}）。Android 5+ 只认 ET_DYN，请确认 GOOS=android。" -f $etype)
    }

    $phoff = [BitConverter]::ToUInt64($bytes, 32)
    $phentsize = [BitConverter]::ToUInt16($bytes, 54)
    $phnum = [BitConverter]::ToUInt16($bytes, 56)
    $interp = ""
    for ($i = 0; $i -lt $phnum; $i++) {
        $o = [int]($phoff + $i * $phentsize)
        $ptype = [BitConverter]::ToUInt32($bytes, $o)
        if ($ptype -eq 3) {
            $off = [int][BitConverter]::ToUInt64($bytes, $o + 8)
            $len = [int][BitConverter]::ToUInt64($bytes, $o + 32)
            $interp = [Text.Encoding]::ASCII.GetString($bytes, $off, $len).TrimEnd([char]0)
        }
    }
    $expect = if ($Goarch -eq "arm64") { "/system/bin/linker64" } else { "/system/bin/linker" }
    if ($interp -ne $expect) {
        throw ("$Path 的 PT_INTERP=${interp}，期望 $expect。用 GOOS=linux 编的产物在 Android 上会 ENOENT。")
    }
}

Write-Host ""
Write-Host "完成。接着重新出 APK："
Write-Host "  cd d:\LLSIFLocal\srvapp"
Write-Host "  ..\sdk\flutter\bin\flutter.bat build apk --release"

$map = @{
    "arm64-v8a"   = @{ goarch = "arm64"; goarm = "" }
    "armeabi-v7a" = @{ goarch = "arm";   goarm = "7" }
}

foreach ($abi in $Abis) {
    if (-not $map.ContainsKey($abi)) { throw "不支持的 ABI：$abi（只有 arm64-v8a / armeabi-v7a）" }
    $arch = $map[$abi].goarch
    $arm = $map[$abi].goarm

    $outDir = Join-Path $JniLibs $abi
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $out = Join-Path $outDir $LibName

    Write-Host "== 编译 $abi (GOOS=android GOARCH=$arch GOARM=$arm)"
    $env:CGO_ENABLED = "0"
    $env:GOOS = "android"
    $env:GOARCH = $arch
    if ($arm) { $env:GOARM = $arm } else { Remove-Item Env:\GOARM -ErrorAction SilentlyContinue }

    Push-Location $ServerSrc
    try {
        & $GoBin build -trimpath -buildvcs=false -ldflags "-s -w" -o $out .
        if ($LASTEXITCODE -ne 0) { throw "编译失败：$abi" }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $out)) { throw "没有产出文件：$out" }
    $size = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Assert-AndroidExecutable -Path $out -Goarch $arch
    Write-Host ("   -> {0}  {1} MB  PIE + /system/bin/linker{2}" -f $out, $size, $(if ($arch -eq "arm64") { "64" } else { "" }))
}

