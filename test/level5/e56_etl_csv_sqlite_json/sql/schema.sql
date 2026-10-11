drop table if exists sales;
create table sales (
  id integer primary key,
  product text not null,
  qty integer not null,
  unit_cents integer not null,
  region text
);
