#!/usr/bin/env python3
"""Script para comparar conteos exactos entre MySQL INFORMATION_SCHEMA y COUNT(*)"""

import sys
from migration_config import config_from_env
from migration_tasks import _count_mysql, _count_pg
from migration_utils import quote_pg_ident
from sqlalchemy import create_engine, text


def get_information_schema_count(mysql_engine, table_name: str) -> int:
    """Obtener conteo desde INFORMATION_SCHEMA.TABLES"""
    with mysql_engine.connect() as conn:
        result = conn.execute(text("""
            SELECT TABLE_ROWS 
            FROM INFORMATION_SCHEMA.TABLES 
            WHERE TABLE_SCHEMA = DATABASE() 
            AND TABLE_NAME = :table_name
        """), {"table_name": table_name})
        return int(result.scalar() or 0)


def get_exact_count(mysql_engine, table_name: str) -> int:
    """Obtener conteo exacto con COUNT(*)"""
    return _count_mysql(mysql_engine, table_name)


def main():
    """Comparar conteos de diferentes métodos"""
    print("Comparando conteos MySQL vs PostgreSQL...")
    
    try:
        config = config_from_env()
        
        # Crear conexiones
        mysql_engine = create_engine(config.mysql_connection_string)
        pg_engine = create_engine(config.postgres_connection_string)
        
        # Tablas a comparar
        tables = [
            "cuenta",
            "descarga_fuente_anmat", 
            "disposicion",
            "frontend_routes",
            "busqueda",
            "busqueda_historica", 
            "email",
            "overlay",
            "disposicion_contenido",
            "alerta_generada",
            "alerta_generada_historica"
        ]
        
        print(f"{'Tabla':<25} {'INFO_SCHEMA':<12} {'COUNT(*)':<10} {'PostgreSQL':<12} {'Diff Info':<10} {'Diff PG':<8}")
        print("-" * 85)
        
        total_info_schema = 0
        total_exact = 0
        total_pg = 0
        
        for table in tables:
            try:
                # Obtener conteos
                info_count = get_information_schema_count(mysql_engine, table)
                exact_count = get_exact_count(mysql_engine, table)
                pg_count = _count_pg(pg_engine, table)
                
                # Calcular diferencias
                diff_info = exact_count - info_count
                diff_pg = exact_count - pg_count
                
                # Acumular totales
                total_info_schema += info_count
                total_exact += exact_count
                total_pg += pg_count
                
                # Mostrar fila con colores para diferencias
                status_info = "OK" if diff_info == 0 else f"±{diff_info}"
                status_pg = "OK" if diff_pg == 0 else f"±{diff_pg}"
                
                print(f"{table:<25} {info_count:<12} {exact_count:<10} {pg_count:<12} {status_info:<10} {status_pg:<8}")
                
            except Exception as e:
                print(f"{table:<25} ERROR: {str(e)}")
        
        print("-" * 85)
        print(f"{'TOTAL':<25} {total_info_schema:<12} {total_exact:<10} {total_pg:<12} {total_exact - total_info_schema:<10} {total_exact - total_pg:<8}")
        
        print("\n" + "="*60)
        print("ANÁLISIS:")
        print(f"1. INFO_SCHEMA vs COUNT(*): {total_info_schema:,} vs {total_exact:,} (diff: {total_exact - total_info_schema:,})")
        print(f"2. MySQL vs PostgreSQL: {total_exact:,} vs {total_pg:,} (diff: {total_exact - total_pg:,})")
        
        if total_exact == total_pg:
            print("3. MIGRACIÓN: Los conteos coinciden perfectamente!")
        else:
            print(f"3. MIGRACIÓN: Hay {total_exact - total_pg:,} filas faltantes en PostgreSQL")
        
        print("\nNOTA: INFORMATION_SCHEMA.TABLE_ROWS en MySQL es una ESTIMACIÓN")
        print("No es un conteo exacto. Use COUNT(*) para valores precisos.")
        
        return total_exact == total_pg
        
    except Exception as e:
        print(f"Error: {e}")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
