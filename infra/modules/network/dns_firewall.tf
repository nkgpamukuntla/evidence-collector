# DNS Firewall: the VPC resolver only answers the allowlist; everything else gets NODATA.
# Cost: $0.60 per million queries.
resource "aws_route53_resolver_firewall_domain_list" "allow" {
  name    = "${var.name_prefix}-allow"
  domains = compact(concat(var.worker_allowed_domains, [var.heartbeat_domain]))
}

resource "aws_route53_resolver_firewall_domain_list" "all" {
  name    = "${var.name_prefix}-all"
  domains = ["*"]
}

resource "aws_route53_resolver_firewall_rule_group" "egress" {
  name = "${var.name_prefix}-egress"
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
  name                   = "${var.name_prefix}-egress"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.egress.id
  vpc_id                 = aws_vpc.main.id
  priority               = 200
}
