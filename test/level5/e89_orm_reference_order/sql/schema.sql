drop table if exists orders;
drop table if exists customers;
create table customers (
  id integer primary key,
  name text not null
);
create table orders (
  id integer primary key,
  customer_id integer not null references customers (id),
  total text not null
);
