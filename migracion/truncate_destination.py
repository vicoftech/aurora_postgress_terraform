#!/usr/bin/env python3
"""Script para truncar todas las tablas de la base de datos PostgreSQL de destino."""

import os
import sys
from typing import List

from sqlalchemy import create_engine, text
from migration_config import config_from_env
from migration_utils import quote_pg_ident


def get_all_tables_to_truncate() -> List[str]:
    """Lista de todas las tablas que serán truncadas antes de la migración."""
    return [
        "cuenta",
        "busqueda", 
        "busqueda_historica",
        "email",
        "overlay",
        "disposicion",
        "disposicion_contenido",
        "alerta_generada",
        "alerta_generada_historica",
        "frontend_routes",
        "migration_errors"  # También limpiar errores de migraciones anteriores
    ]


def truncate_table(engine, table_name: str) -> bool:
    """Trunca una tabla específica con manejo de errores."""
    try:
        with engine.begin() as conn:
            # Desactivar temporalmente las restricciones de clave foránea
            conn.execute(text("SET session_replication_role = 'replica'"))
            
            try:
                quoted_table = quote_pg_ident(table_name)
                truncate_sql = f"TRUNCATE TABLE public.{quoted_table} CASCADE"
                conn.execute(text(truncate_sql))
                print(f"✅ Tabla '{table_name}' truncada exitosamente")
                return True
            finally:
                # Reactivar las restricciones de clave foránea
                conn.execute(text("SET session_replication_role = 'origin'"))
                
    except Exception as e:
        print(f"❌ Error truncando tabla '{table_name}': {e}")
        return False


def main():
    """Función principal que trunca todas las tablas."""
    print("🔄 Iniciando truncado de tablas PostgreSQL...")
    
    try:
        # Cargar configuración desde variables de entorno
        config = config_from_env()
        
        # Crear conexión a PostgreSQL
        pg_engine = create_engine(config.postgres_connection_string)
        
        # Probar conexión
        with pg_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("✅ Conexión a PostgreSQL establecida")
        
        # Obtener lista de tablas a truncar
        tables = get_all_tables_to_truncate()
        print(f"📋 Se truncarán {len(tables)} tablas")
        
        # Truncar cada tabla
        success_count = 0
        error_count = 0
        
        for table_name in tables:
            if truncate_table(pg_engine, table_name):
                success_count += 1
            else:
                error_count += 1
        
        # Resumen
        print("\n" + "="*50)
        print("📊 RESUMEN DEL TRUNCADO:")
        print(f"   ✅ Tablas truncadas exitosamente: {success_count}")
        print(f"   ❌ Tablas con errores: {error_count}")
        print(f"   📋 Total tablas procesadas: {len(tables)}")
        
        if error_count == 0:
            print("\n🎉 Todas las tablas fueron truncadas exitosamente!")
            print("🚀 La base de datos está lista para una nueva migración.")
        else:
            print(f"\n⚠️  {error_count} tablas no pudieron ser truncadas.")
            print("🔍 Revisa los errores mostrados arriba.")
        
        return error_count == 0
        
    except ValueError as e:
        print(f"❌ Error de configuración: {e}")
        print("💡 Asegúrate de configurar las variables de entorno:")
        print("   - POSTGRES_CONNECTION_STRING")
        return False
        
    except Exception as e:
        print(f"❌ Error inesperado: {e}")
        return False


if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)
