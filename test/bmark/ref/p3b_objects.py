# reference for p3b_objects.eve: the same work in Python
class Point:
    def __init__(self, x=0, y=0):
        self.x = x
        self.y = y

    def move(self, dx, dy):
        self.x += dx
        self.y += dy

    def sum(self):
        return self.x + self.y


class Point3(Point):
    def __init__(self, x=0, y=0, z=0):
        super().__init__(x, y)
        self.z = z

    def total(self):
        return self.sum() + self.z


def double(p):
    p.x *= 2


made = 0
for i in range(1, 5001):
    p = Point(i, 1)
    q = Point3(i, 1, 1)
    made += p.sum() + q.total()
assert made == 25020000
walker = Point(0, 0)
for i in range(50000):
    walker.move(1, 2)
assert walker.sum() == 150000
d = Point(1, 0)
for i in range(20000):
    d.x = 1
    double(d)
assert d.x == 2
print("%d,%d,%d" % (made, walker.sum(), d.x))
