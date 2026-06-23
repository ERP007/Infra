# Server MSA Compose

이 문서는 Ubuntu 서버에서 ERP007 backend MSA, Harbor registry, React frontend container 배포를 운영하는 절차를 다룬다.

## Target URLs

- Web/API base URL: `https://erp007.xyz`
- Frontend URL: `https://erp007.xyz`
- Harbor URL: `https://registry.erp007.xyz`
- Jenkins URL: `https://jenkins.erp007.xyz`
- RabbitMQ Management URL: `https://rabbit.erp007.xyz`
- Local nginx binding on server: `127.0.0.1:80`
- Frontend container: compose 내부 `frontend:80`, host port 없음
- Local Harbor binding on server: `127.0.0.1:443`
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

platform/
  harbor/
```

## Ports

- `127.0.0.1:80`: nginx server entrypoint. Cloudflare Tunnel이 compose network의 `nginx:80`으로 연결한다.
- `127.0.0.1:443`, `172.17.0.1:443`: Harbor HTTPS endpoint. Docker daemon, Jenkins, Cloudflare Tunnel이 내부 이미지 push/pull에 사용한다.
- `127.0.0.1:15431`: user-service PostgreSQL debug port.
- `127.0.0.1:15432`: item-service PostgreSQL debug port.
- `127.0.0.1:15433`: inventory-service PostgreSQL debug port.
- `127.0.0.1:15434`: procurement-service PostgreSQL debug port.
- `127.0.0.1:15435`: sales-service PostgreSQL debug port.
- `127.0.0.1:16379`: Redis debug port.
- RabbitMQ AMQP `5672`와 Management UI `15672`는 host port로 열지 않는다. 서비스 컨테이너는 `rabbitmq:5672`, Cloudflare Tunnel은 `rabbitmq:15672`로 접근한다.

서버 compose는 host의 외부 인터페이스에 `80`, PostgreSQL, Redis port를 직접 열지 않는다.

## Network Layout

서버 compose는 역할별 Docker network를 분리한다.

```text
msa-edge-app:
  cloudflared, nginx, rabbitmq

msa-edge-ci:
  cloudflared, erp-jenkins

msa-app:
  nginx, frontend, gateway-service

msa-service:
  gateway-service, user-service, item-service, inventory-service, procurement-service, sales-service, rabbitmq

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

현재 서버는 기존 tunnel `erp007-api`를 사용할 수 있다. compose 내부의 cloudflared 컨테이너에서 실행되므로 `erp007.xyz`, `www.erp007.xyz` ingress service는 `http://nginx:80`, RabbitMQ Management ingress service는 `http://rabbitmq:15672`, Jenkins ingress service는 `http://erp-jenkins:8080`을 사용한다. Keycloak을 별도 compose로 실행할 때는 Keycloak 컨테이너를 external network `msa-edge-app`에 붙이고 auth ingress service를 `http://keycloak:8080`으로 둔다. Harbor처럼 host에서 실행되는 endpoint는 `host.docker.internal`을 사용한다.

nginx는 `erp007.xyz`와 `www.erp007.xyz`에서 frontend 통합 server block으로 동작한다. frontend 도메인의 `/`는 `frontend:80`으로 전달하고, `/api/**`, `/oauth2/**`, `/login/**`, `/error`는 `gateway-service:8080`으로 전달한다. `/internal/**`은 외부 ingress 경로로 열지 않는다.

## Deploy Model

현재 운영 배포 기준은 Harbor image pull이다. 운영 기준 compose 파일은 `docker-compose.yml`이다.

1. 각 backend 서비스 repo에 push되면 해당 서비스 Jenkins job이 돈다.
2. backend Jenkins job은 테스트를 실행하고 `docker/server-service.Dockerfile`로 이미지를 빌드한다.
3. frontend repo에 push되면 frontend Jenkins job이 Dockerfile build stage 안에서 `npm ci`와 `npm run build`를 실행하고 nginx runtime image를 만든다.
4. Jenkins가 `registry.erp007.xyz/erp007/<service>:<git-sha>`와 `:main`을 Harbor에 push한다.
5. Jenkins가 서버에서 `docker compose pull <service>` 후 `docker compose up -d --no-deps <service>`로 해당 서비스만 재기동한다.
6. `infra` repo에 push되면 infra Jenkins job은 필요한 이미지를 pull한 뒤 전체 compose를 `up -d --remove-orphans`로 반영한다.

`docker-compose.yml`에는 더 이상 app 서비스 `build:`가 없다. 서버가 직접 서비스 이미지를 빌드하지 않으므로 Harbor project, robot account, 서버 Docker login 상태가 선행 조건이다.

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

## Storage Prep

Harbor를 같은 서버에 운영하기 전에 root filesystem을 300GB로 확장한다. 현재 서버 디스크는 약 477GB이고 `/` logical volume만 100GB로 잡혀 있다.

```sh
cd infra
./scripts/expand-root-lv.sh 300G
./scripts/prune-docker-build-cache.sh
```

`expand-root-lv.sh`는 `sudo`가 필요하다. 스냅샷/백업 확인 후 실행한다.

## Harbor

Harbor는 `/home/taehyung/apps/platform/harbor` 아래에 설치한다. Docker client가 `registry.erp007.xyz`를 신뢰해야 하므로 `server-secrets/harbor/registry.erp007.xyz.crt`와 `.key`는 Cloudflare Origin Certificate가 아니라 일반 Docker client가 신뢰 가능한 인증서를 사용한다.

```sh
cd infra
./scripts/configure-harbor-host-resolution.sh
./scripts/setup-harbor.sh
./scripts/configure-harbor-project.sh
```

`configure-harbor-project.sh`는 다음 기본 정책을 API로 설정한다.

- private project: `erp007`
- Jenkins robot account credential: `harbor-robot-erp007`
- project quota: `120GB`
- retention: repository별 최신 artifact 10개 유지
- garbage collection: 주 1회

## Frontend Container

React Vite frontend는 `ERP007/frontend` repo의 Dockerfile로 빌드하고 Harbor에 push한다. 서버 compose는 `registry.erp007.xyz/erp007/frontend:main`을 pull해서 `frontend` 컨테이너로 실행한다.

```sh
docker compose -f docker-compose.yml -p msa-server pull frontend
docker compose -f docker-compose.yml -p msa-server up -d --no-deps frontend
```

frontend 컨테이너는 host port를 열지 않는다. 외부 `erp007.xyz`와 `www.erp007.xyz` 요청은 Cloudflare Tunnel이 `nginx:80`으로 넘기고, nginx가 `/`를 `frontend:80`으로 proxy한다.

## RabbitMQ

RabbitMQ는 backend 서비스용 AMQP broker와 운영 확인용 Management UI를 제공한다.

```text
AMQP internal URL: rabbitmq:5672
Management URL: https://rabbit.erp007.xyz
Management internal URL: http://rabbitmq:15672
```

RabbitMQ는 host port를 열지 않는다. `5672`는 Docker network 내부 서비스 통신에만 사용하고, `15672`는 Cloudflare Tunnel이 `rabbit.erp007.xyz`로만 라우팅한다.

Cloudflare Access에서 `rabbit.erp007.xyz` 접근 제한을 반드시 설정한다. Access 적용 전에는 `server-secrets/rabbitmq.env`의 `RABBITMQ_DEFAULT_PASS`를 강한 값으로 바꾼다.

RabbitMQ topology는 `rabbitmq/definitions.json`에서 관리하고, `rabbitmq-topology` one-shot 컨테이너가 Management API로 import한다. `management.load_definitions`를 직접 켜면 RabbitMQ가 기본 vhost/user 생성을 건너뛰므로, 비밀번호를 `server-secrets/rabbitmq.env`로 유지하려면 RabbitMQ 부팅 후 import 방식이 더 안전하다.

현재 기본 topology는 다음과 같다.

```text
topic exchange: erp.events
topic exchange: erp.commands
direct exchange: erp.dlx

erp.events + item.master.snapshot.changed
  -> inventory.item-master-snapshot.q

inventory.item-master-snapshot.q dead-letter
  -> erp.dlx + inventory.item-master-snapshot.q.dlq
  -> inventory.item-master-snapshot.q.dlq
```

`item-service`는 `server-secrets/rabbitmq.env`를 함께 읽는다. 운영 서버에서는 `RABBITMQ_DEFAULT_PASS`와 `SPRING_RABBITMQ_PASSWORD`를 같은 강한 값으로 맞춘다.

```sh
docker compose -f docker-compose.yml -p msa-server pull rabbitmq
docker compose -f docker-compose.yml -p msa-server up -d rabbitmq rabbitmq-topology cloudflared
docker compose -f docker-compose.yml -p msa-server exec rabbitmq rabbitmq-diagnostics -q ping
```

## Run

```sh
cd infra
./scripts/init-server-secrets.sh
docker compose -f docker-compose.yml -p msa-server config
docker compose -f docker-compose.yml -p msa-server pull rabbitmq frontend gateway-service user-service item-service inventory-service procurement-service sales-service
docker compose -f docker-compose.yml -p msa-server up -d --remove-orphans
```

## Test On Server

```sh
curl http://127.0.0.1/health
curl http://127.0.0.1/api/users/health
curl http://127.0.0.1/api/items/health
curl http://127.0.0.1/api/inventory/health
curl http://127.0.0.1/api/procurement-orders/health
curl http://127.0.0.1/api/sales-orders/health
curl -H 'Host: erp007.xyz' http://127.0.0.1/
```

## Test Through Cloudflare

```sh
curl https://erp007.xyz/health
curl https://erp007.xyz/api/users/health
curl https://erp007.xyz/api/items/health
curl https://erp007.xyz/api/inventory/health
curl https://erp007.xyz/api/procurement-orders/health
curl https://erp007.xyz/api/sales-orders/health
curl https://erp007.xyz
curl https://www.erp007.xyz
curl https://erp007.xyz/api/items/health
curl https://registry.erp007.xyz
curl https://rabbit.erp007.xyz
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
- Keycloak은 별도 `erp007/keycloak` repo의 compose로 실행하고, `auth.erp007.xyz` 기준으로 Cloudflare Tunnel에서 라우팅한다.
