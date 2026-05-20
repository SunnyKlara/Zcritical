# RideWind ESP32 快速编译脚本
# 用法：
#   .\build.ps1          — 增量编译（最快，改了 .c/.h 后用这个）
#   .\build.ps1 -Full    — 全量编译（改了 sdkconfig.defaults 后用这个）
#   .\build.ps1 -App     — 只编译 app（跳过 bootloader，更快）
#   .\build.ps1 -Size    — 编译后显示 size 报告

param(
    [switch]$Full,
    [switch]$App,
    [switch]$Size
)

$ErrorActionPreference = "Stop"
$IDF_PATH = "C:\Espressif\frameworks\esp-idf-v5.3.5"

# 设置环境变量（比 export.ps1 快，跳过 Python 包检查）
$env:IDF_PATH = $IDF_PATH
$env:IDF_PYTHON_ENV_PATH = "C:\Espressif\python_env\idf5.3_py3.14_env"

# 构建 PATH（只添加一次，不重复）
$idfTools = @(
    "C:\Espressif\tools\xtensa-esp-elf-gdb\16.3_20250913\xtensa-esp-elf-gdb\bin",
    "C:\Espressif\tools\riscv32-esp-elf-gdb\16.3_20250913\riscv32-esp-elf-gdb\bin",
    "C:\Espressif\tools\xtensa-esp-elf\esp-13.2.0_20250707\xtensa-esp-elf\bin",
    "C:\Espressif\tools\esp-clang\16.0.1-fe4f10a809\esp-clang\bin",
    "C:\Espressif\tools\riscv32-esp-elf\esp-13.2.0_20250707\riscv32-esp-elf\bin",
    "C:\Espressif\tools\esp32ulp-elf\2.38_20240113\esp32ulp-elf\bin",
    "C:\Espressif\tools\cmake\3.30.2\bin",
    "C:\Espressif\tools\openocd-esp32\v0.12.0-esp32-20251215\openocd-esp32\bin",
    "C:\Espressif\tools\ninja\1.12.1\",
    "C:\Espressif\tools\idf-exe\1.0.3\",
    "C:\Espressif\tools\ccache\4.12.1\ccache-4.12.1-windows-x86_64",
    "C:\Espressif\tools\dfu-util\0.11\dfu-util-0.11-win64",
    "C:\Espressif\python_env\idf5.3_py3.14_env\Scripts",
    "$IDF_PATH\tools"
)

# 只在 PATH 中没有 idf.py 时才添加
if (-not ($env:Path -like "*Espressif*tools*ninja*")) {
    $env:Path = ($idfTools -join ";") + ";" + $env:Path
}

# 全量编译：删除 build + sdkconfig
if ($Full) {
    Write-Host "[FULL] Cleaning build directory..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
    Remove-Item sdkconfig -ErrorAction SilentlyContinue
}

# 计时
$sw = [System.Diagnostics.Stopwatch]::StartNew()

# 编译
if ($App) {
    Write-Host "[APP] Building app only (skip bootloader)..." -ForegroundColor Cyan
    idf.py app
} else {
    Write-Host "[BUILD] Incremental build..." -ForegroundColor Cyan
    idf.py build
}

$sw.Stop()
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "`n[OK] Build succeeded in $($sw.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
    
    if ($Size) {
        Write-Host "`n[SIZE] Running size analysis..." -ForegroundColor Cyan
        idf.py size
    }
} else {
    Write-Host "`n[FAIL] Build failed (exit code: $exitCode) after $($sw.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Red
}

exit $exitCode
