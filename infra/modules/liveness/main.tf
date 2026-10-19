# In-account half of the deadman. The topic accepts publishes from CloudWatch only.
# R10: the alarm is gated by alarm_enabled and stays off until the process that publishes
# the heartbeat exists; an alarm that always pages gets muted.
resource "aws_sns_topic" "liveness" {
  name = "${var.name_prefix}-liveness"
}

resource "aws_sns_topic_policy" "liveness" {
  arn = aws_sns_topic.liveness.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudWatchOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.liveness.arn
      Condition = { StringEquals = { "aws:SourceAccount" = var.account_id } }
    }]
  })
}

# Fires after grace_periods silent periods (10-15 min at the defaults).
# Missing data counts as breaching.
resource "aws_cloudwatch_metric_alarm" "heartbeat_missing" {
  count               = var.alarm_enabled ? 1 : 0
  alarm_name          = "${var.name_prefix}-heartbeat-missing"
  namespace           = var.namespace
  metric_name         = var.metric_name
  dimensions          = { Environment = var.environment }
  statistic           = "SampleCount"
  period              = var.period_minutes * 60
  evaluation_periods  = var.grace_periods
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.liveness.arn]
  ok_actions          = [aws_sns_topic.liveness.arn]
}
