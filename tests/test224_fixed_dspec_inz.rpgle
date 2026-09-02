     HDFTACTGRP(*NO)
     D*REGRESSION: INZ ON A FIXED-FORMAT D-SPEC IS HONOURED.  IT USED
     D*TO BE DROPPED SILENTLY, SO EVERY FIELD STARTED AT THE TYPE
     D*DEFAULT NO MATTER WHAT THE DECLARATION SAID.
     DNWHOLE           S              5P 0 INZ(15)
     DNCENTS           S              9P 2 INZ(1250.75)
     DNNEG             S              9P 2 INZ(-42.5)
     DNINT             S             10I 0 INZ(7)
     DCTEXT            S             11A   INZ('HELLO WORLD')
     DCQUOTE           S              7A   INZ('IT''S OK')
     DCBLANK           S              6A   INZ(*BLANKS)
     DNZED             S              5P 2 INZ(*ZEROS)
     DRPTLIN           S             70A
     C                   EVAL      RPTLIN = 'NWHOLE = ' + %EDITC(NWHOLE:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'NCENTS = ' + %EDITC(NCENTS:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'NNEG = ' + %EDITC(NNEG:'3')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'NINT = ' + %EDITC(NINT:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'NZED = ' + %EDITC(NZED:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'CTEXT = [' + CTEXT + ']'
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'CQUOTE = [' + CQUOTE + ']'
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'CBLANK = [' + CBLANK + ']'
     C     RPTLIN        DSPLY
     C                   RETURN
