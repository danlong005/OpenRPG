**FREE
// OVERLOAD whose candidate procedures also have their own DCL-PR, declared
// after the OVERLOAD, as an include file of prototypes would.
dcl-pr show overload(show_int : show_text);
dcl-pr show_int;
  v int(10) const;
end-pr;
dcl-pr show_text;
  v varchar(20) const;
end-pr;
dcl-s n int(10) inz(5);
show(n);
show('x');
*inlr = *on;
dcl-proc show_int;
  dcl-pi *n;
    v int(10) const;
  end-pi;
  dsply ('int ' + %char(v));
end-proc;
dcl-proc show_text;
  dcl-pi *n;
    v varchar(20) const;
  end-pi;
  dsply ('text ' + v);
end-proc;
