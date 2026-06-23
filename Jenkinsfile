pipeline {
    agent any

    parameters {
        booleanParam(name: 'PULL_APP_IMAGES', defaultValue: true, description: 'Pull frontend and backend service images from Harbor before infra deploy')
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        DEPLOY_DIR = '/home/taehyung/apps/msa-server/infra'
        COMPOSE_FILE = 'docker-compose.yml'
        COMPOSE_PROJECT = 'msa-server'
        API_BASE_URL = 'https://erp007.xyz'
        FRONTEND_URL = 'https://erp007.xyz'
        REGISTRY_HOST = 'registry.erp007.xyz'
        APP_SERVICES = 'frontend gateway-service user-service item-service inventory-service procurement-service sales-service'
    }

    stages {
        stage('Validate compose') {
            when {
                not { branch 'main' }
            }
            steps {
                sh '''
                    set -eu
                    ./scripts/init-server-secrets.sh
                    docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" config --quiet
                '''
            }
        }

        stage('Sync infra repo') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'github-kt-jenkins-pat', usernameVariable: 'GITHUB_USERNAME', passwordVariable: 'GITHUB_TOKEN')]) {
                    sh '''
                        set -eu
                        cd "$DEPLOY_DIR"
                        auth_header="$(printf '%s:%s' "$GITHUB_USERNAME" "$GITHUB_TOKEN" | base64 | tr -d '\\n')"
                        git -c "http.extraHeader=Authorization: Basic ${auth_header}" fetch origin main
                        git checkout main
                        git -c "http.extraHeader=Authorization: Basic ${auth_header}" pull --ff-only origin main
                    '''
                }
            }
        }

        stage('Deploy compose') {
            when { branch 'main' }
            steps {
                withCredentials([usernamePassword(credentialsId: 'harbor-robot-erp007', usernameVariable: 'HARBOR_USERNAME', passwordVariable: 'HARBOR_PASSWORD')]) {
                    sh '''
                        set -eu
                        cd "$DEPLOY_DIR"
                        ./scripts/init-server-secrets.sh
                        docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" config >/tmp/msa-server-compose.yml
                        if [ "${PULL_APP_IMAGES:-true}" = "true" ]; then
                            docker_config="$(mktemp -d)"
                            export DOCKER_CONFIG="$docker_config"
                            trap 'docker logout "$REGISTRY_HOST" >/dev/null 2>&1 || true; rm -rf "$docker_config"' EXIT
                            printf '%s' "$HARBOR_PASSWORD" | docker login "$REGISTRY_HOST" -u "$HARBOR_USERNAME" --password-stdin
                            docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" pull $APP_SERVICES
                        fi
                        docker compose -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" up -d --remove-orphans
                    '''
                }
            }
        }

        stage('Health check') {
            when { branch 'main' }
            steps {
                sh '''
                    set -eu
                    for path in \
                        /health \
                        /api/users/health \
                        /api/items/health \
                        /api/inventory/health \
                        /api/procurement-orders/health \
                        /api/sales-orders/health
                    do
                        curl -fsS --retry 10 --retry-delay 3 --max-time 10 "${API_BASE_URL}${path}" >/dev/null
                    done
                    curl -fsS --retry 10 --retry-delay 3 --max-time 10 "$FRONTEND_URL" >/dev/null
                '''
            }
        }
    }
}
