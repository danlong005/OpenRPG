**FREE
DCL-S codes CHAR(3) DIM(4);
DCL-S names VARCHAR(20) DIM(4);
DCL-S found IND;
DCL-S count INT(10);

// %ELEM on varying array
DCL-S dynArr INT(10) DIM(*VAR:50);

// Set up paired tables
codes(1) = 'NYC';
codes(2) = 'LAX';
codes(3) = 'ORD';
codes(4) = 'DFW';

names(1) = 'New York';
names(2) = 'Los Angeles';
names(3) = 'Chicago';
names(4) = 'Dallas';

// %TLOOKUP - found
found = %TLOOKUP('LAX': codes);
IF found;
  DSPLY 'Found LAX';
ENDIF;

// %TLOOKUP - not found
found = %TLOOKUP('SFO': codes);
IF NOT found;
  DSPLY 'SFO not found';
ENDIF;

// %TLOOKUPGE
found = %TLOOKUPGE('LAX': codes);
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
