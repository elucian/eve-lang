# reference for p1d_strings.eve: the same work in Python
import re
text = ""
for i in range(1, 6001):
    text += "line %d;" % i
hits = 0
for i in range(1, 3001):
    if re.search(r"^item[0-9]+$", "item%d" % i):
        hits += 1
assert len(text) == 58893 and hits == 3000
print("%d,%d" % (len(text), hits))
