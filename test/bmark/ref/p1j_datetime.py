# reference for p1j_datetime.eve: the same work with zoneinfo and datetime
import datetime
from zoneinfo import ZoneInfo

z = ZoneInfo("America/New_York")
base = datetime.datetime(2020, 1, 1, tzinfo=datetime.timezone.utc)
chk = 0
for k in range(60000):
    dt = (base + datetime.timedelta(seconds=1000 * k)).astimezone(z)
    chk += dt.hour + dt.day + int(dt.utcoffset().total_seconds())
    if k % 20 == 0:
        made = dt.replace(tzinfo=None).replace(tzinfo=z)
        chk += int((made - dt).total_seconds())
print(chk)
