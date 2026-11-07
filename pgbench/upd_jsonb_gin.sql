-- =============================================================================
-- upd_jsonb_gin.sql  -  Escritura UPDATE sobre MODELO B1 (JSONB + índice GIN)

-- Operación: UPDATE del atributo 'color' dentro del documento JSONB con jsonb_set.
-- Filtro:    id = :id.
-- Variables: :id (1-:nrows), :color_idx (1-4).

-- Propósito:
--   Medir el costo de escritura en JSONB+GIN. Actualizar un campo del documento
--   obliga a reescribir el valor completo (TOAST si supera ~2 KB) y a mantener
--   el índice GIN (pending list, fastupdate, flush periódico).
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_gin -f pgbench/upd_jsonb_gin.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
\set color_idx random(1, 4)
UPDATE producto_jsonb
SET attrs = jsonb_set(
      attrs,
      '{color}',
      to_jsonb((ARRAY['rojo','azul','verde','negro'])[:color_idx]::text)
   )
WHERE id = :id;