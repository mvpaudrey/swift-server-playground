"""Register task definition :7 = :6 with DATABASE_URL moved from environment to secrets.

The plaintext value is dropped in memory before anything is written to disk;
only non-secret JSON reaches the temp file. Prints the new revision ARN.
"""
import json
import os
import subprocess
import sys

R = "eu-west-3"
SECRET_ARN = sys.argv[2]

td = json.loads(subprocess.check_output([
    "aws", "ecs", "describe-task-definition", "--region", R,
    "--task-definition", "production-tournament-server:6",
    "--query", "taskDefinition", "--output", "json",
]))

keep = ("family", "taskRoleArn", "executionRoleArn", "networkMode", "containerDefinitions",
        "volumes", "placementConstraints", "requiresCompatibilities", "cpu", "memory", "runtimePlatform")
new = {k: td[k] for k in keep if k in td}

c = new["containerDefinitions"][0]
c["environment"] = [e for e in c["environment"] if e["name"] != "DATABASE_URL"]
c["secrets"] = c.get("secrets", []) + [{"name": "DATABASE_URL", "valueFrom": SECRET_ARN}]
assert not any("postgres://" in json.dumps(v) for v in c["environment"])

path = os.path.join(sys.argv[1], "td7.json")
with open(path, "w") as f:
    json.dump(new, f)
try:
    print(subprocess.check_output([
        "aws", "ecs", "register-task-definition", "--region", R,
        "--cli-input-json", "file://" + path,
        "--query", "taskDefinition.taskDefinitionArn", "--output", "text",
    ]).decode().strip())
finally:
    os.remove(path)
