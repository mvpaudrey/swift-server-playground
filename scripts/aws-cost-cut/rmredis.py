import sys
p = sys.argv[1]
t = open(p).read()
bar = "  # ========================================\n"

def cut(t, start, end):
    assert t.count(start) == 1 and t.count(end) == 1, (start, end)
    i, j = t.index(start), t.index(end)
    assert i < j
    return t[:i] + t[j:]

t = cut(t, "  CacheNodeType:\n", "  ContainerCpu:\n")
t = cut(t, "  RedisSecurityGroup:\n", bar + "  # RDS PostgreSQL Database\n")
t = cut(t, bar + "  # ElastiCache Redis\n", bar + "  # Network Load Balancer")
t = cut(t, "  RedisEndpoint:\n", "  ECRRepositoryURI:\n")
open(p, "w").write(t)
