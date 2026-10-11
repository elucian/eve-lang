drop table if exists customers;
create table customers (
  id integer primary key autoincrement,
  name text not null,
  city text,
  version integer not null
);
