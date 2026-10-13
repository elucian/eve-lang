drop table if exists orders;
create table orders (id integer primary key, amount text not null, country text not null, note text);
insert into orders (id, amount, country, note) values (1, '50.00', 'FR', null), (2, '200.00', 'DE', 'rush'), (3, '120.00', 'FR', null);
