**FREE
// A BASED data structure without QUALIFIED: its DIM subfield is written
// bare, fkeys(i), and cleared bare. A LIKEDS array whose layout has a
// LIKEDS subfield of its own: buf.l(2).price.val.
dcl-ds amt_t qualified template;
  cur char(3);
  val packed(7:2);
end-ds;
dcl-ds line_t qualified template;
  item char(5);
  price likeds(amt_t);
end-ds;
dcl-ds inds len(99) based(pInd);
  fkeys ind dim(24) pos(1);
end-ds;
dcl-ds buf based(pBuf) qualified;
  l likeds(line_t) dim(2);
end-ds;
dcl-s i int(10);
pInd = %addr(*in);
fkeys(5) = *on;
for i = 1 to %elem(fkeys);
  if fkeys(i);
    dsply ('key ' + %char(i) + ' ' + %char(*in05));
  endif;
endfor;
clear fkeys;
dsply ('after clear ' + %char(*in05));
pBuf = %alloc(%size(buf));
buf.l(2).price.cur = 'EUR';
buf.l(2).price.val = 19.99;
dsply (buf.l(2).price.cur + ' ' + %char(buf.l(2).price.val) + ' ' + %char(%size(buf)));
*inlr = *on;
