output "public_ip" {
  value       = var.create_eip ? aws_eip.ip[0].public_ip : null
  description = "The Public IP address of the Elastic IP. Null when create_eip is false."
  sensitive   = true
}

output "private_ip" {
  value       = aws_instance.ec2_sgw.private_ip
  description = "The Private IP address of the Storage Gateway EC2 instance."
}

output "activation_ip" {
  value       = var.create_eip ? aws_eip.ip[0].public_ip : aws_instance.ec2_sgw.private_ip
  description = "The IP address to use for gateway activation."
  sensitive   = true
}

output "ami_id" {
  value       = data.aws_ssm_parameter.sgw_ami.value
  description = "The AMI ID used for the Storage Gateway EC2 instance"
}

output "instance_id" {
  value       = aws_instance.ec2_sgw.id
  description = "The EC2 instance ID of the Storage Gateway"
}

output "instance_public_ip" {
  value       = aws_instance.ec2_sgw.public_ip
  description = "The public IP address assigned to the EC2 instance (not EIP)"
}
