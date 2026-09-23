**FREE
// Assignment holds a value to the target's declaration.
//
// Declarations were right, but assignment was a plain C++ assignment: a
// CHAR(5) assigned 'AB' held two bytes, one assigned 'ABCDEFG' held seven,
// and a PACKED(9:2) assigned 1.239 held 1.239 — which %CHAR then rounded
// to 1.24, where RPG truncates to 1.23. Concatenation, %LEN and %SUBST
// all saw the wrong value. Brackets below make the padding visible.
DCL-S c    CHAR(5);
DCL-S v    VARCHAR(4);
DCL-S p    PACKED(9:2);
DCL-S big  PACKED(10:2);
DCL-S q    LIKE(p);
DCL-S arr  CHAR(3) DIM(2);
DCL-S n    INT(10);
DCL-S shadow INT(10);

DCL-DS d QUALIFIED;
  s   CHAR(4);
  m   CHAR(2) DIM(2);
  amt PACKED(7:2);
END-DS;

DCL-DS rows QUALIFIED DIM(2);
  sku CHAR(4);
END-DS;

DCL-PR Local VARCHAR(20);
END-PR;

// CHAR: pad with blanks, or truncate on the right.
c = 'AB';
DSPLY ('RESULT:PAD=[' + c + '] ' + %CHAR(%LEN(c)));
c = 'ABCDEFG';
DSPLY ('RESULT:TRUNC=[' + c + ']');
DSPLY ('RESULT:CONCAT=[' + 'x' + c + 'y' + ']');

// Every target shape: array element, subfield, DIM'd subfield element,
// element of a DS array.
arr(1) = 'Z';
d.s = 'LONGER';
d.m(2) = 'Q';
rows(2).sku = 'W';
DSPLY ('RESULT:SHAPES=[' + arr(1) + '][' + d.s + '][' + d.m(2) + '][' + rows(2).sku + ']');

// VARCHAR: truncated past its maximum, never padded.
v = 'ABCDEFG';
DSPLY ('RESULT:VMAX=[' + v + ']');
v = 'X';
DSPLY ('RESULT:VSHORT=[' + v + '] ' + %CHAR(%LEN(v)));

// PACKED: excess decimals truncated, not rounded — including values that
// are not exact in binary (0.29), negatives, and a full-width value.
p = 1.239;
DSPLY ('RESULT:TRUNCDEC=' + %CHAR(p));
p = 0.29;
DSPLY ('RESULT:BINARY=' + %CHAR(p));
p = -1.239;
DSPLY ('RESULT:NEG=' + %CHAR(p));
big = 99999999.99;
DSPLY ('RESULT:FULL=' + %CHAR(big));
d.amt = 3.14159;
DSPLY ('RESULT:SUBDEC=' + %CHAR(d.amt));

// LIKE carries the scale; (H) still rounds; integers truncate as before.
q = 5.678;
DSPLY ('RESULT:LIKE=' + %CHAR(q));
EVAL(H) p = 1.235;
DSPLY ('RESULT:HALF=' + %CHAR(p));
n = 7.9;
DSPLY ('RESULT:INT=' + %CHAR(n));

// EVALR right-adjusts within the declared length.
c = 'AB';
EVALR c = 'XY';
DSPLY ('RESULT:EVALR=[' + c + ']');

// A procedure's local of the same name must not change how the global is
// held: SHADOW here stays an INT, not the procedure's VARCHAR.
shadow = 41 + 1;
DSPLY ('RESULT:SHADOW=' + %CHAR(shadow) + ' ' + %TRIM(Local()));

*INLR = *ON;
RETURN;

DCL-PROC Local;
  DCL-PI Local VARCHAR(20);
  END-PI;
  DCL-S shadow VARCHAR(20);
  shadow = 'local';
  RETURN shadow;
END-PROC;
