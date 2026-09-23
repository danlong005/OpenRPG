**FREE
// Test 63: PREFIX on a program-described DS is rejected.
//
// PREFIX renames the subfields an external description brings in (EXTNAME,
// LIKEREC). This DS writes its subfields out, so there is nothing for PREFIX
// to rename: IBM i rejects the keyword here (RNF3529), and so does rpgc.
// This test used to expect the prefixed names to work.
DCL-DS custRec QUALIFIED PREFIX(CUST_);
  id INT(10);
  name CHAR(30);
  city CHAR(20);
END-DS;

custRec.CUST_id = 100;
custRec.CUST_name = 'John Smith';
custRec.CUST_city = 'New York';

DSPLY %CHAR(custRec.CUST_id);
DSPLY %TRIM(custRec.CUST_name);
DSPLY %TRIM(custRec.CUST_city);

*INLR = *ON;
