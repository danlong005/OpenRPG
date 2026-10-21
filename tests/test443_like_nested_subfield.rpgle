**FREE
// LIKE of a subfield of a data structure nested in another, by its full
// qualified name.
dcl-ds inner_t qualified template;
  code char(4);
  amt packed(9:2);
end-ds;
dcl-ds outer qualified;
  hdr likeds(inner_t);
end-ds;
dcl-s c like(outer.hdr.code) inz('AB');
dcl-s m like(outer.hdr.amt) inz(12.34);
dsply ('[' + c + '] ' + %char(%len(c)));
dsply %char(m);
*inlr = *on;
