**FREE
// DSPLY shows at most 52 characters, judged from declared lengths at
// compile time: 'Name: ' plus a VARCHAR(50) could be 56 even though this
// value is short. IBM i reports RNF7016.
DCL-S name VARCHAR(50) INZ('Alice');
DSPLY ('Name: ' + name);
*INLR = *ON;
