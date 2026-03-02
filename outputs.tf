output "vpc_Id" {

  value = module.vpc.vpc_id

}

output "subnet_Id" {
  value = module.vpc.public_subnets

}

output "route_table_Ids" {

  value = module.vpc.database_route_table_ids

}

output "security_groups_id_http" {


  value = module.web_server_http_allowance_sg.security_group_id


}

output "security_groups_id_ssh" {


  value = module.web_server_ssh_allowance_sg.security_group_id


}

output "aws_ami" {

  value = data.aws_ami.al2023.id
}

output "aws_instance" {

  value = [resource.aws_instance.myInstance[0].id, resource.aws_instance.myInstance[1].id, resource.aws_instance.myInstance[2].id]

}
