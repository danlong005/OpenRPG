**FREE
// TEST(D), (T) and (Z) check a character or numeric field as a date, time
// or timestamp. IBM i rejects them on a field that already is one (RNF7523);
// TEST(E) checks such a field.
DCL-S d DATE;
TEST(DE) d;
DSPLY 'done';
*INLR = *ON;
