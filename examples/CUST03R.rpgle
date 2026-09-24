**FREE

// CUST03R — Mark orders as thanked for all completed messages
//
// Reads:   MESSAGES (sequential — finds messages with status = 'X')
// Updates: ORDERS   (keyed — sets thanked = 'Y')

DCL-F MESSAGES DISK PREFIX(MSG_);
DCL-F ORDERS   DISK KEYED PREFIX(ORD_);

DCL-S orderId PACKED(10:0);

READ MESSAGES;
DOW NOT %EOF(MESSAGES);

  IF MSG_STATUS = 'X';
    orderId = MSG_ORDER_ID;

    CHAIN orderId ORDERS;
    IF %FOUND(ORDERS);
      ORD_THANKED = 'Y';
      UPDATE ORDERS;
      DSPLY ('Order ' + %CHAR(%INT(orderId)) + ' marked as thanked');
    ENDIF;
  ENDIF;

  READ MESSAGES;
ENDDO;

*INLR = *ON;
