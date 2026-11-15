"""Rotate the RDS master password and update both secrets. Never prints the password.

Order: new password -> RDS -> both secrets. The password file (0600) is kept if
anything fails so the state can be repaired, and removed only on full success.
"""
import json
import os
import secrets
import string
import subprocess
import sys
import time

R = "eu-west-3"
DB = "tournament-production-database-fb0cewkojymq"
URL_SECRET = "production-tournament-database-url"
PW_SECRET = "production-tournament-db-password"
d = sys.argv[1]


def aws(*args):
    return subprocess.check_output(["aws", "--region", R, *args]).decode()


def write0600(name, text):
    path = os.path.join(d, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    return path


alphabet = string.ascii_letters + string.digits
new_pw = "".join(secrets.choice(alphabet) for _ in range(40))
pw_file = write0600(".newpw.tmp", new_pw)

# Build both secret payloads before touching RDS, so nothing can fail afterwards for lack of data.
cur_url = aws("secretsmanager", "get-secret-value", "--secret-id", URL_SECRET, "--query", "SecretString", "--output", "text").strip()
scheme, rest = cur_url.split("://", 1)
userinfo, hostpart = rest.rsplit("@", 1)
user = userinfo.split(":", 1)[0]
new_url = f"{scheme}://{user}:{new_pw}@{hostpart}"
cur_pw_secret = json.loads(aws("secretsmanager", "get-secret-value", "--secret-id", PW_SECRET, "--query", "SecretString", "--output", "text"))
cur_pw_secret["password"] = new_pw
url_file = write0600(".newurl.tmp", new_url)
pws_file = write0600(".newpws.tmp", json.dumps(cur_pw_secret))
req_file = write0600(".rds.tmp", json.dumps({"DBInstanceIdentifier": DB, "MasterUserPassword": new_pw, "ApplyImmediately": True}))

aws("rds", "modify-db-instance", "--cli-input-json", "file://" + req_file, "--query", "DBInstance.DBInstanceStatus", "--output", "text")
print("RDS: mot de passe modifié")
aws("secretsmanager", "put-secret-value", "--secret-id", URL_SECRET, "--secret-string", "file://" + url_file)
aws("secretsmanager", "put-secret-value", "--secret-id", PW_SECRET, "--secret-string", "file://" + pws_file)
print("Secrets: URL et mot de passe mis à jour")

for _ in range(40):
    st = aws("rds", "describe-db-instances", "--db-instance-identifier", DB, "--query", "DBInstances[0].[DBInstanceStatus,length(PendingModifiedValues)]", "--output", "text").split()
    print("RDS statut:", st[0], "pending:", st[1])
    if st[0] == "available" and st[1] == "0":
        break
    time.sleep(10)

for p in (pw_file, url_file, pws_file, req_file):
    os.remove(p)
print("fichiers temporaires supprimés")
