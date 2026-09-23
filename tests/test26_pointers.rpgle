**FREE
DCL-S myInt INT(10);
DCL-S myStr VARCHAR(50);
DCL-S ptr1 POINTER;
DCL-S ptr2 POINTER;

// %SIZE of pointer
DCL-S ptrSize INT(10);

// Basic pointer operations
myInt = 42;
ptr1 = %ADDR(myInt);

IF ptr1 <> *NULL;
  DSPLY 'ptr1 not null';
ENDIF;

// Null pointer check
ptr2 = *NULL;
IF ptr2 = *NULL;
  DSPLY 'ptr2 is null';
ENDIF;

// Assign pointer
ptr2 = ptr1;
IF ptr2 <> *NULL;
  DSPLY 'ptr2 copied';
ENDIF;

// Pointer to string
myStr = 'Hello Pointer';
ptr1 = %ADDR(myStr);
IF ptr1 <> *NULL;
  DSPLY 'String pointer ok';
ENDIF;

ptrSize = %SIZE(ptr1);
DSPLY %CHAR(ptrSize);

*INLR = *ON;
