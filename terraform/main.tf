resource "aws_instance" "app" {
  ami           = "ami-ubuntu2404-arm64"
  instance_type = var.instance_type

  key_name = var.key_name

  tags = {
    Name = "deployment-lab"
  }
}

resource "aws_lb_target_group" "app" {
  name     = "deployment-lab"
  port     = 80
  protocol = "HTTP"

  health_check {
    path = "/api/v1/health"
  }
}

resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app.id
  port             = 80 # Which port should the EC2 receive traffic on?
}

resource "aws_lb" "app" {
  name               = "deployment-lab"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn = aws_lb_target_group.app.arn
      }
    }
  }
}