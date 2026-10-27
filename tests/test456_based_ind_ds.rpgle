**FREE
// Named indicators: a data structure BASED on %ADDR(*IN), with LEN. Its
// subfields are the indicator bytes, so setting either one sets the other;
// %LOOKUP searches *IN; CLEAR of the data structure turns them off.
dcl-s pInd pointer inz(%addr(*in));
dcl-ds inds len(99) based(pInd);
  exitKey ind pos(3);
  cancelKey ind pos(12);
  errors char(10) pos(50);
  err1 ind pos(50);
end-ds;
dcl-s n int(10);

*in03 = *on;
if exitKey;
  dsply 'exit via name';
endif;
cancelKey = *on;
if *in12;
  dsply '*IN12 via ds';
endif;
errors = '0010000000';
dsply ('52: ' + %char(*in52) + ' 50: ' + %char(err1));
n = %lookup(*on : *in);
dsply ('first on: ' + %char(n));
n = %lookup(*on : *in : 4);
dsply ('from 4: ' + %char(n));
clear inds;
dsply ('after clear: ' + %char(*in03) + %char(*in12) + %char(*in52));
dsply ('bytes 1-5: ' + %subst(inds : 1 : 5));
*inlr = *on;
