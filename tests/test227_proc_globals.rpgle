**FREE
// A subprocedure sees the module's globals, which is what RPG says: every
// declaration in the main source section is scoped to the whole module,
// mainline and subprocedures alike. These used to be emitted as locals of
// main(), so any reference from a DCL-PROC failed to compile outright.
//
// Covers a plain field, a data structure, an array, a named constant and
// the indicator array, since each is emitted by a different path, plus a
// write from a procedure that the mainline must then observe.

DCL-C Rate 3;

DCL-S counter INT(5) INZ(10);
DCL-S label   CHAR(10) INZ('start');
DCL-S nums    INT(5) DIM(3);

DCL-DS totals QUALIFIED;
  amount PACKED(9:2);
  stamp    CHAR(4);
END-DS;

nums(1) = 7;
totals.amount = 100.50;
totals.stamp = 'INIT';

CALLP Bump();
CALLP Restamp();

DSPLY ('RESULT:COUNTER=' + %CHAR(counter));
DSPLY ('RESULT:LABEL=' + %TRIM(label));
DSPLY ('RESULT:NUM1=' + %CHAR(nums(1)));
// Reported as whole cents: %CHAR on a PACKED subfield of a DS still
// prints 110.000000, because a subfield's declared scale is lost in
// codegen (see TODO.md). That is a separate defect from the one this
// test guards, so don't pin it here.
DSPLY ('RESULT:AMOUNT=' + %CHAR(%INT(totals.amount * 100)));
DSPLY ('RESULT:STAMP=' + %TRIM(totals.stamp));
DSPLY ('RESULT:IND42=' + %CHAR(*IN42));

*INLR = *ON;
RETURN;

// Reads and writes a scalar global, an array global and a named constant.
DCL-PROC Bump;
  DCL-PI Bump;
  END-PI;
  counter = counter + Rate;
  nums(1) = nums(1) * Rate;
  *IN42 = *ON;
END-PROC;

// Writes a DS subfield and a character global the mainline then reports.
DCL-PROC Restamp;
  DCL-PI Restamp;
  END-PI;
  totals.amount = totals.amount + 9.50;
  totals.stamp = 'DONE';
  label = 'restamped';
END-PROC;
