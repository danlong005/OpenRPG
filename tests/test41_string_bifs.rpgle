**FREE
DCL-S str VARCHAR(30);
DCL-S num PACKED(7:2);
DCL-S flt INT(10);

// %SUBDT - extract date part
DCL-S myDate DATE;

// %LOWER / %UPPER
str = %LOWER('HELLO WORLD');
DSPLY str;

str = %UPPER('hello world');
DSPLY str;

myDate = %DATE('2024-06-15');
flt = %SUBDT(myDate : *YEARS);
DSPLY %CHAR(flt);
flt = %SUBDT(myDate : *MONTHS);
DSPLY %CHAR(flt);
flt = %SUBDT(myDate : *DAYS);
DSPLY %CHAR(flt);

// %FLOAT
num = 3.14;
flt = %INT(%FLOAT(num) * 100);
DSPLY %CHAR(flt);

// %SQRT (via runtime)
flt = %INT(%SQRT(144));
DSPLY %CHAR(flt);

*INLR = *ON;
