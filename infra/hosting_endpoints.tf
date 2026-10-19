# Interface endpoints so tasks in no-internet subnets can start (see network.tf notes).
# Each endpoint has its own security group.
# ALSO REQUIRED (edit network.tf, not here): add the regional ECR layer bucket
#   arn:aws:s3:::prod-${var.region}-starport-layer-bucket/*  (s3:GetObject)
# to the S3 gateway endpoint policy.
locals {
  interface_services = toset(["ecr.api", "ecr.dkr", "logs", "kms", "secretsmanager", "monitoring"])
  evaluator_needs    = toset(["ecr.api", "ecr.dkr", "logs"]) # kms already allowed by network.tf
}

resource "aws_security_group" "endpoint" {
  for_each    = local.interface_services
  name        = "${local.name_prefix}-vpce-${replace(each.key, ".", "-")}"
  description = "Interface endpoint ${each.key}"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each          = local.interface_services
  security_group_id = aws_security_group.endpoint[each.key].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_services
  vpc_id              = local.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = slice(local.evaluator_subnet_ids, 0, var.endpoint_az_count)
  security_group_ids  = [aws_security_group.endpoint[each.key].id]
  tags                = { Name = "${local.name_prefix}-vpce-${each.key}" }
}

resource "aws_vpc_security_group_egress_rule" "evaluator_to_endpoint" {
  for_each                     = local.evaluator_needs
  security_group_id            = local.evaluator_sg_id
  referenced_security_group_id = aws_security_group.endpoint[each.key].id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}
