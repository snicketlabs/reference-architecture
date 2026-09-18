output "secret_store_role_arn" {
  description = "ARN of the IAM Role for Secret Store"
  value       = module.eks.secrets_csi_irsa_role_arn
}

output "redis_secret_name" {
  description = "Name of the AWS Secrets Manager secret for Redis."
  value       = module.elasticache_redis.redis_secret_name
}

output "rds_pg_secret_name" {
  description = "Name of the AWS Secrets Manager secret for RDS Postgres."
  value       = module.rds-postgres.rds_pg_secret_name
}

output "user_secret_name" {
  description = "Name of the AWS Secrets Manager secret for user credentials."
  value       = module.application-secrets.user_secret_name
}

output "api_secret_name" {
  description = "Name of the AWS Secrets Manager secret for API credentials."
  value       = module.application-secrets.api_secret_name
}

output "service_account_role_name" {
  description = "The name of the IAM role for service account"
  value       = module.iam_role_for_service_account.role_name
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc
}

output "eks_cluster_endpoint" {
  description = "The endpoint for the EKS Kubernetes API."
  value       = module.eks.eks_cluster_endpoint
}

output "eks_cluster_ca_data" {
  description = "The base64 encoded certificate data required to communicate with the cluster."
  value       = module.eks.eks_cluster_certificate
}

output "eks_cluster_details" {
  description = "The details of the EKS cluster."
  value       = module.eks.eks_cluster
}

output "eks_cluster_node_sg" {
  description = "The security group ID for the EKS cluster nodes"
  value       = module.eks.eks_cluster_node_sg
}

output "cluster_primary_security_group_id" {
  description = "Cluster security group that was created by Amazon EKS for the cluster. Managed node groups use this security group for control-plane-to-data-plane communication. Referred to as 'Cluster security group' in the EKS console"
  value       = module.eks.cluster_primary_security_group_id
}

output "cluster_security_group_id" {
  description = "ID of the cluster security group"
  value       = module.eks.cluster_security_group_id
}

output "private_subnets_detail" {
  description = "Map objects of private subnets"
  value       = module.vpc.private_subnets_detail
}