terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.8"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

variable "libvirt_uri" {
  type        = string
  description = "Libvirt connection URI. Fedora modular libvirt exposes virtqemud-sock instead of the legacy libvirt-sock."
  default     = "qemu:///system?socket=/var/run/libvirt/virtqemud-sock"
}

variable "libvirt_domain_type" {
  type        = string
  description = "Libvirt domain type. Use kvm on hosts where KVM acceleration starts cleanly; qemu is slower but works without KVM acceleration."
  default     = "qemu"
}

variable "pool" {
  type        = string
  description = "Libvirt storage pool used for the base image, VM disks, and cloud-init ISOs."
  default     = "default"
}

variable "ubuntu_image_url" {
  type        = string
  description = "Ubuntu cloud image used as the VM base disk."
  default     = "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}

variable "ssh_public_key_path" {
  type        = string
  description = "Optional SSH public key injected into the ubuntu user when the file exists."
  default     = "~/.ssh/id_rsa.pub"
}

variable "forgejo_version" {
  type        = string
  description = "Forgejo container version. 15.0.3 was the latest release checked on 2026-06-15."
  default     = "15.0.3"
}

variable "forgejo_domain" {
  type        = string
  description = "HTTP virtual host routed by Traefik to Forgejo."
  default     = "forgejo.cc.local"
}

variable "forgejo_db_name" {
  type        = string
  description = "PostgreSQL database name used by Forgejo."
  default     = "forgejo"
}

variable "forgejo_db_user" {
  type        = string
  description = "PostgreSQL user used by Forgejo."
  default     = "forgejo"
}

variable "forgejo_db_password" {
  type        = string
  description = "PostgreSQL password used by Forgejo. Override for non-lab use."
  sensitive   = true
  default     = "HexagoneForgejoDB2026"
}

variable "forgejo_admin_username" {
  type        = string
  description = "Initial Forgejo administrator username."
  default     = "admin"
}

variable "forgejo_admin_email" {
  type        = string
  description = "Initial Forgejo administrator email."
  default     = "admin@cc.local"
}

variable "forgejo_admin_password" {
  type        = string
  description = "Initial Forgejo administrator password. Override for non-lab use."
  sensitive   = true
  default     = "HexagoneForgejoAdmin2026"
}
