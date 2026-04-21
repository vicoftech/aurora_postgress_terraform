# Migración alert_prod: MySQL → PostgreSQL (Prefect)

Flujo Prefect 3 que copia datos de **MySQL** (`alert_prod`) a **PostgreSQL** (`public`) respetando el orden de foreign keys, con chunks, idempotencia (`ON CONFLICT (id) DO NOTHING`), reintentos, tabla `migration_errors` y reporte CSV.

## Archivos

| Archivo | Descripción |
|---------|-------------|
| `migration_config.py` | `MigrationConfig`, orden de tablas, `config_from_env()` |
| `migration_utils.py` | Transformaciones, `execute_with_retry`, inserts, errores |
| `migration_tasks.py` | Tasks Prefect (conteos, migración, FKs, webhook) |
| `migration_flow.py` | Flow `migrate_alert_prod`, subflow `migrate_single_table` |
| `migration_deployment.yaml` | Plantilla de deployment Prefect |
| `test_migration.py` | Tests unitarios (transformaciones, SQL helpers) |

## Requisitos

- Python 3.10+
- Extensiones PostgreSQL ya creadas en destino (p. ej. `vector` para `embedding_vector`)

```bash
cd migracion
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Variables de entorno

| Variable | Descripción |
|----------|-------------|
| `MYSQL_HOST` | Host MySQL (requerido) |
| `MYSQL_PORT` | Puerto (default `3306`) |
| `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE` | Credenciales MySQL |
| `POSTGRES_HOST` | Host PostgreSQL (requerido) |
| `POSTGRES_PORT` | Puerto (default `5432`) |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DATABASE` | Credenciales PG |
| `MIGRATION_CHUNK_SIZE` | Filas por lectura (default `10000`) |
| `MIGRATION_RETRY_ATTEMPTS` | Reintentos en utilidades (default `3`) |
| `MIGRATION_TRUNCATE_DEST` | `true` para `TRUNCATE ... CASCADE` antes de cada tabla |
| `MIGRATION_LOG_DIR` | Directorio de logs y CSV (default `./logs`) |
| `MIGRATION_WEBHOOK_URL` | URL opcional POST JSON con resumen al finalizar |

## Ejecución local

Desde `migracion/` con variables exportadas:

```bash
python migration_flow.py
```

O desde Python:

```python
from migration_flow import migrate_alert_prod
from migration_config import MigrationConfig, config_from_env

# Opción A: entorno
config = config_from_env()

# Opción B: URLs explícitas
config = MigrationConfig(
    mysql_connection_string="mysql+pymysql://user:pass@host:3306/alert_prod",
    postgres_connection_string="postgresql+psycopg2://user:pass@host:5432/alert_prod",
    log_file_path="./logs",
)

result = migrate_alert_prod(config)
print(result["report_path"], result["status"])
```

## Salidas

- Log: `logs/migration_YYYYMMDD_HHMMSS.log`
- CSV: `logs/migration_report_YYYYMMDD_HHMMSS.csv`
- Errores por fila: tabla `public.migration_errors` en PostgreSQL

## Deployment Prefect

1. Crear work pool y arrancar un worker que tenga acceso a MySQL y PostgreSQL.
2. Registrar el deployment (ejemplo):

```bash
cd migracion
prefect deploy migration_flow.py:migrate_alert_prod --name prod --pool <tu-pool>
```

3. Pasar credenciales vía **variables de entorno** del worker o **Prefect Blocks** (recomendado en producción en lugar de texto plano).

Consulta `migration_deployment.yaml` como referencia y ajusta `entrypoint`/`work_pool` a tu layout.

## Tests

```bash
cd migracion
pytest test_migration.py -v
```
