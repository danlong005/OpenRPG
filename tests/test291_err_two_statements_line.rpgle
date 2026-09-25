**FREE
// Only one statement is allowed on a line; nothing but a comment may follow
// a statement's semicolon. IBM i rejects the rest of the line (RNF5508).
DCL-S a INT(10);
DCL-S b INT(10);
a = 1;  b = 2;
DSPLY %CHAR(a + b);
*INLR = *ON;
