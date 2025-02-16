terraform {
  cloud {
    workspaces {
      name = "learn-terraform-drift-and-policy"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.68.0"
    }
  }

  required_version = "~> 1.4"
}
