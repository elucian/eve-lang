drop table if exists orders;
drop table if exists archive;
create table orders (id integer primary key, amount text not null, created text not null);
create table archive (id integer primary key, amount text not null, created text not null);
insert into orders (id, amount, created) values (1, '10.00', '2025-11-02'), (2, '250.00', '2026-02-15'), (3, '75.50', '2025-12-30');
