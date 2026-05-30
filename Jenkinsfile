pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        DEPLOY_DIR = '/home/taehyung/apps/msa-server/infra'
        COMPOSE_FILE = 'docker-compose.server.yml'
        ENV_FILE = 'server-images.env'
        COMPOSE_PROJECT = 'msa-server'
        API_BASE_URL = 'https://api.erp007.xyz'
    }

    stages {
        stage('Sync infra checkout') {
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
                withCredentials([usernamePassword(credentialsId: 'ghcr-kt-packages', usernameVariable: 'GHCR_USERNAME', passwordVariable: 'GHCR_TOKEN')]) {
                    sh '''
                        set -eu
                        cd "$DEPLOY_DIR"
                        printf '%s' "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USERNAME" --password-stdin
                        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" config >/tmp/msa-server-compose.yml
                        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" pull
                        docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" -p "$COMPOSE_PROJECT" up -d --remove-orphans
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
                        /api/procurement/health \
                        /api/sales/health
                    do
                        curl -fsS --retry 10 --retry-delay 3 --max-time 10 "${API_BASE_URL}${path}" >/dev/null
                    done
                '''
            }
        }
    }
}
