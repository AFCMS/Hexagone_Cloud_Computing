# Hexagone - Cloud Computing

Automated OpenTofu/libvirt deployment for the Cloud Computing assignment.

The lab creates three Ubuntu VMs on a libvirt NAT network and deploys the services with cloud-init and Docker:

| VM | IP | Role | Container |
| --- | --- | --- | --- |
| `cc-proxy` | `192.168.101.10` | Reverse proxy | Traefik |
| `cc-app` | `192.168.101.20` | Web application | Forgejo `15.0.3` |
| `cc-db` | `192.168.101.30` | Database | PostgreSQL 17 |

Forgejo is exposed through Traefik at:

```shell
http://forgejo.cc.local/
```

If your host does not resolve `forgejo.cc.local`, use the proxy IP with the host header:

```shell
curl -H 'Host: forgejo.cc.local' http://192.168.101.10/
```

## Recreate The Lab

The simplest way to remove and recreate all VMs is:

```shell
tofu destroy -auto-approve
tofu apply -auto-approve
```

This destroys the VMs, cloud-init ISOs, VM disks, and the `cc-lab` network, then recreates everything from the Terraform/OpenTofu files.

The `ubuntu` user receives the local `~/.ssh/id_rsa.pub` key by default. Override it if needed:

```shell
TF_VAR_ssh_public_key_path='~/.ssh/id_ed25519.pub' tofu apply
```

Useful validation commands:

```shell
tofu fmt -check
tofu validate
tofu plan
```

## Local Libvirt Notes

This project defaults to Fedora's modular libvirt socket:

```shell
qemu:///system?socket=/var/run/libvirt/virtqemud-sock
```

If your host uses the legacy socket, override it:

```shell
TF_VAR_libvirt_uri='qemu:///system' tofu apply
```

This machine failed to start KVM acceleration, so the default domain type is `qemu`. On a host where KVM works, use:

```shell
TF_VAR_libvirt_domain_type='kvm' tofu apply
```

## Smoke Tests

After `tofu apply`, wait a few minutes for cloud-init to install Docker and pull images, then run:

```shell
curl -fsS -H 'Host: forgejo.cc.local' http://192.168.101.10/
curl -fsS -I http://192.168.101.20:3000/
timeout 3 bash -c 'cat < /dev/null > /dev/tcp/192.168.101.30/5432'
```

Expected result:

- Traefik returns the Forgejo web page.
- Forgejo answers directly on app port `3000`.
- PostgreSQL accepts TCP connections on database port `5432`.

## Report Summary

The architecture separates responsibilities into three VMs. The proxy VM is the public HTTP entry point and forwards requests to the app VM. The app VM runs Forgejo in a container and connects only to the database VM for persistence. The database VM runs PostgreSQL in a container with data stored on the VM disk.

Network flows:

- User to Traefik: `192.168.101.10:80`
- Traefik to Forgejo: `192.168.101.20:3000`
- Forgejo to PostgreSQL: `192.168.101.30:5432`
- Optional Forgejo SSH: `192.168.101.20:2222`

Technology choices:

- OpenTofu makes the virtual infrastructure reproducible.
- libvirt provides local VM virtualization with a simple NAT network.
- Ubuntu 26.04 cloud images provide the VM base for cloud-init.
- cloud-init installs Docker and starts services automatically on first boot.
- Containers keep Traefik, Forgejo, and PostgreSQL isolated and easy to replace.
- The three-VM split demonstrates a realistic proxy/app/database architecture without unnecessary complexity.

Limitations:

- HTTP is used instead of HTTPS to keep the lab simple.
- There is no high availability; each role has one VM.
- Passwords are lab defaults and should be overridden with `TF_VAR_*` variables outside a classroom demo.
