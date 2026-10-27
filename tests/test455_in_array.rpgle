**FREE
// The *IN array: *IN(i) is indicator i, one of 01-99, as a value and as a
// target; an index outside 1-99 is status 121. *IN on its own is all 99,
// for an assignment or CLEAR.
dcl-s i int(10);
dcl-s n int(10);
*in = *off;
for i = 50 to 52;
  *in(i) = *on;
endfor;
if *in51 and *in(52) and not *in(53);
  dsply 'set by index';
endif;
n = 0;
for i = 1 to 99;
  if *in(i);
    n += 1;
  endif;
endfor;
dsply ('on: ' + %char(n));
clear *in(51);
dsply ('51 cleared: ' + %char(*in51));
*in = *on;
dsply ('all on: ' + %char(*in99));
clear *in;
dsply ('cleared: ' + %char(*in(1)));
monitor;
  i = 100;
  *in(i) = *on;
on-error;
  dsply ('status ' + %char(%status));
endmon;
*inlr = *on;
