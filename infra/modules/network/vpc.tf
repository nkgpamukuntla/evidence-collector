# One VPC, four subnet tiers, each with its own route table:
#   evaluator  no route off the VPC (R6); S3 via the gateway endpoint only
#   public     NAT gateways and the internet gateway, nothing else
#   worker     default route via NAT; names restricted by DNS Firewall
#   db         local only
# Each tier takes a block of 4 /20 netnums (on a /16), one per AZ.
locals {
  az_count = length(var.availability_zones)
  newbits  = 4
  netnums = {
    evaluator = [for i in range(local.az_count) : 0 + i]
    public    = [for i in range(local.az_count) : 4 + i]
    worker    = [for i in range(local.az_count) : 8 + i]
    db        = [for i in range(local.az_count) : 12 + i]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

# The default security group keeps no rules, so nothing can fall back to it.
resource "aws_default_security_group" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-default-unused" }
}

# ---------- evaluator: no route off the VPC ----------
resource "aws_subnet" "evaluator" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.newbits, local.netnums.evaluator[count.index])
  tags              = { Name = "${var.name_prefix}-evaluator-${count.index}" }
}

resource "aws_route_table" "evaluator" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-evaluator-local-only" }
}

resource "aws_route_table_association" "evaluator" {
  count          = local.az_count
  subnet_id      = aws_subnet.evaluator[count.index].id
  route_table_id = aws_route_table.evaluator.id
}

# ---------- public: NAT only ----------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.newbits, local.netnums.public[count.index])
  tags              = { Name = "${var.name_prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = local.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Cost: ~$33/month per NAT gateway plus data. 1 in dev, one per AZ in prod.
resource "aws_eip" "nat" {
  count  = var.nat_gateway_count
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-${count.index}" }
}

resource "aws_nat_gateway" "main" {
  count         = var.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${var.name_prefix}-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.main]
}

# ---------- worker: egress via NAT (R6) ----------
resource "aws_subnet" "worker" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.newbits, local.netnums.worker[count.index])
  tags              = { Name = "${var.name_prefix}-worker-${count.index}" }
}

resource "aws_route_table" "worker" {
  count  = local.az_count
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-worker-${count.index}" }
}

resource "aws_route" "worker_default" {
  count                  = local.az_count
  route_table_id         = aws_route_table.worker[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[min(count.index, var.nat_gateway_count - 1)].id
}

resource "aws_route_table_association" "worker" {
  count          = local.az_count
  subnet_id      = aws_subnet.worker[count.index].id
  route_table_id = aws_route_table.worker[count.index].id
}

# ---------- db: local only ----------
resource "aws_subnet" "db" {
  count             = local.az_count
  vpc_id            = aws_vpc.main.id
  availability_zone = var.availability_zones[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, local.newbits, local.netnums.db[count.index])
  tags              = { Name = "${var.name_prefix}-db-${count.index}" }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-db-local-only" }
}

resource "aws_route_table_association" "db" {
  count          = local.az_count
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}
