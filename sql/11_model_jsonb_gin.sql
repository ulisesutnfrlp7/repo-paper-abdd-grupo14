-- =============================================================================
-- 11_model_jsonb_gin.sql  -  Modelo B1: JSONB + índice GIN (jsonb_ops)

-- Propósito:
--   Implementar el modelo documental/híbrido: una única columna JSONB que
--   almacena todos los atributos dinámicos, indexada con un árbol invertido GIN.
--
-- Qué hace:
--   1. Crea tabla `producto_jsonb` con columna `attrs JSONB NOT NULL`.
--   2. Carga datos desde `src` (mismo JSONB que la fuente).
--   3. Crea índice GIN sobre `attrs` usando el operador por defecto jsonb_ops.
--   4. Resetea la secuencia SERIAL.
--
-- Por qué existe:
--   Es el modelo que se quiere evaluar: evita migraciones DDL y JOINs, pero
--   impone un costo de escritura por el mantenimiento del índice GIN y carece
--   de estadísticas por clave para el optimizador.
--
-- Notas técnicas:
--   - GIN indexa todas las claves y valores del documento JSONB.
--   - jsonb_ops (por defecto) soporta @>, ?, ?|, ?& pero no operadores de comparación.
--   - La pending list de GIN (fastupdate) acumula actualizaciones en páginas
--     del índice y las vacía periódicamente, generando picos de latencia.
--
-- =============================================================================
-- ============================================================================
-- MODELO B1: JSONB + índice GIN (jsonb_ops, el operador por defecto)
-- ============================================================================
CREATE TABLE producto_jsonb (
    id     SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    precio NUMERIC(10,2) NOT NULL,
    sku    VARCHAR(64) NOT NULL UNIQUE,
    attrs  JSONB NOT NULL
);

INSERT INTO producto_jsonb (id, nombre, precio, sku, attrs)
SELECT id, nombre, precio, sku, attrs FROM src ORDER BY id;

CREATE INDEX idx_jsonb_gin ON producto_jsonb USING GIN (attrs);

SELECT setval(pg_get_serial_sequence('producto_jsonb', 'id'), (SELECT max(id) FROM producto_jsonb));