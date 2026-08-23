**FREE
CTL-OPT NOMAIN;

// Callee for test175's traditional CALL/PARM. Parameters are declared
// without VALUE, so they generate C++ reference parameters — the same
// signature the caller's CALL synthesizes from its PARM operands' types.
DCL-PROC ADDONE EXPORT;
  DCL-PI ADDONE;
    n INT(10);
    msg CHAR(10);
  END-PI;
  n = n + 1;
  msg = 'called';
END-PROC;
