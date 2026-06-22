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

Create these Jenkins credentials before enabling pipelines:

```text
github-kt-jenkins-pat
  username: GitHub username
  password: GitHub PAT with repo, read:org, admin:repo_hook

erp007-server-ssh
  type: SSH username with private key
  username: taehyung
  private key: key that can SSH to the ERP server

harbor-robot-erp007
  type: Username with password
  username: robot$erp007+harbor-robot-erp007
  password: Harbor robot token
```

The current deployed Jenkins credential ID `github-kt-jenkins-pat` is a legacy
name. It can keep working if the token owner has access to `ERP007`; rename it
later only after creating the replacement credential and updating Jenkins job
configs/Jenkinsfiles together.

Backend and frontend multibranch jobs should include `main develop PR-*` and
enable origin pull request discovery. PR/develop backend jobs currently run only
Docker build validation; Gradle tests are intentionally skipped until test
profiles no longer depend on server secrets.

The old `KTHTESTTEST` organization folder was removed from the server Jenkins
controller on 2026-06-08 after creating this backup:

```text
/var/jenkins_home/KTHTESTTEST-jobs-backup-20260608022824.tgz
```

## Notes

- Jenkins is bound to `127.0.0.1:18080` on the server.
- Jenkins is bound to `127.0.0.1:18080` and attached only to the external `msa-edge-ci` Docker network so Cloudflare Tunnel can route `jenkins.erp007.xyz` to `http://erp-jenkins:8080`.
- The controller includes Docker CLI, Buildx, Compose, Git, and SSH client.
- `/var/run/docker.sock` is mounted so Jenkins jobs can build frontend/backend images, push them to Harbor, and run compose against the host Docker daemon.
- `/home/taehyung/apps/msa-server` is mounted at the same path inside Jenkins so compose bind-mount paths resolve correctly on the host.
- Jenkins is not attached to the app, service, or data networks. Docker socket access still gives Jenkins strong host-level control, so restrict Jenkins users, credentials, and trusted repositories.
