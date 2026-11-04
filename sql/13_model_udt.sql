-- =============================================================================
-- 13_model_udt.sql  -  Modelo C: Objeto-relacional (UDT compuesto + DOMAIN)

-- Propósito:
--   Explorar las capacidades Objeto-Relacionales (ORDBMS) nativas de
--   PostgreSQL para almacenar atributos dinámicos sin recurrir a JSON.
--
-- Qué hace:
--   1. Crea dominios dom_voltaje y dom_talle con restricciones CHECK (validación
--      escalar sobre tipos base).
--   2. Crea tipo compuesto udt_especificaciones con NATTS campos (dinámico),
--      agrupando varios atributos en una única columna.
--   3. Crea tabla `producto_udt` con columna del tipo compuesto.
--   4. Carga datos desde `src` extrayendo campos del JSONB y casteando a dominios.
--   5. Crea índices de expresión sobre color y marca (equivalentes a B2).
--   6. Resetea la secuencia SERIAL.
--
-- Por qué existe:
--   Representa el enfoque ORDBMS puro: estructura tipada con validación de
--   dominio, sin formato semiestructurado libre como JSON.
--
-- Limitación para el paper:
--   Agregar un nuevo atributo requiere ALTER TYPE ... ADD ATTRIBUTE (costo de
--   DDL y bloqueo de tabla). Esa rigidez es la contracara del trade-off que
--   analiza el paper (flexibilidad de esquema vs. costo de indexación).
--
-- =============================================================================
-- ============================================================================
-- MODELO C: objeto-relacional (tipo compuesto + dominios)
--
--  * CREATE DOMAIN  -> validación escalar (CHECK) sobre un tipo base.
--  * CREATE TYPE AS -> tipo compuesto (UDT) que agrupa los natts atributos
--                      en una única columna.
--
-- El tipo se genera dinámicamente con natts campos para que tenga el mismo
-- "ancho" de documento que los modelos JSONB y EAV.
-- ============================================================================
CREATE DOMAIN dom_voltaje AS INT CHECK (VALUE IN (110, 220, 380));
CREATE DOMAIN dom_talle   AS VARCHAR(10) CHECK (VALUE IN ('S', 'M', 'L', 'XL'));

SELECT format(
  'CREATE TYPE udt_especificaciones AS (
       color VARCHAR(30), talle dom_talle, voltaje dom_voltaje,
       marca VARCHAR(50), categoria VARCHAR(30) %s)',
  COALESCE((SELECT ', ' || string_agg(format('x%s VARCHAR(40)', lpad(k::text, 2, '0')), ', ' ORDER BY k)
            FROM generate_series(1, :natts - 5) AS k), '')
) \gexec

CREATE TABLE producto_udt (
    id               SERIAL PRIMARY KEY,
    nombre           TEXT NOT NULL,
    precio           NUMERIC(10,2) NOT NULL,
    sku              VARCHAR(64) NOT NULL UNIQUE,
    especificaciones udt_especificaciones NOT NULL
);

SELECT format(
  'INSERT INTO producto_udt (id, nombre, precio, sku, especificaciones)
   SELECT id, nombre, precio, sku,
          ROW(attrs->>''color'', (attrs->>''talle'')::dom_talle,
              (attrs->>''voltaje'')::int::dom_voltaje,
              attrs->>''marca'', attrs->>''categoria'' %s)::udt_especificaciones
   FROM src ORDER BY id',
  COALESCE((SELECT ', ' || string_agg(format('attrs->>''x%s''', lpad(k::text, 2, '0')), ', ' ORDER BY k)
            FROM generate_series(1, :natts - 5) AS k), '')
) \gexec

-- Índices de expresión sobre los campos consultados (equivalentes a B2)
CREATE INDEX idx_udt_color ON producto_udt (((especificaciones).color));
CREATE INDEX idx_udt_marca ON producto_udt (((especificaciones).marca));

SELECT setval(pg_get_serial_sequence('producto_udt', 'id'), (SELECT max(id) FROM producto_udt));