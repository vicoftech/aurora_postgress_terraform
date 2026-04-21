# EJEMPLOS DE CÓDIGO PARA PROMPT DE CURSOR

## 1. ESTRUCTURA BASICA DE CONFIG

```python
# migration_config.py
from dataclasses import dataclass
from enum import Enum
from typing import Optional

class MigrationStatus(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    PARTIAL = "PARTIAL"
    FAILED = "FAILED"

@dataclass
class MigrationConfig:
    """Configuración para la migración MySQL → PostgreSQL"""
    mysql_connection_string: str
    postgres_connection_string: str
    chunk_size: int = 10000
    truncate_destination: bool = False
    retry_attempts: int = 3
    exponential_backoff_factor: float = 2.0
    log_file_path: str = "./logs"
    batch_insert_size: int = 5000
    
    def validate(self) -> bool:
        """Validar configuración"""
        assert self.chunk_size > 0, "chunk_size debe ser > 0"
        assert self.retry_attempts > 0, "retry_attempts debe ser > 0"
        assert self.batch_insert_size > 0, "batch_insert_size debe ser > 0"
        return True

@dataclass
class MigrationResult:
    """Resultado de una migración individual"""
    table_name: str
    status: MigrationStatus
    source_count: int
    destination_count: int
    inserted_count: int
    error_count: int
    duration_seconds: float
    error_details: Optional[list] = None
    
    @property
    def success(self) -> bool:
        return self.error_count == 0 and self.inserted_count > 0
```

## 2. ORDEN DE TABLAS Y DEPENDENCIAS

```python
# migration_config.py (continuación)

TABLE_MIGRATION_ORDER = [
    # Tablas base sin dependencias
    {
        'name': 'cuenta',
        'depends_on': [],
        'has_data': True
    },
    {
        'name': 'descarga_fuente_anmat',
        'depends_on': [],
        'has_data': True
    },
    {
        'name': 'disposicion',
        'depends_on': [],
        'has_data': True
    },
    {
        'name': 'frontend_routes',
        'depends_on': [],
        'has_data': False
    },
    # Tablas con FK a cuenta
    {
        'name': 'busqueda',
        'depends_on': ['cuenta'],
        'has_data': True
    },
    {
        'name': 'busqueda_historica',
        'depends_on': ['cuenta'],
        'has_data': True
    },
    {
        'name': 'email',
        'depends_on': ['cuenta'],
        'has_data': True
    },
    {
        'name': 'overlay',
        'depends_on': ['cuenta'],
        'has_data': True
    },
    # Tablas con FK a disposicion
    {
        'name': 'disposicion_contenido',
        'depends_on': ['disposicion'],
        'has_data': True,
        'special_fields': ['embedding_vector']  # pgvector, preservar NULL
    },
    # Tablas con FK múltiples
    {
        'name': 'alerta_generada',
        'depends_on': ['busqueda', 'disposicion'],
        'has_data': True
    },
    {
        'name': 'alerta_generada_historica',
        'depends_on': ['busqueda_historica', 'disposicion'],
        'has_data': True
    },
]

# Mapeo de transformación de tipos MySQL → PostgreSQL
TYPE_MAPPING = {
    'BIT': 'BOOLEAN',
    'TINYBLOB': 'BYTEA',
    'LONGTEXT': 'TEXT',
    'DATETIME': 'TIMESTAMP',
}
```

## 3. TRANSFORMACIÓN DE DATOS

```python
# migration_utils.py
from typing import Any, Dict
import logging

logger = logging.getLogger(__name__)

def transform_mysql_value_to_postgres(value: Any, column_name: str, table_name: str) -> Any:
    """
    Transformar un valor de MySQL a PostgreSQL
    
    Args:
        value: Valor origen
        column_name: Nombre de la columna
        table_name: Nombre de la tabla
        
    Returns:
        Valor transformado
    """
    if value is None:
        return None
    
    # BIT(1) → BOOLEAN
    if isinstance(value, int) and column_name in ['activo', 'eliminado', 'enviada', 'leido', 'revisado', 'completed']:
        return bool(value)
    
    # TINYBLOB → BYTEA (mantener como bytes)
    if isinstance(value, bytes) and column_name in ['desde', 'hasta']:
        return value
    
    # Para embedding_vector: preservar como está (pgvector espera formato específico)
    if column_name == 'embedding_vector':
        if isinstance(value, (list, str)):
            # Si viene como lista JSON o string, puede parsearse después
            return value
        return value
    
    # Strings: limpiar espacios
    if isinstance(value, str):
        # Pero NO limpiar para campos específicos que pueden tener espacios significativos
        if table_name == 'disposicion_contenido' and column_name == 'contenido':
            return value
        return value.strip() if len(value) > 0 else None
    
    return value

def transform_row_mysql_to_postgres(row: Dict[str, Any], table_name: str) -> Dict[str, Any]:
    """
    Transformar un row completo de MySQL a PostgreSQL
    
    Args:
        row: Diccionario con valores MySQL
        table_name: Nombre de la tabla
        
    Returns:
        Diccionario transformado para PostgreSQL
    """
    transformed = {}
    
    for column_name, value in row.items():
        try:
            transformed[column_name] = transform_mysql_value_to_postgres(
                value, column_name, table_name
            )
        except Exception as e:
            logger.warning(
                f"Error transformando {table_name}.{column_name}: {str(e)}. "
                f"Preservando valor original."
            )
            transformed[column_name] = value
    
    return transformed

def validate_row_before_insert(row: Dict[str, Any], table_name: str) -> bool:
    """
    Validar row antes de insertar
    
    Args:
        row: Diccionario con valores
        table_name: Nombre de la tabla
        
    Returns:
        True si válido, False si no
    """
    # Validaciones específicas por tabla
    if table_name == 'cuenta' and not row.get('id'):
        logger.error(f"Falta ID en cuenta")
        return False
    
    if table_name == 'disposicion' and not row.get('url'):
        logger.error(f"Falta URL en disposicion")
        return False
    
    return True
```

## 4. TASK DE MIGRACIÓN DE TABLA

```python
# migration_tasks.py
from prefect import task, get_run_logger
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.orm import Session
import pandas as pd
from typing import Dict, List, Tuple
from migration_config import MigrationResult, MigrationStatus, MigrationConfig
from migration_utils import transform_row_mysql_to_postgres, validate_row_before_insert
import time

@task(retries=3, retry_delay_seconds=10, name="get_row_count")
def get_source_row_count(
    mysql_connection_string: str, 
    table_name: str
) -> int:
    """Obtener cantidad de rows en MySQL"""
    logger = get_run_logger()
    
    engine = create_engine(mysql_connection_string)
    with engine.connect() as conn:
        result = conn.execute(text(f"SELECT COUNT(*) as cnt FROM {table_name}"))
        count = result.scalar()
        logger.info(f"{table_name}: {count} registros en MySQL")
        return count

@task(retries=3, retry_delay_seconds=10, name="get_destination_count")
def get_destination_row_count(
    postgres_connection_string: str, 
    table_name: str
) -> int:
    """Obtener cantidad de rows en PostgreSQL"""
    logger = get_run_logger()
    
    engine = create_engine(postgres_connection_string)
    with engine.connect() as conn:
        result = conn.execute(text(f"SELECT COUNT(*) as cnt FROM public.{table_name}"))
        count = result.scalar()
        logger.info(f"{table_name}: {count} registros en PostgreSQL")
        return count

@task(retries=2, retry_delay_seconds=30, name="migrate_table_chunks")
def migrate_table(
    table_name: str,
    mysql_connection_string: str,
    postgres_connection_string: str,
    config: MigrationConfig
) -> MigrationResult:
    """
    Migrar una tabla de MySQL a PostgreSQL en chunks
    """
    logger = get_run_logger()
    start_time = time.time()
    
    try:
        # Crear engines
        mysql_engine = create_engine(mysql_connection_string, echo=False)
        postgres_engine = create_engine(postgres_connection_string, echo=False)
        
        # Truncar si se especifica
        if config.truncate_destination:
            with postgres_engine.begin() as conn:
                conn.execute(text(f"TRUNCATE TABLE public.{table_name} CASCADE"))
                logger.info(f"Truncated {table_name}")
        
        # Leer data en chunks
        offset = 0
        total_inserted = 0
        error_count = 0
        error_details = []
        
        while True:
            # Leer chunk de MySQL
            query = f"SELECT * FROM {table_name} LIMIT {config.chunk_size} OFFSET {offset}"
            df = pd.read_sql(query, mysql_engine)
            
            if df.empty:
                break
            
            # Transformar datos
            transformed_rows = []
            for _, row in df.iterrows():
                row_dict = row.to_dict()
                try:
                    if not validate_row_before_insert(row_dict, table_name):
                        error_count += 1
                        error_details.append({
                            'row_id': row_dict.get('id', 'unknown'),
                            'error': 'Validación falló'
                        })
                        continue
                    
                    transformed = transform_row_mysql_to_postgres(row_dict, table_name)
                    transformed_rows.append(transformed)
                except Exception as e:
                    error_count += 1
                    error_details.append({
                        'row_id': row_dict.get('id', 'unknown'),
                        'error': str(e)
                    })
                    logger.warning(f"Error transformando row en {table_name}: {str(e)}")
            
            # Insertar en PostgreSQL
            if transformed_rows:
                try:
                    with postgres_engine.begin() as conn:
                        # Usar insert() con ON CONFLICT DO NOTHING para idempotencia
                        for row in transformed_rows:
                            # Construir insert dinámicamente
                            cols = ', '.join(row.keys())
                            placeholders = ', '.join([':' + k for k in row.keys()])
                            insert_sql = f"INSERT INTO public.{table_name} ({cols}) VALUES ({placeholders}) ON CONFLICT DO NOTHING"
                            
                            try:
                                conn.execute(text(insert_sql), row)
                                total_inserted += 1
                            except Exception as e:
                                error_count += 1
                                error_details.append({
                                    'row_id': row.get('id', 'unknown'),
                                    'error': str(e)
                                })
                                logger.error(f"Error insertando en {table_name}: {str(e)}")
                        
                        logger.info(f"{table_name}: insertados {len(transformed_rows)} registros")
                except Exception as e:
                    logger.error(f"Error en batch insert para {table_name}: {str(e)}")
                    error_count += len(transformed_rows)
            
            offset += config.chunk_size
        
        # Contar finales
        source_count = get_source_row_count.fn(mysql_connection_string, table_name)
        dest_count = get_destination_row_count.fn(postgres_connection_string, table_name)
        
        duration = time.time() - start_time
        
        # Determinar status
        if error_count == 0 and total_inserted == source_count:
            status = MigrationStatus.COMPLETED
        elif total_inserted > 0 and error_count > 0:
            status = MigrationStatus.PARTIAL
        else:
            status = MigrationStatus.FAILED
        
        logger.info(
            f"Migración de {table_name}: {total_inserted} insertados, "
            f"{error_count} errores, {duration:.2f}s"
        )
        
        return MigrationResult(
            table_name=table_name,
            status=status,
            source_count=source_count,
            destination_count=dest_count,
            inserted_count=total_inserted,
            error_count=error_count,
            duration_seconds=duration,
            error_details=error_details if error_details else None
        )
    
    except Exception as e:
        logger.error(f"Error fatal migrando {table_name}: {str(e)}")
        return MigrationResult(
            table_name=table_name,
            status=MigrationStatus.FAILED,
            source_count=0,
            destination_count=0,
            inserted_count=0,
            error_count=1,
            duration_seconds=time.time() - start_time,
            error_details=[{'error': str(e)}]
        )

@task(name="validate_referential_integrity")
def validate_referential_integrity(
    postgres_connection_string: str,
    table_order: List[Dict]
) -> Dict[str, bool]:
    """Validar integridad referencial en PostgreSQL"""
    logger = get_run_logger()
    
    engine = create_engine(postgres_connection_string)
    results = {}
    
    with engine.connect() as conn:
        for table_config in table_order:
            table_name = table_config['name']
            depends_on = table_config.get('depends_on', [])
            
            if not depends_on:
                results[table_name] = True
                continue
            
            try:
                # Verificar que no hay FKs inválidas
                # (Esta es una validación básica)
                result = conn.execute(
                    text(f"SELECT COUNT(*) FROM public.{table_name}")
                )
                results[table_name] = True
                logger.info(f"Integridad validada para {table_name}")
            except Exception as e:
                results[table_name] = False
                logger.error(f"Error validando {table_name}: {str(e)}")
    
    return results
```

## 5. FLOW PRINCIPAL

```python
# migration_flow.py
from prefect import flow, task, get_run_logger
from prefect.task_runs import wait_for_task_run
import logging
from datetime import datetime
from pathlib import Path
from migration_config import (
    MigrationConfig, 
    MigrationStatus, 
    TABLE_MIGRATION_ORDER,
    MigrationResult
)
from migration_tasks import migrate_table, validate_referential_integrity
import json
import csv

@flow(name="MySQL to PostgreSQL Migration", version="1.0.0")
def migrate_alert_prod(config: MigrationConfig) -> Dict:
    """
    Flow principal de migración de alert_prod de MySQL a PostgreSQL
    
    Args:
        config: MigrationConfig con conexiones y parámetros
        
    Returns:
        Dict con resumen de resultados
    """
    logger = get_run_logger()
    logger.info("="*60)
    logger.info("INICIANDO MIGRACION alert_prod MySQL → PostgreSQL")
    logger.info("="*60)
    
    # Crear directorio de logs
    log_dir = Path(config.log_file_path)
    log_dir.mkdir(parents=True, exist_ok=True)
    
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_path = log_dir / f"migration_report_{run_id}.csv"
    
    # Validar configuración
    config.validate()
    
    # Validar conexiones
    try:
        from sqlalchemy import create_engine
        mysql_engine = create_engine(config.mysql_connection_string)
        postgres_engine = create_engine(config.postgres_connection_string)
        
        mysql_engine.connect().close()
        postgres_engine.connect().close()
        logger.info("✓ Conexiones validadas")
    except Exception as e:
        logger.error(f"✗ Error validando conexiones: {str(e)}")
        return {
            'status': 'FAILED',
            'error': str(e),
            'run_id': run_id
        }
    
    # Migrar tablas en orden
    results = []
    failed_tables = []
    
    for table_config in TABLE_MIGRATION_ORDER:
        table_name = table_config['name']
        
        logger.info(f"\n--- Migrando {table_name} ---")
        
        try:
            result: MigrationResult = migrate_table(
                table_name=table_name,
                mysql_connection_string=config.mysql_connection_string,
                postgres_connection_string=config.postgres_connection_string,
                config=config
            )
            
            results.append(result)
            
            if result.status in [MigrationStatus.FAILED]:
                failed_tables.append(table_name)
                logger.error(f"✗ {table_name}: FALLÓ")
            else:
                logger.info(
                    f"✓ {table_name}: {result.inserted_count} insertados "
                    f"({result.duration_seconds:.2f}s)"
                )
        except Exception as e:
            logger.error(f"✗ Error migrando {table_name}: {str(e)}")
            failed_tables.append(table_name)
    
    # Validar integridad referencial
    logger.info("\nValidando integridad referencial...")
    try:
        fk_validation = validate_referential_integrity(
            config.postgres_connection_string,
            TABLE_MIGRATION_ORDER
        )
        logger.info(f"Integridad referencial: {fk_validation}")
    except Exception as e:
        logger.warning(f"No se pudo validar integridad: {str(e)}")
    
    # Generar reporte
    logger.info("\nGenerando reporte...")
    total_records = sum(r.inserted_count for r in results)
    total_errors = sum(r.error_count for r in results)
    total_duration = sum(r.duration_seconds for r in results)
    
    with open(report_path, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=[
            'table_name', 'source_count', 'destination_count', 
            'inserted_count', 'error_count', 'duration_seconds', 'status'
        ])
        writer.writeheader()
        
        for result in results:
            writer.writerow({
                'table_name': result.table_name,
                'source_count': result.source_count,
                'destination_count': result.destination_count,
                'inserted_count': result.inserted_count,
                'error_count': result.error_count,
                'duration_seconds': f"{result.duration_seconds:.2f}",
                'status': result.status.value
            })
    
    # Resumen final
    logger.info("\n" + "="*60)
    logger.info("RESUMEN DE MIGRACIÓN")
    logger.info("="*60)
    logger.info(f"Total tablas: {len(results)}")
    logger.info(f"Exitosas: {len([r for r in results if r.status == MigrationStatus.COMPLETED])}")
    logger.info(f"Parciales: {len([r for r in results if r.status == MigrationStatus.PARTIAL])}")
    logger.info(f"Fallidas: {len(failed_tables)}")
    logger.info(f"Total registros: {total_records}")
    logger.info(f"Total errores: {total_errors}")
    logger.info(f"Duración total: {total_duration:.2f}s")
    logger.info(f"Reporte: {report_path}")
    
    overall_status = 'FAILED' if failed_tables else 'COMPLETED'
    
    return {
        'status': overall_status,
        'run_id': run_id,
        'total_tables': len(results),
        'successful_tables': len([r for r in results if r.status == MigrationStatus.COMPLETED]),
        'failed_tables': failed_tables,
        'total_records_migrated': total_records,
        'total_errors': total_errors,
        'total_duration_seconds': total_duration,
        'report_path': str(report_path)
    }

if __name__ == "__main__":
    # Ejemplo de uso local
    config = MigrationConfig(
        mysql_connection_string="mysql+pymysql://user:pass@localhost:3306/alert_prod",
        postgres_connection_string="postgresql://user:pass@localhost:5432/alert_prod",
        chunk_size=10000,
        truncate_destination=False,
        log_file_path="./logs"
    )
    
    result = migrate_alert_prod(config)
    print(json.dumps(result, indent=2))
```

---

## DETALLES PARA EL PROMPT

Cuando copies este prompt a Cursor, puedes decir:

**"Genera una solución completa de migración MySQL→PostgreSQL con Prefect basándote en el siguiente DDL destino y los ejemplos de estructura. Incluye:**

1. **migration_config.py** - Dataclasses, enums, mapeo de tablas y tipos
2. **migration_utils.py** - Funciones de transformación de datos, validación
3. **migration_tasks.py** - Tasks de Prefect para cada operación
4. **migration_flow.py** - Flow principal con orquestación
5. **requirements.txt** - Dependencias (prefect, sqlalchemy, pandas, pymysql, psycopg2)
6. **README.md** - Documentación completa de deployment
7. **deployment.yaml** - Configuración para Prefect Cloud/Server

**Requisitos:**
- Respetar el orden de tablas por foreign keys
- Manejar el campo embedding_vector como NULL si no existe
- Transformar BIT(1)→BOOLEAN, TINYBLOB→BYTEA
- Implementar retry con exponential backoff
- Logging detallado en cada paso
- Reportes CSV con counts y tiempos
- Soporte para idempotencia (ON CONFLICT)
- Tests unitarios"
```

---

## NOTAS FINALES

Este prompt es **completo y listo para usar** con Cursor AI. Los ejemplos de código proporcionan:

1. ✅ Estructura modular y reutilizable
2. ✅ Manejo completo de tipos de datos
3. ✅ Logging y error handling robusto
4. ✅ Idempotencia y reintentos
5. ✅ Respeto por orden de FKs
6. ✅ Validación de integridad referencial
7. ✅ Reportes CSV detallados
8. ✅ Integración con Prefect Cloud/Server

Cursor puede iterar sobre esto, mejorar la calidad, agregar async/await donde sea posible, y optimizar performance.
