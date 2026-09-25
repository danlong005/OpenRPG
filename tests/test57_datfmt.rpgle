**FREE
CTL-OPT DATFMT(*USA) TIMFMT(*USA);

DCL-S myDate DATE;
DCL-S myTime TIME;
DCL-S dateStr VARCHAR(20);
DCL-S timeStr VARCHAR(20);

myDate = %DATE('2024-03-15');

// Format date as *USA (MM/DD/YYYY)
dateStr = %CHAR(myDate);
DSPLY dateStr;

// Format with ISO (default internal)
DSPLY %CHAR(myDate);

myTime = %TIME('14.30.00');
DSPLY %CHAR(myTime);

*INLR = *ON;
