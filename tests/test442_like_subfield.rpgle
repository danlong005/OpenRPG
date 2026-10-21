**FREE
// LIKE(name) declares a field with name's type, length and scale: a
// standalone field, or a subfield of a qualified data structure, from a
// standalone declaration or a subfield of another data structure. The new
// field starts as its type's initial value (a CHAR(n) is n blanks), and
// takes INZ like any other declaration.
dcl-s a char(7);
dcl-s p packed(7:2);
dcl-ds ds_a qualified;
  f1 char(7);
  amt packed(7:2);
end-ds;
dcl-ds ds_b qualified;
  g1 like(ds_a.f1);
  g2 like(ds_a.amt);
end-ds;
dcl-s b like(a);
dcl-s c like(a) inz('xy');
dcl-s q like(p) inz(2.25);
dcl-s s like(ds_a.f1);
dcl-s m like(ds_a.amt) inz(1.5);

dsply ('[' + b + '] ' + %char(%len(b)));
dsply ('[' + c + ']');
dsply %char(q);
s = 'abcdefghij';
dsply ('[' + s + '] ' + %char(%len(s)));
m = m * 3;
dsply %char(m);
ds_b.g1 = 'klmnopqrst';
ds_b.g2 = 3.14159;
dsply ('[' + ds_b.g1 + ']');
dsply %char(ds_b.g2);
*inlr = *on;
