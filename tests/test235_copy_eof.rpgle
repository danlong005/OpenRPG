**FREE
// /EOF in a /COPY member ends that member, not the compile.
//
// It used to end the whole scan (yyterminate), so every line after the
// /COPY was silently discarded: a program that declared nothing and did
// nothing, compiled with exit status 0.
/COPY tests/copybook_free_eof.rpgle
DCL-S after VARCHAR(10) INZ('after');
DSPLY ('RESULT:COPY=' + fromCopy);
DSPLY ('RESULT:AFTER=' + after);
*INLR = *ON;
