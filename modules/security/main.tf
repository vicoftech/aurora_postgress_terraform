resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for Aurora RDS"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_app" {
  description = "PostgreSQL access from application layer"

  security_group_id            = aws_security_group.rds.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.app_security_group_id

  tags = {
    Name = "PostgreSQL from App"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_trusted_cidr" {
  count = length(var.postgres_ingress_cidrs)

  description = "PostgreSQL from trusted CIDR (VPN/office/admin)"

  security_group_id = aws_security_group.rds.id
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = var.postgres_ingress_cidrs[count.index]

  tags = {
    Name = "PostgreSQL CIDR ${count.index + 1}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgresql_from_rds" {
  description = "PostgreSQL replication from other RDS nodes"

  security_group_id            = aws_security_group.rds.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.rds.id

  tags = {
    Name = "PostgreSQL from RDS"
  }
}

resource "aws_vpc_security_group_egress_rule" "dns" {
  description = "DNS resolution"

  security_group_id = aws_security_group.rds.id
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "DNS"
  }
}

resource "aws_vpc_security_group_egress_rule" "ntp" {
  description = "NTP for time synchronization"

  security_group_id = aws_security_group.rds.id
  from_port         = 123
  to_port           = 123
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "NTP"
  }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  description = "HTTPS for AWS service communication"

  security_group_id = aws_security_group.rds.id
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "HTTPS"
  }
}

resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "${var.project_name}-private-nacl"
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 100
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    protocol   = "tcp"
    rule_no    = 110
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 5432
    to_port    = 5432
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}
