drop table if exists pairs;
create table pairs (id integer primary key, a text not null, b text not null);
insert into pairs (id, a, b) values (1, '10', '4'), (2, '1', '0'), (3, '9', '3');
