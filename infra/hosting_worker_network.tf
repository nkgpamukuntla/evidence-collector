# Worker network (R6): own subnets + own route tables, egress via NAT,
# kept apart from the evaluator's no-route subnets.
resource "aws_internet_gateway" "main" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count             = length(var.availability_zones)
  vpc_id            = local.vpc_id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, local.public_netnums[count.index])
  tags              = { Name = "${local.name_prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-${count.index}" }
}

resource "aws_nat_gateway" "worker" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${local.name_prefix}-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_subnet" "worker" {
  count             = length(var.availability_zones)
  vpc_id            = local.vpc_id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.subnet_newbits, local.worker_netnums[count.index])
  tags              = { Name = "${local.name_prefix}-worker-${count.index}" }
}

resource "aws_route_table" "worker" {
  count  = length(aws_subnet.worker)
  vpc_id = local.vpc_id
  tags   = { Name = "${local.name_prefix}-worker-${count.index}" }
}

resource "aws_route" "worker_default" {
  count                  = length(aws_route_table.worker)
  route_table_id         = aws_route_table.worker[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.worker[min(count.index, var.nat_gateway_count - 1)].id
}

resource "aws_route_table_association" "worker" {
  count          = length(aws_subnet.worker)
  subnet_id      = aws_subnet.worker[count.index].id
  route_table_id = aws_route_table.worker[count.index].id
}

# Worker's S3 PUTs stay on the gateway endpoint (its policy admits the raw bucket only).
resource "aws_vpc_endpoint_route_table_association" "worker_s3" {
  count           = length(aws_route_table.worker)
  vpc_endpoint_id = local.s3_gateway_endpoint
  route_table_id  = aws_route_table.worker[count.index].id
}

resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-worker"
  description = "Worker tasks: HTTPS out (names restricted by DNS Firewall), Postgres to RDS"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_egress_rule" "worker_https" {
  security_group_id = aws_security_group.worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "worker_db" {
  security_group_id            = aws_security_group.worker.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

# DNS Firewall: the VPC resolver only answers the allowlist.
resource "aws_route53_resolver_firewall_domain_list" "allow" {
  name    = "${local.name_prefix}-allow"
  domains = compact(concat(var.worker_allowed_domains, [var.heartbeat_domain]))
}

resource "aws_route53_resolver_firewall_domain_list" "all" {
  name    = "${local.name_prefix}-all"
  domains = ["*"]
}

resource "aws_route53_resolver_firewall_rule_group" "egress" {
  name = "${local.name_prefix}-egress"
}

resource "aws_route53_resolver_firewall_rule" "allow" {
  name                               = "allow-listed"
  firewall_rule_group_id             = aws_route53_resolver_firewall_rule_group.egress.id
  firewall_domain_list_id            = aws_route53_resolver_firewall_domain_list.allow.id
  action                             = "ALLOW"
  priority                           = 100
  firewall_domain_redirection_action = "TRUST_REDIRECTION_DOMAIN" # Microsoft hosts CNAME through other domains
}

resource "aws_route53_resolver_firewall_rule" "block" {
  name                    = "block-rest"
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.egress.id
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.all.id
  action                  = "BLOCK"
  block_response          = "NODATA"
  priority                = 200
}

resource "aws_route53_resolver_firewall_rule_group_association" "vpc" {
  name                   = "${local.name_prefix}-egress"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.egress.id
  vpc_id                 = local.vpc_id
  priority               = 200
}
