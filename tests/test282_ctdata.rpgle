**FREE
// Test 282: compile-time data (CTDATA)
// A CTDATA array is loaded from the **CTDATA section that names it, after
// the program's last line. Each record holds PERRCD elements (default 1),
// each as wide as the element; a number is written as its digits, with the
// decimal point implied by the declaration.
DCL-S months CHAR(3) DIM(12) CTDATA PERRCD(6);
DCL-S rates PACKED(5:2) DIM(3) CTDATA;
DCL-S tabDays CHAR(3) DIM(3) ASCEND CTDATA;
DCL-S i INT(10);

DSPLY months(1);
DSPLY months(6);
DSPLY months(12);
FOR i = 1 TO 3;
  DSPLY %CHAR(rates(i));
ENDFOR;
IF %TLOOKUP('TUE' : tabDays);
  DSPLY 'TUE found';
ENDIF;
*INLR = *ON;
**CTDATA months
JANFEBMARAPRMAYJUN
JULAUGSEPOCTNOVDEC
**CTDATA rates
00125
01000
99999
**CTDATA tabDays
MON
TUE
WED
