**FREE
DCL-S x INT(10);
DCL-S result VARCHAR(50);
x = 75;
IF x >= 90;
  result = 'A';
ELSEIF x >= 80;
  result = 'B';
ELSEIF x >= 70;
  result = 'C';
ELSE;
  result = 'F';
ENDIF;
DSPLY result;

// Test AND/OR/NOT
IF x > 50 AND x < 100;
  DSPLY 'In range';
ENDIF;

IF x < 10 OR x > 50;
  DSPLY 'Outside 10-50';
ENDIF;

IF NOT (x = 0);
  DSPLY 'Not zero';
ENDIF;
*INLR = *ON;
