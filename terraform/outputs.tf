output "instance_id" {
  value = aws_instance.app.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "load_balancer_arn" {
  value = aws_lb.app.arn
}

output "listener_arn" {
  value = aws_lb_listener.app.arn
}