**FREE
DCL-PR doWork;
END-PR;

doWork();
DSPLY 'Done';

*INLR = *ON;

DCL-PROC doWork;
  DCL-PI doWork;
  END-PI;
  DSPLY 'Working';
  ON-EXIT;
    DSPLY 'Cleanup';
END-PROC;
