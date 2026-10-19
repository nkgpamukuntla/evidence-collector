# Portal entry: CloudFront (HTTPS on its default *.cloudfront.net certificate, so no domain
# is needed) -> VPC origin -> internal ALB -> ECS portal tasks. The ALB has no public address;
# CloudFront reaches it privately. Sign-in is Cognito with MFA required, admin-created users only.

data "aws_region" "current" {}

# ---------- internal ALB ----------
resource "aws_lb" "portal" {
  name                       = "${var.name_prefix}-portal"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = var.alb_subnet_ids
  security_groups            = [var.alb_sg_id]
  drop_invalid_header_fields = true
  idle_timeout               = 60
}

resource "aws_lb_target_group" "portal" {
  name                 = "${var.name_prefix}-portal"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 15
  health_check {
    path                = "/healthz"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.portal.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.portal.arn
  }
}

# CloudFront creates this group in the VPC for its VPC-origin ENIs; the ALB must admit it by
# reference (a CIDR rule for the VPC range does not match this traffic). Read after the origin exists.
data "aws_security_group" "cloudfront_vpc_origins" {
  vpc_id     = var.vpc_id
  name       = "CloudFront-VPCOrigins-Service-SG"
  depends_on = [aws_cloudfront_vpc_origin.portal]
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id            = var.alb_sg_id
  referenced_security_group_id = data.aws_security_group.cloudfront_vpc_origins.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  description                  = "CloudFront VPC origin"
}

# ---------- CloudFront ----------
resource "aws_cloudfront_vpc_origin" "portal" {
  vpc_origin_endpoint_config {
    name                   = "${var.name_prefix}-portal"
    arn                    = aws_lb.portal.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

locals {
  # AWS managed policies.
  cache_disabled         = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled
  cache_optimized        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized
  all_viewer_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader
  security_headers       = "67f7725c-6f97-4210-82d7-5512b31e9d03" # SecurityHeadersPolicy (HSTS etc.)
  origin_id              = "portal-alb"
}

resource "aws_cloudfront_distribution" "portal" {
  enabled         = true
  comment         = "${var.name_prefix} portal"
  price_class     = "PriceClass_100" # US, Canada, Europe edges only (cost)
  http_version    = "http2and3"
  is_ipv6_enabled = true

  origin {
    origin_id   = local.origin_id
    domain_name = aws_lb.portal.dns_name
    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.portal.id
    }
  }

  # API, sign-in and pages: never cached; cookies, headers and query strings pass through.
  default_cache_behavior {
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.cache_disabled
    origin_request_policy_id   = local.all_viewer_except_host
    response_headers_policy_id = local.security_headers
    compress                   = true
  }

  # Hashed build assets: cached at the edge.
  ordered_cache_behavior {
    path_pattern               = "/assets/*"
    target_origin_id           = local.origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    cache_policy_id            = local.cache_optimized
    response_headers_policy_id = local.security_headers
    compress                   = true
  }

  restrictions {
    geo_restriction {
      restriction_type = length(var.allowed_countries) == 0 ? "none" : "whitelist"
      locations        = var.allowed_countries
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------- Cognito ----------
resource "aws_cognito_user_pool" "portal" {
  name                     = "${var.name_prefix}-portal"
  mfa_configuration        = "ON"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = var.deletion_protection ? "ACTIVE" : "INACTIVE"

  software_token_mfa_configuration { enabled = true }

  admin_create_user_config {
    allow_admin_create_user_only = true # no self sign-up; offices are invited
  }

  password_policy {
    minimum_length                   = 14
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 3
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_domain" "portal" {
  domain       = "${var.name_prefix}-${var.account_id}"
  user_pool_id = aws_cognito_user_pool.portal.id
}

locals {
  public_url = "https://${aws_cloudfront_distribution.portal.domain_name}"
}

# Public client: authorization code + PKCE, no client secret to store.
resource "aws_cognito_user_pool_client" "portal" {
  name                                 = "${var.name_prefix}-portal"
  user_pool_id                         = aws_cognito_user_pool.portal.id
  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["${local.public_url}/auth/callback"]
  logout_urls                          = ["${local.public_url}/"]
  explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_USER_SRP_AUTH"]
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  id_token_validity                    = var.session_minutes
  access_token_validity                = 60
  refresh_token_validity               = 1
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_group" "role" {
  for_each     = toset(["platform_admin", "aoc_viewer"])
  name         = each.key
  user_pool_id = aws_cognito_user_pool.portal.id
}

# Initial administrators. Cognito emails each a temporary password; Terraform never sees one.
resource "aws_cognito_user" "admin" {
  for_each                 = toset(var.admin_emails)
  user_pool_id             = aws_cognito_user_pool.portal.id
  username                 = each.key
  desired_delivery_mediums = ["EMAIL"]
  attributes = {
    email          = each.key
    email_verified = "true"
  }
  lifecycle {
    ignore_changes = [attributes]
  }
}

resource "aws_cognito_user_in_group" "admin" {
  for_each     = aws_cognito_user.admin
  user_pool_id = aws_cognito_user_pool.portal.id
  group_name   = aws_cognito_user_group.role["platform_admin"].name
  username     = each.value.username
}
