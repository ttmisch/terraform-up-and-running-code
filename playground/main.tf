terraform {
  required_version = ">= 1.0.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region =  "us-east-2"
}

# my: Directs Terraform to look up the data for the default VPC which you can use later.
# my: Typically for to other data sources you use the 'filter' option.
data "aws_vpc" "default" {
  default = true
}

# my: To provide the subnets to the auto scaling group to deploy in we have Terraform look up the existing subnets in the default vpc 
data "aws_subnets" "default" {
  filter {
    name = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_launch_configuration" "example" {
  image_id = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"
  security_groups = [aws_security_group.instance.id]
  
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello World!" > index.html
    nohup busybox httpd -f -p ${var.server_port} &
    EOF
  
  # Required when using a launch configuration with an autoscaling group
  # my: autoscaling group has a reference to here thus this launch configuration can't be destroyed upon a change here
  # Therefore, first create a new one that will be referenced in the auto scaling group, then destroy this existing one
  lifecycle {
    create_before_destroy = true
  }
}

# my: provide subnets ids in the default vpc to the vpc_zone_identifier option so the autoscaling group knows 
# to which subnets to deploy 
resource "aws_autoscaling_group" "example" {
  launch_configuration = aws_launch_configuration.example.name
  vpc_zone_identifier = data.aws_subnets.default.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 5

  tag {
    key = "Name"
    value = "terraform-asg-example"
    propagate_at_launch = true
  }
  
}

resource "aws_security_group" "instance" {
  name = "terraform-example-instance"
} 

resource "aws_vpc_security_group_ingress_rule" "example" {
  security_group_id = aws_security_group.instance.id

  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = var.server_port
  to_port = var.server_port
}

# my: Create ALB in all subnets of default VPC
resource "aws_lb" "example" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnets.default.ids
  security_groups = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port = 80
  protocol = "HTTP" 

  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "terraform-example-alb"
} 

# my: Allow inbound HTTP requests for ALB
resource "aws_vpc_security_group_ingress_rule" "alb" {
  security_group_id = aws_security_group.alb.id

  ip_protocol = "tcp"
  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port = 80
}

# my: Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id = aws_security_group.alb.id

  ip_protocol = "-1"
  cidr_ipv4 = "0.0.0.0/0"
  # from_port = 0
  # to_port = 0
}

resource "aws_lb_target_group" "asg" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.default.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2

  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

output "alb_dns_name" {
  value = aws_lb.example.dns_name
  description = "The domain name of the load balancer"
}
