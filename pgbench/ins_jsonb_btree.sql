-- =============================================================================
-- ins_jsonb_btree.sql  -  Escritura INSERT sobre MODELO B2 (JSONB + B-tree expresión)

-- Operación: INSERT de un producto nuevo en producto_jsonb.
-- Filtro:    selecciona un producto existente por :id para copiar precio y attrs.
-- Variables: :id (1-:nrows).

-- Propósito:
--   Medir el costo de inserción en JSONB con índices B-tree de expresión, que
--   incluye actualizar los dos índices B-tree (color y marca) sin el costo de
--   la pending list de GIN.
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_btree -f pgbench/ins_jsonb_btree.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
INSERT INTO producto_jsonb (nombre, precio, sku, attrs)
SELECT 'Nuevo_' || s.n, p.precio, 'SKU-NEW-' || s.n, p.attrs
FROM producto_jsonb p, LATERAL (SELECT nextval('seq_sku_nuevo') AS n) s
WHERE p.id = :id;