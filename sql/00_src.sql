-- =============================================================================
-- 00_src.sql  -  Fuente única de datos sintéticos (determinística)

-- Propósito:
--   Generar una tabla `src` con N filas de productos y NATTS atributos por
--   producto, usando una semilla aleatoria fija (setseed(0.42)) para que TODAS
--   las bases (EAV, JSONB-GIN, JSONB-Btree, UDT) reciban EXACTAMENTE los mismos
--   datos. Esto es crítico para que la comparación de rendimiento sea válida.
--
-- Por qué existe:
--   Si cada modelo tuviera datos distintos, las diferencias de TPS o latencia
--   podrían deberse a la distribución de los datos y no al modelo de almacenaje.
--
-- Uso:
--   psql -d <base> -v nrows=1000000 -v natts=5 -f sql/00_src.sql
--
-- Variables:
--   nrows   Número de filas (productos) a generar.
--   natts   Cantidad de atributos por producto (5 a 50).
--           Los 5 primeros son "núcleo" (color, talle, voltaje, marca, categoria)
--           con cardinalidades distintas; los natts-5 restantes son atributos
--           extra (x01, x02, ...) con valores de 20 caracteres.
--
-- =============================================================================
-- ============================================================================
-- 00_src.sql  -  Fuente única de datos sintéticos (determinística)
--
-- Variables psql requeridas:  nrows  (filas)   natts  (atributos por producto, 5..50)
--
-- Los 5 atributos "núcleo" (color, talle, voltaje, marca, categoria) tienen
-- cardinalidades distintas; los natts-5 restantes (x01, x02, ...) son atributos
-- extra con valores de 20 caracteres y cardinalidad variable (10..105 valores).
-- Esto agranda el documento de forma realista (sin un relleno constante que
-- distorsionaría el índice GIN).
--
-- setseed() hace que cada base (eav, jsonb, udt) reciba EXACTAMENTE los mismos
-- datos, de modo que las estimaciones del optimizador sean comparables.
-- ============================================================================
SELECT setseed(0.42);

SELECT format($f$
CREATE TABLE src AS
SELECT
    i AS id,
    'Producto_' || i AS nombre,
    round((random() * 500 + 10)::numeric, 2) AS precio,
    'SKU-' || lpad(i::text, 10, '0') AS sku,
    jsonb_build_object(
        'color',     (ARRAY['rojo','azul','verde','negro'])[1 + floor(random()*4)::int],
        'talle',     (ARRAY['S','M','L','XL'])[1 + floor(random()*4)::int],
        'voltaje',   (ARRAY[110,220,380])[1 + floor(random()*3)::int],
        'marca',     'Marca_' || (1 + floor(random()*2000)::int),
        'categoria', 'Cat_'   || (1 + floor(random()*50)::int)
        %s
    ) AS attrs
FROM generate_series(1, %s) AS i
$f$,
  COALESCE((
    SELECT ', ' || string_agg(
             format($e$'x%s', 'valor_' || lpad((floor(random()*%s))::int::text, 14, '0')$e$,
                    lpad(k::text, 2, '0'),
                    5 * (k % 20 + 2)),
             ', ' ORDER BY k)
    FROM generate_series(1, :natts - 5) AS k
  ), ''),
  :nrows
) \gexec

ALTER TABLE src ADD PRIMARY KEY (id);