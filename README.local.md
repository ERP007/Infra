# Local MSA Compose

이 문서는 운영 배포가 아닌 로컬 개발 환경 실행 절차만 다룬다. Jenkins, GHCR, Cloudflare, production compose 설정은 포함하지 않는다.

현재 service/frontend repo들은 Docker Compose, nginx proxy, Gateway routing, Keycloak, PostgreSQL/Redis 연결을 검증하기 위한 최소 스캐폴드다. 실제 ERP 비즈니스 로직, 사용자 JWT 검증, Entity, Repository, 도메인 Service layer는 아직 구현하지 않았다.

## Directory Layout

`infra` repo와 각 서비스 repo는 같은 depth에 있어야 한다.

```text
msa-local/
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

`infra/docker-compose.local.yml`은 sibling repo를 build context 또는 bind mount로 사용한다.

전체 compose 실행은 `gateway-service`, `keycloak`, `user-service`, `item-service`, `inventory-service`, `procurement-service`, `sales-service`, `frontend` repo가 모두 같은 depth에 실제 코드로 준비된 뒤에만 가능하다. repo가 아직 없다면 PostgreSQL과 Redis만 먼저 실행해서 infra 구성을 검증한다.

브라우저 요청 흐름은 다음과 같다.

```text
http://localhost:18080
  -> nginx
    -> /api/** -> gateway-service:8080
    -> /keycloak/** -> keycloak:8080
    -> /**     -> frontend:3000
  -> gateway-service
    -> /api/users/**       -> user-service:8080
    -> /api/items/**       -> item-service:8080
    -> /api/inventory/**   -> inventory-service:8080
    -> /api/procurement/** -> procurement-service:8080
    -> /api/sales/**       -> sales-service:8080
    -> /internal/**        -> internal service routes with service token
```

PostgreSQL과 Redis는 같은 compose network 안에서 각각 `postgres:5432`, `redis:6379`로 접근한다.

## Local Ports

- `18080`: nginx local entrypoint. Jenkins가 host의 `8080`을 사용 중이므로 이 프로젝트는 `18080`을 사용한다.
- `15432`: PostgreSQL local debug port.
- `16379`: Redis local debug port.

## Requirements

- Docker
- Docker Compose
- `infra`와 각 service/frontend repo가 같은 depth에 있어야 한다.
- 각 Spring backend repo에는 compose build가 가능한 `Dockerfile`이 있어야 한다.
- `frontend/package.json`에는 `dev` script가 있어야 한다.

## Local Secrets

실제 로컬 env 파일은 Git에 올리지 않는다. 예시 파일을 복사해서 사용한다.

```sh
cd infra
./scripts/init-local-secrets.sh
```

이미 `local-secrets/*.env` 파일이 있으면 스크립트가 덮어쓰지 않는다.

## Run

local secret 파일 생성:

```sh
./scripts/init-local-secrets.sh
```

설정 확인:

```sh
docker compose -f docker-compose.local.yml -p msa-local config
```

전체 실행:

```sh
docker compose -f docker-compose.local.yml -p msa-local up -d --build
```

위 명령은 모든 sibling repo가 준비된 뒤에 실행한다. repo가 없는 상태에서는 build context가 없어서 실패하는 것이 정상이다.

PostgreSQL과 Redis만 먼저 실행:

```sh
docker compose -f docker-compose.local.yml -p msa-local up -d postgres redis
```

## Logs

전체 로그:

```sh
docker compose -f docker-compose.local.yml -p msa-local logs -f
```

특정 서비스 로그:

```sh
docker compose -f docker-compose.local.yml -p msa-local logs -f gateway-service
docker compose -f docker-compose.local.yml -p msa-local logs -f user-service
docker compose -f docker-compose.local.yml -p msa-local logs -f keycloak
```

## Stop

컨테이너 종료:

```sh
docker compose -f docker-compose.local.yml -p msa-local down
```

DB/Redis volume까지 삭제:

```sh
docker compose -f docker-compose.local.yml -p msa-local down -v
```

`down -v`는 PostgreSQL/Redis named volume까지 삭제한다. 생성된 DB와 Redis 데이터가 모두 사라지므로 필요한 경우에만 실행한다.

## Test

frontend dashboard:

```text
http://localhost:18080
```

Keycloak local console:

```text
http://localhost:18080/keycloak/
```

```sh
curl http://localhost:18080/health
curl http://localhost:18080/api/users/health
curl http://localhost:18080/api/items/health
curl http://localhost:18080/api/inventory/health
curl http://localhost:18080/api/procurement/health
curl http://localhost:18080/api/sales/health
curl http://localhost:18080/keycloak/realms/erp-local/.well-known/openid-configuration
```

`/health`는 nginx가 직접 `nginx ok`를 응답한다. `/api/**` 요청은 gateway-service를 거쳐 각 backend service로 전달되고, `/keycloak/**` 요청은 nginx가 Keycloak으로 직접 전달한다.

## Internal Calls

로컬 스캐폴드에서는 서비스 간 내부 호출을 검증하기 위해 `/internal/**` endpoint를 추가했다. 내부 호출도 권한/정책을 Gateway에서 통제할 수 있도록 각 서비스는 target service를 직접 호출하지 않고 `gateway-service:8080`을 호출한다.

```text
item-service -> http://gateway-service:8080/internal/inventory/health -> inventory-service
inventory-service -> http://gateway-service:8080/internal/items/health -> item-service
procurement-service -> http://gateway-service:8080/internal/inventory/health -> inventory-service
sales-service -> http://gateway-service:8080/internal/inventory/health -> inventory-service
sales-service -> http://gateway-service:8080/internal/procurement/health -> procurement-service
```

Gateway에는 internal 호출용 `/internal/**` 라우트를 열어 두었고, `X-Internal-Service-Token` 헤더가 `INTERNAL_SERVICE_TOKEN`과 일치해야 통과한다. 서비스 컨테이너들은 같은 `INTERNAL_SERVICE_TOKEN`을 env로 받고 내부 호출 시 이 헤더를 자동으로 붙인다.

외부에서 `/internal/**`을 헤더 없이 직접 호출하면 `403`이 정상이다.

```sh
INTERNAL_SERVICE_TOKEN="$(grep '^INTERNAL_SERVICE_TOKEN=' local-secrets/gateway-service.env | cut -d= -f2-)"
curl -H "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" http://localhost:18080/internal/users/health
curl -H "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" http://localhost:18080/internal/items/health
curl -H "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" http://localhost:18080/internal/inventory/health
curl -H "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" http://localhost:18080/internal/procurement/health
curl -H "X-Internal-Service-Token: ${INTERNAL_SERVICE_TOKEN}" http://localhost:18080/internal/sales/health
curl -i http://localhost:18080/internal/users/health
```

서비스가 Gateway를 거쳐 내부 호출을 수행하는지 확인하는 endpoint:

```sh
curl http://localhost:18080/api/items/internal/inventory-health
curl http://localhost:18080/api/inventory/internal/items-health
curl http://localhost:18080/api/procurement/internal/inventory-health
curl http://localhost:18080/api/sales/internal/inventory-health
curl http://localhost:18080/api/sales/internal/procurement-health
```

현재는 최소 구현으로 shared service token을 사용한다. prod 단계에서는 사용자 JWT 필터와 별도로 `/internal/**` 전용 정책을 강화해야 한다. 후보는 OAuth2 client credentials, mTLS, 서비스별 allowlist, nginx 외부 차단 조합이다.

## Gateway Path Prefix

local 라우팅은 `StripPrefix=1`을 기준으로 한다.

예를 들어 `GET /api/users/health`는 gateway에서 `/api`만 제거되어 `user-service:8080/users/health`로 전달된다. 로컬 스캐폴드의 user-service endpoint가 `/users/health`이므로 `StripPrefix=1`이 맞다.

다른 서비스도 같은 방식으로 `/items/health`, `/inventory/health`, `/procurement/health`, `/sales/health`를 직접 받는다. 인증 서버 역할은 별도 Keycloak 컨테이너가 담당하고, user-service는 사용자 도메인 API를 위한 최소 스캐폴드로 둔다.

## PostgreSQL Init

`postgres/init/01-create-databases.sh`는 PostgreSQL 컨테이너의 `/docker-entrypoint-initdb.d`에 mount된다.

이 스크립트는 PostgreSQL data volume이 처음 생성될 때만 실행된다. 이미 volume이 만들어진 뒤 DB/user 구성을 바꾸려면 직접 SQL을 실행하거나 다음 명령으로 volume을 삭제한 뒤 다시 올린다.

```sh
docker compose -f docker-compose.local.yml -p msa-local down -v
docker compose -f docker-compose.local.yml -p msa-local up -d --build postgres
```

## Common Issues

- 컨테이너 안에서는 `localhost`가 host machine이 아니라 자기 자신이다. DB/Redis/서비스 접근에는 `postgres`, `redis`, `user-service`, `keycloak` 같은 compose service name을 사용한다.
- PostgreSQL init script는 volume이 처음 만들어질 때만 실행된다.
- backend 코드 수정 후에는 해당 service를 다시 빌드해야 한다.

```sh
docker compose -f docker-compose.local.yml -p msa-local up -d --build user-service
```

- frontend dev server는 컨테이너 안에서 `0.0.0.0:3000`으로 bind되어야 nginx가 `frontend:3000`으로 proxy할 수 있다.
