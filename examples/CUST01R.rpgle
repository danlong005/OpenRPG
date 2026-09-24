**FREE
// CUST01R — Find today's orders and create thank-you messages
//
// Reads:  ORDERS    (sequential — finds today's unfulfilled orders)
//         CUSTOMERS (keyed — looks up customer name)
// Writes: messages  (EXEC SQL INSERT — auto-generated id)

DCL-F ORDERS    DISK PREFIX(ORD_);
DCL-F CUSTOMERS DISK KEYED PREFIX(CUST_);

DCL-S today   VARCHAR(10);
DCL-S custId  PACKED(10:0);
DCL-S orderId PACKED(10:0);
DCL-S msg     VARCHAR(500);

// Get today's date from the database
EXEC SQL SELECT date('now') INTO :today;

READ ORDERS;
DOW NOT %EOF(ORDERS);

  IF ORD_PLACED_AT = today AND ORD_THANKED = 'N';
    custId  = ORD_CUSTOMER_ID;
    orderId = ORD_ID;

    CHAIN custId CUSTOMERS;
    IF %FOUND(CUSTOMERS);
      msg = 'Dear ' + %TRIM(CUST_FIRST_NAME) + ' ' +
            %TRIM(CUST_LAST_NAME) +
            ', thank you for your order! We appreciate your business.';

      EXEC SQL INSERT INTO messages(customer_id, order_id, message, email, status)
               VALUES(:custId, :orderId, :msg, '', ' ');

      DSPLY ('Message queued for ' + %TRIM(CUST_FIRST_NAME) + ' ' +
             %TRIM(CUST_LAST_NAME));
    ENDIF;
  ENDIF;

  READ ORDERS;
ENDDO;

*INLR = *ON;
