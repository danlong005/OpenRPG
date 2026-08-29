     H**ENTRY PLIST — this member compiles to a function named after its
     H*own file (ADDTWO), taking its parameters by reference, instead of
     H*an int main(). That is what makes it reachable from another
     H*program's traditional CALL, which resolves a program name to a
     H*same-named C++ function.
     HDFTACTGRP(*NO)
     DN                S             10I0
     DMSG              S             10A
     DSEEN             S             10I0
     C*Factor 1 on an *ENTRY PARM is the entry-time copy: SEEN receives
     C*N once this program gets control (p.929 step 3).
     C     *ENTRY        PLIST
     C     SEEN          PARM                    N
     C                   PARM                    MSG
     C*Both parameters are written through the caller's own storage.
     C                   EVAL      N = SEEN + 2
     C                   EVAL      MSG = 'entered'
     C                   RETURN
