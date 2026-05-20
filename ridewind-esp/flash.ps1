# RideWind ESP32 烧录脚本 — 锁定 Python 环境，避免版本冲突
# 用法：
#   .\flash.ps1              — 烧录到默认 COM 口（自动检测）
#   .\flash.ps1 -Port COM3   — 指定 COM 口
#   .\flash.ps1 -Monitor     — 烧录后打开串口监视器

param(
    [string]$Port = "",
    [switch]$Monitor
)

$ErrorActionPreference = "Stop"
$IDF_PATH = "C:\Espressif\frameworks\esp-idf-v5.3.5"

# 强制锁定 Python 环境（解决多版本冲突）
$env:IDF_PATH = $IDF_PATH
$env:IDF_PYTHON_ENV_PATH = "C:\Espressif\python_env\idf5.3_py3.14_env"
$env:PYTHON = "C:\Espressif\python_env\idf5.3_py3.14_env\Scripts\python.exe"

# 构建 PATH
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

if (-not ($env:Path -like "*Espressif*tools*ninja*")) {
    $env:Path = ($idfTools -join ";") + ";" + $env:Path
}

# 检查 build 目录是否存在
if (-not (Test-Path "build\ridewind-esp.bin")) {
    Write-Host "[ERROR] 未找到 build\ridewind-esp.bin，请先运行 .\build.ps1" -ForegroundColor Red
    exit 1
}

# 构建烧录命令
$flashCmd = "idf.py"
$flashArgs = @()

if ($Port) {
    $flashArgs += "-p"
    $flashArgs += $Port
}

$flashArgs += "flash"

if ($Monitor) {
    $flashArgs += "monitor"
}

Write-Host "[FLASH] 烧录固件..." -ForegroundColor Cyan
if ($Port) {
    Write-Host "  端口: $Port" -ForegroundColor Gray
} else {
    Write-Host "  端口: 自动检测" -ForegroundColor Gray
}

& $flashCmd @flashArgs
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "`n[OK] 烧录成功！" -ForegroundColor Green
} else {
    Write-Host "`n[FAIL] 烧录失败 (exit code: $exitCode)" -ForegroundColor Red
    Write-Host "  常见原因：" -ForegroundColor Yellow
    Write-Host "  - 设备未连接或 COM 口错误" -ForegroundColor Yellow
    Write-Host "  - 串口被其他程序占用（关闭串口监视器）" -ForegroundColor Yellow
    Write-Host "  - 需要按住 BOOT 按钮再上电" -ForegroundColor Yellow
}

exit $exitCode
