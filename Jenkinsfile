// CI/CD: build the three images, push them to ECR, apply the DB schema, then roll out to the servers.
// Runs on the Jenkins agent (label "docker"). The agent's IAM role is limited to ECR push, SSM deploy on
// the three app servers, and reading the DB secret. Region, registry and instance IDs come from
// /etc/coldchain/env, which Terraform writes on the agent.
pipeline {
  agent { label 'docker' }

  options {
    timestamps()
    disableConcurrentBuilds()
    timeout(time: 30, unit: 'MINUTES')
  }

  // Checks the Git repo every 2 minutes. If you set up a GitHub webhook instead, remove this trigger.
  triggers { pollSCM('H/2 * * * *') }

  stages {
    stage('Build and push images') {
      steps {
        sh '''
          set +x
          set -eu
          set -a; . /etc/coldchain/env; set +a
          TAG=$(git rev-parse --short=12 HEAD)
          echo "$TAG" > .image_tag
          aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY
          for svc in backend frontend mqtt-ingest; do
            img=$REGISTRY/$PROJECT/$svc
            docker build -t $img:$TAG -t $img:latest ./$svc
            docker push $img:$TAG
            docker push $img:latest
          done
        '''
      }
    }

    stage('Apply database schema') {
      steps {
        sh '''
          set +x
          set -eu
          set -a; . /etc/coldchain/env; set +a
          SECRET=$(aws secretsmanager get-secret-value --region $AWS_REGION --secret-id $DB_SECRET_ARN --query SecretString --output text)
          export PGPASSWORD=$(echo "$SECRET" | jq -r .password)
          DBU=$(echo "$SECRET" | jq -r .username)
          docker run --rm -e PGPASSWORD -e PGSSLMODE=require -v "$PWD/database:/db:ro" postgres:16-alpine \
            psql -h $DB_HOST -U $DBU -d $DB_NAME -v ON_ERROR_STOP=1 -f /db/schema.sql
        '''
      }
    }

    stage('Deploy') {
      steps {
        sh '''
          set +x
          set -eu
          set -a; . /etc/coldchain/env; set +a
          TAG=$(cat .image_tag)

          deploy() {
            name=$1; id=$2
            params=$(mktemp)
            printf '{"commands":["/opt/coldchain/deploy.sh %s"]}' "$TAG" > $params
            cid=$(aws ssm send-command --region $AWS_REGION --document-name AWS-RunShellScript \
                  --instance-ids "$id" --parameters file://$params --comment "deploy $name $TAG" \
                  --query Command.CommandId --output text)
            while :; do
              st=$(aws ssm list-command-invocations --region $AWS_REGION --command-id $cid \
                   --query 'CommandInvocations[0].Status' --output text)
              case $st in
                Success) echo "$name deployed ($TAG)"; return 0 ;;
                Pending|InProgress|Delayed|None) sleep 5 ;;
                *) echo "$name deploy failed: $st"
                   aws ssm get-command-invocation --region $AWS_REGION --command-id $cid --instance-id "$id" \
                     --query '[StandardOutputContent,StandardErrorContent]' --output text || true
                   return 1 ;;
              esac
            done
          }

          # backend first, then the MQTT ingest service, then the frontend that proxies to the backend
          deploy backend  $BACKEND_ID
          deploy ingest   $INGEST_ID
          deploy frontend $FRONTEND_ID
        '''
      }
    }
  }

  post {
    always { sh 'docker image prune -f || true' }
  }
}
