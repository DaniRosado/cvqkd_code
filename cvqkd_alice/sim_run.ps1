<#
.SYNOPSIS
    Script de simulación para cvqkd_alice (LDPC Decoder) en Windows con Vivado XSim
.DESCRIPTION
    Compila, elabora y simula los testbenches del decodificador LDPC.
    Uso: .\sim_run.ps1 -Target <test> [-Gui]
    
    Targets:
      system   - Testbench del sistema completo (tb_ldpc_top_system)
      vnu      - Testbench VNU Processor
      cnu      - Testbench CNU Serial Min-Sum
      shifter  - Testbench Barrel Shifter
      all      - Todos los testbenches
      clean    - Limpia archivos generados
.PARAMETER Target
    Target de simulación (system|vnu|cnu|shifter|all|clean)
.PARAMETER Gui
    Abre la GUI de XSim en lugar de ejecución en consola
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("system", "vnu", "cnu", "shifter", "all", "clean", "help")]
    [string]$Target = "help",
    [switch]$Gui
)

# === Configuración ===
$XILINX_VIVADO = if (Test-Path "C:\AMDDesignTools\2025.2\Vivado") {
    "C:\AMDDesignTools\2025.2\Vivado"
} elseif (Test-Path $env:XILINX_VIVADO) {
    $env:XILINX_VIVADO
} else {
    Write-Error "Vivado no encontrado. Establece XILINX_VIVADO o instala en C:\AMDDesignTools"
    exit 1
}

$XVLOG  = "$XILINX_VIVADO\bin\xvlog.bat"
$XELAB  = "$XILINX_VIVADO\bin\xelab.bat"
$XSIM   = "$XILINX_VIVADO\bin\xsim.bat"

$ROOT   = Split-Path -Parent $PSScriptRoot
$RTL    = Join-Path $PSScriptRoot "rtl"
$SIM    = Join-Path $PSScriptRoot "sim"
$WORK   = Join-Path $PSScriptRoot "xsim_work"

$SOURCES = @(
    "bg_rom_pkg.sv",
    "barrel_shifter_word.sv",
    "cnu_serial_minsum.sv",
    "cnu_cell.sv",
    "cnu_min_sum_array.sv",
    "vnu_processor.sv",
    "ldpc_bram_block.sv",
    "ldpc_rom_controller.sv",
    "ldpc_layer_datapath.sv",
    "ldpc_decoder_top.sv"
)

$TBS = @{
    vnu     = @{ file = "tb_vnu_processor.sv";        work = "work.tb_vnu_processor" }
    cnu     = @{ file = "tb_cnu_serial_minsum.sv";    work = "work.tb_cnu_serial_minsum" }
    shifter = @{ file = "tb_barrel_shifter_word.sv";  work = "work.tb_barrel_shifter_word" }
    system  = @{ file = "tb_ldpc_top_system.sv";      work = "work.tb_ldpc_top_system" }
}

function Log-Info($msg) { Write-Host "=== $msg ===" -ForegroundColor Cyan }
function Log-Ok($msg)  { Write-Host "[OK] $msg" -ForegroundColor Green }
function Log-Err($msg) { Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Invoke-Xvlog {
    param([string[]]$Files, [string]$WorkLib = "work")
    $srcList = $Files | ForEach-Object { "`"$_`"" }
    $cmd = "& `"$XVLOG`" --sv --work $WorkLib $srcList 2>&1"
    Log-Info "Compilando: $($Files | Split-Path -Leaf)"
    $result = Invoke-Expression $cmd
    $result | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "xvlog falló" }
}

function Invoke-Xelab {
    param([string]$Top)
    $cmd = "& `"$XELAB`" -debug typical $Top 2>&1"
    Log-Info "Elaborando: $Top"
    $result = Invoke-Expression $cmd
    $result | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "xelab falló" }
}

function Invoke-Xsim {
    param([string]$Top)
    if ($Gui) {
        $cmd = "& `"$XSIM`" $Top --gui 2>&1"
    } else {
        $cmd = "& `"$XSIM`" $Top --runall 2>&1"
    }
    Log-Info "Simulando: $Top"
    $result = Invoke-Expression $cmd
    $result | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "xsim falló" }
}

function Invoke-Clean {
    Log-Info "Limpiando archivos generados"
    $dirs = @("xsim_work", "xsim.dir", ".Xil", "obj_dir")
    $files = @("*.log", "*.jou", "*.str", "webtalk*", "xvlog*", "xelab*", "xsim*")
    foreach ($d in $dirs) {
        $path = Join-Path $PSScriptRoot $d
        if (Test-Path $path) { Remove-Item -Recurse -Force $path; Log-Ok "Eliminado $d" }
    }
    foreach ($f in $files) {
        Get-ChildItem -Path $PSScriptRoot -Filter $f -ErrorAction SilentlyContinue | Remove-Item -Force
    }
}

function Invoke-Target {
    param([string]$Name)
    $tb = $TBS[$Name]
    if (-not $tb) { throw "Target desconocido: $Name" }
    
    $srcFiles = $SOURCES | ForEach-Object { Join-Path $RTL $_ }
    $srcFiles += Join-Path $SIM $tb.file
    
    Invoke-Xvlog -Files $srcFiles
    Invoke-Xelab -Top $tb.work
    Invoke-Xsim -Top $tb.work
}

# === Main ===
try {
    Push-Location $PSScriptRoot
    
    switch ($Target) {
        "help" {
            Get-Help $MyInvocation.MyCommand.Definition -Detailed
        }
        "clean" {
            Invoke-Clean
        }
        "all" {
            @("vnu", "cnu", "shifter", "system") | ForEach-Object { Invoke-Target $_ }
        }
        default {
            Invoke-Target $Target
        }
    }
    
    Log-Ok "Simulación completada: $Target"
} catch {
    Log-Err $_.Exception.Message
    exit 1
} finally {
    Pop-Location
}
