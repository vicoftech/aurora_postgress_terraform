#!/usr/bin/env python3
"""Flow de migración parcial desde disposicion_contenido hacia abajo."""

import os
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict

from prefect import flow, task
from sqlalchemy import create_engine, text

from migration_config import config_from_env, MigrationResult, MigrationStatus, FlowSummary, TABLE_MIGRATION_ORDER
from migration_tasks import migrate_table, validate_referential_integrity_task, validate_connections_task
from prefect.logging import get_run_logger
from migration_utils import log_migration_error


@task
def truncate_partial_tables(pg_engine) -> bool:
    """Trunca solo las tablas desde disposicion_contenido hacia abajo."""
    logger = get_run_logger()
    
    tables_to_truncate = [
        "disposicion_contenido",
        "alerta_generada", 
        "alerta_generada_historica",
        "migration_errors"
    ]
    
    try:
        with pg_engine.begin() as conn:
            # Desactivar temporalmente las restricciones de clave foránea
            conn.execute(text("SET session_replication_role = 'replica'"))
            
            try:
                for table_name in tables_to_truncate:
                    quoted_table = f'"{table_name}"'
                    truncate_sql = f"TRUNCATE TABLE public.{quoted_table} CASCADE"
                    conn.execute(text(truncate_sql))
                    logger.info(f"✅ Tabla '{table_name}' truncada exitosamente")
                    
            finally:
                # Reactivar las restricciones de clave foránea
                conn.execute(text("SET session_replication_role = 'origin'"))
                
        return True
        
    except Exception as e:
        logger.error(f"❌ Error truncando tablas parciales: {e}")
        return False


@flow(
    name="migracion-parcial-alert_prod",
    log_prints=True,
)
def migration_flow_partial() -> Dict[str, Any]:
    """Flow principal de migración parcial desde disposicion_contenido."""
    logger = get_run_logger()
    
    # Configuración desde variables de entorno
    try:
        config = config_from_env()
    except ValueError as e:
        logger.error("Error de configuración: %s", e)
        return {"status": "FAILED", "error": str(e)}
    
    config.validate()
    
    # ID único para esta corrida
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Directorios de logs y reportes
    log_dir = Path(config.log_file_path)
    log_dir.mkdir(exist_ok=True)
    log_path = log_dir / f"migration_{run_id}.log"
    
    report_dir = Path("./reports")
    report_dir.mkdir(exist_ok=True)
    report_path = report_dir / f"migration_report_{run_id}.csv"
    
    logger.info("=" * 60)
    logger.info("INICIANDO MIGRACIÓN PARCIAL desde disposicion_contenido → PostgreSQL run_id=%s", run_id)
    logger.info("Log archivo: %s", log_path)
    logger.info("=" * 60)
    
    try:
        validate_connections_task(config.mysql_connection_string, config.postgres_connection_string)
        
        # Truncar solo las tablas parciales
        logger.info("Truncando tablas parciales PostgreSQL...")
        pg_engine = create_engine(config.postgres_connection_string)
        
        if not truncate_partial_tables(pg_engine):
            logger.error("Error truncando tablas parciales")
            return {
                "status": "FAILED",
                "error": "Error truncando tablas parciales",
                "run_id": run_id,
                "report_path": str(report_path),
                "log_path": str(log_path),
            }
        logger.info("Tablas parciales truncadas exitosamente")
        
    except Exception as e:
        logger.error("Error validando conexiones: %s", e)
        return {
            "status": "FAILED",
            "error": str(e),
            "run_id": run_id,
            "report_path": str(report_path),
            "log_path": str(log_path),
        }
    
    # Encontrar índice donde empieza disposicion_contenido
    start_index = None
    for i, table_config in enumerate(TABLE_MIGRATION_ORDER):
        if table_config["name"] == "disposicion_contenido":
            start_index = i
            break
    
    if start_index is None:
        logger.error("No se encontró la tabla disposicion_contenido en la configuración")
        return {
            "status": "FAILED", 
            "error": "Tabla disposicion_contenido no encontrada",
            "run_id": run_id,
            "report_path": str(report_path),
            "log_path": str(log_path),
        }
    
    # Migrar solo desde disposicion_contenido hacia abajo
    partial_tables = TABLE_MIGRATION_ORDER[start_index:]
    results = []
    failed_tables: list[str] = []
    
    for table_config in partial_tables:
        table_name = table_config["name"]
        logger.info("--- Migrando %s ---", table_name)
        try:
            result = migrate_table(
                table_name=table_name,
                mysql_connection_string=config.mysql_connection_string,
                postgres_connection_string=config.postgres_connection_string,
                chunk_size=config.chunk_size,
                retry_attempts=config.retry_attempts,
                migration_run_id=run_id,
            )
            results.append(result)
            
            if not result.success:
                failed_tables.append(table_name)
                logger.error("Falló migración de %s: %d errores", table_name, result.error_count)
            else:
                logger.info(
                    "✅ %s migrada: %d/%d filas (%.1fs)",
                    table_name,
                    result.inserted_count,
                    result.source_count,
                    result.duration_seconds,
                )
                
        except Exception as e:
            logger.error("Error crítico migrando %s: %s", table_name, e)
            failed_tables.append(table_name)
            results.append(
                MigrationResult(
                    table_name=table_name,
                    status=MigrationStatus.FAILED,
                    source_count=0,
                    destination_count=0,
                    inserted_count=0,
                    error_count=1,
                    duration_seconds=0.0,
                )
            )
    
    # Validar integridad referencial
    logger.info("--- Validando integridad referencial ---")
    try:
        integrity_ok = validate_referential_integrity(config.postgres_connection_string)
        if integrity_ok:
            logger.info("✅ Integridad referencial válida")
        else:
            logger.warning("⚠️ Problemas de integridad referencial detectados")
    except Exception as e:
        logger.error("Error validando integridad: %s", e)
    
    # Generar reporte CSV
    logger.info("--- Generando reporte CSV ---")
    try:
        with open(report_path, "w", encoding="utf-8") as f:
            f.write("table_name,status,source_count,destination_count,inserted_count,error_count,duration_seconds\n")
            for r in results:
                f.write(
                    f"{r.table_name},{r.status.value},{r.source_count},"
                    f"{r.destination_count},{r.inserted_count},{r.error_count},{r.duration_seconds}\n"
                )
        logger.info("📄 Reporte guardado en %s", report_path)
    except Exception as e:
        logger.error("Error generando reporte: %s", e)
    
    # Resumen final
    total_records = sum(r.inserted_count for r in results)
    total_errors = sum(r.error_count for r in results)
    total_duration = sum(r.duration_seconds for r in results)
    
    summary = FlowSummary(
        status="COMPLETED" if not failed_tables else "PARTIAL",
        run_id=run_id,
        report_path=str(report_path),
        log_path=str(log_path),
        total_tables=len(partial_tables),
        successful_tables=len(partial_tables) - len(failed_tables),
        failed_tables=failed_tables,
        total_records_migrated=total_records,
        total_errors=total_errors,
        total_duration_seconds=total_duration,
    )
    
    logger.info("=" * 60)
    logger.info("RESUMEN MIGRACIÓN PARCIAL:")
    logger.info("Run ID: %s", summary.run_id)
    logger.info("Estado: %s", summary.status)
    logger.info("Tablas procesadas: %d/%d", summary.successful_tables, summary.total_tables)
    logger.info("Registros migrados: %d", summary.total_records_migrated)
    logger.info("Errores totales: %d", summary.total_errors)
    logger.info("Duración total: %.1f segundos", summary.total_duration_seconds)
    if summary.failed_tables:
        logger.error("Tablas fallidas: %s", ", ".join(summary.failed_tables))
    logger.info("Reporte: %s", summary.report_path)
    logger.info("=" * 60)
    
    return {
        "status": summary.status,
        "run_id": summary.run_id,
        "report_path": summary.report_path,
        "log_path": summary.log_path,
        "summary": summary.__dict__,
    }


if __name__ == "__main__":
    result = migration_flow_partial()
    sys.exit(0 if result["status"] in ["COMPLETED", "PARTIAL"] else 1)
