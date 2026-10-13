drop table if exists people;
create table people (id integer primary key, name text);
insert into people (id, name) values (1, 'ann'), (2, null);
