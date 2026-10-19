# S3 gateway endpoint (free): admits the raw bucket, plus the region's ECR layer bucket
# so tasks can pull images. Associated with the evaluator and worker route tables, so the
# worker's PUTs stay off NAT too.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([aws_route_table.evaluator.id], aws_route_table.worker[*].id)
  tags              = { Name = "${var.name_prefix}-vpce-s3" }
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "RawBucketOnly"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:PutObject", "s3:GetObject", "s3:GetObjectVersion", "s3:ListBucket"]
        Resource  = [var.raw_bucket_arn, "${var.raw_bucket_arn}/*"]
      },
      {
        Sid       = "EcrImageLayers"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["arn:${var.partition}:s3:::prod-${var.region}-starport-layer-bucket/*"]
      },
    ]
  })
}

# Interface endpoints in the evaluator subnets, each with its own security group.
# Cost: ~$7.30/month per endpoint per AZ plus data.
resource "aws_security_group" "endpoint" {
  for_each    = toset(var.interface_endpoints)
  name        = "${var.name_prefix}-vpce-${replace(each.key, ".", "-")}"
  description = "Interface endpoint ${each.key}"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "endpoint_https" {
  for_each          = toset(var.interface_endpoints)
  security_group_id = aws_security_group.endpoint[each.key].id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = slice(aws_subnet.evaluator[*].id, 0, var.endpoint_az_count)
  security_group_ids  = [aws_security_group.endpoint[each.key].id]
  tags                = { Name = "${var.name_prefix}-vpce-${each.key}" }
}
