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
    [string]$LibName = "libhonoka_chan.so",
    [string]$NdkRoot = "d:\LLSIFLocal\android-sdk\ndk\28.2.13676358",
    [int]$ApiLevel = 24
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
    # ELF e_machine: 183=arm64, 40=arm, 62=x86_64, 3=i386
    $machine = [BitConverter]::ToUInt16($bytes, 18)
    $machineMap = @{ "arm64" = 183; "arm" = 40; "amd64" = 62; "386" = 3 }
    $want = $machineMap[$Goarch]
    if (-not $want) { throw "未知 GOARCH 的 machine 期望值：$Goarch" }
    if ($machine -ne $want) { throw "$Path 的 machine=$machine，期望 $want" }

    $etype = [BitConverter]::ToUInt16($bytes, 16)
    if ($etype -ne 3) {
        throw ("$Path 不是 PIE（e_type={0}）。Android 5+ 只认 ET_DYN，请确认 GOOS=android。" -f $etype)
    }

    # EI_CLASS: 1=ELF32, 2=ELF64；两种头布局不同，必须分开解析。
    $elfClass = $bytes[4]
    $is64 = $elfClass -eq 2
    if ($elfClass -ne 1 -and $elfClass -ne 2) { throw "$Path 的 EI_CLASS=$elfClass 非法" }

    if ($is64) {
        $phoff     = [long][BitConverter]::ToUInt64($bytes, 32)
        $phentsize = [int][BitConverter]::ToUInt16($bytes, 54)
        $phnum     = [int][BitConverter]::ToUInt16($bytes, 56)
        $offField  = 8     # p_offset 在 64 位 Phdr 中的偏移
        $szField   = 32    # p_filesz
        $readOff   = { param($o) [long][BitConverter]::ToUInt64($bytes, $o) }
    } else {
        $phoff     = [long][BitConverter]::ToUInt32($bytes, 28)
        $phentsize = [int][BitConverter]::ToUInt16($bytes, 42)
        $phnum     = [int][BitConverter]::ToUInt16($bytes, 44)
        $offField  = 4     # p_offset 在 32 位 Phdr 中的偏移
        $szField   = 16    # p_filesz
        $readOff   = { param($o) [long][BitConverter]::ToUInt32($bytes, $o) }
    }

    $interp = ""
    for ($i = 0; $i -lt $phnum; $i++) {
        $o = [int]($phoff + $i * $phentsize)
        $ptype = [BitConverter]::ToUInt32($bytes, $o)
        if ($ptype -eq 3) {
            $off = [int](& $readOff ($o + $offField))
            $len = [int](& $readOff ($o + $szField))
            $interp = [Text.Encoding]::ASCII.GetString($bytes, $off, $len).TrimEnd([char]0)
        }
    }
    # 64 位 ABI(aarch64/x86_64) 用 linker64，32 位用 linker
    $expect = if ($is64) { "/system/bin/linker64" } else { "/system/bin/linker" }
    if ($interp -ne $expect) {
        throw ("$Path 的 PT_INTERP=${interp}，期望 $expect。用 GOOS=linux 编的产物在 Android 上会 ENOENT。")
    }
}

$map = @{
    "arm64-v8a"   = @{ goarch = "arm64"; goarm = "" }
    "armeabi-v7a" = @{ goarch = "arm";   goarm = "7" }
    "x86_64"      = @{ goarch = "amd64"; goarm = "" }
    "x86"         = @{ goarch = "386";   goarm = "" }
}

foreach ($abi in $Abis) {
    if (-not $map.ContainsKey($abi)) { throw "不支持的 ABI：$abi（支持 arm64-v8a / armeabi-v7a / x86_64 / x86）" }
    $arch = $map[$abi].goarch
    $arm = $map[$abi].goarm

    $outDir = Join-Path $JniLibs $abi
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $out = Join-Path $outDir $LibName

    # Go 的 android/{amd64,386,arm} 都强制外部链接(cgo)；arm64 也能走 cgo。
    # 统一用 NDK 的 clang 外部链接，覆盖全部 ABI。
    $needCgo = $true
    $cc = ""
    if ($needCgo) {
        if (-not $NdkRoot) { throw "构建 $abi 需要 -NdkRoot（Go 的 android 目标需要外部链接）" }
        $ccDir = Join-Path $NdkRoot "toolchains\llvm\prebuilt\windows-x86_64\bin"
        $triple = switch ($arch) {
            "arm64" { "aarch64-linux-android" }
            "arm"   { "armv7a-linux-androideabi" }
            "amd64" { "x86_64-linux-android" }
            "386"   { "i686-linux-android" }
            default { throw "未知 GOARCH：$arch" }
        }
        $cc = Join-Path $ccDir "$triple$ApiLevel-clang.cmd"
        if (-not (Test-Path $cc)) { throw "找不到 NDK 编译器：$cc" }
    }

    Write-Host "== 编译 $abi (GOOS=android GOARCH=$arch GOARM=$arm CGO=$(if ($needCgo) { 1 } else { 0 }))"
    if ($needCgo) { $env:CGO_ENABLED = "1"; $env:CC = $cc } else { $env:CGO_ENABLED = "0"; Remove-Item Env:\CC -ErrorAction SilentlyContinue }
    $env:GOOS = "android"
    $env:GOARCH = $arch
    if ($arm) { $env:GOARM = $arm } else { Remove-Item Env:\GOARM -ErrorAction SilentlyContinue }

    Push-Location $ServerSrc
    try {
        # 必须锁 go1.25.0：auto 会拉到 go1.26，modernc.org/sqlite 编译失败
        $env:GOTOOLCHAIN = "go1.25.0"
        $env:GOFLAGS = "-mod=mod"
        & $GoBin build -trimpath -buildvcs=false -ldflags "-s -w" -o $out .
        if ($LASTEXITCODE -ne 0) { throw "编译失败：$abi" }
    } finally {
        Pop-Location
    }

    if (-not (Test-Path $out)) { throw "没有产出文件：$out" }
    $size = [math]::Round((Get-Item $out).Length / 1MB, 1)
    Assert-AndroidExecutable -Path $out -Goarch $arch
    $suffix = if (($arch -eq "arm64") -or ($arch -eq "amd64")) { "64" } else { "" }
    Write-Host ("   -> {0}  {1} MB  PIE + /system/bin/linker{2}" -f $out, $size, $suffix)
}

Write-Host ""
Write-Host "全部 ABI 编译完成。接着重新出 APK："
Write-Host "  cd d:\LLSIFLocal\srvapp"
Write-Host "  ..\sdk\flutter\bin\flutter.bat build apk --release"

