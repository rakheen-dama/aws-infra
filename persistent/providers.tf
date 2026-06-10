# State key is environment-specific, passed via CLI:
#   terraform init -backend-config="key=staging/persistent.tfstate"

terraform {
  backend "s3" {
    bucket         = "binarymash-terraform-state"
    dynamodb_table = "binarymash-terraform-locks"
    encrypt        = true
    region         = "af-south-1"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Layer       = "persistent"
    }
  }
}
