**FREE
// An array of LIKEDS subfields in a data structure, with DIM written after
// LIKEDS or before it, and a LIKE subfield with DIM. %SIZE of a data
// structure is its length in bytes; of an array, one element's.
// INZ on the data structure reaches every element; CLEAR of the array
// subfield clears them all.
dcl-ds line_t qualified template;
  item char(10);
  qty packed(5:0);
end-ds;
dcl-ds order qualified inz;
  id int(10);
  lines likeds(line_t) dim(3);
  spare dim(2) likeds(line_t);
  codes dim(2) like(order.id);
end-ds;
dcl-s i int(10);
order.id = 7;
for i = 1 to %elem(order.lines);
  order.lines(i).item = 'ITEM' + %char(i);
  order.lines(i).qty = i * 10;
endfor;
order.spare(2).item = 'SPARE';
order.spare(2).qty = 99;
order.codes(1) = 5;
order.codes(2) = order.codes(1) + 1;
for i = 1 to %elem(order.lines);
  dsply (order.lines(i).item + %char(order.lines(i).qty));
endfor;
dsply (order.spare(2).item + %char(order.spare(2).qty));
dsply ('spare(1) [' + order.spare(1).item + '] ' + %char(order.spare(1).qty));
dsply ('codes ' + %char(order.codes(1)) + ' ' + %char(order.codes(2)));
dsply ('elem ' + %char(%elem(order.lines)) + ' ' + %char(%elem(order.spare)));
dsply ('size ' + %char(%size(order)) + ' ' + %char(%size(order.lines))
       + ' ' + %char(%size(order.lines(2))));
clear order.lines;
dsply ('cleared [' + order.lines(1).item + '] ' + %char(order.lines(3).qty));
clear order.spare(2);
clear order.codes;
dsply ('[' + order.spare(2).item + '] ' + %char(order.spare(2).qty)
       + ' codes ' + %char(order.codes(1) + order.codes(2)));
*inlr = *on;
