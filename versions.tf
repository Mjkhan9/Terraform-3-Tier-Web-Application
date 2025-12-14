terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Optional: Uncomment to use remote state
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "3-tier-app/terraform.tfstate"
  #   region = "us-east-1"
  #   encrypt = true
  # }
}

