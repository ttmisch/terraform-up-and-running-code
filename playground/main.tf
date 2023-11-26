provider "aws" {
  region =  "us-east-2"
}

resource "aws_instance" "example" {
  ami = "ami-0fb653ca2d3203ac1"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.instance.id]
  
  user_data = <<-EOF
    #!/bin/bash
    echo "Hello World!" > index.html
    nohup busybox httpd -f -p ${var.server_port} &
    EOF
  
  user_data_replace_on_change = true
  
  tags = {
    Name = "terraform-example"
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

variable "server_port" {
  description = "The port the server will use for HTTP requests"
  type = number
  default = 8080
}











