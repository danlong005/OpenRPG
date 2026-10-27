**FREE
// The RPG cycle: a program with no primary file that reaches the end of
// its calculations with LR off runs them again. Fields keep their values
// from one pass to the next, and the pass that sets LR runs to its end.
dcl-s n int(10);
n += 1;
dsply ('pass ' + %char(n));
if n = 3;
  *inlr = *on;
endif;
dsply ('after ' + %char(n));
