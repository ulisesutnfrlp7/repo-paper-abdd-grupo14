-- =============================================================================
-- read_eav.sql  -  Lectura selectiva sobre MODELO A (EAV relacional)

-- Operación: SELECT count(*) con dos JOINs (búsqueda compuesta).
-- Filtros:   color (baja cardinalidad: 4 valores) + marca (alta cardinalidad: 2000 valores).
-- Variables: :color_idx (1-4), :marca_id (1-2000).

-- Propósito:
--   Medir el costo de consultar atributos dinámicos en un modelo relacional
--   normalizado, que requiere tantos JOINs como atributos se filtren.
--
-- Uso con pgbench:
--   pgbench -d base_eav -f pgbench/read_eav.sql@<peso_lectura> ...
-- =============================================================================

\set color_idx random(1, 4)
\set marca_id random(1, 2000)
SELECT count(*)
FROM producto_eav p
JOIN producto_atributo_eav a1 ON p.id = a1.producto_id
   AND a1.clave = 'color'
   AND a1.valor = (ARRAY['rojo','azul','verde','negro'])[:color_idx]
JOIN producto_atributo_eav a2 ON p.id = a2.producto_id
   AND a2.clave = 'marca'
   AND a2.valor = 'Marca_' || :marca_id;