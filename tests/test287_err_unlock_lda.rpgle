**FREE
// The local data area is never locked, so IBM i rejects UNLOCK of a field
// defined on it (RNF7091).
DCL-S lda CHAR(20) DTAARA(*LDA);
IN lda;
UNLOCK lda;
*INLR = *ON;
