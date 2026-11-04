#!/usr/bin/env pwsh
# =============================================================================
# scripts/medir_resultados_.ps1
#
# Benchmark automatizado: 4 modelos x 5 ratios x N repeticiones.
# Restaura cada base desde un TEMPLATE antes de cada corrida (estado limpio).
# Calcula WAL, TPS, latencia, p95, p99 y guarda CSV con BOM.
#
# Requisitos:
#   - psql, pgbench en el PATH
#   - PGUSER, PGPASSWORD configurados
#   - Las 4 bases ya cargadas con 1.000.000 filas cada una (léase antes_de_ejecutar_medir_resultados.ps1.md)
#
# Uso:
#   .\scripts\medir_resultados_.ps1 -DURATION 60 -CLIENTS 10 -THREADS 2 -REPS 3
# =============================================================================
param(
    [ValidateRange(1, 86400)][int]$DURATION = 60,
    [ValidateRange(1, 10000)][int]$CLIENTS = 10,
    [ValidateRange(1, 10000)][int]$THREADS = 2,
    [ValidateRange(1, 1000)][int]$REPS = 3,
    [string]$ROOT = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

if ($THREADS -gt $CLIENTS) {
    throw "THREADS cannot be greater than CLIENTS."
}

$ROOT = (Resolve-Path -LiteralPath $ROOT).Path
$PSQL = (Get-Command psql -CommandType Application -ErrorAction Stop).Source
$PGBENCH = (Get-Command pgbench -CommandType Application -ErrorAction Stop).Source

# ---- Modelos: base de trabajo + plantilla + scripts pgbench ----
$MODELS = @{
    eav         = @{ db="base_eav";                  template="base_eav_template";                  read="read_eav.sql";         upd="upd_eav.sql";         ins="ins_eav.sql" }
    jsonb_gin   = @{ db="base_jsonb_gin";            template="base_jsonb_gin_template";            read="read_jsonb_gin.sql";   upd="upd_jsonb_gin.sql";   ins="ins_jsonb_gin.sql" }
    jsonb_btree = @{ db="base_jsonb_btree";          template="base_jsonb_btree_template";          read="read_jsonb_btree.sql"; upd="upd_jsonb_btree.sql"; ins="ins_jsonb_btree.sql" }
    udt         = @{ db="base_udt";                  template="base_udt_template";                  read="read_udt.sql";         upd="upd_udt.sql";         ins="ins_udt.sql" }
}

# ---- Ratios: pesos que SUMAN 100 para dar el porcentaje exacto ----
$RATIOS = @(
    @{ label="90/10"; read=90; upd=5; ins=5;  fileLabel="90_10" },
    @{ label="70/30"; read=70; upd=15; ins=15; fileLabel="70_30" },
    @{ label="50/50"; read=50; upd=25; ins=25; fileLabel="50_50" },
    @{ label="30/70"; read=30; upd=35; ins=35; fileLabel="30_70" },
    @{ label="10/90"; read=10; upd=45; ins=45; fileLabel="10_90" }
)

# ---- Salida ----
$OUTDIR = Join-Path $ROOT "results"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null
$CSV = Join-Path $OUTDIR "benchmark_resultados.csv"

foreach ($modelKey in $MODELS.Keys) {
    $model = $MODELS[$modelKey]
    foreach ($scriptName in @($model.read, $model.upd, $model.ins)) {
        $scriptPath = Join-Path $ROOT (Join-Path "pgbench" $scriptName)
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw "Missing pgbench script: $scriptPath"
        }
    }
}

# ---- Funciones ----
function Ejecutar-Psql {
    param([string]$Db, [string]$Comando)
    $psqlArgs = @("-X", "-q", "-v", "ON_ERROR_STOP=1", "-d", $Db, "-c", $Comando)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 5.1 promotes native stderr to NativeCommandError
        # when ErrorActionPreference is Stop, even when psql exits successfully.
        $ErrorActionPreference = "Continue"
        $salida = @(& $PSQL @psqlArgs 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $detalle = $salida -join [Environment]::NewLine
        throw "psql failed (exit code ${exitCode}) against ${Db}: ${Comando}`n$detalle"
    }
    return $salida
}

function Ejecutar-PsqlScalar {
    param([string]$Db, [string]$Comando)
    $psqlArgs = @("-X", "-q", "-t", "-A", "-v", "ON_ERROR_STOP=1", "-d", $Db, "-c", $Comando)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $salida = @(& $PSQL @psqlArgs 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $detalle = $salida -join [Environment]::NewLine
        throw "psql scalar query failed (exit code ${exitCode}) against ${Db}: ${Comando}`n$detalle"
    }

    $valores = @($salida | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
    if ($valores.Count -gt 1) {
        throw "Expected one scalar from psql against ${Db}, got $($valores.Count): $($salida -join ' | ')"
    }
    if ($valores.Count -eq 0) { return "" }
    return $valores[0]
}

function Obtener-WAL {
    param([string]$Db)
    $lsn = Ejecutar-PsqlScalar -Db $Db -Comando "SELECT pg_current_wal_lsn();"
    if ($lsn -notmatch '^[0-9A-F]+/[0-9A-F]+$') {
        throw "Invalid WAL LSN returned by PostgreSQL for '$Db': $lsn"
    }
    return $lsn
}

function Calcular-WAL-Diff {
    param([string]$Db, [string]$Antes, [string]$Despues)
    $diff = Ejecutar-PsqlScalar -Db $Db -Comando "SELECT pg_wal_lsn_diff('$Despues', '$Antes');"
    if ($diff -notmatch '^\d+(\.\d+)?$') {
        throw "Invalid WAL byte difference returned by PostgreSQL: $diff"
    }
    return $diff
}

function Crear-Plantillas {
    Write-Host ">> Phase 0: validating source databases and templates" -ForegroundColor Cyan

    # Validate every source database before any DROP/CREATE operation.
    foreach ($modelKey in $MODELS.Keys) {
        $db = $MODELS[$modelKey].db
        $exists = Ejecutar-PsqlScalar -Db postgres -Comando "SELECT 1 FROM pg_database WHERE datname='$db';"
        if ($exists -ne "1") {
            throw "Required source database '$db' does not exist. No databases were reset."
        }
    }

    Write-Host ">> Creating missing TEMPLATE databases" -ForegroundColor Cyan
    foreach ($modelKey in $MODELS.Keys) {
        $m = $MODELS[$modelKey]
        $tpl = $m.template
        $db = $m.db
        $exists = Ejecutar-PsqlScalar -Db postgres -Comando "SELECT 1 FROM pg_database WHERE datname='$tpl';"
        if ($exists -ne "1") {
            Write-Host "   Creating template $tpl from $db ..."
            Ejecutar-Psql -Db postgres -Comando "CREATE DATABASE $tpl TEMPLATE $db"
        }

        $verified = Ejecutar-PsqlScalar -Db postgres -Comando "SELECT 1 FROM pg_database WHERE datname='$tpl';"
        if ($verified -ne "1") {
            throw "Template database '$tpl' could not be verified."
        }
    }
    Write-Host ">> Templates are ready." -ForegroundColor Green
}

function Restaurar-Base {
    param([string]$Db, [string]$Template)
    Write-Host "   Restoring $Db from $Template ..."
    $exists = Ejecutar-PsqlScalar -Db postgres -Comando "SELECT 1 FROM pg_database WHERE datname='$Db';"
    if ($exists -eq "1") {
        Ejecutar-Psql -Db postgres -Comando "DROP DATABASE $Db WITH (FORCE)"
    }
    Ejecutar-Psql -Db postgres -Comando "CREATE DATABASE $Db TEMPLATE $Template"
    Ejecutar-Psql -Db $Db -Comando "VACUUM (ANALYZE)"
    Ejecutar-Psql -Db $Db -Comando "CHECKPOINT"

    $verified = Ejecutar-PsqlScalar -Db postgres -Comando "SELECT 1 FROM pg_database WHERE datname='$Db';"
    if ($verified -ne "1") {
        throw "Restored database '$Db' could not be verified."
    }
}

function Ejecutar-PgBench {
    param(
        [string]$Db,
        [string]$ReadScript,
        [string]$UpdScript,
        [string]$InsScript,
        [int]$ReadWeight,
        [int]$UpdWeight,
        [int]$InsWeight,
        [string]$LogFilePrefix
    )
    $readPath = Join-Path $ROOT "pgbench\$ReadScript"
    $updPath  = Join-Path $ROOT "pgbench\$UpdScript"
    $insPath  = Join-Path $ROOT "pgbench\$InsScript"

    $pgbenchArgs = @(
        "-n",
        "-f", "${readPath}@${ReadWeight}",
        "-f", "${updPath}@${UpdWeight}",
        "-f", "${insPath}@${InsWeight}",
        "-c", "$CLIENTS",
        "-j", "$THREADS",
        "-T", "$DURATION",
        "-D", "nrows=1000000",
        "-l",
        "--log-prefix=$LogFilePrefix",
        $Db
    )

    $dir = Split-Path -Parent $LogFilePrefix
    $leaf = Split-Path -Leaf $LogFilePrefix
    $prefixPattern = '^' + [regex]::Escape($leaf) + '\.'
    Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match $prefixPattern } |
        Remove-Item -Force

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $salida = @(& $PGBENCH @pgbenchArgs 2>&1 | ForEach-Object { "$_" })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $detalle = $salida -join [Environment]::NewLine
        throw "pgbench failed (exit code ${exitCode}) for database '$Db'.`n$detalle"
    }
    return $salida
}

function Parsear-Tps {
    param([string[]]$Salida)
    $texto = $Salida -join [Environment]::NewLine
    $match = [regex]::Match($texto, '(?im)^\s*tps\s*=\s*([0-9]+(?:[.,][0-9]+)?)')
    if (-not $match.Success) {
        throw "Could not parse global TPS from pgbench output:`n$texto"
    }
    $numero = $match.Groups[1].Value.Replace(',', '.')
    return [double]::Parse($numero, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Parsear-Latencia {
    param([string[]]$Salida)
    $texto = $Salida -join [Environment]::NewLine
    $match = [regex]::Match($texto, '(?im)^\s*latency average\s*=\s*([0-9]+(?:[.,][0-9]+)?)')
    if (-not $match.Success) {
        throw "Could not parse average latency from pgbench output:`n$texto"
    }
    $numero = $match.Groups[1].Value.Replace(',', '.')
    return [double]::Parse($numero, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Calcular-Percentiles {
    param([string]$LogFilePrefix)
    $dir = Split-Path $LogFilePrefix -Parent
    $leaf = Split-Path $LogFilePrefix -Leaf
    $prefixPattern = '^' + [regex]::Escape($leaf) + '\.'
    $archivos = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Name -match $prefixPattern })
    if ($archivos.Count -eq 0) {
        throw "pgbench transaction logs were not found for prefix '$LogFilePrefix'."
    }

    $duraciones = New-Object 'System.Collections.Generic.List[long]'
    foreach ($archivo in $archivos) {
        foreach ($linea in Get-Content -LiteralPath $archivo.FullName) {
            $partes = $linea.Trim() -split '\s+'
            # pgbench 17 log fields: client, transaction, elapsed time (us),
            # script, completion epoch, timestamp fraction, optional schedule lag.
            if ($partes.Length -ge 6 -and $partes[0] -match '^\d+$' -and $partes[2] -match '^\d+$') {
                $duraciones.Add([long]$partes[2])
            }
        }
    }

    if ($duraciones.Count -eq 0) {
        throw "No valid transaction latency records found in pgbench logs for '$LogFilePrefix'."
    }
    [long[]]$ordenados = @($duraciones | Sort-Object)
    $n = $ordenados.Count
    $i95 = [math]::Max(0, [math]::Ceiling($n * 0.95) - 1)
    $i99 = [math]::Max(0, [math]::Ceiling($n * 0.99) - 1)
    $v95 = $ordenados[[math]::Min($i95, $n - 1)] / 1000
    $v99 = $ordenados[[math]::Min($i99, $n - 1)] / 1000
    @([math]::Round($v95, 2), [math]::Round($v99, 2))
}

function Formatear-NumeroCsv {
    param([double]$Valor)
    return $Valor.ToString("0.################", [System.Globalization.CultureInfo]::InvariantCulture)
}

# ---- Ejecucion principal ----
Crear-Plantillas

Write-Host ">> Iniciando benchmark automatizado" -ForegroundColor Cyan
Write-Host ">> Modelos: $($MODELS.Keys -join ', ')" -ForegroundColor Cyan
$ratioLabels = $RATIOS | ForEach-Object { $_.label }
Write-Host ">> Ratios: $($ratioLabels -join ', ')" -ForegroundColor Cyan
Write-Host ">> Repeticiones por combinacion: $REPS" -ForegroundColor Cyan
Write-Host ">> Duracion por corrida: $DURATION segundos" -ForegroundColor Cyan

# Header uses UTF-8 BOM; appended rows use UTF-8 without another BOM.
$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[System.IO.File]::WriteAllText($CSV, "modelo,ratio,repeticion,tps,latencia_promedio_ms,p95_ms,p99_ms,wal_bytes`r`n", $utf8Bom)

foreach ($modelKey in $MODELS.Keys) {
    $m = $MODELS[$modelKey]
    $db = $m.db
    $tpl = $m.template

    foreach ($ratio in $RATIOS) {
        for ($rep = 1; $rep -le $REPS; $rep++) {
            Write-Host ">>> Modelo $modelKey | Ratio $($ratio.label) | Repeticion $rep" -ForegroundColor Yellow

            # 1. Restaurar base limpia desde TEMPLATE
            Restaurar-Base -Db $db -Template $tpl

            # 2. WAL antes
            $walAntes = Obtener-WAL -Db $db

            # 3. Ejecutar pgbench
            $logFilePrefix = Join-Path $OUTDIR "pgbench_${modelKey}_$($ratio.fileLabel)_rep${rep}"
            $salida = Ejecutar-PgBench -Db $db `
                -ReadScript $m.read -UpdScript $m.upd -InsScript $m.ins `
                -ReadWeight $ratio.read -UpdWeight $ratio.upd -InsWeight $ratio.ins `
                -LogFilePrefix $logFilePrefix

            # 4. WAL despues
            $walDespues = Obtener-WAL -Db $db

            # 5. Diff de WAL
            $walBytes = Calcular-WAL-Diff -Db $db -Antes $walAntes -Despues $walDespues

            # 6. Parse TPS and average latency (global output lines)
            $tps = Parsear-Tps -Salida $salida
            $lat = Parsear-Latencia -Salida $salida

            # 7. Percentiles p95/p99 desde todos los archivos de log del prefijo
            $p95, $p99 = Calcular-Percentiles -LogFilePrefix $logFilePrefix

            # 8. Guardar fila en CSV (append con BOM solo en la primera escritura ya se hizo)
            $fila = "$modelKey,$($ratio.label),$rep,$(Formatear-NumeroCsv $tps),$(Formatear-NumeroCsv $lat),$(Formatear-NumeroCsv $p95),$(Formatear-NumeroCsv $p99),$walBytes`r`n"
            [System.IO.File]::AppendAllText($CSV, $fila, (New-Object System.Text.UTF8Encoding($false)))

            Write-Host "      TPS=$tps  LatProm=$lat ms  P95=$p95 ms  P99=$p99 ms  WAL=$walBytes bytes" -ForegroundColor Green
        }
    }
}

Write-Host ">> Listo. Resultados consolidados en: $CSV" -ForegroundColor Green
Write-Host ">> Logs en: $OUTDIR" -ForegroundColor Green