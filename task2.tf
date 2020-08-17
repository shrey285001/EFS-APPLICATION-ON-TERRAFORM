provider "aws"{
	region  = "ap-south-1"
		
}


// Creating Key Pair
resource "tls_private_key" "myKey" {
  algorithm = "RSA"
}

module "key_pair" {
  source = "terraform-aws-modules/key-pair/aws"

  key_name   = "myKey"
  public_key = tls_private_key.myKey.public_key_openssh
}


// Creating Security Group
resource "aws_security_group" "SecurityGroup" {
  name        = "SecurityGroup"
  description = "Allow http and ssh inbound traffic"
  vpc_id      = "vpc-1559457d"

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    description = "Allow EFS communication with EC2"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "SecurityGroup"
  }
}

// EC2 Instance
resource "aws_instance" "EC2Instance" {
  depends_on = [ aws_security_group.SecurityGroup ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "myKey"
  security_groups = [ "${aws_security_group.SecurityGroup.name}"]

  connection{
  		type = "ssh"
  		user = "ec2-user"
  		private_key = tls_private_key.myKey.private_key_pem
  		host = aws_instance.EC2Instance.public_ip
  }
  provisioner "remote-exec"{
  		inline = [
  			"sudo yum install httpd git amazon-efs-utils -y",        
  			"sudo systemctl restart httpd",
  			"sudo systemctl enable httpd"
  		]
  }

  tags = {
    Name = "EC2Instance"
  }
}


//EFS Volume
resource "aws_efs_file_system" "EFSVolume" {
  depends_on = [ aws_instance.EC2Instance ]
  creation_token = "efstoken"

  tags = {
    Name = "EFSVolume"
  }
}

//Target of EFS Volume
resource "aws_efs_mount_target" "EFSVolumeTarget" {
  depends_on = [ aws_efs_file_system.EFSVolume ]
  file_system_id = aws_efs_file_system.EFSVolume.id
  subnet_id = aws_instance.EC2Instance.subnet_id
  security_groups = [ aws_security_group.SecurityGroup.id ]
}


// volume mounting and Github Code cloning
resource "null_resource" "MountingAndClonning" {

  depends_on =[
  		aws_efs_mount_target.EFSVolumeTarget
  	]

  connection{
  		type = "ssh"
  		user = "ec2-user"
  		private_key = tls_private_key.myKey.private_key_pem
  		host = aws_instance.EC2Instance.public_ip
  }

  provisioner "remote-exec"{
  	inline = [
  		"sudo mount -t '${aws_efs_file_system.EFSVolume.id}':/ /var/www/html",
  		"sudo rm -rf /var/www/html/*",
  		"sudo git clone https://github.com/shrey285001/Terraform.git /var/www/html/"
  	]
  }
 }

 //S3 bucket  
 resource "aws_s3_bucket" "myBucket" {
  bucket = "task581"
  acl    = "public-read"
  tags = {
    Name        = "myBucket"
  }
}

resource "null_resource" "DownloadImagesFromGithub" {

  
   provisioner "local-exec"{
  	command = "git clone https://github.com/himanshuj581/image.git"
	working_dir = "C:/Users/gupta/Downloads/"
  }
 }

resource "aws_s3_bucket_object" "object" {
depends_on = [aws_s3_bucket.myBucket,
		null_resource.DownloadImagesFromGithub
    	     ]
  bucket = aws_s3_bucket.myBucket.bucket
  key    = "image2.jpg"
  source = "C:/Users/gupta/Downloads/logo.jpg"
  content_type = "image/jpg"
  acl = "public-read"
}


//CloudFront
resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.myBucket.bucket_regional_domain_name}"
    origin_id   = "myS3Origin"

    custom_origin_config {
      http_port = 80
      https_port = 80
      origin_protocol_policy = "match-viewer"
      origin_ssl_protocols = ["TLSv1","TLSv1.1","TLSv1.2"]
    }
  }
  enabled  = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "myS3Origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
     }
  }
  viewer_certificate{
  	cloudfront_default_certificate = true
  }
  depends_on = [
        aws_s3_bucket_object.object
    ]
 }

//Lauching of website from cmd prompt

resource "null_resource" "toLauchWebsite"  {
depends_on = [
    null_resource.MountingAndClonning,
    aws_cloudfront_distribution.s3_distribution
  ]

	provisioner "local-exec" {
	    command = "start  http://${aws_instance.EC2Instance.public_ip}/index1.html"
  	}
} 