"""Copy DATABASE_URL from task definition :6 into a new Secrets Manager secret.

The value is never printed: it goes through a 0600 temp file that is removed
right after the aws call. Prints only the secret ARN.
"""
import json
import os
import subprocess
import sys

R = "eu-west-3"
td = json.loads(subprocess.check_output([
    "aws", "ecs", "describe-task-definition", "--region", R,
    "--task-definition", "production-tournament-server:6",
    "--query", "taskDefinition", "--output", "json",
]))
url = next(e["value"] for e in td["containerDefinitions"][0]["environment"] if e["name"] == "DATABASE_URL")

path = os.path.join(sys.argv[1], ".dburl.tmp")
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    f.write(url)
try:
    arn = subprocess.check_output([
        "aws", "secretsmanager", "create-secret", "--region", R,
        "--name", "production-tournament-database-url",
        "--description", "Full DATABASE_URL (password URL-encoded) injected into the ECS task",
        "--secret-string", "file://" + path,
        "--query", "ARN", "--output", "text",
    ])
    print(arn.decode().strip())
finally:
    os.remove(path)
