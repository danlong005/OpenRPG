**free

// Test 86: SQL end-to-end with data structure FETCH INTO

dcl-ds row qualified;
  id packed(10:0);
  name varchar(50);
  salary varchar(20);
end-ds;

dcl-s connStr varchar(200);

// DSPLY shows at most 52 characters (IBM i RNF7016)
DCL-S dspLine VARCHAR(52);

connStr = 'Driver={SQLite3};Database=/tmp/rpgc_test86.sqlite;';
exec sql connect using :connStr;

exec sql create table emp86 (
  id integer primary key,
  name varchar(50),
  salary decimal(9,2)
);

exec sql insert into emp86 values(1, 'Alice', 75000.00);
exec sql insert into emp86 values(2, 'Bob', 65000.00);
exec sql insert into emp86 values(3, 'Charlie', 90000.00);

exec sql declare c1 cursor for
         select id, name, salary from emp86 order by id;

exec sql open c1;

exec sql fetch next from c1 into :row;
dow sqlstate < '02000';
  dspLine = (%trim(%char(row.id)) + ' ' + %trim(row.name) + ' ' + %trim(row.salary));
  DSPLY dspLine;
  exec sql fetch next from c1 into :row;
enddo;

exec sql close c1;

exec sql drop table emp86;
exec sql disconnect;

*inlr = *on;
return;
