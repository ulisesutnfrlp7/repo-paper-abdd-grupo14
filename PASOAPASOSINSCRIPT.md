# Plan: Estructura de capturas para el paper y paso a paso.

## 1. ¿Qué capturas (figuras) van a ir en el paper?

Un paper de benchmark académico necesita mostrar **evidencia reproducible**. A partir de la estructura del paper MPI/OpenMP y de tu hipótesis (punto de quiebre), estas son las capturas que se deberían tomar y en qué orden:

| Figura / Tabla | Qué se muestra | Comando que la genera | Cuándo en la ejecución |
|---|---|---|---|
| **Fig. 1** Entorno de prueba | Versión de PostgreSQL, CPU, RAM, SO | `SELECT version();` + info del sistema | Paso 1 (setup) |
| **Fig. 2** Creación de esquemas | Salida de `psql` ejecutando los DDL de un modelo | `\dt` o mensajes `CREATE TABLE` | Paso 4 (DDL) |
| **Fig. 3** Verificación de datos idénticos | `COUNT(*)` en las 4 bases (debe dar lo mismo) | `SELECT count(*) FROM producto_eav;` etc. | Paso 6 (verificación) |
| **Fig. 4** Ejecución de pgbench (ejemplo) | Output de terminal con TPS, latencia promedio | `pgbench -d base_... -f ... -c 10 -j 2 -T 60` | Paso 7 (piloto) |
| **Fig. 5** Medición de WAL | `pg_current_wal_lsn()` antes y después + `pg_wal_lsn_diff()` | SQL de WAL | Paso 8 (WAL) |
| **Fig. 6** Tamaño en disco | Output de `sizes.sql` (bytes heap, toast, índices, total) | `psql --csv -f sql/sizes.sql` | Paso 9 (tamaños) |
| **Fig. 7** EXPLAIN ANALYZE | Plan de ejecución mostrando `rows=` estimado vs `Actual rows` | `psql -f sql/explain_optimizador.sql` | Paso 10 (optimizador) |
| **Tabla 1** Resultados consolidados | CSV con TPS, p95, p99, WAL bytes por modelo/ratio | `results/n1000000_a5/resultados.csv` | Paso 11 (compilación) |
| **Gráfico 1** | TPS vs % escrituras (4 modelos, 5 ratios) | Generado en Excel/Python desde el CSV | Post-ejecución |
| **Gráfico 2** | Comparativa de tamaños en disco (barra por modelo) | Desde `sizes.sql` | Post-ejecución |
| **Gráfico 3** | WAL generado por corrida (barra por modelo) | Desde resultados WAL | Post-ejecución |

> **Regla de oro:** cada figura debe tener su número, título al pie y una frase en el texto que la refiera (ej: "Como se observa en la Figura 4, el modelo JSONB+GIN alcanza X TPS con 90% lecturas").

---

## 2. Paso a paso (ejecución manual)

Se asume el hecho de tener PostgreSQL instalado y saber abrir una terminal PowerShell.

### Paso 0: Abrir terminal y ubicarse en el repo

```powershell
cd C:\Users\tauma\OneDrive\Escritorio\repo-adbb-paper\repo-paper-abdd-grupo14
```

### Paso 1: Verificar PostgreSQL y configurar conexión

```powershell
psql --version
pgbench --version
```

Configurar las variables de conexión (reemplazar `tu_password`):

```powershell
$env:PGHOST="localhost"
$env:PGPORT="5432"
$env:PGUSER="postgres"
$env:PGPASSWORD="tu_password"
```

### Paso 2: Crear y cargar cada modelo (hacer 4 veces, una por modelo)

Hay que hacer esto para cada uno: `eav`, `jsonb_gin`, `jsonb_btree`, `udt`.

**Ejemplo para EAV:**

```powershell
# Crear base de datos
psql -d postgres -c "DROP DATABASE IF EXISTS base_eav WITH (FORCE)"
psql -d postgres -c "CREATE DATABASE base_eav"

# Cargar fuente de datos + DDL del modelo (1.000.000 filas, 5 atributos)
psql -d base_eav -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\10_model_eav.sql

# Crear secuencia para SKUs únicos (necesaria para los INSERT de pgbench)
psql -d base_eav -c "CREATE SEQUENCE seq_sku_nuevo"

# Limpiar tabla intermedia y dejar estadísticas actualizadas
psql -d base_eav -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

**Repetir para los otros 3 modelos**, cambiando solo el nombre de la base y el archivo DDL:
- `base_jsonb_gin` → `sql\11_model_jsonb_gin.sql`
- `base_jsonb_btree` → `sql\12_model_jsonb_btree.sql`
- `base_udt` → `sql\13_model_udt.sql`

### Paso 3: Verificar que los 4 modelos tienen los mismos datos

En cada base, ejecutar:

```powershell
psql -d base_eav -c "SELECT count(*) FROM producto_eav;"
psql -d base_jsonb_gin -c "SELECT count(*) FROM producto_jsonb;"
psql -d base_jsonb_btree -c "SELECT count(*) FROM producto_jsonb;"
psql -d base_udt -c "SELECT count(*) FROM producto_udt;"
```

Los 4 deben devolver el mismo número (1.000.000). **Tomá captura de esto** para la Figura 3.

### Paso 4: Ejecutar pgbench (una corrida piloto de prueba)

Probar una combinación corta antes de hacer todo el benchmark. Ejemplo: JSONB+GIN, 90% lecturas / 10% escrituras, 60 segundos:

```powershell
pgbench -d base_jsonb_gin `
    -f pgbench\read_jsonb_gin.sql@9 `
    -f pgbench\upd_jsonb_gin.sql@1 `
    -f pgbench\ins_jsonb_gin.sql@1 `
    -c 10 -j 2 -T 60 -D nrows=1000000 -l resultados_piloto.log
```

**Tomar captura del output** que termina con algo como:

```
number of transactions actually processed: XXXXX
latency average = XX ms
tps = XX.XXXXXX
```

### Paso 5: Medir WAL generado (antes y después de una corrida)

Antes de correr pgbench:

```powershell
psql -d base_jsonb_gin -t -A -c "SELECT pg_current_wal_lsn();"
```

Guardar ese valor (ejemplo: `16/A3B4C5D0`).

Después de correr pgbench:

```powershell
psql -d base_jsonb_gin -t -A -c "SELECT pg_wal_lsn_diff('16/XXXXXXXX', '16/A3B4C5D0');"
```

**Tomar captura de ambos valores y el resultado.** Esa es la Figura 5.

### Paso 6: Medir tamaño en disco

```powershell
psql -d base_jsonb_gin --csv -t -f sql\sizes.sql
```

Repetir para cada modelo. **Tomar captura de cada output.** Esa es la Figura 6.

Para EAV, recordar sumar las dos tablas (`producto_eav` + `producto_atributo_eav`).

### Paso 7: Diagnosticar el optimizador (EXPLAIN ANALYZE)

```powershell
psql -d base_jsonb_gin -f sql\explain_optimizador.sql -v nrows=1000000
```

Repetir en cada base. **Tomar captura de la salida**, especialmente donde dice:

```
rows= XXXX (estimado)   vs   Actual rows= XXXX (real)
```

Esa es la Figura 7 y sustenta el argumento del paper sobre las estadísticas pobres de JSONB.

### Paso 8: Ejecutar todas las combinaciones (el benchmark completo)

Tenenmos 4 modelos × 5 ratios × 3 repeticiones = 60 corridas mínimas.

Los ratios son:
- 90/10 (9 lecturas : 1 escritura)
- 70/30
- 50/50
- 30/70
- 10/90

Ejemplo para EAV, ratio 50/50:

```powershell
pgbench -d base_eav `
    -f pgbench\read_eav.sql@5 `
    -f pgbench\upd_eav.sql@5 `
    -f pgbench\ins_eav.sql@5 `
    -c 10 -j 2 -T 60 -D nrows=1000000 -l resultados_eav_5050_rep1.log
```

Entre cada corrida, limpiar la base:

```powershell
psql -d base_eav -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

### Paso 9: Compilar los resultados

Crear un CSV manualmente o usá el script `script\medir_resultados.ps1` que automatiza esto:

```powershell
.\script\medir_resultados.ps1 -NROWS 1000000 -NATT5 5 -DURATION 60 -CLIENTS 10 -THREADS 2 -REPS 3
```

El resultado queda en `results\n1000000_a5\resultados.csv`.

---

## 3. Revisión de sintaxis y contenido de los archivos

### ✅ Archivos que están bien

| Archivo | Estado | Comentario |
|---------|--------|------------|
| `sql\00_src.sql` | OK | Fuente única determinística con `setseed(0.42)`. Usa `format()` + `\gexec`, válido en psql. |
| `sql\10_model_eav.sql` | OK | DDL EAV correcto, `setval` al final para secuencia. |
| `sql\11_model_jsonb_gin.sql` | OK | JSONB + índice GIN por defecto. |
| `sql\12_model_jsonb_btree.sql` | OK | JSONB + B-tree sobre expresiones. |
| `sql\13_model_udt.sql` | OK | UDT compuesto + dominios con `CHECK`. |
| `sql\sizes.sql` | OK | Devuelve bytes crudos (no usa `pg_size_pretty`). |
| `sql\explain_optimizador.sql` | OK | `EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)` para los 4 modelos. |
| `pgbench\read_*.sql` | OK | Sintaxis válida para pgbench (`\set`, `:variable`). |
| `pgbench\upd_*.sql` | OK | Sintaxis válida. |
| `pgbench\ins_*.sql` | OK | Sintaxis válida, usa `seq_sku_nuevo`. |
| `script\medir_resultados.ps1` | OK | PowerShell, válido para Windows. |

### ⚠️ Archivos con advertencias

| Archivo | Advertencia |
|---------|-------------|
| `script\medir_resultados.ps1` | Requiere que las políticas de ejecución de PowerShell permitan scripts. Si falla, ejecutar: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Todos los `pgbench\*.sql` | Requieren que se pase `-D nrows=1000000` en pgbench, de lo contrario `:nrows` no está definido y falla. |
| Todos los `ins_*.sql` | Requieren que exista la secuencia `seq_sku_nuevo` en la base (se crea en el Paso 2). |

### 🔍 Cosas a verificar antes de lanzar el benchmark completo

1. **Que las 4 bases existan** y tengan el mismo número de filas.
2. **Que la secuencia `seq_sku_nuevo` exista** en cada base (si no, los `ins_*.sql` fallan).
3. **Que `pgbench` esté en el PATH** de Windows.
4. **Que tengamos suficiente espacio en disco** (1M filas con 5 atributos en 4 modelos + índices GIN pueden ocupar varios GB).
5. **Que no haya otras aplicaciones consumiendo CPU/RAM** durante las corridas de pgbench (el benchmark es sensible a ruido).

---

## 4. ¿Qué sigue?

Cuando hayas ejecutado el paso a paso y tengas las capturas y el CSV, podemos:

1. Pegar las figuras en el paper (sección Metodología y Resultados).
2. Generar los 3 gráficos (TPS vs escrituras, tamaños, WAL) a partir del CSV.
3. Escribir la Discusión definiendo el **punto de quiebre** (el ratio de escrituras donde JSONB deja de ser rentable).
4. Linkear este repositorio en la sección Anexos del paper.

---

