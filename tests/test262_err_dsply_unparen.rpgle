**FREE
// DSPLY's operands are separated by blanks (message, message queue,
// response), so an expression must be in parentheses. Without them IBM i
// reports RNF0637.
DCL-S n INT(10) INZ(5);
DSPLY 'Count: ' + %CHAR(n);
*INLR = *ON;
