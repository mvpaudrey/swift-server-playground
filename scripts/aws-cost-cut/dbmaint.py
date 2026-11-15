"""Run one SQL statement against the production database from a one-off Fargate task.

The RDS instance is private, so the statement runs in a throwaway task that sits in the
VPC, uses the ECS security group, and gets DATABASE_URL injected from Secrets Manager
(this script never reads the URL). Output comes back through CloudWatch Logs.

    python3 dbmaint.py "SELECT count(*) FROM device_registrations"

The task definition is registered for the run and deregistered afterwards.
"""
import json
import subprocess
import sys
import time

R = "eu-west-3"
CLUSTER = "production-tournament-cluster"
FAMILY = "production-db-maintenance"
LOG_GROUP = "/ecs/production-tournament-server"
STREAM_PREFIX = "dbmaint"
SUBNET = "subnet-020195585207e7058"  # public, AZ1: the task needs a public IP to pull the image
SECURITY_GROUP = "sg-0dc01b426ccb246ab"  # ECSSecurityGroup, allowed to reach RDS
SECRET_ARN = "arn:aws:secretsmanager:eu-west-3:757242163270:secret:production-tournament-database-url-6CA7JH"
EXEC_ROLE = "arn:aws:iam::757242163270:role/tournament-production-ECSTaskExecutionRole-yZCX6jO4HNMp"


def aws(*args):
    return subprocess.check_output(["aws", "--region", R, *args]).decode()


sql = sys.argv[1]
td = {
    "family": FAMILY,
    "networkMode": "awsvpc",
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512",
    "executionRoleArn": EXEC_ROLE,
    "containerDefinitions": [{
        "name": "psql",
        "image": "postgres:16-alpine",
        "essential": True,
        "entryPoint": ["sh", "-c"],
        "command": ['exec psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -c "$SQL"'],
        "environment": [{"name": "SQL", "value": sql}],
        "secrets": [{"name": "DATABASE_URL", "valueFrom": SECRET_ARN}],
        "logConfiguration": {"logDriver": "awslogs", "options": {
            "awslogs-group": LOG_GROUP, "awslogs-region": R, "awslogs-stream-prefix": STREAM_PREFIX}},
    }],
}

td_arn = json.loads(aws("ecs", "register-task-definition", "--cli-input-json", json.dumps(td)))["taskDefinition"]["taskDefinitionArn"]
try:
    net = {"awsvpcConfiguration": {"subnets": [SUBNET], "securityGroups": [SECURITY_GROUP], "assignPublicIp": "ENABLED"}}
    run = json.loads(aws("ecs", "run-task", "--cluster", CLUSTER, "--launch-type", "FARGATE",
                         "--task-definition", td_arn, "--network-configuration", json.dumps(net)))
    if run.get("failures"):
        sys.exit(f"run-task failed: {run['failures']}")
    task_arn = run["tasks"][0]["taskArn"]
    task_id = task_arn.rsplit("/", 1)[1]
    for _ in range(60):
        t = json.loads(aws("ecs", "describe-tasks", "--cluster", CLUSTER, "--tasks", task_arn))["tasks"][0]
        if t["lastStatus"] == "STOPPED":
            break
        time.sleep(5)
    code = t["containers"][0].get("exitCode")
    time.sleep(3)  # let the log stream flush
    stream = f"{STREAM_PREFIX}/psql/{task_id}"
    try:
        ev = json.loads(aws("logs", "get-log-events", "--log-group-name", LOG_GROUP, "--log-stream-name", stream, "--query", "events[].message", "--output", "json"))
        print("\n".join(ev))
    except subprocess.CalledProcessError:
        print("(pas de logs)", t.get("stoppedReason"), t["containers"][0].get("reason"))
    print(f"[exit code: {code}]")
finally:
    aws("ecs", "deregister-task-definition", "--task-definition", td_arn)
