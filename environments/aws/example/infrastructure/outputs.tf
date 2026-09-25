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

output "match_helm_values" {
  description = "Values the match chart needs so it consumes the synced secrets instead of generating its own. `terraform output -raw match_helm_values > secrets.yaml`."
  value       = module.secret_provider_classes.match_helm_values
}

output "load_balancer_ip_ranges" {
  description = "CIDRs the load balancer's security group will admit, the Snicket Labs support address included when snicket_labs_remote_lb_access adds it. Check this against what you asked for before relying on it."
  value       = module.ingress_resources.inbound_cidrs
}

###############################################################################
# Names and ARNs the match helm chart has to be told.
#
# Each of these is created by a module above and was previously discoverable
# only from the console, so every environment hardcoded it into its values file
# and a rename broke the release rather than the plan.
#
# `terraform output -json` gives you all of them in one go, which is what we ask
# for when building a customer's values file.
###############################################################################

output "shared_storage_class_name" {
  description = "EFS-backed StorageClass for the shared ReadWriteMany volume the workers write to. -> storage.sharedStorage.storageClassName"
  value       = module.efs.storage_class_name
}

output "block_storage_class_name" {
  description = "EBS StorageClass that provisions under EKS Auto Mode. The in-tree gp2 class does not, and its PVCs sit Pending. -> the Prometheus, Grafana and Loki volumes"
  value       = module.auto_mode_storage_class.storage_class_name
}

output "ingress_class_name" {
  description = "IngressClass created for this cluster. -> ingress.className"
  value       = module.ingress_resources.ingress_class_name
}

output "active_storage_bucket_name" {
  description = "ActiveStorage bucket. The chart wants the NAME, not the ARN. -> s3.primaryBucket"
  value       = module.s3-active-storage.bucket_name
}

output "service_account_role_arn" {
  description = "ARN of the IRSA role the match workloads run as. The name alone is output above, but the chart wants the ARN and rebuilding one from a name needs the account id. -> serviceAccount.annotations"
  value       = module.iam_role_for_service_account.role_arn
}

output "grafana_cloudwatch_role_arn" {
  description = "Role Grafana assumes to read CloudWatch. Created for every deployment, but previously with no way to discover it. -> monitoring.awsDashboards.cloudwatch.assumeRoleArn"
  value       = module.iam_role_for_service_account.grafana_cloudwatch_role_arn
}

output "redis_url" {
  description = "Connection URL for the primary endpoint. Prefer reading the synced k8s secret in the chart (sidekiq.redisServerSecret) over pasting this into a values file."
  value       = module.elasticache_redis.redis_url
}

output "database_name" {
  description = "-> postgres.database"
  value       = module.rds-postgres.db_name
}

output "database_username" {
  description = "-> postgres.username"
  value       = module.rds-postgres.db_username

  # terraform-aws-modules marks the RDS master username sensitive, and that
  # propagates here. Marked rather than unwrapped with nonsensitive(), so the
  # guard survives: `terraform output -json` still carries the value in full
  # (flagged "sensitive": true), which is the form this is collected in.
  # Plain `terraform output` shows <sensitive> for this one.
  sensitive = true
}

output "database_port" {
  description = "-> postgres.port"
  value       = module.rds-postgres.db_port
}

output "k8s_secret_names" {
  description = "Kubernetes Secrets the CSI driver syncs Secrets Manager into -> postgres.*Secret, sidekiq.redis*Secret. These, not rds_pg_secret_name / redis_secret_name, are what the chart is told: those two are the Secrets Manager names, and differ."
  value       = module.secret_provider_classes.k8s_secret_names
}
