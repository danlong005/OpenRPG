     HDFTACTGRP(*NO)
     D* INZ ON A SUBFIELD SETS THAT SUBFIELD ALONE. THE REST OF A DATA
     D* STRUCTURE WITHOUT INZ STARTS AS BLANKS, AS ON IBM I: AN INTEGER
     D* SUBFIELD READS AS X'40404040', 1077952576. INZ ON THE DATA
     D* STRUCTURE GIVES EVERY SUBFIELD ITS TYPE'S DEFAULT, AND A
     D* SUBFIELD'S OWN INZ STILL WINS.
     DPART             DS                  QUALIFIED
     DKEY                            10A   INZ('X')
     DQTY                            10I 0
     DTOTS             DS                  QUALIFIED INZ
     DCNT                            10I 0
     DAMT                             7P 2 INZ(12.5)
     DSUM                             7P 2
     DTMPDSP           S             52A
      /free
       DSPLY part.key;
       TMPDSP = %CHAR(part.qty);
       DSPLY TMPDSP;
       TMPDSP = %CHAR(tots.cnt) + ' ' + %CHAR(tots.amt) + ' ' +
                %CHAR(tots.sum);
       DSPLY TMPDSP;
       *INLR = *ON;
      /end-free
