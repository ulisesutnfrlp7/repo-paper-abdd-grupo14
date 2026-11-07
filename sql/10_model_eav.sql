-- =============================================================================
-- 10_model_eav.sql  -  Modelo A: Relacional normalizado (EAV)

-- Propósito:
--   Implementar el modelo relacional clásico tipo Entity-Attribute-Value como
--   línea base del benchmark. Almacena atributos dinámicos en filas clave-valor
--   en lugar de columnas fijas.
--
-- Qué hace:
--   1. Crea tabla maestro `producto_eav` (id, nombre, precio, sku).
--   2. Crea tabla de atributos `producto_atributo_eav` (producto_id, clave, valor).
--   3. Carga datos desde `src` desnormalizando el JSONB con jsonb_each_text.
--   4. Crea índice compuesto (clave, valor) para búsquedas por atributo.
--   5. Resetea la secuencia SERIAL para permitir INSERTs posteriores de pgbench.
--
-- Por qué existe:
--   Representa la alternativa normalizada a JSONB. Sirve para medir el costo
--   de los JOINs necesarios al consultar atributos dinámicos.
--
-- Limitación para el paper:
--   EAV se considera un antipatrón en modelado relacional estricto, pero se usa
--   aquí como línea base porque es la forma más común de almacenar atributos
--   dinámicos sin recurrir a JSON.
--
-- =============================================================================
-- ============================================================================
-- MODELO A: relacional normalizado (EAV - Entity/Attribute/Value)
-- Carga primero, índices después (más rápido y árboles compactos).
-- ============================================================================
CREATE TABLE producto_eav (
    id     SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    sku    VARCHAR(64) NOT NULL UNIQUE
);

CREATE TABLE producto_atributo_eav (
    producto_id INT NOT NULL REFERENCES producto_eav(id) ON DELETE CASCADE,
    clave       VARCHAR(50)  NOT NULL,
    valor       VARCHAR(255) NOT NULL,
    PRIMARY KEY (producto_id, clave)
);

INSERT INTO producto_eav (id, nombre, precio, sku)
SELECT id, nombre, precio, sku FROM src ORDER BY id;

INSERT INTO producto_atributo_eav (producto_id, clave, valor)
SELECT s.id, e.key, e.value
FROM src s, LATERAL jsonb_each_text(s.attrs) AS e
ORDER BY s.id, e.key;

-- Índice de búsqueda por atributo (el único que necesita el modelo para filtrar)
CREATE INDEX idx_eav_clave_valor ON producto_atributo_eav (clave, valor);

SELECT setval(pg_get_serial_sequence('producto_eav', 'id'), (SELECT max(id) FROM producto_eav));