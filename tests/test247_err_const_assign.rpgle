**FREE
// A CONST parameter is read-only: the caller may have passed a literal.
DCL-PR Touch;
  v INT(10) CONST;
END-PR;
Touch(1);
*INLR = *ON;
RETURN;
DCL-PROC Touch;
  DCL-PI *N;
    v INT(10) CONST;
  END-PI;
  v = 2;
END-PROC;
