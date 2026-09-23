**FREE
// The rule holds in each subprocedure too: its declarations come before its
// own first calculation. Declaring at the top of the procedure body is fine
// even though the main procedure has already run code; declaring after a
// calculation inside the procedure is out of sequence (RNF0724).
DCL-S total INT(10);
total = 1;
Work();
*INLR = *ON;
RETURN;

DCL-PROC Work;
  DCL-S first INT(10);
  first = total + 1;
  DCL-S late INT(10);
  late = first * 2;
END-PROC;
