**FREE
// BASED data structures over %ALLOC storage: one LIKEDS a template, one
// with LEN, both on a pointer BASED declares. Numeric subfields are in IBM
// i formats, and %SIZE needs no pointer. A procedure bases one on a
// parameter, and a *NULL basing pointer is status 222.
dcl-ds rec_t qualified template;
  code char(4);
  qty packed(7:2);
  cnt int(10);
  z zoned(5:0);
end-ds;
dcl-ds view likeds(rec_t) based(pMem);
dcl-ds raw len(19) based(pMem);
  all char(19);
end-ds;
dsply ('sizes ' + %char(%size(view)) + ' ' + %char(%size(rec_t)));
pMem = %alloc(19);
view.code = 'AB12';
view.qty = -123.45;
view.cnt = 70000;
view.z = 42;
dsply (view.code + ' ' + %char(view.qty) + ' ' + %char(view.cnt) + ' ' + %char(view.z));
dsply ('size ' + %char(%size(raw)));
showIt(pMem);
dealloc pMem;
monitor;
  pMem = *null;
  dsply view.code;
on-error;
  dsply ('unset: ' + %char(%status));
endmon;
*inlr = *on;

dcl-proc showIt;
  dcl-pi *n;
    p pointer value;
  end-pi;
  dcl-ds loc likeds(rec_t) based(p);
  dsply ('in proc: ' + loc.code + ' ' + %char(loc.cnt));
end-proc;
