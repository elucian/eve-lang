drop table if exists orders;
create table orders (
  id integer primary key,
  amount text not null
);
