resource "aws_vpc" "dev" {
  cidr_block           = "10.0.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "DEV-VPC"
  }
}
resource "aws_subnet" "public-sn-1a" {
  vpc_id                  = aws_vpc.dev.id
  cidr_block              = "10.0.0.0/26"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-sn-1a"
  }
}
resource "aws_subnet" "private-sn-1a" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.64/26"
  availability_zone = "ap-south-1a"
  tags = {
    Name = "private-sn-1a"
  }
}
resource "aws_subnet" "public-sn-1b" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.128/26"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "public-sn-1b"
  }
}
resource "aws_subnet" "private-sn-1b" {
  vpc_id            = aws_vpc.dev.id
  cidr_block        = "10.0.0.192/26"
  availability_zone = "ap-south-1b"
  tags = {
    Name = "private-sn-1b"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.dev.id
  tags = {
    Name = "dev-igw"
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public-sn-1a.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public-sn-1b.id
  route_table_id = aws_route_table.public-rt.id
}

resource "aws_eip" "eip" {

  domain = "vpc"
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.eip.id
  subnet_id     = aws_subnet.public-sn-1a.id

  tags = {
    Name = "ngw"
  }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.dev.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = {
    Name = "private-rt"
  }
}

resource "aws_route_table_association" "pa" {
  subnet_id      = aws_subnet.private-sn-1a.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_route_table_association" "pb" {
  subnet_id      = aws_subnet.private-sn-1b.id
  route_table_id = aws_route_table.private-rt.id
}

resource "aws_security_group" "allow_tls" {
  name        = "dev-vpc-web-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.dev.id

  ingress = [
    {
      description      = "HTTP"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false


    },
    {
      description      = "SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress = [
    {
      description      = "for all outgoing traffics"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      prefix_list_ids  = []
      security_groups  = []
      self             = false

    }
  ]

  tags = {
    Name = "dev-vpc-web-sg"
  }
}

resource "aws_instance" "web" {
  ami             = "ami-0d951b011aa0b2c19"
  instance_type   = "t3.micro"
  key_name        = "ansible"
  subnet_id       = aws_subnet.public-sn-1a.id
  security_groups = [aws_security_group.allow_tls.id]
  user_data       = <<EOF
  #!/bin/bash
    yum update -y
    yum install -y httpd 
    systemctl start httpd
    systemctl enable httpd
    echo "<h1> $(hostname -f) </h1>"  >/var/www/html/index.html
    EOF

  tags = {
    Name = "web-server"
  }
}
resource "aws_elb" "clb" {
  name            = "my-clb"
  security_groups = [aws_security_group.allow_tls.id]
  subnets         = [aws_subnet.public-sn-1a.id, aws_subnet.public-sn-1b.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"

  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  instances                 = [aws_instance.web.id]
  cross_zone_load_balancing = true
  idle_timeout              = 40

  tags = {
    Name = "production"
  }
}

resource "aws_s3_bucket" "example" {
  bucket = "mys3fromterrafrombucket2016"

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}