**FREE
// DIM, LIKE and LIKEDS subfields of BASED data structures: an indicator
// array and a character array over *IN, and over %ALLOC storage an array
// of LIKEDS subfields, a LIKEDS subfield and a LIKE array. CLEAR of one
// element leaves the others.
dcl-ds line_t qualified template;
  item char(5);
  qty packed(5:0);
end-ds;
dcl-s pInd pointer inz(%addr(*in));
dcl-ds inds len(99) based(pInd) qualified;
  fkeys ind dim(24) pos(1);
  errs char(1) dim(5) pos(50);
end-ds;
dcl-s cnt int(10);
dcl-ds order based(pOrd) qualified;
  id int(10);
  lines likeds(line_t) dim(3);
  first likeds(line_t);
  codes like(cnt) dim(2);
end-ds;
dcl-s i int(10);

inds.fkeys(3) = *on;
dsply ('03: ' + %char(*in03) + ' elems ' + %char(%elem(inds.fkeys)));
*in52 = *on;
dsply ('errs(3): ' + inds.errs(3));
pOrd = %alloc(%size(order));
clear order;
order.id = 9;
for i = 1 to 3;
  order.lines(i).item = 'IT' + %char(i);
  order.lines(i).qty = i * 5;
endfor;
order.first.item = 'FIRST';
order.codes(2) = 77;
dsply (order.lines(2).item + %char(order.lines(2).qty) + ' ' + order.first.item
       + ' ' + %char(order.codes(2)) + ' ' + %char(%size(order)));
clear order.lines(2);
dsply ('[' + order.lines(2).item + '] ' + %char(order.lines(3).qty));
*inlr = *on;
