output "alb_dns_name" { 
    value = aws_lb.app.dns_name 
}
output "alb_zone_id"  { 
    value = aws_lb.app.zone_id 
}
output "ecs_cluster_name" { 
    value = aws_ecs_cluster.this.name 
}
output "ecs_service_name" { 
    value = aws_ecs_service.app.name 
}
output "log_group_name"   { 
    value = aws_cloudwatch_log_group.app.name 
}
output "alb_arn_suffix"   { 
    value = aws_lb.app.arn_suffix 
}
output "tg_arn_suffix"    { 
    value = aws_lb_target_group.tg.arn_suffix 
}
