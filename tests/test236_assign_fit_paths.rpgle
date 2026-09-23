**FREE
// Values stored by something other than EVAL fit the target's declaration.
//
// Test 231 covers EVAL. The same rule applies wherever a declared field is
// stored into — a VALUE parameter, a procedure's return value, a field
// filled by XML-INTO or DATA-INTO — and each of these assigned the raw
// value: a CHAR(10) VALUE parameter passed 'AB' held two bytes, a
// procedure declared CHAR(8) returning 'hi' returned two, and a
// PACKED(7:2) subfield filled from '3.14159' held 3.14159.
DCL-DS rec QUALIFIED;
  code  CHAR(6);
  label VARCHAR(4);
  amt   PACKED(7:2);
END-DS;

DCL-DS jrec QUALIFIED;
  code  CHAR(6);
  amt   PACKED(7:2);
END-DS;

DCL-S xmlDoc  VARCHAR(200);
DCL-S jsonDoc VARCHAR(200);
DCL-S r       CHAR(20);
DCL-S n       PACKED(7:2);

DCL-PR Echo CHAR(20);
  s CHAR(10) VALUE;
END-PR;
DCL-PR Short CHAR(8);
END-PR;
DCL-PR Cents PACKED(7:2);
END-PR;

// A VALUE parameter holds its declared length inside the procedure.
r = Echo('AB');
DSPLY ('RESULT:VALUE=' + %TRIM(r));

// A return value has the procedure's declared return type.
DSPLY ('RESULT:RETCHAR=[' + Short() + ']');
n = Cents();
DSPLY ('RESULT:RETDEC=' + %CHAR(n) + ' ' + %CHAR(Cents()));

// XML-INTO: CHAR padded, VARCHAR cut at its maximum, PACKED truncated.
xmlDoc = '<rec><code>A1</code><label>LONGLABEL</label><amt>3.14159</amt></rec>';
XML-INTO rec %XML(xmlDoc : 'case=any');
DSPLY ('RESULT:XML=[' + rec.code + '][' + rec.label + '] ' + %CHAR(rec.amt));

// DATA-INTO (JSON): the same rules.
jsonDoc = '{"code":"B2","amt":2.999}';
DATA-INTO jrec %DATA(jsonDoc : 'case=any') %PARSER('JSON');
DSPLY ('RESULT:JSON=[' + jrec.code + '] ' + %CHAR(jrec.amt));

*INLR = *ON;
RETURN;

DCL-PROC Echo;
  DCL-PI Echo CHAR(20);
    s CHAR(10) VALUE;
  END-PI;
  RETURN '[' + s + ']';
END-PROC;

DCL-PROC Short;
  DCL-PI Short CHAR(8);
  END-PI;
  RETURN 'hi';
END-PROC;

DCL-PROC Cents;
  DCL-PI Cents PACKED(7:2);
  END-PI;
  RETURN 1.239;
END-PROC;
