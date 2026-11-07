-- =============================================================================
-- read_jsonb_gin.sql  -  Lectura selectiva sobre MODELO B1 (JSONB + índice GIN)

-- Operación: SELECT count(*) con operador @> sobre columna JSONB.
-- Filtros:   color (baja cardinalidad) + marca (alta cardinalidad).
-- Variables: :color_idx (1-4), :marca_id (1-2000).

-- Propósito:
--   Medir el rendimiento de lecturas sobre JSONB usando índice GIN. El operador
--   @> no tiene estadísticas por clave, por lo que el optimizador usa estimaciones
--   genéricas.
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_gin -f pgbench/read_jsonb_gin.sql@<peso_lectura> ...
-- =============================================================================
-- Lectura selectiva sobre MODELO B1 (JSONB + índice GIN)
-- Filtro compuesto con operador @> (sin estadísticas por clave en GIN)

\set color_idx random(1, 4)
\set marca_id random(1, 2000)
SELECT count(*)
FROM producto_jsonb
WHERE attrs @> jsonb_build_object(
      'color', (ARRAY['rojo','azul','verde','negro'])[:color_idx],
      'marca', 'Marca_' || :marca_id
);