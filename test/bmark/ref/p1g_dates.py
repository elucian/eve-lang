# reference for p1g_dates.eve: the same work with datetime.date
import datetime
import calendar


def add_months(d, n):
    t = d.year * 12 + (d.month - 1) + n
    y, m = divmod(t, 12)
    m += 1
    return datetime.date(y, m, min(d.day, calendar.monthrange(y, m)[1]))


start = datetime.date(2000, 1, 1)
chk = 0
saturdays = 0
for i in range(40000):
    d = start + datetime.timedelta(days=i)
    chk += d.year + d.month + d.day + d.isoweekday() + d.isocalendar()[1]
    e = add_months(d, 5)
    chk += (e - d).days
    if d.isoweekday() == 6:
        saturdays += 1
print("%d,%d" % (chk, saturdays))
