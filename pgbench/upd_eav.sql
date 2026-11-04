-- =============================================================================
-- upd_eav.sql  -  Escritura UPDATE sobre MODELO A (EAV relacional)

-- Operación: UPDATE del valor del atributo 'color' en producto_atributo_eav.
-- Filtro:    producto_id = :id AND clave = 'color'.
-- Variables: :id (1-:nrows), :color_idx (1-4).

-- Propósito:
--   Medir el costo de actualizar un solo atributo en el modelo EAV, que requiere
--   localizar la fila por (producto_id, clave) y modificar el valor.
--
-- Uso con pgbench:
--   pgbench -d base_eav -f pgbench/upd_eav.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
\set color_idx random(1, 4)
UPDATE producto_atributo_eav
SET valor = (ARRAY['rojo','azul','verde','negro'])[:color_idx]
WHERE producto_id = :id
  AND clave = 'color';