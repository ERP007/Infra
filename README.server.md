# Server MSA Compose

이 문서는 Ubuntu 서버에서 API/backend MSA를 실행하는 절차를 다룬다. Frontend는 Vercel에서 운영하고, 이 서버는 Cloudflare Tunnel 뒤의 backend API와 CI/CD를 담당한다.

## Target URLs

- Web/API base URL: `https://api.erp007.xyz`
- Jenkins URL: `https://jenkins.erp007.xyz`
- Local nginx binding on server: `127.0.0.1:80`
- SSH tunnel hostname: `ssh.erp007.xyz`

서버의 Wi-Fi IPv4가 바뀌어도 Cloudflare Tunnel이 outbound 연결을 유지하면 외부 base URL은 그대로 유지된다.

## Directory Layout

서버에서도 `infra`와 각 서비스 repo가 같은 depth에 있어야 한다. `infra`는 얇은 deploy repo로 유지하고, 실제 애플리케이션 코드는 각 서비스 repo에서 관리한다.

```text
msa-server/
  infra/
    docker-compose.yml
    docker-compose.jenkins.yml
    Jenkinsfile
    jenkins/
    nginx/
    server-secrets/
  gateway-service/
  user-service/
  item-service/
  inventory-service/
  procurement-service/
  sales-service/
```

## Ports

- `127.0.0.1:80`: nginx server entrypoint. Cloudflare Tunnel이 이 compose network의 `nginx:80`으로 연결한다.
- `127.0.0.1:15431`: user-service PostgreSQL debug port.
- `127.0.0.1:15432`: item-service PostgreSQL debug port.
- `127.0.0.1:15433`: inventory-service PostgreSQL debug port.
- `127.0.0.1:15434`: procurement-service PostgreSQL debug port.
- `127.0.0.1:15435`: sales-service PostgreSQL debug port.
- `127.0.0.1:16379`: Redis debug port.

서버 compose는 host의 외부 인터페이스에 `80`, PostgreSQL, Redis port를 직접 열지 않는다.

## Network Layout

서버 compose는 역할별 Docker network를 분리한다.

```text
msa-edge-app:
  cloudflared, nginx

msa-edge-ci:
  cloudflared, erp-jenkins

msa-app:
  nginx, gateway-service

msa-service:
  gateway-service, user-service, item-service, inventory-service, procurement-service, sales-service

msa-data:
  user-service, user-postgres
  item-service, item-postgres
  inventory-service, inventory-postgres
  procurement-service, procurement-postgres
  sales-service, sales-postgres
  redis
```

Jenkins는 `msa-edge-ci`에만 연결한다. 따라서 컨테이너 네트워크 기준으로는 `gateway-service`, PostgreSQL, Redis에 직접 접근하지 않는다. 단, Jenkins는 이미지 빌드와 배포를 위해 host Docker socket을 사용하므로 Jenkins 권한 관리는 여전히 중요하다.

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

현재 서버는 기존 tunnel `erp007-api`를 사용할 수 있다. compose 내부의 cloudflared 컨테이너에서 실행되므로 API ingress service는 `http://nginx:80`, Jenkins ingress service는 `http://erp-jenkins:8080`을 사용한다.

nginx는 backend API만 분기한다. `/api/**`는 gateway-service로 전달되고, `/internal/**`은 외부 ingress 경로로 열지 않는다. `/`는 frontend 서버가 아니므로 404를 반환한다.

## Deploy Model

현재 운영 배포 기준은 GHCR image pull이 아니라 서버 직접 build다.
운영 기준 compose 파일은 `docker-compose.yml`이다.

1. 각 서비스 repo에 push되면 해당 서비스 Jenkins job이 돈다.
2. Jenkins가 서버의 `infra`와 해당 서비스 repo를 `git pull --ff-only`로 갱신한다.
3. Jenkins가 `infra/docker-compose.yml` 기준으로 해당 서비스만 `docker compose up -d --build --no-deps <service>`로 재빌드/재기동한다.
4. `infra` repo에 push되면 infra Jenkins job이 전체 compose를 `up -d --build --remove-orphans`로 반영한다.

`docker-compose.yml`은 `docker/server-service.Dockerfile`로 서비스를 빌드한다. 이 Dockerfile은 운영 배포 속도와 DB 의존성 분리를 위해 `bootJar -x test`만 수행한다. 테스트는 각 서비스 repo의 CI 단계에서 통과시킨 뒤 배포한다.

서비스 Jenkins job이 `infra`도 pull하는 이유는 compose 파일과 secrets 초기화 스크립트가 `infra` repo에 있기 때문이다. 서비스 배포 시점에 서버의 `infra/docker-compose.yml`이 오래된 상태면, 최신 서비스 코드가 구형 compose로 올라갈 수 있다. `git pull --ff-only`만 수행하므로 서버의 tracked file에 수동 변경이 있으면 덮어쓰지 않고 실패한다.

## Database Model

운영 기준은 서비스별 PostgreSQL 컨테이너 분리 구조다.

```text
user-service        -> user-postgres        / user_db        / user_user
item-service        -> item-postgres        / item_db        / item_user
inventory-service   -> inventory-postgres   / inventory_db   / inventory_user
procurement-service -> procurement-postgres / procurement_db / procurement_user
sales-service       -> sales-postgres       / sales_db       / sales_user
```

각 PostgreSQL 컨테이너는 자기 volume을 가진다.

```text
user_postgres_data
item_postgres_data
inventory_postgres_data
procurement_postgres_data
sales_postgres_data
```

`server-secrets/<service>-service.env`는 서비스 애플리케이션이 바라볼 datasource를 담고, `server-secrets/<service>-postgres.env`는 해당 PostgreSQL 컨테이너의 `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`를 담는다. `./scripts/init-server-secrets.sh`는 기존 서비스 env의 DB username/password를 읽어서 새 `<service>-postgres.env`를 만든다.

기존 공용 `postgres` 컨테이너에 실제 운영 데이터가 이미 들어 있다면 이 구조로 올리기 전에 DB별 dump/restore가 필요하다. 새 compose는 기존 `postgres_data` volume을 자동으로 재사용하지 않는다.

## Team Workflow

팀원은 서버 PostgreSQL을 공유하지 않는다. `infra` repo의 `server-secrets/`와 `scripts/init-server-secrets.sh`는 운영 서버/Jenkins 전용이다. 로컬 개발 DB는 각자 로컬 Docker 또는 서비스 repo의 테스트 설정으로 띄운다.

## Run

```sh
cd infra
./scripts/init-server-secrets.sh
docker compose -f docker-compose.yml -p msa-server config
docker compose -f docker-compose.yml -p msa-server up -d --build --remove-orphans
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
docker compose -f docker-compose.yml -p msa-server down
```

DB/Redis volume까지 삭제:

```sh
docker compose -f docker-compose.yml -p msa-server down -v
```

`down -v`는 PostgreSQL, Redis 데이터를 삭제한다. 필요한 경우에만 실행한다.

## Notes

- 현재 backend는 최소 스캐폴드다. 실제 ERP 비즈니스 로직, 사용자 JWT 검증, Entity, Repository, Service layer는 아직 구현하지 않았다.
- Gateway는 `StripPrefix=1`을 사용한다. 예: `/api/users/health`는 `/users/health`로 user-service에 전달된다.
- Keycloak은 이 서버 구성에서 제외한다. 인증 서버는 나중에 `auth.erp007.xyz` 기준으로 별도 설계한다.
