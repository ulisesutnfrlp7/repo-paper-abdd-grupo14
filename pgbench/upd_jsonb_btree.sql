-- =============================================================================
-- upd_jsonb_btree.sql  -  Escritura UPDATE sobre MODELO B2 (JSONB + B-tree expresión)

-- Operación: UPDATE del atributo 'color' dentro del documento JSONB con jsonb_set.
-- Filtro:    id = :id.
-- Variables: :id (1-:nrows), :color_idx (1-4).

-- Propósito:
--   Medir escritura en JSONB con índices B-tree de expresión. Al actualizar
--   'color', también se debe actualizar el índice B-tree de expresión
--   (attrs->>'color'), pero sin el costo de la pending list de GIN.
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_btree -f pgbench/upd_jsonb_btree.sql@<peso_escritura> ...
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