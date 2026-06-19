locals {
  network_name    = "cc-lab"
  network_domain  = "cc.local"
  network_gateway = "192.168.101.1"

  forgejo_image      = "codeberg.org/forgejo/forgejo:${var.forgejo_version}"
  forgejo_root_url   = "http://${var.forgejo_domain}/"
  postgres_image     = "postgres:17-alpine"
  traefik_image      = "traefik:v3"
  db_password_b64    = base64encode(var.forgejo_db_password)
  admin_password_b64 = base64encode(var.forgejo_admin_password)

  ssh_pubkey = fileexists(pathexpand(var.ssh_public_key_path)) ? trimspace(file(pathexpand(var.ssh_public_key_path))) : ""
  ssh_authorized_keys = local.ssh_pubkey == "" ? [] : [
    local.ssh_pubkey
  ]

  vms = {
    proxy = {
      name     = "cc-proxy"
      hostname = "proxy"
      ip       = "192.168.101.10"
      mac      = "52:54:00:cc:10:10"
      memory   = 1024
      vcpu     = 1
      disk_gib = 10
      role     = "reverse proxy"
    }

    app = {
      name     = "cc-app"
      hostname = "app"
      ip       = "192.168.101.20"
      mac      = "52:54:00:cc:20:20"
      memory   = 2048
      vcpu     = 2
      disk_gib = 20
      role     = "Forgejo application"
    }

    db = {
      name     = "cc-db"
      hostname = "db"
      ip       = "192.168.101.30"
      mac      = "52:54:00:cc:30:30"
      memory   = 2048
      vcpu     = 2
      disk_gib = 20
      role     = "PostgreSQL database"
    }
  }

  common_packages = [
    "ca-certificates",
    "curl",
    "docker.io",
  ]

  common_cloud_config = {
    package_update  = true
    package_upgrade = false
    packages        = local.common_packages
    disable_root    = true
    ssh_pwauth      = false
    users = [
      {
        name                = "ubuntu"
        gecos               = "Ubuntu"
        groups              = "adm,sudo"
        shell               = "/bin/bash"
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        ssh_authorized_keys = local.ssh_authorized_keys
      }
    ]
    growpart = {
      mode    = "auto"
      devices = ["/"]
    }
    resize_rootfs = true
  }

  db_write_files = [
    {
      path        = "/usr/local/sbin/cc-start-db.sh"
      owner       = "root:root"
      permissions = "0755"
      content     = <<-EOT
        #!/usr/bin/env bash
        set -euo pipefail

        FORGEJO_DB_PASSWORD="$(printf '%s' '${local.db_password_b64}' | base64 -d)"

        install -d -m 0755 /opt/forgejo/postgres
        docker pull ${local.postgres_image}
        docker rm -f forgejo-postgres >/dev/null 2>&1 || true
        docker run \
          --name forgejo-postgres \
          --restart unless-stopped \
          -p 5432:5432 \
          -e POSTGRES_DB='${var.forgejo_db_name}' \
          -e POSTGRES_USER='${var.forgejo_db_user}' \
          -e POSTGRES_PASSWORD="$FORGEJO_DB_PASSWORD" \
          -v /opt/forgejo/postgres:/var/lib/postgresql/data \
          -d ${local.postgres_image}
      EOT
    },
    {
      path        = "/etc/systemd/system/cc-db.service"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        [Unit]
        Description=Forgejo PostgreSQL container
        After=docker.service network-online.target
        Wants=docker.service network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/local/sbin/cc-start-db.sh

        [Install]
        WantedBy=multi-user.target
      EOT
    },
  ]

  app_write_files = [
    {
      path        = "/usr/local/sbin/cc-start-forgejo.sh"
      owner       = "root:root"
      permissions = "0755"
      content     = <<-EOT
        #!/usr/bin/env bash
        set -euo pipefail

        FORGEJO_DB_PASSWORD="$(printf '%s' '${local.db_password_b64}' | base64 -d)"

        until timeout 2 bash -c "cat < /dev/null > /dev/tcp/${local.vms.db.ip}/5432"; do
          echo "Waiting for PostgreSQL at ${local.vms.db.ip}:5432"
          sleep 5
        done

        install -d -m 0755 /opt/forgejo/data
        docker pull ${local.forgejo_image}
        docker rm -f forgejo >/dev/null 2>&1 || true
        docker run \
          --name forgejo \
          --restart unless-stopped \
          -p 3000:3000 \
          -p 2222:22 \
          -e USER_UID=1000 \
          -e USER_GID=1000 \
          -e FORGEJO____APP_NAME='Hexagone Forgejo' \
          -e FORGEJO__database__DB_TYPE=postgres \
          -e FORGEJO__database__HOST='${local.vms.db.ip}:5432' \
          -e FORGEJO__database__NAME='${var.forgejo_db_name}' \
          -e FORGEJO__database__USER='${var.forgejo_db_user}' \
          -e FORGEJO__database__PASSWD="$FORGEJO_DB_PASSWORD" \
          -e FORGEJO__server__DOMAIN='${var.forgejo_domain}' \
          -e FORGEJO__server__ROOT_URL='${local.forgejo_root_url}' \
          -e FORGEJO__server__SSH_DOMAIN='${var.forgejo_domain}' \
          -e FORGEJO__server__SSH_PORT=2222 \
          -e FORGEJO__server__START_SSH_SERVER=false \
          -e FORGEJO__security__INSTALL_LOCK=true \
          -e FORGEJO__service__DISABLE_REGISTRATION=true \
          -v /opt/forgejo/data:/data \
          -d ${local.forgejo_image}
      EOT
    },
    {
      path        = "/usr/local/sbin/cc-bootstrap-forgejo-admin.sh"
      owner       = "root:root"
      permissions = "0755"
      content     = <<-EOT
        #!/usr/bin/env bash
        set -euo pipefail

        FORGEJO_ADMIN_PASSWORD="$(printf '%s' '${local.admin_password_b64}' | base64 -d)"

        for attempt in $(seq 1 120); do
          if curl -fsS http://127.0.0.1:3000/ >/dev/null; then
            break
          fi
          echo "Waiting for Forgejo HTTP service"
          sleep 5
        done

        docker exec --user 1000:1000 forgejo forgejo admin user create \
          --admin \
          --username '${var.forgejo_admin_username}' \
          --password "$FORGEJO_ADMIN_PASSWORD" \
          --email '${var.forgejo_admin_email}' || true
      EOT
    },
    {
      path        = "/etc/systemd/system/cc-forgejo.service"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        [Unit]
        Description=Forgejo application container
        After=docker.service network-online.target
        Wants=docker.service network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/local/sbin/cc-start-forgejo.sh

        [Install]
        WantedBy=multi-user.target
      EOT
    },
    {
      path        = "/etc/systemd/system/cc-forgejo-admin.service"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        [Unit]
        Description=Create initial Forgejo admin user
        After=cc-forgejo.service
        Wants=cc-forgejo.service

        [Service]
        Type=oneshot
        ExecStart=/usr/local/sbin/cc-bootstrap-forgejo-admin.sh

        [Install]
        WantedBy=multi-user.target
      EOT
    },
  ]

  proxy_write_files = [
    {
      path        = "/etc/traefik/traefik.yml"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        entryPoints:
          web:
            address: ":80"

        providers:
          file:
            filename: /etc/traefik/dynamic.yml

        api:
          dashboard: false

        log:
          level: INFO

        accessLog: {}
      EOT
    },
    {
      path        = "/etc/traefik/dynamic.yml"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        http:
          routers:
            forgejo:
              entryPoints:
                - web
              rule: "Host(`${var.forgejo_domain}`)"
              service: forgejo
              priority: 10
            forgejo-catchall:
              entryPoints:
                - web
              rule: "PathPrefix(`/`)"
              service: forgejo
              priority: 1

          services:
            forgejo:
              loadBalancer:
                servers:
                  - url: "http://${local.vms.app.ip}:3000"
      EOT
    },
    {
      path        = "/usr/local/sbin/cc-start-traefik.sh"
      owner       = "root:root"
      permissions = "0755"
      content     = <<-EOT
        #!/usr/bin/env bash
        set -euo pipefail

        docker pull ${local.traefik_image}
        docker rm -f traefik >/dev/null 2>&1 || true
        docker run \
          --name traefik \
          --restart unless-stopped \
          -p 80:80 \
          -v /etc/traefik:/etc/traefik:ro \
          -d ${local.traefik_image} \
          --configFile=/etc/traefik/traefik.yml
      EOT
    },
    {
      path        = "/etc/systemd/system/cc-traefik.service"
      owner       = "root:root"
      permissions = "0644"
      content     = <<-EOT
        [Unit]
        Description=Traefik reverse proxy container
        After=docker.service network-online.target
        Wants=docker.service network-online.target

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/usr/local/sbin/cc-start-traefik.sh

        [Install]
        WantedBy=multi-user.target
      EOT
    },
  ]

  cloud_init_user_data = {
    proxy = <<-EOT
      #cloud-config
      ${yamlencode(merge(local.common_cloud_config, {
    write_files = local.proxy_write_files
    runcmd = [
      ["systemctl", "enable", "--now", "docker"],
      ["systemctl", "daemon-reload"],
      ["systemctl", "enable", "--now", "cc-traefik.service"],
    ]
}))}
    EOT

app = <<-EOT
      #cloud-config
      ${yamlencode(merge(local.common_cloud_config, {
write_files = local.app_write_files
runcmd = [
  ["systemctl", "enable", "--now", "docker"],
  ["systemctl", "daemon-reload"],
  ["systemctl", "enable", "--now", "cc-forgejo.service"],
  ["systemctl", "enable", "--now", "cc-forgejo-admin.service"],
]
}))}
    EOT

db = <<-EOT
      #cloud-config
      ${yamlencode(merge(local.common_cloud_config, {
write_files = local.db_write_files
runcmd = [
  ["systemctl", "enable", "--now", "docker"],
  ["systemctl", "daemon-reload"],
  ["systemctl", "enable", "--now", "cc-db.service"],
]
}))}
    EOT
}
}

resource "libvirt_network" "cloud_lab" {
  name      = local.network_name
  autostart = true

  forward = {
    mode = "nat"
  }

  domain = {
    name = local.network_domain
  }

  dns = {
    enable = "yes"
    host = [
      for vm in values(local.vms) : {
        ip = vm.ip
        hostnames = [
          {
            hostname = vm.hostname
          },
          {
            hostname = "${vm.hostname}.${local.network_domain}"
          },
        ]
      }
    ]
  }

  ips = [
    {
      address = local.network_gateway
      prefix  = 24

      dhcp = {
        ranges = [
          {
            start = "192.168.101.100"
            end   = "192.168.101.200"
          }
        ]

        hosts = [
          for vm in values(local.vms) : {
            mac  = lower(vm.mac)
            name = vm.hostname
            ip   = vm.ip
          }
        ]
      }
    }
  ]
}

resource "libvirt_volume" "ubuntu_base" {
  name = "ubuntu-26.04-resolute-base.qcow2"
  pool = var.pool

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.ubuntu_image_url
    }
  }
}

resource "libvirt_volume" "vm_disk" {
  for_each = local.vms

  name     = "${each.value.name}.qcow2"
  pool     = var.pool
  capacity = each.value.disk_gib * 1024 * 1024 * 1024

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "vm" {
  for_each = local.vms

  name      = "${each.value.name}-cloudinit"
  user_data = local.cloud_init_user_data[each.key]
  meta_data = yamlencode({
    instance-id    = each.value.name
    local-hostname = each.value.hostname
  })
  network_config = yamlencode({
    version = 2
    ethernets = {
      eth0 = {
        match = {
          macaddress = lower(each.value.mac)
        }
        dhcp4     = false
        addresses = ["${each.value.ip}/24"]
        routes = [
          {
            to  = "default"
            via = local.network_gateway
          }
        ]
        nameservers = {
          addresses = [
            local.network_gateway,
            "1.1.1.1",
          ]
        }
      }
    }
  })
}

resource "libvirt_volume" "cloudinit" {
  for_each = local.vms

  name = "${each.value.name}-cloudinit.iso"
  pool = var.pool

  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = libvirt_cloudinit_disk.vm[each.key].path
    }
  }
}

resource "libvirt_domain" "vm" {
  for_each = local.vms

  name                = each.value.name
  title               = "Cloud Computing assignment - ${each.value.role}"
  type                = var.libvirt_domain_type
  autostart           = true
  running             = true
  memory              = each.value.memory
  memory_unit         = "MiB"
  current_memory      = each.value.memory
  current_memory_unit = "MiB"
  vcpu                = each.value.vcpu

  os = {
    type = "hvm"
    boot_devices = [
      {
        dev = "hd"
      }
    ]
  }

  devices = {
    disks = [
      {
        device = "disk"
        driver = {
          name  = "qemu"
          type  = "qcow2"
          cache = "none"
        }
        source = {
          file = {
            file = libvirt_volume.vm_disk[each.key].path
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device    = "cdrom"
        read_only = true
        driver = {
          name = "qemu"
          type = "raw"
        }
        source = {
          file = {
            file = libvirt_volume.cloudinit[each.key].path
          }
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
      },
    ]

    interfaces = [
      {
        mac = {
          address = lower(each.value.mac)
        }
        source = {
          network = {
            network = libvirt_network.cloud_lab.name
          }
        }
        model = {
          type = "virtio"
        }
      }
    ]

  }
}

output "vm_ips" {
  description = "Static IP addresses used by the assignment topology."
  value = {
    for key, vm in local.vms : key => vm.ip
  }
}

output "forgejo_url" {
  description = "Forgejo URL routed through Traefik."
  value       = local.forgejo_root_url
}

output "proxy_ip_url" {
  description = "Direct proxy IP URL for local smoke tests when cc.local is not resolvable on the host."
  value       = "http://${local.vms.proxy.ip}/"
}

output "test_commands" {
  description = "Basic host-side smoke tests after cloud-init finishes."
  value = [
    "curl -fsS -H 'Host: ${var.forgejo_domain}' http://${local.vms.proxy.ip}/",
    "curl -fsS http://${local.vms.proxy.ip}/",
    "timeout 3 bash -c 'cat < /dev/null > /dev/tcp/${local.vms.db.ip}/5432'",
  ]
}
