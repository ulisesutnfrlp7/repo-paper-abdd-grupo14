-- =============================================================================
-- 12_model_jsonb_btree.sql  -  Modelo B2: JSONB + índices B-tree sobre expresiones

-- Propósito:
--   Variante intermedia del modelo JSONB: misma columna JSONB, pero indexada
--   con índices B-tree sobre expresiones (attrs->>'color', attrs->>'marca')
--   en lugar de GIN.
--
-- Qué hace:
--   1. Crea tabla `producto_jsonb` (misma estructura que B1).
--   2. Carga datos desde `src`.
--   3. Crea dos índices B-tree de expresión sobre los atributos consultados.
--   4. Resetea la secuencia SERIAL.
--
-- Por qué existe:
--   Permite aislar si el costo de JSONB proviene del índice GIN en sí o de la
--   falta de estadísticas del optimizador. Los índices B-tree de expresión
--   hacen que ANALYZE recolecte estadísticas en pg_statistic, lo que mejora
--   las estimaciones de selectividad del planificador.
--
-- Limitación:
--   Solo indexa los atributos que se conocen de antemano. No cubre claves
--   arbitrarias del JSON como lo haría GIN.
--
-- =============================================================================
-- ============================================================================
-- MODELO B2: JSONB + índices B-tree sobre expresiones (color, marca)
-- Mismo documento que B1, pero indexando solo los atributos que se consultan.
-- Los índices de expresión hacen que ANALYZE recolecte estadísticas de
-- (attrs->>'color') y (attrs->>'marca'), cosa que GIN no hace.
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

CREATE INDEX idx_jsonb_expr_color ON producto_jsonb ((attrs->>'color'));
CREATE INDEX idx_jsonb_expr_marca ON producto_jsonb ((attrs->>'marca'));

SELECT setval(pg_get_serial_sequence('producto_jsonb', 'id'), (SELECT max(id) FROM producto_jsonb));