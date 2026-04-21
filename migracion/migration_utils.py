"""Utilidades: transformación de tipos, reintentos y logging de errores."""

from __future__ import annotations

import functools
import logging
import time
from typing import Any, Callable, Dict, Optional, TypeVar

from sqlalchemy import text
from sqlalchemy.engine import Connection, Engine

logger = logging.getLogger(__name__)

T = TypeVar("T")


def execute_with_retry(
    func: Callable[..., T],
    retry_attempts: int,
    backoff_factor: float = 2.0,
) -> Callable[..., T]:
    """Envuelve una función con reintentos y backoff exponencial."""

    @functools.wraps(func)
    def wrapper(*args: Any, **kwargs: Any) -> T:
        last_exc: Optional[Exception] = None
        delay = 1.0
        for attempt in range(retry_attempts):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                last_exc = e
                logger.warning(
                    "Intento %s/%s falló: %s — reintentando en %.1fs",
                    attempt + 1,
                    retry_attempts,
                    e,
                    delay,
                )
                time.sleep(delay)
                delay *= backoff_factor
        assert last_exc is not None
        raise last_exc

    return wrapper


def transform_mysql_value_to_postgres(
    value: Any, column_name: str, table_name: str
) -> Any:
    """Transforma un valor MySQL → PostgreSQL según reglas del prompt."""
    if value is None:
        return None

    # Handle NaT (Not a Time) values from pandas
    try:
        # Check if it's a pandas NaT or similar invalid datetime
        if hasattr(value, 'isna') and value.isna():
            return None
        # Check for string representation of NaT
        if isinstance(value, str) and value == 'NaT':
            return None
        # Check for pandas Timestamp NaT by checking the string representation
        if str(value) == 'NaT':
            return None
        # Check for numpy NaN
        import math
        if isinstance(value, float) and math.isnan(value):
            return None
        # Check for numpy.nan specifically
        if hasattr(value, '__module__') and 'numpy' in str(value.__module__):
            try:
                import numpy as np
                if value is np.nan or (isinstance(value, float) and math.isnan(value)):
                    return None
            except ImportError:
                pass
    except (AttributeError, TypeError):
        pass  # Not a datetime-like object, continue processing

    # BIT(1) / tinyint / bytes usados como flags booleanos
    if column_name in (
        "activo",
        "eliminado",
        "enviada",
        "leido",
        "revisado",
        "completed",
        "enviado",
    ):
        if isinstance(value, (bytes, bytearray)):
            # Convert bytes to boolean (b'\x01' -> True, b'\x00' -> False)
            return bool(value[0]) if len(value) > 0 else False
        elif isinstance(value, int):
            return bool(value)
        elif isinstance(value, str):
            return value in ('1', 'true', 'True', 'TRUE')
        else:
            return bool(value)

    if isinstance(value, (bytes, bytearray)) and column_name in ("desde", "hasta"):
        return bytes(value)

    if column_name == "embedding_vector":
        return value

    if isinstance(value, str):
        if table_name == "disposicion_contenido" and column_name == "contenido":
            return value
        return value.strip() if value else None

    return value


def transform_row_mysql_to_postgres(
    row: Dict[str, Any], table_name: str
) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    for col, val in row.items():
        try:
            out[col] = transform_mysql_value_to_postgres(val, col, table_name)
        except Exception as e:
            logger.warning(
                "Error transformando %s.%s: %s — se preserva valor original",
                table_name,
                col,
                e,
            )
            out[col] = val
    return out


def validate_row_before_insert(row: Dict[str, Any], table_name: str) -> bool:
    if table_name == "cuenta" and row.get("id") is None:
        logger.error("Falta id en cuenta")
        return False
    if table_name == "disposicion" and not row.get("url"):
        logger.error("Falta url en disposicion")
        return False
    return True


def ensure_migration_errors_table(conn: Connection) -> None:
    conn.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS public.migration_errors (
                id bigserial PRIMARY KEY,
                migration_run_id varchar(64) NOT NULL,
                table_name text NOT NULL,
                row_id text,
                error_message text,
                row_data jsonb,
                error_timestamp timestamptz NOT NULL DEFAULT now()
            );
            """
        )
    )


def log_migration_error(
    engine: Engine,
    migration_run_id: str,
    table_name: str,
    error_msg: str,
    row_id: Optional[str] = None,
    row_data: Optional[Dict[str, Any]] = None,
) -> None:
    import json
    import math

    def safe_json_serializer(obj):
        """Handle NaN and other problematic values for PostgreSQL JSON."""
        if isinstance(obj, float) and math.isnan(obj):
            return None
        if isinstance(obj, (bytes, bytearray)):
            return obj.hex()
        return str(obj)

    conn = engine.connect()
    try:
        with conn.begin():
            ensure_migration_errors_table(conn)
            row_json = json.dumps(row_data, default=safe_json_serializer) if row_data else None
            params = {
                "run_id": migration_run_id,
                "tbl": table_name,
                "rid": row_id,
                "msg": error_msg[:8000],
            }
            if row_json is None:
                conn.execute(
                    text(
                        """
                        INSERT INTO public.migration_errors
                        (migration_run_id, table_name, row_id, error_message, row_data)
                        VALUES (:run_id, :tbl, :rid, :msg, NULL)
                        """
                    ),
                    params,
                )
            else:
                params["data"] = row_json
                conn.execute(
                    text(
                        """
                        INSERT INTO public.migration_errors
                        (migration_run_id, table_name, row_id, error_message, row_data)
                        VALUES (:run_id, :tbl, :rid, :msg, CAST(:data AS jsonb))
                        """
                    ),
                    params,
                )
    except Exception as e:
        logger.error("Failed to log migration error: %s", e)
    finally:
        conn.close()


def quote_pg_ident(name: str) -> str:
    """Identificador PostgreSQL entre comillas dobles."""
    return '"' + name.replace('"', '""') + '"'


def build_insert_sql(table_name: str, columns: list[str]) -> str:
    """INSERT ... ON CONFLICT (id) DO NOTHING (PK `id` en todas las tablas del DDL)."""
    cols = ", ".join(quote_pg_ident(c) for c in columns)
    placeholders = ", ".join(f":{c}" for c in columns)
    return (
        f"INSERT INTO public.{quote_pg_ident(table_name)} ({cols}) VALUES ({placeholders}) "
        "ON CONFLICT (id) DO NOTHING"
    )
