# Email notifications (app Phase 5): one summary email per scan, sent through Amazon SES by the
# portal and the worker (both reach SES through NAT; *.amazonaws.com is on the DNS allowlist).
#
# 1. Set email_domain to a domain (e.g. dbizsolution.com) and apply: SES creates the domain
#    identity and `terraform output email_dkim_records` lists three CNAMEs for its DNS admin.
#    For testing without DNS, set it to one mailbox instead (name@domain): SES emails that
#    mailbox a verification link, and only that address can send.
# 2. When SES shows the identity verified, set email_from and apply: the app starts sending.
#    Until then mail stays queued in the app's outbox and nothing leaves the platform.
# 3. A new SES account is in the sandbox (verified recipients only); request production access
#    once in the SES console. ~$0.10 per 1,000 emails.

variable "email_domain" {
  description = "SES identity the notification emails are sent from: a domain (DKIM, production) or one mailbox (testing, no DNS). Empty: no email."
  type        = string
  default     = ""
}

variable "email_from" {
  description = "Sender, e.g. \"CCR Platform <noreply@dbizsolution.com>\". Set only after the domain is verified."
  type        = string
  default     = ""
}

resource "aws_sesv2_email_identity" "domain" {
  count          = var.email_domain != "" ? 1 : 0
  email_identity = var.email_domain
}

# Send only, only from this identity, only as the configured From address.
data "aws_iam_policy_document" "send_email" {
  count = var.email_domain != "" ? 1 : 0
  statement {
    actions   = ["ses:SendEmail"]
    resources = [aws_sesv2_email_identity.domain[0].arn]
    condition {
      test     = "StringLike"
      variable = "ses:FromAddress"
      values   = [strcontains(var.email_domain, "@") ? var.email_domain : "*@${var.email_domain}"]
    }
  }
}

resource "aws_iam_role_policy" "send_email" {
  for_each = var.email_domain != "" ? {
    portal = module.identity.portal_role_name
    worker = module.identity.worker_role_name
  } : {}
  name   = "send-notification-email"
  role   = each.value
  policy = data.aws_iam_policy_document.send_email[0].json
}

output "email_dkim_records" {
  description = "CNAME records for the email domain's DNS (name -> value)."
  value = var.email_domain != "" && !strcontains(var.email_domain, "@") ? {
    for t in aws_sesv2_email_identity.domain[0].dkim_signing_attributes[0].tokens :
    "${t}._domainkey.${var.email_domain}" => "${t}.dkim.amazonses.com"
  } : {}
}
