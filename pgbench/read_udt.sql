-- =============================================================================
-- read_udt.sql  -  Lectura selectiva sobre MODELO C (UDT compuesto + DOMAIN)

-- Operación: SELECT count(*) sobre campos del tipo compuesto.
-- Filtros:   color (baja cardinalidad) + marca (alta cardinalidad).
-- Variables: :color_idx (1-4), :marca_id (1-2000).

-- Propósito:
--   Medir lecturas sobre un tipo compuesto (UDT) con índices de expresión sobre
--   sus campos. Compara contra JSONB y EAV para evaluar el enfoque ORDBMS puro.
--
-- Uso con pgbench:
--   pgbench -d base_udt -f pgbench/read_udt.sql@<peso_lectura> ...
-- =============================================================================

\set color_idx random(1, 4)
\set marca_id random(1, 2000)
SELECT count(*)
FROM producto_udt
WHERE (especificaciones).color = (ARRAY['rojo','azul','verde','negro'])[:color_idx]
  AND (especificaciones).marca = 'Marca_' || :marca_id;