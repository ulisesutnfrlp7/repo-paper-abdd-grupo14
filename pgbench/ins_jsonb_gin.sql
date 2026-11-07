-- =============================================================================
-- ins_jsonb_gin.sql  -  Escritura INSERT sobre MODELO B1 (JSONB + índice GIN)

-- Operación: INSERT de un producto nuevo en producto_jsonb.
-- Filtro:    selecciona un producto existente por :id para copiar precio y attrs.
-- Variables: :id (1-:nrows).

-- Propósito:
--   Medir el costo de inserción en JSONB+GIN, que incluye escribir el documento
--   JSONB y actualizar el índice invertido GIN (pending list).
--
-- Uso con pgbench:
--   pgbench -d base_jsonb_gin -f pgbench/ins_jsonb_gin.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
INSERT INTO producto_jsonb (nombre, precio, sku, attrs)
SELECT 'Nuevo_' || s.n, p.precio, 'SKU-NEW-' || s.n, p.attrs
FROM producto_jsonb p, LATERAL (SELECT nextval('seq_sku_nuevo') AS n) s
WHERE p.id = :id;