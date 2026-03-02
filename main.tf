provider "aws" {
  region = var.region
}


module "terraform_state_backend" {
  source     = "cloudposse/tfstate-backend/aws"
  namespace  = "terraform"
  stage      = "state"
  name       = "bucket"
  attributes = ["2138"]

  terraform_backend_config_file_path = ""
  terraform_backend_config_file_name = "backend.tf"
  force_destroy                      = true


}


module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "my-vpc"
  cidr   = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b", "${var.region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway                 = true
  single_nat_gateway                 = true
  create_database_subnet_route_table = true
  tags = {

    Terraform   = "true"
    Environment = "dev"
  }

}

module "web_server_http_allowance_sg" {

  source              = "terraform-aws-modules/security-group/aws//modules/http-80"
  name                = "web-server-80"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

module "web_server_ssh_allowance_sg" {

  source              = "terraform-aws-modules/security-group/aws//modules/ssh"
  name                = "web-server-22"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_cidr_blocks  = ["0.0.0.0/0"]
}

data "aws_ami" "al2023" {

  most_recent = true
  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-*"]

  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["amazon"] #apparently exists for most regions other than ap-south-2

}


resource "aws_key_pair" "myKey" {
  key_name   = "infra-key"
  public_key = file("infra-key.pub")

}


resource "aws_instance" "myInstance" {
  count                       = 3
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.public_subnets[count.index]
  vpc_security_group_ids      = [module.web_server_http_allowance_sg.security_group_id, module.web_server_ssh_allowance_sg.security_group_id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.myKey.key_name
  user_data                   = file("userdata.tpl")
  user_data_replace_on_change = true
  tags = {

    Name = "myAl2023Instance-${count.index}"

  }


}


