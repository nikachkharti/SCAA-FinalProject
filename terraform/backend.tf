# ---------------------------------------------------------------------------
# Remote state.
#
# The pipeline runs on a fresh machine every time, so the state file cannot
# live on disk. We keep it in S3. `use_lockfile = true` makes Terraform write
# a small lock object in the same bucket, so two pipelines can never apply at
# the same time (no DynamoDB table needed).
#
# The bucket name is NOT written here on purpose. The pipeline passes it with
#   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
# This is called a "partial backend configuration".
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {
    key          = "scaa-final/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}