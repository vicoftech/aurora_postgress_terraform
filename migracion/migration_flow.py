"""Flow principal Prefect: migración alert_prod MySQL → PostgreSQL."""

from __future__ import annotations

import csv
import logging
import sys
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from prefect import flow
from prefect.logging import get_run_logger

from migration_config import (
    TABLE_MIGRATION_ORDER,
    MigrationConfig,
    MigrationStatus,
    config_from_env,
)
from migration_tasks import (
    migrate_table,
    send_notification_task,
    validate_connections_task,
    validate_referential_integrity_task,
)


def _setup_file_logging(log_dir: Path, run_id: str) -> Path:
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / f"migration_{run_id}.log"
    root = logging.getLogger()
    if not any(
        isinstance(h, logging.FileHandler) and getattr(h, "baseFilename", None) == str(log_path)
        for h in root.handlers
    ):
        fh = logging.FileHandler(log_path, encoding="utf-8")
        fh.setLevel(logging.INFO)
        fh.setFormatter(
            logging.Formatter("%(asctime)s | %(levelname)s | %(name)s | %(message)s")
        )
        root.addHandler(fh)
    return log_path


def _format_duration(seconds: float) -> str:
    s = int(seconds)
    h, rem = divmod(s, 3600)
    m, sec = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{sec:02d}"


@flow(name="MySQL to PostgreSQL Migration", version="1.0.0")
def migrate_alert_prod(config: MigrationConfig) -> Dict[str, Any]:
    """
    Orquesta la migración completa: validar conexiones, migrar tablas en orden,
    validar FKs, CSV de reporte y notificación opcional.
    """
    logger = get_run_logger()
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_dir = Path(config.log_file_path)
    log_path = _setup_file_logging(log_dir, run_id)
    report_path = log_dir / f"migration_report_{run_id}.csv"

    config.validate()

    logger.info("=" * 60)
    logger.info("INICIANDO MIGRACIÓN alert_prod MySQL → PostgreSQL run_id=%s", run_id)
    logger.info("Log archivo: %s", log_path)
    logger.info("=" * 60)

    try:
        validate_connections_task(config.mysql_connection_string, config.postgres_connection_string)
    except Exception as e:
        logger.error("Error validando conexiones: %s", e)
        return {
            "status": "FAILED",
            "error": str(e),
            "run_id": run_id,
            "report_path": str(report_path),
            "log_path": str(log_path),
        }

    results = []
    failed_tables: list[str] = []

    for table_config in TABLE_MIGRATION_ORDER:
        table_name = table_config["name"]
        logger.info("--- Migrando %s ---", table_name)
        try:
            result = migrate_table(
                table_name=table_name,
                mysql_connection_string=config.mysql_connection_string,
                postgres_connection_string=config.postgres_connection_string,
                config=config,
                migration_run_id=run_id,
            )
            results.append(result)
            if result.status == MigrationStatus.FAILED:
                failed_tables.append(table_name)
                logger.error("%s: FALLÓ", table_name)
            else:
                logger.info(
                    "%s: insertados=%s errores=%s (%.2fs)",
                    table_name,
                    result.inserted_count,
                    result.error_count,
                    result.duration_seconds,
                )
        except Exception as e:
            logger.exception("Error migrando %s: %s", table_name, e)
            failed_tables.append(table_name)

    logger.info("Validando integridad referencial...")
    fk_validation: Dict[str, bool] = {}
    try:
        fk_validation = validate_referential_integrity_task(
            config.postgres_connection_string,
            TABLE_MIGRATION_ORDER,
        )
    except Exception as e:
        logger.warning("No se pudo validar integridad: %s", e)

    total_records = sum(r.inserted_count for r in results)
    total_errors = sum(r.error_count for r in results)
    total_duration = sum(r.duration_seconds for r in results)
    successful = len([r for r in results if r.status == MigrationStatus.COMPLETED])

    with open(report_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "table_name",
                "source_count",
                "destination_count",
                "inserted_count",
                "error_count",
                "duration_seconds",
                "status",
            ],
        )
        writer.writeheader()
        for r in results:
            writer.writerow(
                {
                    "table_name": r.table_name,
                    "source_count": r.source_count,
                    "destination_count": r.destination_count,
                    "inserted_count": r.inserted_count,
                    "error_count": r.error_count,
                    "duration_seconds": f"{r.duration_seconds:.2f}",
                    "status": r.status.value,
                }
            )

    overall = "FAILED" if failed_tables else "COMPLETED"
    summary: Dict[str, Any] = {
        "status": overall,
        "run_id": run_id,
        "total_tables": len(results),
        "successful_tables": successful,
        "failed_tables": failed_tables,
        "total_records_migrated": total_records,
        "total_errors": total_errors,
        "total_duration_seconds": total_duration,
        "total_duration_hms": _format_duration(total_duration),
        "report_path": str(report_path),
        "log_path": str(log_path),
        "fk_validation": fk_validation,
    }

    send_notification_task(summary, config.webhook_url)

    logger.info("RESUMEN: status=%s tablas OK=%s fallidas=%s registros=%s errores=%s duración=%s",
                overall, successful, len(failed_tables), total_records, total_errors,
                _format_duration(total_duration))
    logger.info("Reporte CSV: %s", report_path)

    return summary


@flow(name="Migrate single table", version="1.0.0")
def migrate_single_table(
    table_name: str,
    config: MigrationConfig,
    migration_run_id: str | None = None,
) -> Any:
    """Subflow para migrar una sola tabla (reutiliza la task `migrate_table`)."""
    rid = migration_run_id or datetime.now().strftime("%Y%m%d_%H%M%S")
    return migrate_table(
        table_name=table_name,
        mysql_connection_string=config.mysql_connection_string,
        postgres_connection_string=config.postgres_connection_string,
        config=config,
        migration_run_id=rid,
    )


def main() -> None:
    """CLI mínimo: variables de entorno vía `config_from_env()`."""
    try:
        cfg = config_from_env()
    except ValueError as e:
        print(f"Config error: {e}", file=sys.stderr)
        sys.exit(1)
    out = migrate_alert_prod(cfg)
    print(out)


if __name__ == "__main__":
    main()
