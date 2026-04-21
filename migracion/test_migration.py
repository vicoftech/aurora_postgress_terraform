"""Tests unitarios: transformaciones, validación y SQL helpers."""

from __future__ import annotations

import pytest

from migration_utils import (
    build_insert_sql,
    execute_with_retry,
    quote_pg_ident,
    transform_mysql_value_to_postgres,
    transform_row_mysql_to_postgres,
    validate_row_before_insert,
)


def test_bit_to_bool_flags() -> None:
    assert transform_mysql_value_to_postgres(1, "activo", "cuenta") is True
    assert transform_mysql_value_to_postgres(0, "activo", "cuenta") is False


def test_embedding_passthrough() -> None:
    assert transform_mysql_value_to_postgres(None, "embedding_vector", "disposicion_contenido") is None
    v = [0.1, 0.2]
    assert transform_mysql_value_to_postgres(v, "embedding_vector", "disposicion_contenido") is v


def test_bytes_desde_hasta() -> None:
    b = b"\x00\xff"
    assert transform_mysql_value_to_postgres(b, "desde", "x") == b


def test_validate_cuenta_requires_id() -> None:
    assert validate_row_before_insert({"id": 1}, "cuenta") is True
    assert validate_row_before_insert({}, "cuenta") is False


def test_validate_disposicion_requires_url() -> None:
    assert validate_row_before_insert({"id": 1, "url": "http://x"}, "disposicion") is True
    assert validate_row_before_insert({"id": 1}, "disposicion") is False


def test_transform_row_preserves_keys() -> None:
    row = {"id": 1, "activo": 1, "nombre": "  x  "}
    out = transform_row_mysql_to_postgres(row, "cuenta")
    assert out["activo"] is True
    assert out["nombre"] == "x"


def test_quote_pg_ident() -> None:
    assert quote_pg_ident("overlay") == '"overlay"'
    assert quote_pg_ident('a"b') == '"a""b"'


def test_build_insert_sql_on_conflict() -> None:
    sql = build_insert_sql("cuenta", ["id", "nombre"])
    assert "ON CONFLICT (id) DO NOTHING" in sql
    assert 'public."cuenta"' in sql or "public.\"cuenta\"" in sql
    assert ":id" in sql and ":nombre" in sql


def test_execute_with_retry_succeeds_first() -> None:
    calls = {"n": 0}

    def f() -> int:
        calls["n"] += 1
        return 42

    w = execute_with_retry(f, retry_attempts=3, backoff_factor=2.0)
    assert w() == 42
    assert calls["n"] == 1


def test_execute_with_retry_raises_after_attempts() -> None:
    def f() -> None:
        raise RuntimeError("fail")

    w = execute_with_retry(f, retry_attempts=2, backoff_factor=1.0)
    with pytest.raises(RuntimeError, match="fail"):
        w()
