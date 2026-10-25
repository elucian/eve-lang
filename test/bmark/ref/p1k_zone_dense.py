# reference for p1k_zone_dense.eve: the same work with zoneinfo
import datetime
from zoneinfo import ZoneInfo

base = datetime.datetime(2024, 3, 31, 0, 0, 0, tzinfo=datetime.timezone.utc)
total = 0
for name in ("Europe/Bucharest", "America/New_York", "Australia/Lord_Howe"):
    zi = ZoneInfo(name)
    for k in range(20000):
        total += int((base + datetime.timedelta(seconds=k)).astimezone(zi).utcoffset().total_seconds())
print(total)
