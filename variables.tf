variable "region" {
  type    = string
  default = "eu-west-3"
} # Paris

variable "key_name" {
  type = string
  default = "aws-lab"
}

variable "public_key_path" {
  type = string
}

variable "my_ip_cidr" {
  type    = string
}

variable "instance_type" {
  type    = string
  default = "t4g.small"
}

variable "gitops_repo_url" {
  type    = string
  default = "https://github.com/clemuscle/weekend-gitops"
}

variable "gitops_branch" {
  type    = string
  default = "main"
}

variable "use_spot" {
  type    = bool
  default = true
}