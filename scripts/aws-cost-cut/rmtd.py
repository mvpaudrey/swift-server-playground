import sys
p = sys.argv[1]
t = open(p).read()
a = "  # ECS Task Definition\n  TaskDefinition:\n"
b = "  # ECS Service\n"
i, j = t.index(a), t.index(b)
assert t.count(a) == 1 and t.count(b) == 1 and i < j
note = "  # The task definition is registered outside this stack (see TaskDefinitionArn): it needs a\n  # URL-encoded DATABASE_URL injected from Secrets Manager, which CloudFormation cannot build.\n\n"
open(p, "w").write(t[:i] + note + t[j:])
