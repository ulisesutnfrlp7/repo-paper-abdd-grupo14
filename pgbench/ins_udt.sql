-- =============================================================================
-- ins_udt.sql  -  Escritura INSERT sobre MODELO C (UDT compuesto + DOMAIN)

-- Operación: INSERT de un producto nuevo en producto_udt.
-- Filtro:    selecciona un producto existente por :id para copiar precio y especificaciones.
-- Variables: :id (1-:nrows).

-- Propósito:
--   Medir el costo de inserción en un tipo compuesto (UDT), que incluye escribir
--   la tupla con el tipo estructurado y actualizar los índices de expresión.
--
-- Uso con pgbench:
--   pgbench -d base_udt -f pgbench/ins_udt.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
INSERT INTO producto_udt (nombre, precio, sku, especificaciones)
SELECT 'Nuevo_' || s.n, p.precio, 'SKU-NEW-' || s.n, p.especificaciones
FROM producto_udt p, LATERAL (SELECT nextval('seq_sku_nuevo') AS n) s
WHERE p.id = :id;