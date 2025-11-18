output "sns_topic_arn"      { 
    value = aws_sns_topic.alerts.arn 
}
output "sns_subscription_arn" { 
    value = try(aws_sns_topic_subscription.email[0].arn, null) 
}
