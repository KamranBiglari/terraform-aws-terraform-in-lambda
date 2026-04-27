terraform {
  required_version = ">= 1.0.11"
  required_providers {
    aws = ">= 5.8.0"
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.2.0"
    }
  }
}