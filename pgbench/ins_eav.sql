-- =============================================================================
-- ins_eav.sql  -  Escritura INSERT sobre MODELO A (EAV relacional)

-- Operación: INSERT de un producto nuevo en las dos tablas (maestro + atributos).
-- Filtro:    selecciona un producto existente por :id para copiar precio y sku.
-- Variables: :id (1-:nrows).

-- Propósito:
--   Medir el costo de inserción en EAV, que requiere escribir en dos tablas
--   (producto_eav + producto_atributo_eav) por cada producto nuevo.
--
-- Uso con pgbench:
--   pgbench -d base_eav -f pgbench/ins_eav.sql@<peso_escritura> ...
-- =============================================================================

\set id random(1, :nrows)
WITH new_prod AS (
    INSERT INTO producto_eav (nombre, precio, sku)
    SELECT 'Nuevo_' || s.n, p.precio, 'SKU-NEW-' || s.n
    FROM producto_eav p, LATERAL (SELECT nextval('seq_sku_nuevo') AS n) s
    WHERE p.id = :id
    RETURNING id
)
INSERT INTO producto_atributo_eav (producto_id, clave, valor)
SELECT n.id, a.clave, a.valor
FROM new_prod n, producto_atributo_eav a
WHERE a.producto_id = :id;