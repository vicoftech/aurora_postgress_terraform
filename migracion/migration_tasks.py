"""Tasks de Prefect para migración MySQL → PostgreSQL."""

from __future__ import annotations

import time
from typing import Any, Dict, List

import pandas as pd
from prefect import task
from prefect.logging import get_run_logger
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from migration_config import MigrationConfig, MigrationResult, MigrationStatus
from migration_utils import (
    build_insert_sql,
    ensure_migration_errors_table,
    execute_with_retry,
    log_migration_error,
    quote_pg_ident,
    transform_row_mysql_to_postgres,
    validate_row_before_insert,
)


def _mysql_table_ref(table_name: str) -> str:
    return f"`{table_name.replace('`', '')}`"


def _count_mysql(engine: Engine, table_name: str) -> int:
    with engine.connect() as conn:
        r = conn.execute(text(f"SELECT COUNT(*) AS c FROM {_mysql_table_ref(table_name)}"))
        return int(r.scalar() or 0)


def _count_pg(engine: Engine, table_name: str) -> int:
    qt = quote_pg_ident(table_name)
    with engine.connect() as conn:
        r = conn.execute(text(f"SELECT COUNT(*) AS c FROM public.{qt}"))
        return int(r.scalar() or 0)


def _truncate_pg(engine: Engine, table_name: str) -> None:
    qt = quote_pg_ident(table_name)
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE public.{qt} CASCADE"))


@task(retries=3, retry_delay_seconds=10, name="get_source_row_count")
def get_source_row_count(mysql_connection_string: str, table_name: str) -> int:
    logger = get_run_logger()
    engine = create_engine(mysql_connection_string)
    n = _count_mysql(engine, table_name)
    logger.info("%s: %s registros en MySQL", table_name, n)
    return n


@task(retries=3, retry_delay_seconds=10, name="get_destination_row_count")
def get_destination_row_count(postgres_connection_string: str, table_name: str) -> int:
    logger = get_run_logger()
    engine = create_engine(postgres_connection_string)
    n = _count_pg(engine, table_name)
    logger.info("%s: %s registros en PostgreSQL", table_name, n)
    return n


@task(name="validate_connections")
def validate_connections_task(
    mysql_connection_string: str, postgres_connection_string: str
) -> bool:
    logger = get_run_logger()
    m = create_engine(mysql_connection_string)
    p = create_engine(postgres_connection_string)
    with m.connect() as c:
        c.execute(text("SELECT 1"))
    with p.connect() as c:
        c.execute(text("SELECT 1"))
    logger.info("Conexiones MySQL y PostgreSQL OK")
    return True


def _insert_one_row(
    pg_engine: Engine,
    table_name: str,
    transformed: Dict[str, Any],
    config: MigrationConfig,
) -> bool:
    """Inserta una fila; devuelve True si se insertó fila nueva (rowcount > 0)."""

    cols = list(transformed.keys())
    insert_sql = build_insert_sql(table_name, cols)

    def _run() -> int:
        with pg_engine.begin() as conn:  # Fresh connection with clean transaction
            try:
                res = conn.execute(text(insert_sql), transformed)
                return int(res.rowcount or 0)
            except Exception as e:
                # If there's a constraint violation or other error, log it but don't fail the migration
                # The retry mechanism will handle transient errors
                raise e

    wrapped = execute_with_retry(
        _run,
        config.retry_attempts,
        config.exponential_backoff_factor,
    )
    return wrapped() > 0


@task(retries=2, retry_delay_seconds=30, name="migrate_table")
def migrate_table(
    table_name: str,
    mysql_connection_string: str,
    postgres_connection_string: str,
    config: MigrationConfig,
    migration_run_id: str,
) -> MigrationResult:
    logger = get_run_logger()
    start = time.time()
    mysql_engine = create_engine(mysql_connection_string, pool_pre_ping=True)
    pg_engine = create_engine(postgres_connection_string, pool_pre_ping=True)

    error_details: List[Dict[str, Any]] = []
    total_inserted = 0
    error_count = 0

    try:
        with pg_engine.begin() as conn:
            ensure_migration_errors_table(conn)

        if config.truncate_destination:
            _truncate_pg(pg_engine, table_name)
            logger.info("TRUNCATE aplicado a %s", table_name)

        offset = 0
        while True:
            q = (
                f"SELECT * FROM {_mysql_table_ref(table_name)} "
                f"LIMIT {config.chunk_size} OFFSET {offset}"
            )
            df = pd.read_sql(q, mysql_engine)
            if df.empty:
                break

            for raw in df.to_dict("records"):
                row_dict = {k: raw[k] for k in raw}
                rid = str(row_dict.get("id", "unknown"))
                try:
                    if not validate_row_before_insert(row_dict, table_name):
                        error_count += 1
                        error_details.append({"row_id": rid, "error": "validación"})
                        log_migration_error(
                            pg_engine,
                            migration_run_id,
                            table_name,
                            "validación fallida",
                            rid,
                            row_dict,
                        )
                        continue

                    transformed = transform_row_mysql_to_postgres(row_dict, table_name)

                    try:
                        if _insert_one_row(pg_engine, table_name, transformed, config):
                            total_inserted += 1
                    except Exception as ex:
                        error_count += 1
                        error_details.append({"row_id": rid, "error": str(ex)})
                        log_migration_error(
                            pg_engine,
                            migration_run_id,
                            table_name,
                            str(ex),
                            rid,
                            transformed,
                        )
                        logger.warning("Error insert %s id=%s: %s", table_name, rid, ex)

                except Exception as ex:
                    error_count += 1
                    error_details.append({"row_id": rid, "error": str(ex)})
                    log_migration_error(
                        pg_engine, migration_run_id, table_name, str(ex), rid, row_dict
                    )

            offset += config.chunk_size

        source_count = _count_mysql(mysql_engine, table_name)
        dest_count = _count_pg(pg_engine, table_name)
        duration = time.time() - start

        if error_count == 0:
            status = MigrationStatus.COMPLETED
        elif total_inserted > 0:
            status = MigrationStatus.PARTIAL
        else:
            status = MigrationStatus.FAILED

        return MigrationResult(
            table_name=table_name,
            status=status,
            source_count=source_count,
            destination_count=dest_count,
            inserted_count=total_inserted,
            error_count=error_count,
            duration_seconds=duration,
            error_details=error_details or None,
        )

    except Exception as e:
        logger.exception("Error fatal en %s: %s", table_name, e)
        return MigrationResult(
            table_name=table_name,
            status=MigrationStatus.FAILED,
            source_count=0,
            destination_count=0,
            inserted_count=0,
            error_count=1,
            duration_seconds=time.time() - start,
            error_details=[{"error": str(e)}],
        )


@task(name="validate_referential_integrity")
def validate_referential_integrity_task(
    postgres_connection_string: str,
    table_order: List[Dict[str, Any]],
) -> Dict[str, bool]:
    logger = get_run_logger()
    engine = create_engine(postgres_connection_string)
    results: Dict[str, bool] = {}

    checks = [
        (
            "busqueda",
            "SELECT COUNT(*) FROM public.busqueda b WHERE b.cuenta_id IS NOT NULL "
            "AND NOT EXISTS (SELECT 1 FROM public.cuenta c WHERE c.id = b.cuenta_id)",
        ),
        (
            "busqueda_historica",
            "SELECT COUNT(*) FROM public.busqueda_historica b WHERE b.cuenta_id IS NOT NULL "
            "AND NOT EXISTS (SELECT 1 FROM public.cuenta c WHERE c.id = b.cuenta_id)",
        ),
        (
            "email",
            "SELECT COUNT(*) FROM public.email e WHERE e.cuenta_id IS NOT NULL "
            "AND NOT EXISTS (SELECT 1 FROM public.cuenta c WHERE c.id = e.cuenta_id)",
        ),
        (
            "overlay",
            'SELECT COUNT(*) FROM public."overlay" o WHERE o.cuenta_id IS NOT NULL '
            "AND NOT EXISTS (SELECT 1 FROM public.cuenta c WHERE c.id = o.cuenta_id)",
        ),
        (
            "disposicion_contenido",
            "SELECT COUNT(*) FROM public.disposicion_contenido d WHERE d.disposicion_id IS NOT NULL "
            "AND NOT EXISTS (SELECT 1 FROM public.disposicion x WHERE x.id = d.disposicion_id)",
        ),
        (
            "alerta_generada",
            "SELECT COUNT(*) FROM public.alerta_generada a WHERE "
            "(a.busqueda_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.busqueda b WHERE b.id = a.busqueda_id)) "
            "OR (a.disposicion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.disposicion d WHERE d.id = a.disposicion_id))",
        ),
        (
            "alerta_generada_historica",
            "SELECT COUNT(*) FROM public.alerta_generada_historica a WHERE "
            "(a.busqueda_historica_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.busqueda_historica b WHERE b.id = a.busqueda_historica_id)) "
            "OR (a.disposicion_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.disposicion d WHERE d.id = a.disposicion_id))",
        ),
    ]

    with engine.connect() as conn:
        for table_name, sql in checks:
            try:
                n = conn.execute(text(sql)).scalar()
                ok = int(n or 0) == 0
                results[table_name] = ok
                if not ok:
                    logger.warning("Integridad: %s tiene %s filas huérfanas", table_name, n)
                else:
                    logger.info("Integridad OK: %s", table_name)
            except Exception as e:
                logger.error("No se pudo validar %s: %s", table_name, e)
                results[table_name] = False

        for t in table_order:
            name = t["name"]
            if name not in results:
                results[name] = True

    return results


@task(name="send_notification_stub")
def send_notification_task(summary: Dict[str, Any], webhook_url: str | None) -> None:
    logger = get_run_logger()
    msg = (
        f"Migración alert_prod: status={summary.get('status')} "
        f"tablas={summary.get('total_tables')} registros={summary.get('total_records_migrated')}"
    )
    logger.info("Notificación: %s", msg)
    if webhook_url:
        try:
            import urllib.request
            import json

            req = urllib.request.Request(
                webhook_url,
                data=json.dumps(summary).encode(),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception as e:
            logger.warning("Webhook falló: %s", e)
