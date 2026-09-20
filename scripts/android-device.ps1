function Set-SemesterGradleJava {
    $javaCandidates = @($env:SEMESTEROS_JDK_HOME, $env:JAVA_HOME)
    foreach ($vendorFolder in @('Microsoft', 'Java', 'Eclipse Adoptium')) {
        $javaVendorPath = Join-Path $env:ProgramFiles $vendorFolder
        if (Test-Path -LiteralPath $javaVendorPath) {
            $javaCandidates += Get-ChildItem -LiteralPath $javaVendorPath -Directory | Select-Object -ExpandProperty FullName
        }
    }
    foreach ($javaCandidate in $javaCandidates) {
        if (!$javaCandidate) { continue }
        $javaRelease = Join-Path $javaCandidate 'release'
        if ((Test-Path -LiteralPath $javaRelease) -and (Select-String -LiteralPath $javaRelease -Pattern '^JAVA_VERSION="21\.' -Quiet)) {
            $resolvedJava = (Resolve-Path -LiteralPath $javaCandidate).Path
            $env:GRADLE_OPTS = (($env:GRADLE_OPTS, "-Dorg.gradle.java.installations.paths=`"$resolvedJava`"") -join ' ').Trim()
            Write-Host '已为本次构建定位 JDK 21（不修改全局 Java 配置）。'
            return
        }
    }
    throw '未找到本机 JDK 21。请安装 JDK 21，或用 SEMESTEROS_JDK_HOME 指定其目录。'
}

function Get-SemesterAndroidSdk([string]$ProjectRoot) {
    $candidates = @()
    $properties = Join-Path $ProjectRoot 'apps/mobile/android/local.properties'
    if (Test-Path -LiteralPath $properties) {
        foreach ($line in Get-Content -LiteralPath $properties) {
            if ($line -match '^sdk\.dir=(.+)$') {
                $candidates += $Matches[1].Replace('\\', '\').Replace('\:', ':')
            }
        }
    }
    $candidates += @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android/sdk'))
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'platform-tools/adb.exe'))) {
            return $candidate
        }
    }
    throw '未找到 Android SDK。请在 Android Studio 中安装 SDK，或设置 ANDROID_HOME。'
}

function Get-SemesterAndroidDevices([string]$Adb) {
    $lines = @(& $Adb devices 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'ADB 查询失败，请检查 Android SDK 的 platform-tools。' }
    foreach ($line in $lines) {
        if ($line -match '^(\S+)\s+(device|offline|unauthorized)\s*$') {
            [pscustomobject]@{ Id = $Matches[1]; State = $Matches[2] }
        }
    }
}

function Resolve-SemesterAndroidDevice {
    param(
        [Parameter(Mandatory)][string]$ProjectRoot,
        [string]$Device = 'auto',
        [string]$Emulator = 'Medium_Phone_33',
        [ValidateRange(10, 600)][int]$WaitSeconds = 150
    )
    $sdk = Get-SemesterAndroidSdk $ProjectRoot
    $adb = Join-Path $sdk 'platform-tools/adb.exe'
    $devices = @(Get-SemesterAndroidDevices $adb)
    $target = $Device
    if ($Device -eq 'auto') {
        $ready = @($devices | Where-Object State -eq 'device')
        if ($ready.Count -gt 1) { throw "检测到多个 Android 设备，请用 -Device 指定：$($ready.Id -join ', ')" }
        if ($ready.Count -eq 1) { $target = $ready[0].Id }
        elseif ($devices.Count -eq 1) { $target = $devices[0].Id }
        elseif ($devices.Count -gt 1) { throw "设备尚未就绪，请用 -Device 指定：$($devices.Id -join ', ')" }
        else { $target = $null }
    }
    $entry = $devices | Where-Object Id -eq $target | Select-Object -First 1
    if ($entry -and $entry.State -eq 'unauthorized') {
        throw "设备 $target 尚未授权，请在设备上确认 USB 调试。"
    }

    $launched = $null
    $errorLog = $null
    if (!$entry) {
        $port = $null
        if ($target) {
            if ($target -notmatch '^emulator-(\d+)$') {
                throw "未找到 Android 设备 '$target'。请连接设备，或省略 -Device 自动启动模拟器。"
            }
            $port = [int]$Matches[1]
            if ($port -lt 5554 -or $port -gt 5584 -or $port % 2 -ne 0) {
                throw '模拟器端口应是5554至5584之间的偶数，例如 emulator-5554。'
            }
        }
        $emulatorExe = Join-Path $sdk 'emulator/emulator.exe'
        if (!(Test-Path -LiteralPath $emulatorExe)) { throw '未安装 Android Emulator，请通过 Android Studio 的 SDK Manager 安装。' }
        $avds = @(& $emulatorExe -list-avds 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if ($LASTEXITCODE -ne 0 -or !$avds.Count) { throw '没有可启动的虚拟设备，请先在 Android Studio 的 Device Manager 创建模拟器。' }
        if ($Emulator -notin $avds) {
            if ($avds.Count -eq 1 -and $Emulator -eq 'Medium_Phone_33') { $Emulator = $avds[0] }
            else { throw "找不到模拟器 '$Emulator'。请用 -Emulator 指定：$($avds -join ', ')" }
        }
        foreach ($running in $devices | Where-Object { $_.Id -like 'emulator-*' -and $_.State -eq 'device' }) {
            $name = @(& $adb -s $running.Id emu avd name 2>$null)
            if ($Emulator -in $name) { throw "$Emulator 已运行在 $($running.Id)，请使用 -Device $($running.Id)。" }
        }
        $ports = @([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | ForEach-Object Port)
        if (!$port) {
            $port = @(5554..5584 | Where-Object { $_ % 2 -eq 0 -and $_ -notin $ports -and ($_ + 1) -notin $ports } | Select-Object -First 1)
            if (!$port.Count) { throw '没有可用的模拟器端口，请检查已经运行的模拟器。' }
            $port = [int]$port[0]
            $target = "emulator-$port"
        }
        if ($port -in $ports -or ($port + 1) -in $ports) {
            throw "$target 的端口已占用但 ADB 尚未识别它；请等设备启动后重试，或在 Device Manager 检查设备状态。"
        }
        $logDir = Join-Path $ProjectRoot 'tmp/android-start'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
        $errorLog = Join-Path $logDir "$stamp.stderr.log"
        Write-Host "启动 Android 模拟器：$Emulator ($target)"
        $launched = Start-Process -FilePath $emulatorExe -ArgumentList @('-avd', $Emulator, '-port', "$port") `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir "$stamp.stdout.log") -RedirectStandardError $errorLog
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $nextNotice = 0
    while ($watch.Elapsed.TotalSeconds -lt $WaitSeconds) {
        if ($launched) {
            $launched.Refresh()
            if ($launched.HasExited -and $launched.ExitCode -ne 0) { throw "模拟器启动失败，请查看日志：$errorLog" }
        }
        $entry = @(Get-SemesterAndroidDevices $adb | Where-Object Id -eq $target)
        if ($entry.Count -and $entry[0].State -eq 'unauthorized') { throw "设备 $target 尚未授权，请在设备上确认调试连接。" }
        if ($entry.Count -and $entry[0].State -eq 'device') {
            $boot = (& $adb -s $target shell getprop sys.boot_completed 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -eq 0 -and $boot -eq '1') {
                $package = (& $adb -s $target shell pm path android 2>$null | Out-String).Trim()
                if ($LASTEXITCODE -eq 0 -and $package -like 'package:*') {
                    Write-Host "Android 设备已就绪：$target"
                    return $target
                }
            }
        }
        if ($watch.Elapsed.TotalSeconds -ge $nextNotice) {
            Write-Host "等待 $target 启动完成（已等待 $([int]$watch.Elapsed.TotalSeconds) 秒）…"
            $nextNotice += 15
        }
        Start-Sleep -Seconds 2
    }
    throw "等待 $target 就绪超时。请检查 Device Manager 中的设备；启动日志：$errorLog"
}
