# Aurora PostgreSQL — Instalación (producción)

Terraform despliega en AWS: **VPC**, **Aurora PostgreSQL**, **grupos de seguridad**, **bastión EC2** (subred pública), **monitoreo** y **alarmas**. El estado remoto vive en **S3** + bloqueos en **DynamoDB** (`terraform-locks`).

Los valores concretos de red y DNS dependen del despliegue; para **endpoints y credenciales** usa siempre los comandos de [Endpoints](#1-endpoints) y [Credenciales](#2-credenciales).

---

## 1) Endpoints

Tras el despliegue, los hostnames salen de Terraform (desde la raíz del repo):

```bash
export AWS_PROFILE=asap_main   # o el perfil que uses
cd /ruta/al/proyecto

terraform output -raw cluster_endpoint
terraform output -raw cluster_reader_endpoint
```

| Uso | Descripción |
|-----|-------------|
| **Escritura** | `cluster_endpoint` — endpoint del clúster (writer). Puerto **5432**. |
| **Lectura** | `cluster_reader_endpoint` — solo lectura (réplicas). Puerto **5432**. |

Endpoints por instancia (depuración / operación):

```bash
terraform output -json all_instance_endpoints
```

Patrón DNS típico de Aurora:

- Clúster (writer): `<cluster_identifier>.cluster-<hash>.<region>.rds.amazonaws.com`
- Solo lectura: `<cluster_identifier>.cluster-ro-<hash>.<region>.rds.amazonaws.com`

**Región de producción** (según `environments/prod/terraform.tfvars`): **`us-east-1`**.

---

## 2) Credenciales

| Concepto | Detalle |
|----------|---------|
| **Usuario maestro** | `master_username` en `environments/prod/terraform.tfvars` (en prod suele ser `postgres`). |
| **Contraseña maestro** | `master_password` en ese mismo archivo (variable de Terraform; **sensible**). No se genera con `random_password`; la defines tú en el `tfvars` o la inyectas por CI/secretos. |

Obtener la contraseña que Terraform tiene en estado (debe coincidir con la del `tfvars` aplicado):

```bash
terraform output -raw master_password
```

**Recomendación:** no versionar contraseñas reales en Git; usar **AWS Secrets Manager** (o parámetros seguros) y rotar según política. El estado en S3 puede contener datos sensibles: restringir IAM al bucket de estado y a la tabla de locks.

**Autenticación IAM a la base:** el clúster tiene **`iam_database_authentication_enabled = true`** (`modules/aurora_cluster/main.tf`). Las aplicaciones pueden usar tokens IAM además de usuario/contraseña, según el diseño.

---

## 3) Bastión EC2

Hay un **bastión** en la **primera subred pública** (instancia pequeña, por defecto `t3.micro`, AMI **Amazon Linux 2023**). Sirve para administrar Aurora desde **la misma VPC** (Aurora no es accesible desde Internet directo).

| Tema | Detalle |
|------|---------|
| **SSM Session Manager** | Rol IAM con `AmazonSSMManagedInstanceCore`. Conexión sin abrir SSH: `aws ssm start-session --target $(terraform output -raw bastion_instance_id) --region us-east-1` |
| **SSH** | Opcional: `bastion_key_name` (key pair EC2) + `bastion_ssh_cidrs` con tu IP pública en `/32`. Sin reglas de entrada al **22**, el cliente suele ver **timeout**. Usuario SSH en Amazon Linux: **`ec2-user`**. |
| **Cliente `psql`** | Por defecto se instala `postgresql15` vía user-data (`bastion_install_postgresql_client`). |
| **RDS** | Regla en el SG de Aurora: **5432 desde el security group del bastión** (`postgres_from_bastion` en `main.tf`). |

Outputs útiles:

```bash
terraform output -raw bastion_instance_id
terraform output -raw bastion_public_ip
terraform output -raw bastion_security_group_id
```

**Conexión típica a la base desde el bastión** (misma VPC; usar el writer endpoint y la base `database_name`):

```bash
psql -h "$(terraform output -raw cluster_endpoint)" -U postgres -d "$(terraform output -raw database_name)" -p 5432
```

Variables relacionadas (raíz `variables.tf`): `bastion_instance_type`, `bastion_ssh_cidrs`, `bastion_key_name`, `bastion_install_postgresql_client`.

**CIDRs extra hacia PostgreSQL** (VPN, oficina): lista opcional `postgres_ingress_cidrs` en el `tfvars` (además del SG de app y del bastión).

---

## 4) Proyecto y nombres (producción actual)

Valores orientativos según `environments/prod/terraform.tfvars` (ajustar si cambiáis el archivo):

| Campo | Ejemplo en prod |
|-------|-------------------|
| `project_name` | `alert` |
| `aurora_cluster_name` | `postgres-aurora-prod` |
| `database_name` | `alert_db` |
| `availability_zones` | `us-east-1a`, `us-east-1b` |
| Cifrado RDS | `storage_encrypted = true`, `kms_key_id` (ARN de KMS en la región) |

---

## 5) “Family” y servidores (motor e instancias)

| Elemento | Valor en esta instalación |
|----------|---------------------------|
| **Motor** | `aurora-postgresql` |
| **Versión de motor** | `aurora_engine_version` en `terraform.tfvars` (p. ej. **15.17**). Comprobar con `terraform output engine_version`. |
| **Familia del parameter group** | `aurora-postgresql15` (`modules/aurora_cluster/main.tf`) |
| **Modo** | `provisioned` (no Serverless v2) |
| **Clase de instancia** | Configurable (`aurora_instance_class`, p. ej. `db.t4g.medium` en writer y readers) |
| **Topología** | 1 **writer** + `aurora_replica_count` **readers** (en prod típicamente **1 reader**). |
| **Multi-AZ** | Instancias en las zonas de `availability_zones` (p. ej. `us-east-1a` / `us-east-1b`). |
| **Acceso público** | `publicly_accessible = false` (solo red privada / VPC). |

---

## 6) Esquema de snapshots y backups

Esta instalación usa el modelo estándar de **Aurora / RDS**:

| Tipo | Comportamiento |
|------|----------------|
| **Backups automáticos continuos** | Aurora mantiene backups continuos dentro de la **ventana de retención** configurada. |
| **Retención** | `backup_retention_days` (en prod: **30 días**). |
| **Ventana de backup** | `backup_window` (en prod: **02:00–03:00 UTC**). |
| **Ventana de mantenimiento** | `maintenance_window` (en prod: **domingo 03:00–04:00 UTC**). |
| **Copia de etiquetas** | `copy_tags_to_snapshot = true` en el clúster. |
| **Snapshot final al borrar** | `skip_final_snapshot = false` y snapshot final con identificador fijo; al destruir con Terraform, RDS intenta crear ese snapshot (revisar conflictos si ya existiera uno con el mismo nombre). |
| **PITR** | Dentro del período de retención podéis restaurar a un momento concreto desde consola RDS o API. |

No hay en este repo un flujo separado de “exportar snapshot a S3” para archivo largo; sería un paso adicional.

---

## 7) ¿Dónde se guardan los snapshots? ¿En un bucket?

- Los **backups automáticos y snapshots de clúster** de Aurora están en la **infraestructura gestionada por AWS RDS/Aurora**, no en un bucket S3 vuestro por defecto.
- El bucket **`terraform-state-<account>-aurora-<region>`** guarda el **estado de Terraform** (y locks en DynamoDB), **no** los datos ni los snapshots de la base.

---

## 8) Ciclo de vida: ¿los snapshots caducan o se “pisan”?

- **Backups automáticos (dentro de la retención):** RDS/Aurora **rota** los puntos de recuperación; al superar los días configurados, los más antiguos dejan de estar disponibles para restauración.
- **Snapshots manuales:** no caducan solos salvo borrado o políticas externas.
- **Snapshot final** al eliminar el clúster: persiste con el identificador configurado hasta que lo borréis.

---

## 9) ¿Dónde ver el monitoreo?

| Capa | Dónde verlo |
|------|-------------|
| **Métricas y alarmas (CloudWatch)** | **CloudWatch → Alarms** — prefijo del identificador de clúster (p. ej. `postgres-aurora-prod-high-cpu`, `...-high-connections`). |
| **Dashboard** | **CloudWatch → Dashboards** — `<cluster_identifier>-dashboard`. |
| **Performance Insights** | **RDS → clúster → Performance Insights** (retención en días según variable). |
| **Enhanced Monitoring** | **RDS → Monitoring** de la instancia. |
| **Logs de PostgreSQL** | **CloudWatch Logs** — `/aws/rds/cluster/<cluster_identifier>/postgresql`. |
| **Notificaciones** | **SNS** `<cluster_identifier>-alerts`; la suscripción por email requiere **confirmación** (`alarm_email`). |
| **Eventos RDS** | Suscripción de eventos al clúster; revisar **RDS → Events**. |

Ejemplo (ajusta región y prefijo):

```bash
aws cloudwatch describe-alarms --alarm-name-prefix postgres-aurora-prod --region us-east-1
```

---

## 10) Máximo de conexiones simultáneas

- En **`environments/prod/terraform.tfvars`** suele definirse `max_connections` (p. ej. **100**).
- Se aplica vía **cluster parameter group**; los cambios pueden requerir **reinicio** según Aurora.

La alarma `*-high-connections` usa `max_connections * (connection_threshold_percent / 100)` (por defecto **80%**).

Para el valor efectivo en sesión:

```sql
SHOW max_connections;
```

---

## Archivos de referencia

| Ruta | Contenido |
|------|-----------|
| `environments/prod/terraform.tfvars` | Valores de producción (región, nombres, bastión, RDS, KMS). |
| `main.tf` | Orquestación: networking, app SG, security, **bastión**, regla Postgres desde bastión, Aurora, monitoring. |
| `variables.tf` | Variables raíz (incl. bastión y `postgres_ingress_cidrs`). |
| `outputs.tf` | Endpoints, bastión, plantillas de connection string, etc. |
| `modules/networking/` | VPC, subredes, NAT, flow logs. |
| `modules/security/` | SG de RDS, NACLs, reglas. |
| `modules/bastion/` | EC2 bastión, SG, SSM, SSH opcional. |
| `modules/aurora_cluster/` | Clúster Aurora PostgreSQL. |
| `modules/monitoring/` | Dashboard, alarmas, SNS, suscripción a eventos RDS. |

---

## Comandos rápidos

```bash
export AWS_PROFILE=asap_main
cd /ruta/al/proyecto

terraform init -upgrade                    # tras añadir módulos o providers
terraform validate
terraform plan  -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
terraform output
```

---

## Backend remoto (recordatorio)

El bloque `backend "s3" {}` en `versions.tf` se configura en **`terraform init`** con `-backend-config` (bucket, key, región, tabla DynamoDB, cifrado). Patrón de bucket: `terraform-state-<account_id>-aurora-<region>` (ver output `terraform_state_bucket_hint`).
