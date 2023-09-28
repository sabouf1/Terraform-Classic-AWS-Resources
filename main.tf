# Initialize Terraform with the required AWS provider
provider "aws" {
  region = "sa-east-1"  
}

# Create an S3 Bucket
resource "aws_s3_bucket" "my_bucket" {
  bucket = "saidexammetrocollege2023" 
  acl = "public-read"
}


resource "aws_s3_bucket_object" "script" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "script.py"
  source = "script.py"  # Assuming you have a file named script.py in the same directory as your Terraform configuration
  etag   = filemd5("script.py")
}


# Create an IAM Role
resource "aws_iam_role" "Said_role" {
  name = "my-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

# Attach a sample IAM Policy to the IAM Role
resource "aws_iam_policy" "sample_policy" {
  name        = "sample-policy"
  description = "A sample IAM policy"

  # Define your policy document here
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action   = "s3:*",
      Effect   = "Allow",
      Resource = aws_s3_bucket.my_bucket.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sample_policy_attachment" {
  policy_arn = aws_iam_policy.sample_policy.arn
  role       = aws_iam_role.Said_role.name
}

# Create a Security Group
resource "aws_security_group" "my_security_group" {
  name        = "my-security-group"
  description = "Security Group with Port 3306 open for RDS"
  vpc_id      = "vpc-0a689659aaceb4efc"  

  # Define an inbound rule to allow incoming traffic on port 3306 (MySQL)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_db_subnet_group" "rdssubnetgroup1" {
  name       = "rdssubnetgroup1"
  subnet_ids            = ["subnet-0d33177353c6099a5", "subnet-016422784058a41f5"]  

  tags = {
    Name = "My DB subnet group"
  }
}

resource "aws_db_instance" "myrds" {
  allocated_storage      = 20
  db_name                = "metrodb"
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = "foobarbaz"
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.rdssubnetgroup1.id
  multi_az               = true
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
}

resource "aws_glue_job" "my_glue_job" {
  name     = "example"
  role_arn = aws_iam_role.Said_role.arn

  command {
    script_location = "s3://${aws_s3_bucket.my_bucket.bucket}/script.py"
  }
}

# Create a KMS Key
resource "aws_kms_key" "my_kms_key" {
  description             = "My KMS Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

# Create an Application Load Balancer (ALB)
resource "aws_lb" "my_alb" {
  name               = "my-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = ["subnet-0d33177353c6099a5", "subnet-016422784058a41f5"] 
}

resource "aws_key_pair" "ec2KeyPair1" {
  key_name   = "deployer-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5O0Hd4IsPZ9PTFJSxZoNUtOWzPNp+nZJnmyrocdb3/bZjHB51o3qswxViWyTh0SnjrWHZASZ5QtRNZ80j0Xf2g50P5bMAlvg7x5wEEg7BEkovqCDSuZ24CRv1rj3AMChDHbdidios17MejcZarizCo88gZ88hwP8fO2Azj7MxcXAJLJWsrbmfhPM4rKPsORNkijs90fKIFj/Kld6C9AwlHTvSMYdDGvrwGkKmQ8XAtHSlu6gPQPuh0XpW4ZEkfzMWNaMY8S5WMR7Jl0OFMqy26dR/ULwUa3oF3NDadHMA/Hn3WYGey/I2oD7BtqoYr5ph3At7YZ53cn8XQ5KCf9IN ec2-user@ip-172-31-13-249.us-east-2.compute.internal"
}

resource "aws_launch_template" "ASGLaunchTemplate" {
  name = "MyASGLaunchTemplate"

  image_id               = "ami-00103992c587e27cc"
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.ec2KeyPair1.id
  vpc_security_group_ids = [aws_security_group.my_security_group.id]
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "Web"
    }
  }
  #   user_data = filebase64("${path.module}/bootstrap.sh")
}

resource "aws_lb_target_group" "taregtgroup1" {
  name        = "tf-example-lb-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = "vpc-0a689659aaceb4efc"  
  target_type = "instance"
}

resource "aws_autoscaling_group" "myasg" {
#   availability_zones  = ["sa-east-1a", "sa-east-1b"]
  desired_capacity    = 1
  max_size            = 1
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.taregtgroup1.arn]
  vpc_zone_identifier = ["subnet-0d33177353c6099a5", "subnet-016422784058a41f5"] 

  launch_template {
    id      = aws_launch_template.ASGLaunchTemplate.id
    version = "$Latest"
  }
}
