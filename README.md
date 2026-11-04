# repo-paper-abdd-grupo14

Repositorio de soporte técnico para el paper:

> **"El Dilema de JSONB en SGBD Objeto-Relacionales: Flexibilidad de Esquema vs. Sobrecosto de Indexación (GIN) y Reconstrucción en Disco en PostgreSQL"**

Cátedra: Administración de Bases de Datos – UTN FRLP.

Este repositorio contiene los scripts DDL, el generador de datos sintéticos, los scripts de `pgbench`, el script de orquestación y las consultas de diagnóstico utilizadas para el benchmark cuantitativo del paper. Está pensado para linkearse en la sección **"Anexos"**.

---

## Estructura del repositorio

| Carpeta | Contenido |
|---------|-----------|
| `sql/` | Scripts DDL: fuente única de datos (`00_src.sql`), 4 modelos comparados (`10_model_eav.sql`, `11_model_jsonb_gin.sql`, `12_model_jsonb_btree.sql`, `13_model_udt.sql`), medición de tamaños (`sizes.sql`) y diagnóstico del optimizador (`explain_optimizador.sql`). |
| `pgbench/` | Scripts de lectura, escritura (`UPDATE`) e inserción (`INSERT`) para cada uno de los 4 modelos, con sintaxis válida para `pgbench`. |
| `script/` | `medir_resultados.ps1`: orquestación automática del benchmark en PowerShell (4 modelos × 5 ratios × N repeticiones). |
| `results/` | (Generado al correr) CSV y logs de las corridas de `pgbench`. |

---

## Modelos comparados

| Código | Modelo | Descripción |
|--------|--------|-------------|
| `eav` | Relacional normalizado (EAV) | Tabla maestro + tabla de atributos clave-valor. Línea base relacional clásica. |
| `jsonb_gin` | JSONB + índice GIN | Columna `JSONB` indexada con árbol invertido GIN (`jsonb_ops`). Modelo documental/híbrido. |
| `jsonb_btree` | JSONB + B-tree sobre expresiones | Misma columna `JSONB`, pero indexada con B-tree sobre `(attrs->>'color')` y `(attrs->>'marca')`. Variante intermedia para aislar el efecto de GIN. |
| `udt` | Objeto-relacional (UDT + DOMAIN) | Tipo compuesto `CREATE TYPE` + dominios `CREATE DOMAIN` con `CHECK`. Explora capacidades ORDBMS nativas de PostgreSQL. |

---

## Requisitos

- PostgreSQL 14 o superior (probado con 16.15).
- `psql` y `pgbench` disponibles en el PATH.
- Variables de entorno de libpq: `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`.

---

## Paso a paso rápido

1. **Cargar datos en cada modelo** (una sola vez):
   ```powershell
   psql -d postgres -c "DROP DATABASE IF EXISTS base_eav WITH (FORCE)"
   psql -d postgres -c "CREATE DATABASE base_eav"
   psql -d base_eav -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\10_model_eav.sql
   psql -d base_eav -c "CREATE SEQUENCE seq_sku_nuevo"
   psql -d base_eav -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
   ```
   Repetir para `base_jsonb_gin`, `base_jsonb_btree` y `base_udt` cambiando el archivo de modelo.

2. **Correr una prueba de pgbench** (ejemplo: JSONB+GIN, ratio 90/10, 60 segundos):
   ```powershell
   pgbench -d base_jsonb_gin `
       -f pgbench\read_jsonb_gin.sql@9 `
       -f pgbench\upd_jsonb_gin.sql@1 `
       -f pgbench\ins_jsonb_gin.sql@1 `
       -c 10 -j 2 -T 60 -D nrows=1000000 -l resultados.log
   ```

3. **Medir WAL** (antes y después de la corrida):
   ```powershell
   psql -d base_jsonb_gin -t -A -c "SELECT pg_current_wal_lsn();"
   psql -d base_jsonb_gin -t -A -c "SELECT pg_wal_lsn_diff('<despues>', '<antes>');"
   ```

4. **Medir tamaño en disco:**
   ```powershell
   psql -d base_jsonb_gin --csv -t -f sql\sizes.sql
   ```

5. **Diagnóstico del optimizador:**
   ```powershell
   psql -d base_jsonb_gin -f sql\explain_optimizador.sql -v nrows=1000000
   ```

6. **Orquestación completa** (opcional, automatiza todo lo anterior):
   ```powershell
   .\script\medir_resultados.ps1 -NROWS 1000000 -NATT5 5 -DURATION 60 -CLIENTS 10 -THREADS 2 -REPS 3
   ```

---

## Métricas recolectadas

- **TPS** y **latencia promedio** (salida estándar de `pgbench`).
- **Percentiles p95 y p99** (calculados desde el log generado con `-l`).
- **Bytes de WAL** generados durante cada corrida (`pg_wal_lsn_diff`).
- **Tamaño en disco** (heap + TOAST + índices, en bytes crudos).
- **Estimaciones del optimizador** vs filas reales (`EXPLAIN ANALYZE`).

