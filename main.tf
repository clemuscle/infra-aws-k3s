terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
}

provider "aws" {
  region = var.region
}

# VPC par défaut
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Ubuntu 22.04 ARM64 officiel
data "aws_ami" "ubuntu_arm" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-*"]
  }
}

resource "aws_security_group" "k3s" {
  name        = "k3s-lab-sg"
  description = "SSH + NodePort demo"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

locals {
  user_data = <<-EOT
    #!/bin/bash
    set -euxo pipefail
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y curl ca-certificates jq

    # k3s sans Traefik (on expose via NodePort 30080)
    export INSTALL_K3S_EXEC="server --disable=traefik --write-kubeconfig-mode=644"
    curl -sfL https://get.k3s.io | sh -
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

    # Attendre que le serveur réponde
    for i in {1..60}; do kubectl get nodes && break || sleep 5; done

    # Installer les contrôleurs Flux
    kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

    # Attendre les CRDs Flux
    for i in {1..60}; do kubectl get crd gitrepositories.source.toolkit.fluxcd.io && break || sleep 5; done

    # Déclarer la source Git et les Kustomizations
    cat <<YAML | kubectl apply -f -
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata:
      name: gitops
      namespace: flux-system
    spec:
      interval: 1m
      url: ${var.gitops_repo_url}
      ref:
        branch: ${var.gitops_branch}
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: platform
      namespace: flux-system
    spec:
      interval: 1m
      prune: true
      sourceRef: { kind: GitRepository, name: gitops }
      path: ./clusters/lab/platform
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata:
      name: apps
      namespace: flux-system
    spec:
      interval: 1m
      prune: true
      sourceRef: { kind: GitRepository, name: gitops }
      path: ./clusters/lab/apps
    YAML
  EOT
}

resource "aws_key_pair" "this" {
  key_name   = var.key_name
  public_key = file(var.public_key_path) # ex: /home/user/.ssh/aws-lab.pub
}

resource "aws_instance" "k3s" {
  ami                         = data.aws_ami.ubuntu_arm.id
  instance_type               = var.instance_type
  subnet_id                   = element(data.aws_subnets.default.ids, 0)
  vpc_security_group_ids      = [aws_security_group.k3s.id]
  key_name                    = aws_key_pair.this.key_name
  user_data                   = local.user_data
  associate_public_ip_address = true

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        instance_interruption_behavior = "terminate"
        max_price                      = "0.05"
      }
    }
  }

  tags = { Name = "k3s-lab" }
}