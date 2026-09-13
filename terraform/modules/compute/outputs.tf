output "instance_id" {
  description = "EC2 instance ID - used by the SSM deploy command."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Static public IP of the application."
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "Public DNS name."
  value       = aws_instance.app.public_dns
}

output "availability_zone" {
  value = aws_instance.app.availability_zone
}