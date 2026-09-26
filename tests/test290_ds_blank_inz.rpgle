**FREE
// A data structure without INZ starts as blanks, as on IBM i. Each subfield
// reads as what blank bytes decode to: an INT(10) is x'40404040',
// 1077952576, an INT(5) x'4040', 16448. A PACKED or ZONED subfield holds no
// decimal data at all, and reading it is a decimal data error (status 907).
// INZ on the DS gives every subfield its type's default; INZ on a subfield
// sets that subfield alone. LIKEDS copies the layout but not the
// initialization: INZ(*LIKEDS) copies that too. RESET restores the declared
// state, and a DS inside a procedure is initialized the same way.
DCL-C START 7;
DCL-DS blank QUALIFIED;
  n    INT(10);
  s    INT(5);
  code CHAR(3);
  amt  PACKED(7:2);
  lbl  CHAR(4) INZ('LBLX');
  cnt  INT(10) INZ(START);
END-DS;
DCL-DS zero QUALIFIED INZ;
  n    INT(10);
  amt  PACKED(7:2);
  cnt  INT(10) INZ(3);
  arr  ZONED(3:0) DIM(2);
END-DS;
DCL-DS copy LIKEDS(zero) INZ(*LIKEDS);
DCL-DS bare LIKEDS(zero);
DCL-S line VARCHAR(52);

line = %CHAR(blank.n) + '|' + %CHAR(blank.s) + '|' + blank.code + '|' +
       blank.lbl + '|' + %CHAR(blank.cnt);
DSPLY line;
line = %CHAR(zero.n) + '|' + %CHAR(zero.amt) + '|' + %CHAR(zero.cnt) + '|' +
       %CHAR(zero.arr(2));
DSPLY line;
line = %CHAR(copy.cnt) + '|' + %CHAR(bare.n);
DSPLY line;
zero.cnt = 99;
RESET zero;
line = 'RESET ' + %CHAR(zero.cnt);
DSPLY line;
showLocal();
MONITOR;
  line = %CHAR(blank.amt);
  DSPLY line;
ON-ERROR;
  line = 'STATUS ' + %CHAR(%STATUS);
  DSPLY line;
ENDMON;
*INLR = *ON;

DCL-PROC showLocal;
  DCL-DS loc QUALIFIED INZ;
    k INT(10) INZ(5);
    q PACKED(5:2);
  END-DS;
  DCL-DS lc LIKEDS(loc) INZ;
  DCL-S txt VARCHAR(52);
  txt = %CHAR(loc.k) + '|' + %CHAR(loc.q) + '|' + %CHAR(lc.k);
  DSPLY txt;
END-PROC;
