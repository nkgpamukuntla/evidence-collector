output "public_url" { value = local.public_url }
output "target_group_arn" {
  description = "Waits for the listener: ECS refuses a target group with no load balancer attached."
  value       = aws_lb_target_group.portal.arn
  depends_on  = [aws_lb_listener.http]
}
output "listener_arn" { value = aws_lb_listener.http.arn }
output "cognito_user_pool_id" { value = aws_cognito_user_pool.portal.id }
output "cognito_client_id" { value = aws_cognito_user_pool_client.portal.id }
output "cognito_domain_url" { value = "https://${aws_cognito_user_pool_domain.portal.domain}.auth.${data.aws_region.current.region}.amazoncognito.com" }
output "distribution_id" { value = aws_cloudfront_distribution.portal.id }
