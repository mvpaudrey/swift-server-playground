import sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src).read()
a = "    Description: Maximum number of ECS tasks for auto-scaling\n"
b = a + "\n  TaskDefinitionArn:\n    Type: String\n    Description: Task definition revision the ECS service runs (required, no default).\n"
c = "      TaskDefinition: !Ref TaskDefinition\n      DesiredCount: !Ref DesiredCount"
d = "      TaskDefinition: !Ref TaskDefinitionArn\n      DesiredCount: !Ref DesiredCount"
assert t.count(a) == 1 and t.count(c) == 1
open(dst, "w").write(t.replace(a, b).replace(c, d))
