**FREE
// EXSR resolves in either direction. RPG imposes no ordering on
// subroutines, so the conventional layout — a driver first, calling leaves
// written below it — has to work, and so does a pair that call each other.
//
// Both used to fail to compile. Subroutines were emitted as lambdas inside
// main() in source order, and a lambda is not in scope until its own
// declaration is reached, so a subroutine could only call one defined
// textually above it.
DCL-S trail CHAR(20);
DCL-S depth INT(5);

EXSR Driver;
DSPLY ('RESULT:TRAIL=' + %TRIM(trail));
*INLR = *ON;
RETURN;

// Calls two subroutines defined BELOW it — the conventional layout, and
// the case that used to be 'use of undeclared identifier sr_LEAF'.
BEGSR Driver;
  trail = 'D';
  EXSR Leaf;
  EXSR Ping;
ENDSR;

BEGSR Leaf;
  trail = %TRIM(trail) + 'L';
ENDSR;

// Ping and Pong call each other, so no ordering of definitions can
// satisfy both; only a forward declaration can. Bounded by depth.
BEGSR Ping;
  trail = %TRIM(trail) + 'P';
  depth = depth + 1;
  IF depth < 3;
    EXSR Pong;
  ENDIF;
ENDSR;

BEGSR Pong;
  trail = %TRIM(trail) + 'Q';
  EXSR Ping;
ENDSR;
