# Jenkins Bootstrap

This compose file runs Jenkins on the ERP server. Jenkins is exposed through
Cloudflare Tunnel at `https://jenkins.erp007.xyz` and remains bound to
`127.0.0.1:18080` for SSH tunnel access.

## Start

```sh
cd /home/taehyung/apps/msa-server/infra
DOCKER_GID=$(stat -c %g /var/run/docker.sock) docker compose -f docker-compose.jenkins.yml up -d --build
```

## Open

Public URL:

```text
https://jenkins.erp007.xyz
```

From a local machine:

```sh
ssh -L 18080:127.0.0.1:18080 taehyung@ssh.erp007.xyz
```

Then open:

```text
http://127.0.0.1:18080
```

## Initial Admin Password

```sh
docker exec erp-jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

## Required Credentials

Create these Jenkins username/password credentials before enabling pipelines:

```text
github-kt-jenkins-pat
  username: GitHub username
  password: GitHub PAT with repo, read:org, admin:repo_hook

ghcr-kt-packages
  username: GitHub username
  password: GitHub PAT with read:packages, write:packages
```

The Jenkins GitHub Organization item should scan `KTHTESTTEST`.

## Notes

- Jenkins is bound to `127.0.0.1:18080` on the server.
- Jenkins is attached only to the external `msa-edge-ci` Docker network so Cloudflare Tunnel can route `jenkins.erp007.xyz` to `http://erp-jenkins:8080`.
- The controller includes Docker CLI, Buildx, Compose, Git, and SSH client.
- `/var/run/docker.sock` is mounted so Jenkins jobs can build images and run compose against the host Docker daemon.
- `/home/taehyung/apps/msa-server` is mounted at the same path inside Jenkins so compose bind-mount paths resolve correctly on the host.
- Jenkins is not attached to the app, service, or data networks. Docker socket access still gives Jenkins strong host-level control, so restrict Jenkins users, credentials, and trusted repositories.
