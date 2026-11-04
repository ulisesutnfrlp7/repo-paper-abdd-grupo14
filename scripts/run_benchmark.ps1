#!/usr/bin/env pwsh
# =============================================================================
# run_benchmark.ps1  -  Orquestación del benchmark JSONB vs Relacional
#
# Requisitos:
#   - psql y pgbench en el PATH (instalación de PostgreSQL)
#   - Variables de entorno de libpq: PGHOST, PGPORT, PGUSER, PGPASSWORD
#   - Las bases deben estar ya cargadas (el script las crea y carga acá)
#
# Uso ejemplo (PowerShell):
#   $env:PGUSER='postgres'; $env:PGPASSWORD='tu_password'
#   .\scripts\run_benchmark.ps1 -NROWS 1000000 -NATT5 5 -DURATION 60 -CLIENTS 10 -THREADS 2 -REPS 3
# =============================================================================
param(
    [int]$NROWS   = 1000000,
    [int]$NATT5   = 5,
    [int]$DURATION= 60,
    [int]$CLIENTS = 10,
    [int]$THREADS = 2,
    [int]$REPS    = 3,
    [string]$ROOT = (Resolve-Path "..").Path
)

# $ErrorActionPreference = "Stop": detiene el script ante el primer error.
$ErrorActionPreference = "Stop"

$PSQL   = @("psql", "-X", "-q", "-v", "ON_ERROR_STOP=1", "-v", "nrows=$NROWS", "-v", "natts=$NATT5")
# PSQL: array de argumentos comunes para psql (modo silencioso, detener ante error, pasar nrows y natts).
# PGBENCH: array de argumentos comunes para pgbench (pasar nrows como variable -D).
$PGBENCH= @("pgbench", "-v", "ON_ERROR_STOP=1", "-D", "nrows=$NROWS")
# Directorio de salida: results/n<NROWS>_a<NATTS> (por ejemplo results/n1000000_a5).

$OUTDIR = Join-Path $ROOT ("results/n${NROWS}_a${NATT5}")
# MODELS: los cuatro modelos a benchmarkear.
# SCRIPT_MAP: asigna a cada modelo sus tres scripts de pgbench (lectura, update, insert).
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$CSV      = Join-Path $OUTDIR "resultados.csv"
$MODELS   = @("eav","jsonb_gin","jsonb_btree","udt")
$SCRIPT_MAP = @{
# RATIOS: mezclas lectura/escritura a probar. El formato es (lecturas : escrituras).
#   90/10 = 9 lecturas por cada escritura, etc.
# pgbench interpreta el peso como frecuencia relativa de selección de cada script.
    eav         = @{ read="read_eav.sql";         upd="upd_eav.sql";         ins="ins_eav.sql" }
    jsonb_gin   = @{ read="read_jsonb_gin.sql";   upd="upd_jsonb_gin.sql";   ins="ins_jsonb_gin.sql" }
    jsonb_btree = @{ read="read_jsonb_btree.sql"; upd="upd_jsonb_btree.sql"; ins="ins_jsonb_btree.sql" }
    udt         = @{ read="read_udt.sql";         upd="upd_udt.sql";         ins="ins_udt.sql" }
}

# Ratios lectura/escritura (lecturas : escrituras)
$RATIOS = @(
    @{ read=9; write=1; label="90/10" },
################################################################################
# Función Ejecutar-PgBench
#
# Ejecuta pgbench contra una base de datos con una mezcla de scripts de lectura,
# UPDATE e INSERT, ponderados por los pesos recibidos. Genera un log por transacción
# (-l) para poder calcular percentiles p95/p99 después.
#
# Parámetros:
#   Db         - nombre de la base de datos destino
#   ReadScript - script SQL de lectura (con su peso @ReadWeight)
#   UpdScript  - script SQL de UPDATE (con su peso @WriteWeight)
#   InsScript  - script SQL de INSERT (con su peso @WriteWeight)
#   ReadWeight - peso de lecturas en la mezcla (ej: 9 para 90%)
#   WriteWeight- peso de escrituras en la mezcla (ej: 1 para 10%)
#   LogFile    - ruta al archivo de log por transacción de pgbench
################################################################################
    @{ read=7; write=3; label="70/30" },
    @{ read=5; write=5; label="50/50" },
    @{ read=3; write=7; label="30/70" },
    @{ read=1; write=9; label="10/90" }
)

# Cabecera CSV
################################################################################
# Función Obtener-WAL
#
# Devuelve el LSN actual de WAL (Write-Ahead Log) de la base de datos.
# Se llama antes y después de cada corrida de pgbench para medir cuántos bytes
################################################################################
# Función Calcular-Percentiles
#
# Lee el archivo de log generado por pgbench (-l) y extrae la latencia de cada
# transacción (tercer columna, en microsegundos). Calcula los percentiles p95 y p99
# y los convierte a milisegundos.
#
# Estos percentiles son importantes porque capturan picos de latencia causados por
# el flush de la pending list de GIN, que el promedio de TPS por sí solo oculta.
################################################################################
# de WAL se generaron durante la prueba (mediante pg_wal_lsn_diff).
################################################################################
"modelo,ratio,repeticion,tps,latencia_promedio_ms,latencia_p95_ms,latencia_p99_ms,wal_bytes" | Out-File -FilePath $CSV -Encoding utf8

function Ejecutar-PgBench {
    param(
# Fase 1: Crear y cargar las 4 bases de datos con datos idénticos (misma semilla).
# Esto se hace una sola vez al inicio del script.
        [string]$Db,
        [string]$ReadScript,
        [string]$UpdScript,
        [string]$InsScript,
        [int]$ReadWeight,
        [int]$WriteWeight,
        [string]$LogFile
    )
    $args = @(
        "-d", $Db,
        "-f", (Join-Path $ROOT "pgbench\$ReadScript") + "@$ReadWeight",
        "-f", (Join-Path $ROOT "pgbench\$UpdScript")   + "@$WriteWeight",
        "-f", (Join-Path $ROOT "pgbench\$InsScript")   + "@$WriteWeight",
        "-c", $CLIENTS,
        "-j", $THREADS,
# Fase 2: Ejecutar el benchmark para cada combinación (modelo × ratio × repetición).
# Entre cada corrida se ejecuta VACUUM ANALYZE + CHECKPOINT para dejar la base
# en un estado consistente y no acumular bloat entre corridas.
        "-T", $DURATION,
        "-l", $LogFile
    )
    & $PGBENCH @args
}

function Obtener-WAL {
    param([string]$Db)
    & $PSQL -d $Db -t -A -c "SELECT pg_current_wal_lsn();"
}

function Calcular-Percentiles {
    param([string]$LogFile)
    if (!(Test-Path $LogFile)) { return @(0,0) }
    $duraciones = Get-Content $LogFile | Where-Object { $_ -match '^\d+\s+' } | ForEach-Object {
        $partes = $_ -split '\s+'
        if ($partes.Length -ge 3) { [int]$partes[2] }
    } | Where-Object { $_ -gt 0 }
    if ($duraciones.Count -eq 0) { return @(0,0) }
    $ordenados = $duraciones | Sort-Object
    $p95 = [math]::Floor($ordenados.Count * 0.95)
    $p99 = [math]::Floor($ordenados.Count * 0.99)
    $v95 = if ($p95 -lt 1) { $ordenados[0] } else { $ordenados[[math]::Min($p95-1, $ordenados.Count-1)] }
    $v99 = if ($p99 -lt 1) { $ordenados[0] } else { $ordenados[[math]::Min($p99-1, $ordenados.Count-1)] }
    @([math]::Round($v95/1000, 2), [math]::Round($v99/1000, 2))
}

Write-Host ">> Preparando bases de datos (nrows=$NROWS, natts=$NATT5)" -ForegroundColor Cyan

foreach ($m in $MODELS) {
    $db = "base_$m"
    Write-Host "   Creando/cargando $db ..."
    & $PSQL -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" | Out-Null
    & $PSQL -d postgres -c "CREATE DATABASE $db" | Out-Null
    $archivoModelo = switch ($m) {
        "eav"         { "10_model_eav.sql" }
        "jsonb_gin"   { "11_model_jsonb_gin.sql" }
        "jsonb_btree" { "12_model_jsonb_btree.sql" }
        "udt"         { "13_model_udt.sql" }
    }
    & $PSQL -d $db -c "SET maintenance_work_mem='512MB'" -f (Join-Path $ROOT "sql\00_src.sql") -f (Join-Path $ROOT ("sql\$archivoModelo")) -c "CREATE SEQUENCE seq_sku_nuevo" -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT" | Out-Null
}
Write-Host ">> Bases listas." -ForegroundColor Green

foreach ($ratio in $RATIOS) {
    $label = $ratio.label
    Write-Host ">>> Ratio $label (lectura $($ratio.read) / escritura $($ratio.write))" -ForegroundColor Yellow

    foreach ($m in $MODELS) {
        $db = "base_$m"
        $s  = $SCRIPT_MAP[$m]
        $mapRead    = $s.read
        $mapUpd     = $s.upd
        $mapIns     = $s.ins

        for ($rep = 1; $rep -le $REPS; $rep++) {
            Write-Host "      Modelo $m, repeticion $rep ..."

            & $PSQL -d $db -c "VACUUM (ANALYZE)" -c "CHECKPOINT" | Out-Null

            $wal_before = Obtener-WAL -Db $db

            $logFile = Join-Path $OUTDIR "pgbench_${m}_${label}_rep${rep}.log"
            $salida = Ejecutar-PgBench -Db $db -ReadScript $mapRead -UpdScript $mapUpd -InsScript $mapIns `
                -ReadWeight $ratio.read -WriteWeight $ratio.write -LogFile $logFile 2>&1

            $wal_after = Obtener-WAL -Db $db

            $wal_bytes = 0
            try {
                $wal_bytes = & $PSQL -d $db -t -A -c "SELECT pg_wal_lsn_diff('$wal_after', '$wal_before');" | Out-String | Trim
                if ([string]::IsNullOrWhiteSpace($wal_bytes)) { $wal_bytes = 0 }
            } catch { $wal_bytes = 0 }

            $tps = 0; $lat_prom = 0
            $lineaTPS = $salida | Where-Object { $_ -match "tps\s*=\s*" }
            if ($lineaTPS) {
                $tps = ($lineaTPS -replace '[^\d\.]', '') -as [double]
            }
            $lineaLat = $salida | Where-Object { $_ -match "latency\s*=\s*" }
            if ($lineaLat) {
                $lat_prom = ($lineaLat -replace '[^\d\.]', '') -as [double]
            }

            $p95, $p99 = Calcular-Percentiles -LogFile $logFile

            $fila = "$m,$label,$rep,$tps,$lat_prom,$p95,$p99,$wal_bytes"
            $fila | Out-File -FilePath $CSV -Append -Encoding utf8
            Write-Host "         TPS=$tps  LatProm=$lat_prom ms  P95=$p95 ms  P99=$p99 ms  WAL=$wal_bytes bytes"
        }
    }
}

Write-Host ">> Listo. Resultados en: $CSV" -ForegroundColor Green