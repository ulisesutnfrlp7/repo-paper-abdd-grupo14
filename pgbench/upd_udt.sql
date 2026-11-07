-- =============================================================================
-- upd_udt.sql  -  Escritura UPDATE sobre MODELO C (UDT compuesto + DOMAIN)

-- Operación: UPDATE del campo color del tipo compuesto.
-- Filtro:    id = :id.
-- Variables: :id (1-:nrows), :color_idx (1-4).

-- Propósito:
--   Medir escritura en un tipo compuesto (UDT). Actualizar un campo del UDT
--   reescribe la tupla completa y actualiza los índices de expresión sobre
--   los campos del tipo compuesto.
--
-- Uso con pgbench:
--   pgbench -d base_udt -f pgbench/upd_udt.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
\set color_idx random(1, 4)
UPDATE producto_udt
SET especificaciones.color = (ARRAY['rojo','azul','verde','negro'])[:color_idx]
WHERE id = :id;