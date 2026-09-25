**FREE
// %TLOOKUP searches a table: an array whose name begins with TAB (IBM:
// RNF0597). %TLOOKUPLT/LE/GT/GE also need it in ASCEND or DESCEND order
// (RNF0507). A table is not indexed (RNF0752); it is filled from
// compile-time data, the **CTDATA section at the end.
DCL-S tabCodes CHAR(3) DIM(4) ASCEND CTDATA;
DCL-S found IND;
DCL-S count INT(10);

// %ELEM on varying array
DCL-S dynArr INT(10) DIM(*VAR:50);

// %TLOOKUP - found
found = %TLOOKUP('LAX': tabCodes);
IF found;
  DSPLY 'Found LAX';
ENDIF;

// %TLOOKUP - not found
found = %TLOOKUP('SFO': tabCodes);
IF NOT found;
  DSPLY 'SFO not found';
ENDIF;

// %TLOOKUPGE
found = %TLOOKUPGE('LAX': tabCodes);
IF found;
  DSPLY 'Found >= LAX';
ENDIF;

%ELEM(dynArr) = 3;
dynArr(1) = 10;
dynArr(2) = 20;
dynArr(3) = 30;
count = %ELEM(dynArr);
DSPLY %CHAR(count);  // 3

// Resize up
%ELEM(dynArr) = 5;
dynArr(4) = 40;
dynArr(5) = 50;
count = %ELEM(dynArr);
DSPLY %CHAR(count);  // 5

*INLR = *ON;
**CTDATA tabCodes
DFW
LAX
NYC
ORD
