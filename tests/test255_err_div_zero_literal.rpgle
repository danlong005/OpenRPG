**FREE
// A literal zero divisor is a compile-time error on IBM i (RNF0552), not a
// runtime status 102: that is for a divisor only known when the program runs.
DCL-S n INT(10);
n = %DIV(10 : 0);
*INLR = *ON;
