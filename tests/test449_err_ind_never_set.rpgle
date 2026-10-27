**FREE
// *IN55 is tested but nothing sets it: IBM i rejects the program (RNF7030).
// A display file or an I-spec indicator would count as setting it.
dcl-s x int(10);
if *in55;
  x = 1;
endif;
*inlr = *on;
