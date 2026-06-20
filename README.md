# Hexagone - Cloud Computing

Automated OpenTofu/libvirt deployment of a containerized Forgejo application.

[ASSIGNMENT REPORT](./RAPPORT.md)

## Architecture

The lab creates three Ubuntu VMs on a libvirt NAT network. Each service runs in a Docker container deployed by cloud-init.

| VM         | IP               | Role            | Container  |
| ---------- | ---------------- | --------------- | ---------- |
| `cc-proxy` | `192.168.101.10` | Reverse proxy   | Traefik    |
| `cc-app`   | `192.168.101.20` | Web application | Forgejo    |
| `cc-db`    | `192.168.101.30` | Database        | PostgreSQL |

Forgejo is exposed through Traefik at:

```text
http://forgejo.cc.local/
```

## Local DNS

Add this line to `/etc/hosts` on the host machine:

```text
192.168.101.10 forgejo.cc.local
```

Without editing `/etc/hosts`, you can test through the proxy IP with an explicit Host header:

```shell
curl -H 'Host: forgejo.cc.local' http://192.168.101.10/
```

## Deployment

Apply the infrastructure:

```shell
tofu apply
```

Destroy the infrastructure:

```shell
tofu destroy
```

## Local libvirt notes

This project defaults to Fedora's modular libvirt socket:

```text
qemu:///system?socket=/var/run/libvirt/virtqemud-sock
```

If your host uses the legacy socket, override it:

```shell
TF_VAR_libvirt_uri='qemu:///system' tofu apply
```

## Tests

After `tofu apply`, wait a few minutes for cloud-init to install Docker and pull the container images.

With `/etc/hosts` configured:

```shell
curl -fsS -I http://forgejo.cc.local/
```

Without `/etc/hosts` configured:

```shell
curl -fsS -H 'Host: forgejo.cc.local' http://192.168.101.10/
```

Expected result:

- Traefik routes HTTP requests to the Forgejo container.
- Forgejo can connect to PostgreSQL.
- The Forgejo initial setup page is available in the browser.

Open `http://forgejo.cc.local/` and create the initial Forgejo administrator account through the setup page.
