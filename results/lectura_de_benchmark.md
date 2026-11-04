## ¿Qué significa cada campo?

* TPS: cuántas operaciones por segundo completó la base. Acá una “transacción” es una sola operación (una búsqueda, un UPDATE o un INSERT). Más alto es mejor.

* LatProm: cuánto tardó en promedio cada operación, en milisegundos. Más bajo es mejor. Con 10 clientes en paralelo incluye esperas por la competencia entre ellos.

* P95 / P99: el 95% (o 99%) de las operaciones tardó menos que ese valor. Muestran los “malos ratos” (picos por disco, checkpoints, vaciado del GIN) que el promedio esconde.

* WAL: el WAL es el diario donde PostgreSQL anota cada cambio antes de aplicarlo, para no perder datos si se cae. wal_bytes es cuánto diario se escribió durante la corrida. Más WAL significa más escritura a disco y más peso para backups y réplicas. Cada índice que hay que actualizar agrega WAL.

* Ratios (90/10, etc.): de cada 100 operaciones, cuántas son lecturas y cuántas escrituras (mitad UPDATE, mitad INSERT). 90/10 es un catálogo que se consulta mucho. 10/90 es un sistema que ingesta datos todo el tiempo. Se prueban varios para ver dónde cambia el ganador.

* Repeticiones: cada corrida tiene ruido (caché, Windows, procesos de fondo). Repetir y promediar, con el desvío, te dice cuánto confiar en el número. Con una sola corrida podés tener un resultado “con suerte”.

## ¿Por qué aparecen dos archivos por corrida?

Es normal: el comando se ejecutó con `-THREADS 2`, que el script pasa a pgbench como `-j 2`. Con `-l`, pgbench escribe un archivo de log por **hilo trabajador**, no por cliente. Los 10 clientes se reparten entre esos dos hilos.

Por eso, para una corrida con prefijo `pgbench_eav_10_90_rep1`, aparecen nombres como:

- `pgbench_eav_10_90_rep1.15440`: el archivo del primer hilo; `15440` es el PID del proceso.
- `pgbench_eav_10_90_rep1.15440.1`: el archivo del segundo hilo; `.1` identifica al hilo adicional.

No son dos corridas ni copias. Si usáramos un hilo habría un archivo por corrida; con cuatro hilos, normalmente cuatro. La [documentación de pgbench](https://www.postgresql.org/docs/current/pgbench.html#PGBENCH-LOGGING) describe este formato.

El script lee **los dos logs** de cada corrida y combina las latencias de sus transacciones para calcular p95 y p99. Así, con 4 modelos × 5 ratios × 3 repeticiones tienes **60 corridas y 120 logs**; el CSV consolidado tiene **60 filas**, una por corrida. La configuración de logs y el cálculo de percentiles están en medir_resultados.ps1.

## Qué dicen los resultados

La salida confirma que se completaron las 60 combinaciones y que se generó benchmark_resultados.csv. Cada ejecución mide 60 segundos, así que hay una hora de benchmark efectivo, además del tiempo de restauración y preparación de las bases.

Los ratios son lecturas/escrituras. Por ejemplo, `90/10` usa pesos de 90 para lectura, 5 para `UPDATE` y 5 para `INSERT`; `10/90` usa 10, 45 y 45. En cada transacción, pgbench selecciona uno de esos scripts según sus pesos: no ejecuta lectura, actualización e inserción juntas. Esa distribución está definida en medir_resultados.ps1.

En criollo:

- **UDT lidera el TPS** en todos los ratios. Por ejemplo, en 90/10 promedia aproximadamente 3.848 TPS y en 10/90, 4.685.
- **JSONB con B-tree queda segundo**: cerca de 685 TPS en 90/10 y 3.023 en 10/90.
- **JSONB con GIN y EAV quedan más abajo** en TPS en estas pruebas.
- El TPS aumenta al crecer la proporción de escrituras. **No significa que escribir sea necesariamente más rápido**: la lectura de este benchmark hace un `COUNT` con filtros (y en EAV, varios `JOIN`), mientras que cada escritura ejecuta otra operación. Estamos midiendo el rendimiento de distintas mezclas, no operaciones de igual costo. Los scripts de lectura muestran esas diferencias: EAV, JSONB+GIN, JSONB+B-tree y UDT.
- El WAL total generalmente sube al aumentar las escrituras. Pero los bytes de WAL de una corrida dependen también de cuántas transacciones completó: comparar solo el total puede ser engañoso. Para comparar, mirar primero el mismo ratio y, si se puede, calcular también una aproximación de WAL por transacción: `wal_bytes / (tps * 60)`.
- Hay algunas corridas más variables. En EAV 50/50, la repetición 1 tiene p95 de 168 ms y p99 de 267,84 ms, frente a valores bastante menores en las otras dos. También UDT 50/50 rep1 se aparta de las otras. Conviene mostrar dispersión (barras de error) y, si el tiempo da, repetir esos casos.