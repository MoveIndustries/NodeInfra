# Validator Identity Secret Management
#
# This file handles AWS Secrets Manager integration
# The module reads from AWS SM and outputs the data
# NOTE: K8s secret must be created in root config to avoid circular dependencies

# Read validator identity from AWS Secrets Manager (if configured)
data "aws_secretsmanager_secret_version" "validator_identity" {
  count = var.validator_keys_secret_name != "" ? 1 : 0

  secret_id = var.validator_keys_secret_name
}
