# Server MSA Compose

이 문서는 Ubuntu 서버에서 최소 스캐폴드 MSA를 실행하는 절차를 다룬다. 현재 목적은 실제 ERP 기능 구현이 아니라 `Cloudflare Tunnel -> nginx -> gateway-service -> 각 service` 연결을 검증하는 것이다.

## Target URLs

- Web/API base URL: `https://api.erp007.xyz`
- Local nginx binding on server: `127.0.0.1:80`
- SSH tunnel hostname: `ssh.erp007.xyz`

서버의 Wi-Fi IPv4가 바뀌어도 Cloudflare Tunnel이 outbound 연결을 유지하면 외부 base URL은 그대로 유지된다.

## Directory Layout

서버에서도 `infra`와 각 repo가 같은 depth에 있어야 한다.

```text
msa-server/
  infra/
  gateway-service/
  keycloak/
  user-service/
  item-service/
  inventory-service/
  procurement-service/
  sales-service/
  frontend/
```

## Ports

- `127.0.0.1:80`: nginx server entrypoint. Cloudflare Tunnel이 이 compose network의 `nginx:80`으로 연결한다.
- `127.0.0.1:15432`: PostgreSQL debug port.
- `127.0.0.1:16379`: Redis debug port.

서버 compose는 host의 외부 인터페이스에 `80`, `15432`, `16379`를 직접 열지 않는다.

## Server Secrets

실제 서버 env 파일은 Git에 올리지 않는다.

```sh
cd infra
./scripts/init-server-secrets.sh
```

생성 후 `server-secrets/*.env`의 `change_me_*` 값은 서버 전용 값으로 바꾼다. `server-secrets/`는 `.gitignore`에 포함되어 있다.

Cloudflare Tunnel은 다음 파일이 필요하다.

```text
infra/server-secrets/cloudflared/config.yml
infra/server-secrets/cloudflared/<tunnel-uuid>.json
```

현재 서버는 기존 tunnel `erp007-api`를 사용할 수 있다. compose 내부의 cloudflared 컨테이너에서 실행되므로 ingress service는 `http://nginx:80`을 사용한다.

## Run

```sh
cd infra
./scripts/init-server-secrets.sh
docker compose -f docker-compose.server.yml -p msa-server config
docker compose -f docker-compose.server.yml -p msa-server up -d --build
```

## Test On Server

```sh
curl http://127.0.0.1/health
curl http://127.0.0.1/api/users/health
curl http://127.0.0.1/api/items/health
curl http://127.0.0.1/api/inventory/health
curl http://127.0.0.1/api/procurement/health
curl http://127.0.0.1/api/sales/health
```

## Test Through Cloudflare

```sh
curl https://api.erp007.xyz/health
curl https://api.erp007.xyz/api/users/health
curl https://api.erp007.xyz/api/items/health
curl https://api.erp007.xyz/api/inventory/health
curl https://api.erp007.xyz/api/procurement/health
curl https://api.erp007.xyz/api/sales/health
```

## SSH Through Cloudflare

Cloudflare Access SSH를 사용할 경우 로컬 Mac의 `~/.ssh/config`에 다음 alias를 둔다.

```sshconfig
Host erp-server
  HostName ssh.erp007.xyz
  User taehyung
  ProxyCommand cloudflared access ssh --hostname %h
```

그 뒤에는 IP 대신 다음 명령으로 접속한다.

```sh
ssh erp-server
```

## Stop

```sh
docker compose -f docker-compose.server.yml -p msa-server down
```

DB/Redis/Keycloak volume까지 삭제:

```sh
docker compose -f docker-compose.server.yml -p msa-server down -v
```

`down -v`는 PostgreSQL, Redis, Keycloak 데이터를 삭제한다. 필요한 경우에만 실행한다.

## Notes

- 현재 backend/frontend는 최소 스캐폴드다. 실제 ERP 비즈니스 로직, JWT 검증, Entity, Repository, Service layer는 아직 구현하지 않았다.
- Gateway는 `StripPrefix=1`을 사용한다. 예: `/api/users/health`는 `/users/health`로 user-service에 전달된다.
- Keycloak은 현재 스캐폴드 검증을 위해 `start-dev`로 실행한다. 운영 전에는 별도 production 설정이 필요하다.
