**FREE
DCL-S myDate DATE;
DCL-S myDate2 DATE;
DCL-S myTime TIME;
DCL-S myTimestamp TIMESTAMP;
DCL-S result VARCHAR(50);
DCL-S days INT(10);

// Set date using %DATE BIF
myDate = %DATE('2024-03-15');
result = %CHAR(myDate);
DSPLY result;

// Set time using %TIME BIF
myTime = %TIME('14.30.00');
result = %CHAR(myTime);
DSPLY result;

// Set timestamp
myTimestamp = %TIMESTAMP('2024-03-15-14.30.00.000000');
result = %CHAR(myTimestamp);
DSPLY result;

// Date arithmetic with %DIFF
myDate2 = %DATE('2024-03-20');
days = %DIFF(myDate2 : myDate : *DAYS);
DSPLY %CHAR(days);

// %YEARS, %MONTHS, %DAYS BIFs for adding to dates
myDate2 = myDate + %DAYS(10);
result = %CHAR(myDate2);
DSPLY result;

myDate2 = myDate + %MONTHS(2);
result = %CHAR(myDate2);
DSPLY result;

myDate2 = myDate + %YEARS(1);
result = %CHAR(myDate2);
DSPLY result;

*INLR = *ON;
