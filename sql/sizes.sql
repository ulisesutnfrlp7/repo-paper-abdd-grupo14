-- =============================================================================
-- sizes.sql  -  Huella física en disco (bytes crudos)

-- Propósito:
--   Medir el tamaño en disco de cada tabla del modelo: heap, TOAST, índices y
--   total. Los valores se devuelven en bytes crudos (sin pg_size_pretty) para
--   facilitar el graficado y el análisis cuantitativo del paper.
--
-- Qué hace:
--   Para cada tabla relnombre LIKE 'producto%' en el esquema public, devuelve:
--     - bytes_heap: tamaño del montón principal de la tabla.
--     - bytes_toast: tamaño de la tabla TOAST (valor grande fuera de línea).
--     - bytes_indices: tamaño de todos los índices de la tabla.
--     - bytes_total: suma total (pg_total_relation_size).
--     - filas_aprox: filas aproximadas según pg_class.reltuples.
--
-- Por qué existe:
--   Cuantificar el costo de almacenamiento de cada modelo. Los índices GIN
--   pueden ser significativamente más grandes que los B-tree, y TOAST entra en
--   juego cuando las tuplas superan aproximadamente 2 KB.
--
-- Uso:
--   psql -d <base> --csv -t -f sql/sizes.sql
--
-- Nota para el modelo EAV:
--   Este modelo tiene dos tablas (producto_eav y producto_atributo_eav); hay
--   que sumar los tamaños de ambas para comparar con los demás modelos.
--
-- =============================================================================
-- Huella física en bytes crudos: heap, TOAST e índices, sumando todas las tablas del modelo.
-- Salida CSV (usar con: psql --csv -f sizes.sql)
SELECT
    c.relname                                                        AS tabla,
    pg_relation_size(c.oid)                                          AS bytes_heap,
    COALESCE(pg_relation_size(NULLIF(c.reltoastrelid, 0)), 0)
      + COALESCE((SELECT sum(pg_relation_size(i.indexrelid))
                  FROM pg_index i WHERE i.indrelid = NULLIF(c.reltoastrelid, 0)), 0)
                                                                     AS bytes_toast,
    pg_indexes_size(c.oid)                                           AS bytes_indices,
    pg_total_relation_size(c.oid)                                    AS bytes_total,
    c.reltuples::bigint                                              AS filas_aprox
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'producto%'
ORDER BY c.relname;