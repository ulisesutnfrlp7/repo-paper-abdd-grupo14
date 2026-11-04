-- =============================================================================
-- read_jsonb_btree.sql  -  Lectura selectiva sobre MODELO B2 (JSONB + B-tree expresión)

-- Operación: SELECT count(*) con operadores ->> sobre columnas indexadas por B-tree.
-- Filtros:   color (baja cardinalidad) + marca (alta cardinalidad).
-- Variables: :color_idx (1-4), :marca_id (1-2000).

-- Propósito:
--   Medir lecturas sobre JSONB usando índices B-tree de expresión. A diferencia
--   de GIN, estos índices permiten que ANALYZE recolecte estadísticas en
--   pg_statistic, mejorando las estimaciones del optimizador.
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_btree -f pgbench/read_jsonb_btree.sql@<peso_lectura> ...
-- =============================================================================

\set color_idx random(1, 4)
\set marca_id random(1, 2000)
SELECT count(*)
FROM producto_jsonb
WHERE attrs->>'color' = (ARRAY['rojo','azul','verde','negro'])[:color_idx]
  AND attrs->>'marca' = 'Marca_' || :marca_id;