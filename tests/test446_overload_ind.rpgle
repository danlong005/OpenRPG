**FREE
// OVERLOAD told an indicator from a string: an indicator argument calls the
// IND candidate, a character one the string candidate. An OpenRPG
// extension: on IBM i an indicator is CHAR(1), so both candidates match
// (RNF3246; IBM Ideas IBMI-I-4227, declined).
dcl-pr assertEqual overload(assertEqual_string : assertEqual_ind);
dcl-pr assertEqual_string;
  a varchar(20) const;
  b varchar(20) const;
end-pr;
dcl-pr assertEqual_ind;
  a ind const;
  b ind const;
end-pr;
dcl-s f ind inz(*on);
assertEqual(f : *on);
assertEqual('x' : 'y');
*inlr = *on;
dcl-proc assertEqual_string;
  dcl-pi *n;
    a varchar(20) const;
    b varchar(20) const;
  end-pi;
  dsply ('string ' + a + b);
end-proc;
dcl-proc assertEqual_ind;
  dcl-pi *n;
    a ind const;
    b ind const;
  end-pi;
  dsply ('ind ' + a + b);
end-proc;
