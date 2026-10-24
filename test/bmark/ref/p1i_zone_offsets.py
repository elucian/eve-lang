# reference for p1i_zone_offsets.eve: the same work with zoneinfo
import datetime
from zoneinfo import ZoneInfo

epoch = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
total = 0
for name in ("Europe/Bucharest", "America/New_York", "Australia/Lord_Howe"):
    zi = ZoneInfo(name)
    x = 123456789
    for k in range(20000):
        x = (x * 1103515245 + 12345) % 2147483648
        t = -2208988800 + (x * 2939) % 6311520000
        total += int((epoch + datetime.timedelta(seconds=t)).astimezone(zi).utcoffset().total_seconds())
print(total)
