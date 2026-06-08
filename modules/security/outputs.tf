output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.this.arn
}

output "guardduty_detector_id" {
  value = aws_guardduty_detector.this.id
}

output "sns_security_alerts_arn" {
  value = aws_sns_topic.security_alerts.arn
}
