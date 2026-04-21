"""Configuración y orden de migración MySQL → PostgreSQL."""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class MigrationStatus(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    PARTIAL = "PARTIAL"
    FAILED = "FAILED"


@dataclass
class MigrationConfig:
    """Configuración para la migración MySQL → PostgreSQL."""

    mysql_connection_string: str
    postgres_connection_string: str
    chunk_size: int = 10000
    truncate_destination: bool = False
    retry_attempts: int = 3
    exponential_backoff_factor: float = 2.0
    log_file_path: str = "./logs"
    batch_insert_size: int = 5000
    disable_fk_checks_during_load: bool = True
    webhook_url: Optional[str] = None

    def validate(self) -> bool:
        assert self.chunk_size > 0, "chunk_size debe ser > 0"
        assert self.retry_attempts > 0, "retry_attempts debe ser > 0"
        assert self.batch_insert_size > 0, "batch_insert_size debe ser > 0"
        return True


@dataclass
class MigrationResult:
    """Resultado de migración de una tabla."""

    table_name: str
    status: MigrationStatus
    source_count: int
    destination_count: int
    inserted_count: int
    error_count: int
    duration_seconds: float
    error_details: Optional[List[Dict[str, Any]]] = None

    @property
    def success(self) -> bool:
        return self.error_count == 0 and self.status in (
            MigrationStatus.COMPLETED,
            MigrationStatus.PARTIAL,
        )


@dataclass
class FlowSummary:
    """Resumen del flow completo."""

    status: str
    run_id: str
    report_path: str
    log_path: str
    total_tables: int
    successful_tables: int
    failed_tables: List[str] = field(default_factory=list)
    total_records_migrated: int = 0
    total_errors: int = 0
    total_duration_seconds: float = 0.0


# Orden respetando FKs (ejemplos del repo)
TABLE_MIGRATION_ORDER: List[Dict[str, Any]] = [
    {"name": "cuenta", "depends_on": [], "has_data": True},
    {"name": "descarga_fuente_anmat", "depends_on": [], "has_data": True},
    {"name": "disposicion", "depends_on": [], "has_data": True},
    {"name": "frontend_routes", "depends_on": [], "has_data": False},
    {"name": "busqueda", "depends_on": ["cuenta"], "has_data": True},
    {"name": "busqueda_historica", "depends_on": ["cuenta"], "has_data": True},
    {"name": "email", "depends_on": ["cuenta"], "has_data": True},
    {"name": "overlay", "depends_on": ["cuenta"], "has_data": True},
    {
        "name": "disposicion_contenido",
        "depends_on": ["disposicion"],
        "has_data": True,
        "special_fields": ["embedding_vector"],
    },
    {
        "name": "alerta_generada",
        "depends_on": ["busqueda", "disposicion"],
        "has_data": True,
    },
    {
        "name": "alerta_generada_historica",
        "depends_on": ["busqueda_historica", "disposicion"],
        "has_data": True,
    },
]

TYPE_MAPPING = {
    "BIT": "BOOLEAN",
    "TINYBLOB": "BYTEA",
    "LONGTEXT": "TEXT",
    "DATETIME": "TIMESTAMP",
}


def config_from_env() -> MigrationConfig:
    """Construye MigrationConfig desde variables de entorno (Prefect / CI)."""

    def _req(name: str) -> str:
        v = os.getenv(name)
        if not v:
            raise ValueError(f"Variable de entorno requerida: {name}")
        return v

    mysql_host = _req("MYSQL_HOST")
    mysql_port = os.getenv("MYSQL_PORT", "3306")
    mysql_user = _req("MYSQL_USER")
    mysql_password = _req("MYSQL_PASSWORD")
    mysql_db = _req("MYSQL_DATABASE")

    pg_host = _req("POSTGRES_HOST")
    pg_port = os.getenv("POSTGRES_PORT", "5432")
    pg_user = _req("POSTGRES_USER")
    pg_password = _req("POSTGRES_PASSWORD")
    pg_db = _req("POSTGRES_DATABASE")

    mysql_url = (
        f"mysql+pymysql://{mysql_user}:{mysql_password}@{mysql_host}:{mysql_port}/{mysql_db}"
    )
    pg_url = f"postgresql+psycopg2://{pg_user}:{pg_password}@{pg_host}:{pg_port}/{pg_db}"

    return MigrationConfig(
        mysql_connection_string=mysql_url,
        postgres_connection_string=pg_url,
        chunk_size=int(os.getenv("MIGRATION_CHUNK_SIZE", "10000")),
        truncate_destination=os.getenv("MIGRATION_TRUNCATE_DEST", "false").lower()
        == "true",
        retry_attempts=int(os.getenv("MIGRATION_RETRY_ATTEMPTS", "3")),
        log_file_path=os.getenv("MIGRATION_LOG_DIR", "./logs"),
        webhook_url=os.getenv("MIGRATION_WEBHOOK_URL"),
    )
