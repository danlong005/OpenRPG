**FREE
// Test 53: Date/Time BIFs - %HOURS, %MINUTES, %SECONDS, %SUBDT for time
DCL-S t1 TIME;
DCL-S t2 TIME;
DCL-S diff INT(10);
DCL-S hr INT(10);
DCL-S mn INT(10);

t1 = %TIME('14.30.00');
t2 = %TIME('10.15.00');

// %DIFF with *HOURS
diff = %DIFF(t1 : t2 : *HOURS);
DSPLY %CHAR(diff);

// %DIFF with *MINUTES
diff = %DIFF(t1 : t2 : *MINUTES);
DSPLY %CHAR(diff);

// %SUBDT with *HOURS
hr = %SUBDT(t1 : *HOURS);
DSPLY %CHAR(hr);

// %SUBDT with *MINUTES
mn = %SUBDT(t1 : *MINUTES);
DSPLY %CHAR(mn);

// Time + %HOURS duration
t2 = t1 + %HOURS(2);
DSPLY %CHAR(t2);

*INLR = *ON;
