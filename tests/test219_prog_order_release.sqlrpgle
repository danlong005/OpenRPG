     H*-----------------------------------------------------------------
     H* ORDREL  -  ORDER CREDIT REVIEW AND RELEASE
     H*-----------------------------------------------------------------
     H* WALKS THE UNRELEASED ORDERS, LOOKS EACH ONE'S CUSTOMER UP IN THE
     H* MASTER AND EITHER RELEASES IT AGAINST AVAILABLE CREDIT OR PUTS
     H* IT ON HOLD.  A RELEASED ORDER CONSUMES CREDIT IMMEDIATELY, SO A
     H* LATER ORDER FOR THE SAME CUSTOMER SEES THE REDUCED BALANCE.
     H*
     H* EVERY LINE IS FIXED FORMAT, EMBEDDED SQL INCLUDED.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
     F* CUSTOMER MASTER, KEYED ON CUSTOMER NUMBER
     FCUSTFL219 UF   E           K DISK
     F                                     EXTDESC('CUSTFL219')
     F* ORDER FILE, READ SEQUENTIALLY AND UPDATED IN PLACE
     FORDFL219  UF   E             DISK
     F                                     EXTDESC('ORDFL219')
     DCONN             S            200A   VARYING
     D* CREDIT DECISION WORK FIELDS
     DAVAIL            S             11P 2
     DKEYCUS           S             10A
     D* RUN ACCUMULATORS
     DRELCNT           S              5P 0
     DHLDCNT           S              5P 0
     DREJCNT           S              5P 0
     DRELAMT           S             13P 2
     DHLDAMT           S             13P 2
     DAUDCNT           S              5P 0
     DAUDAMT           S             13P 2
     DRPTLIN           S             70A
     C*-----------------------------------------------------------------
     C* MAIN LINE
     C*-----------------------------------------------------------------
     C                   EXSR      INZSR1
     C                   READ      ORDFL219
     C                   DOW       NOT %EOF(ORDFL219)
     C                   EXSR      ORDSR
     C                   READ      ORDFL219
     C                   ENDDO
     C                   EXSR      TRLSR
     C                   RETURN
     C*-----------------------------------------------------------------
     C* INZSR1  -  CONNECT AND BUILD THE FILES THIS RUN WORKS ON
     C*-----------------------------------------------------------------
     C     INZSR1        BEGSR
     C                   EVAL      CONN = 'Driver={SQLite3};' +
     C                             'Database=/tmp/rpgc_test219.sqlite;'
     C/EXEC SQL
     C+ CONNECT USING :CONN
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE IF EXISTS custfl219
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE IF EXISTS ordfl219
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE IF EXISTS audfl219
     C/END-EXEC
     C/EXEC SQL
     C+ CREATE TABLE custfl219 (CUSTNO VARCHAR(10) PRIMARY KEY,
     C+                         CUSTNAME VARCHAR(50),
     C+                         CUSTLIM DECIMAL(11,2),
     C+                         CUSTBAL DECIMAL(11,2))
     C/END-EXEC
     C/EXEC SQL
     C+ CREATE TABLE ordfl219 (ORDNO VARCHAR(10) PRIMARY KEY,
     C+                        ORDCUST VARCHAR(10),
     C+                        ORDAMT DECIMAL(11,2),
     C+                        ORDSTS VARCHAR(1))
     C/END-EXEC
     C* THE AUDIT TRAIL IS SQL ONLY - NO RECORD LEVEL ACCESS ON IT
     C/EXEC SQL
     C+ CREATE TABLE audfl219 (ORDNO VARCHAR(10),
     C+                        DECISN VARCHAR(1),
     C+                        AMT DECIMAL(11,2))
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO custfl219
     C+   VALUES('C001','ACME MANUFACTURING',5000.00,1200.00)
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO custfl219
     C+   VALUES('C002','BOLT AND NUT SUPPLY',2000.00,1950.00)
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO custfl219
     C+   VALUES('C003','CONSOLIDATED TOOL',10000.00,0.00)
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1001','C001',1500.00,'N')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1002','C002',500.00,'N')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1003','C003',9500.00,'N')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1004','C001',2000.00,'N')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1005','C999',100.00,'N')
     C/END-EXEC
     C/EXEC SQL
     C+ INSERT INTO ordfl219 VALUES('O1006','C003',1000.00,'N')
     C/END-EXEC
     C                   Z-ADD     0             RELCNT
     C                   Z-ADD     0             HLDCNT
     C                   Z-ADD     0             REJCNT
     C                   Z-ADD     0             RELAMT
     C                   Z-ADD     0             HLDAMT
     C                   EVAL      RPTLIN = 'ORDER RELEASE REGISTER'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* RELSR   -  RELEASE THE ORDER AND CONSUME THE CREDIT
     C*-----------------------------------------------------------------
     C     RELSR         BEGSR
     C                   EVAL      ORDSTS = 'R'
     C                   UPDATE    ORDFL219
     C                   ADD       ORDAMT        CUSTBAL
     C                   UPDATE    CUSTFL219
     C                   ADD       1             RELCNT
     C                   ADD       ORDAMT        RELAMT
     C                   EVAL      RPTLIN = ORDNO + ' ' + ORDCUST + ' ' +
     C                             %EDITC(ORDAMT:'1') + ' RELEASED'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* HLDSR   -  NOT ENOUGH CREDIT, HOLD IT
     C*-----------------------------------------------------------------
     C     HLDSR         BEGSR
     C                   EVAL      ORDSTS = 'H'
     C                   UPDATE    ORDFL219
     C                   ADD       1             HLDCNT
     C                   ADD       ORDAMT        HLDAMT
     C                   EVAL      RPTLIN = ORDNO + ' ' + ORDCUST + ' ' +
     C                             %EDITC(ORDAMT:'1') + ' HELD - AVAIL ' +
     C                             %EDITC(AVAIL:'1')
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* REJSR   -  THE ORDER NAMES A CUSTOMER THAT IS NOT ON FILE
     C*-----------------------------------------------------------------
     C     REJSR         BEGSR
     C                   EVAL      ORDSTS = 'X'
     C                   UPDATE    ORDFL219
     C                   ADD       1             REJCNT
     C                   EVAL      RPTLIN = ORDNO + ' ' + ORDCUST + ' ' +
     C                             %EDITC(ORDAMT:'1') +
     C                             ' REJECTED - NO CUSTOMER'
     C     RPTLIN        DSPLY
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* ORDSR   -  CREDIT REVIEW FOR ONE ORDER
     C*-----------------------------------------------------------------
     C     ORDSR         BEGSR
     C                   EVAL      KEYCUS = ORDCUST
     C     KEYCUS        CHAIN     CUSTFL219
     C                   IF        NOT %FOUND(CUSTFL219)
     C                   EXSR      REJSR
     C                   ELSE
     C* AVAILABLE CREDIT IS THE LIMIT LESS WHAT IS ALREADY COMMITTED
     C     CUSTLIM       SUB       CUSTBAL       AVAIL
     C                   IF        ORDAMT <= AVAIL
     C                   EXSR      RELSR
     C                   ELSE
     C                   EXSR      HLDSR
     C                   ENDIF
     C                   ENDIF
     C* EVERY DECISION IS AUDITED, WHICHEVER WAY IT WENT
     C/EXEC SQL
     C+ INSERT INTO audfl219 VALUES(:ORDNO, :ORDSTS, :ORDAMT)
     C/END-EXEC
     C                   ENDSR
     C*-----------------------------------------------------------------
     C* TRLSR   -  TOTALS, THEN READ THE AUDIT TRAIL BACK TO PROVE IT
     C*-----------------------------------------------------------------
     C     TRLSR         BEGSR
     C                   EVAL      RPTLIN = '---- TOTALS ----'
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'RELEASED ' + %CHAR(RELCNT) + ' ' +
     C                             %EDITC(RELAMT:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'HELD     ' + %CHAR(HLDCNT) + ' ' +
     C                             %EDITC(HLDAMT:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = 'REJECTED ' + %CHAR(REJCNT)
     C     RPTLIN        DSPLY
     C* THE AUDIT TRAIL MUST ACCOUNT FOR EVERY ORDER THE RUN SAW
     C/EXEC SQL
     C+ SELECT COUNT(*), SUM(AMT) INTO :AUDCNT, :AUDAMT
     C+   FROM audfl219
     C/END-EXEC
     C                   EVAL      RPTLIN = 'AUDITED  ' + %CHAR(AUDCNT) + ' ' +
     C                             %EDITC(AUDAMT:'1')
     C     RPTLIN        DSPLY
     C* AND THE CUSTOMER BALANCES MUST REFLECT EVERY RELEASE
     C/EXEC SQL
     C+ SELECT SUM(CUSTBAL) INTO :AUDAMT FROM custfl219
     C/END-EXEC
     C                   EVAL      RPTLIN = 'CUSTOMER BALANCES ' +
     C                             %EDITC(AUDAMT:'1')
     C     RPTLIN        DSPLY
     C/EXEC SQL
     C+ DROP TABLE custfl219
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE ordfl219
     C/END-EXEC
     C/EXEC SQL
     C+ DROP TABLE audfl219
     C/END-EXEC
     C                   ENDSR
