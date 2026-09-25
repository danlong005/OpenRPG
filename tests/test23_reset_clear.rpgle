**FREE
CTL-OPT DFTACTGRP(*NO);
DCL-S myInt INT(10) INZ(42);
DCL-S myStr VARCHAR(50) INZ('Hello');
DCL-S myDec PACKED(9:2) INZ(3.14);
DCL-S myChar CHAR(10) INZ('RPG');
DCL-S nums INT(10) DIM(3) INZ(7);
DCL-DS rec QUALIFIED TEMPLATE;
  id   INT(10);
  code CHAR(3);
END-DS;
DCL-DS one LIKEDS(rec);
DCL-DS many LIKEDS(rec) DIM(2);
DCL-S line VARCHAR(52);

// Show initial values
DSPLY %CHAR(myInt);
DSPLY myStr;

// Change values
myInt = 100;
myStr = 'Changed';
myDec = 99.99;
myChar = 'Modified';

DSPLY %CHAR(myInt);
DSPLY myStr;

// RESET restores to INZ value
RESET myInt;
RESET myStr;
DSPLY %CHAR(myInt);
DSPLY myStr;

// CLEAR sets to type default (0, empty string, etc.)
CLEAR myInt;
CLEAR myStr;
CLEAR myDec;
CLEAR myChar;
DSPLY %CHAR(myInt);
DSPLY myStr;
DSPLY %CHAR(myDec);
DSPLY myChar;

// CLEAR on a whole array clears every element, and on a data structure
// every subfield -- in each element of a DS array, and through a LIKEDS
// parameter too
one.id = 5;
one.code = 'ABC';
many(2).id = 6;
many(2).code = 'DEF';
CLEAR nums;
CLEAR one;
CLEAR many;
line = %CHAR(nums(3)) + '|' + %CHAR(one.id) + '|' + one.code + '|'
     + %CHAR(many(2).id) + '|' + many(2).code + '|';
DSPLY line;
one.id = 8;
line = ClearRec(one);
DSPLY line;

*INLR = *ON;

DCL-PROC ClearRec;
  DCL-PI *N VARCHAR(52);
    r LIKEDS(rec);
  END-PI;
  CLEAR r;
  RETURN %CHAR(r.id) + '|' + r.code + '|';
END-PROC;
