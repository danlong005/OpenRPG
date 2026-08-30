**FREE
DCL-DS result QUALIFIED;
  sum INT(10);
  product INT(10);
END-DS;

DCL-PR calcBoth;
  a INT(10) VALUE;
  b INT(10) VALUE;
  res LIKEDS(result);
END-PR;

calcBoth(5 : 7 : result);
DSPLY %CHAR(result.sum);
DSPLY %CHAR(result.product);

*INLR = *ON;

DCL-PROC calcBoth;
  DCL-PI calcBoth;
    a INT(10) VALUE;
    b INT(10) VALUE;
    res LIKEDS(result);
  END-PI;
  res.sum = a + b;
  res.product = a * b;
END-PROC;
