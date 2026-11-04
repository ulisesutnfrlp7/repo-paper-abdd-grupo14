# =============================================================================
# load.sh  -  Carga de datos y medición de tamaños para el benchmark JSONB
#
# Propósito:
#   Crear 4 bases de datos (una por modelo) con EXACTAMENTE los mismos datos,
#   de modo que la comparación de rendimiento entre modelos sea válida.
#   Luego mide la huella física en disco de cada modelo (heap, TOAST, índices).
#
# Requisitos:
#   - psql en el PATH.
#   - Variables de entorno de libpq: PGHOST, PGPORT, PGUSER, PGPASSWORD.
#
# Uso:
#   NROWS=1000000 NATTS=5 ./scripts/load.sh
#
# Variables:
#   NROWS   Número de filas (productos) a generar. Default: 100000.
#   NATTS   Cantidad de atributos por producto (5 a 50). Default: 5.
#   OUT     Directorio de salida para el CSV de tamaños.
# =============================================================================
#!/usr/bin/env bash
# Conexión: variables estándar de libpq (PGHOST, PGPORT, PGUSER, PGPASSWORD).
# set -euo pipefail: falla ante cualquier error, variable no definida o comando fallido en tuberías.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
NROWS=${NROWS:-100000}
NATTS=${NATTS:-5}
OUT=${OUT:-$ROOT/results/n${NROWS}_a${NATTS}}
MODELS_BASE=${MODELS_BASE:-"eav jsonb_gin jsonb_btree udt"}
mkdir -p "$OUT"

if (( NATTS < 5 || NATTS > 50 )); then echo "NATTS debe estar entre 5 y 50" >&2; exit 1; fi

PSQL=(psql -X -q -v ON_ERROR_STOP=1 -v nrows="$NROWS" -v natts="$NATTS")
# Validar rango de atributos: mínimo 5 (los núcleo) y máximo 50 (para no generar
# documentos excesivamente grandes que distorsionarían el índice GIN).
echo "modelo,tabla,bytes_heap,bytes_toast,bytes_indices,bytes_total,filas_aprox" > "$OUT/sizes.csv"
# psql con variables pasadas al SQL (nrows y natts se usan en 00_src.sql).

for m in $MODELS_BASE; do
  case $m in
    eav)         f=10_model_eav.sql ;;
    jsonb_gin)   f=11_model_jsonb_gin.sql ;;
    jsonb_btree) f=12_model_jsonb_btree.sql ;;
    udt)         f=13_model_udt.sql ;;
    *) echo "modelo desconocido: $m" >&2; exit 1 ;;
  esac
  db=base_$m
  echo ">> Cargando $db  (nrows=$NROWS, natts=$NATTS)"
# 1. Crear base de datos limpia (drop si existe, luego create).
  "${PSQL[@]}" -d postgres -c "DROP DATABASE IF EXISTS $db WITH (FORCE)" -c "CREATE DATABASE $db"
  start=$(date +%s)
# 2. Cargar fuente única de datos (00_src.sql) + DDL del modelo específico.
#    00_src.sql crea la tabla 'src' con datos idénticos para todos los modelos
#    (usa setseed(0.42) para determinismo).
#    El archivo del modelo (10/11/12/13) crea la tabla destino y copia datos desde src.
  "${PSQL[@]}" -d "$db" \
# 3. Medir tamaño físico en disco y append al CSV.
#    sizes.sql devuelve bytes crudos (sin pg_size_pretty) para facilitar graficado.
      -c "SET maintenance_work_mem='512MB'" \
      -f "$ROOT/sql/00_src.sql" -f "$ROOT/sql/$f" \
      -c "CREATE SEQUENCE seq_sku_nuevo" -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
  echo "   carga: $(( $(date +%s) - start )) s"
  "${PSQL[@]}" -d "$db" --csv -t -f "$ROOT/sql/sizes.sql" | sed "s/^/$m,/" >> "$OUT/sizes.csv"
done
echo ">> Tamaños en $OUT/sizes.csv"