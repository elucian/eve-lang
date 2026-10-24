# reference for p1h_time_format.eve: the same work with datetime strftime and strptime
import datetime

first = datetime.date(2000, 1, 1)
chk = 0
for i in range(20000):
    d = first + datetime.timedelta(days=i)
    text = d.strftime("%d/%m/%Y")
    back = datetime.datetime.strptime(text, "%d/%m/%Y").date()
    chk += (back - first).days
t0 = datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc)
total = 0
for i in range(20000):
    t = t0 + datetime.timedelta(milliseconds=1500 * i)
    text = t.strftime("%Y-%m-%dT%H:%M:%S.") + "%03dZ" % (t.microsecond // 1000)
    total += len(text)
print("%d,%d" % (chk, total))
