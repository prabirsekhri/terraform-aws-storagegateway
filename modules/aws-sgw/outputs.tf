output "storage_gateway" {
  value       = aws_storagegateway_gateway.mysgw
  description = "Storage Gateway Module"
  sensitive   = true
}

output "storage_gateway_name" {
  value       = aws_storagegateway_gateway.mysgw.gateway_name
  description = "Storage Gateway Name"
}

output "storage_gateway_arn" {
  value       = aws_storagegateway_gateway.mysgw.arn
  description = "Storage Gateway ARN"
}

output "storage_gateway_id" {
  value       = aws_storagegateway_gateway.mysgw.gateway_id
  description = "Storage Gateway ID"
}