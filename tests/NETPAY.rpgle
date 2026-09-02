     H*-----------------------------------------------------------------
     H* NETPAY  -  WITHHOLDING AND NET PAY CALCULATION
     H*-----------------------------------------------------------------
     H* CALLED WITH A GROSS AMOUNT AND AN EXEMPTION COUNT; ANSWERS WITH
     H* THE TAX WITHHELD AND THE NET.  EVERY PARAMETER IS BY REFERENCE,
     H* WHICH IS WHAT A TRADITIONAL CALL/PARM EXPECTS.
     H*-----------------------------------------------------------------
     HDFTACTGRP(*NO)
     DPGROSS           S             11P 2
     DPEXEMP           S              3P 0
     DPTAX             S             11P 2
     DPNET             S             11P 2
     DTXABLE           S             11P 2
     DALLOW            S             11P 2
     C* EACH EXEMPTION SHELTERS 75.00 OF THE PERIOD'S GROSS
     C     *ENTRY        PLIST
     C                   PARM                    PGROSS
     C                   PARM                    PEXEMP
     C                   PARM                    PTAX
     C                   PARM                    PNET
     C     PEXEMP        MULT      75.00         ALLOW
     C     PGROSS        SUB       ALLOW         TXABLE
     C* NOTHING BELOW THE ALLOWANCE IS TAXED
     C                   IF        TXABLE < 0
     C                   Z-ADD     0             TXABLE
     C                   ENDIF
     C* FLAT 22 PERCENT OF THE TAXABLE AMOUNT
     C     TXABLE        MULT      0.22          PTAX
     C     PGROSS        SUB       PTAX          PNET
     C                   RETURN
