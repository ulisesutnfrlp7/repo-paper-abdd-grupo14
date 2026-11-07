### Bloque 1: base_eav (Relacional normalizado / EAV)

```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS base_eav WITH (FORCE)"
psql -d postgres -c "CREATE DATABASE base_eav"
psql -d base_eav -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\10_model_eav.sql
psql -d base_eav -c "CREATE SEQUENCE seq_sku_nuevo"
psql -d base_eav -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

---

### Bloque 2: base_jsonb_gin (JSONB + índice GIN)

```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS base_jsonb_gin WITH (FORCE)"
psql -d postgres -c "CREATE DATABASE base_jsonb_gin"
psql -d base_jsonb_gin -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\11_model_jsonb_gin.sql
psql -d base_jsonb_gin -c "CREATE SEQUENCE seq_sku_nuevo"
psql -d base_jsonb_gin -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

---

### Bloque 3: base_jsonb_btree (JSONB + B-tree sobre expresiones)

```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS base_jsonb_btree WITH (FORCE)"
psql -d postgres -c "CREATE DATABASE base_jsonb_btree"
psql -d base_jsonb_btree -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\12_model_jsonb_btree.sql
psql -d base_jsonb_btree -c "CREATE SEQUENCE seq_sku_nuevo"
psql -d base_jsonb_btree -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

---

### Bloque 4: base_udt (Objeto-relacional / UDT + DOMAIN)

```powershell
psql -d postgres -c "DROP DATABASE IF EXISTS base_udt WITH (FORCE)"
psql -d postgres -c "CREATE DATABASE base_udt"
psql -d base_udt -v nrows=1000000 -v natts=5 -f sql\00_src.sql -f sql\13_model_udt.sql
psql -d base_udt -c "CREATE SEQUENCE seq_sku_nuevo"
psql -d base_udt -c "DROP TABLE src" -c "VACUUM (ANALYZE)" -c "CHECKPOINT"
```

---

### Bloque 5: Verificación (ejecutar después de cargar las 4 bases)

Este comando confirma que los 4 modelos tienen exactamente los mismos datos (debería devolver `1000000` en los 4):

```powershell
psql -d base_eav -c "SELECT count(*) FROM producto_eav;"
psql -d base_jsonb_gin -c "SELECT count(*) FROM producto_jsonb;"
psql -d base_jsonb_btree -c "SELECT count(*) FROM producto_jsonb;"
psql -d base_udt -c "SELECT count(*) FROM producto_udt;"
```

---

**Recordá:** ejecutá los bloques en orden (1, 2, 3, 4) y recién al final el bloque 5 de verificación. Si algún conteo no da `1000000`, algo falló en esa carga y tenés que repetir ese bloque específico.