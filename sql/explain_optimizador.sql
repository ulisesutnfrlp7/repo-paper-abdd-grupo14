-- =============================================================================
-- explain_optimizador.sql  -  Diagnóstico del planificador (estimaciones vs reales)

-- Propósito:
--   Comparar, para cada modelo, las estimaciones de filas del optimizador
--   (rows= estimado en EXPLAIN) contra las filas reales (rows= actual en
--   EXPLAIN ANALYZE) en una consulta con filtro compuesto sobre atributo
--   dinámico (color + marca).
--
-- Qué hace:
--   Ejecuta EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE) sobre la misma consulta
--   en cada uno de los 4 modelos:
--     - MODELO A (EAV): dos JOINs sobre la tabla de atributos clave-valor.
--     - MODELO B1 (JSONB + GIN): operador @> sobre la columna JSONB.
--     - MODELO B2 (JSONB + B-tree): operadores ->> sobre columnas indexadas.
--     - MODELO C (UDT + DOMAIN): acceso a campos del tipo compuesto.
--
-- Por qué existe:
--   JSONB con el operador @> no tiene estadísticas por clave en pg_statistic,
--   por lo que el optimizador usa estimaciones genéricas que pueden desviarse
--   mucho de la realidad. Esto afecta planes de consulta y rendimiento en
--   consultas agregadas.
--
-- Qué buscar en la salida:
--   Comparar la línea "rows=" del plan (estimado) contra "Actual rows" (real).
--   Un desvío grande indica que el optimizador no tiene estadísticas precisas.
--
-- Uso:
--   psql -d <base_del_modelo> -f sql/explain_optimizador.sql -v nrows=1000000
--
-- =============================================================================
-- ============================================================================
-- explain_optimizador.sql
--
-- Compara estimaciones del planificador (rows= estimado) vs filas reales
-- (rows= actual) para cada modelo, en una consulta con filtro compuesto
-- sobre atributo dinámico.
--
-- Uso: psql -d <base_del_modelo> -f sql/explain_optimizador.sql -v nrows=1000000
-- ============================================================================

-- Valores constantes para que el planificador pueda estimar los filtros
-- y considerar los índices; random() sería VOLATILE y se evaluaría por fila.

-- ------------------------------------------------------------
-- MODELO A: EAV relacional (dos JOINs sobre tabla de atributos)
-- ------------------------------------------------------------
\echo '=== MODELO A: EAV ==='

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT count(*)
FROM producto_eav p
JOIN producto_atributo_eav a1 ON p.id = a1.producto_id
   AND a1.clave = 'color'
   AND a1.valor = 'rojo'
JOIN producto_atributo_eav a2 ON p.id = a2.producto_id
   AND a2.clave = 'marca'
   AND a2.valor = 'Marca_42';

-- ------------------------------------------------------------
-- MODELO B1: JSONB + GIN (operador @>, sin estadísticas por clave)
-- ------------------------------------------------------------
\echo '=== MODELO B1: JSONB + GIN ==='

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT count(*)
FROM producto_jsonb
WHERE attrs @> jsonb_build_object(
   'color', 'rojo',
   'marca', 'Marca_42'
   );

-- ------------------------------------------------------------
-- MODELO B2: JSONB + B-tree sobre expresiones
-- ------------------------------------------------------------
\echo '=== MODELO B2: JSONB + B-tree expresión ==='

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT count(*)
FROM producto_jsonb
WHERE attrs->>'color' = 'rojo'
   AND attrs->>'marca' = 'Marca_42';

-- ------------------------------------------------------------
-- MODELO C: UDT compuesto + dominios
-- ------------------------------------------------------------
\echo '=== MODELO C: UDT + DOMAIN ==='

EXPLAIN (ANALYZE, BUFFERS, COSTS, VERBOSE)
SELECT count(*)
FROM producto_udt
WHERE (especificaciones).color = 'rojo'
   AND (especificaciones).marca = 'Marca_42';