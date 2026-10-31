-- In this SQL file, write (and comment!) the typical SQL queries users will run on your database
------ check duplicate rows

SELECT  * ,count(*) AS occurrences
FROM online_retail
GROUP BY
    "invoiceno",
    "stockcode",
    "description",
    "quantity",
    "invoicedate",
    "unitprice",
    "customerid",
    "country"
HAVING COUNT(*) > 1
LIMIT 5;

invoiceno | stockcode |           description            | quantity |     invoicedate     | unitprice | customerid |    country     | occurrences 
-----------+-----------+----------------------------------+----------+---------------------+-----------+------------+----------------+-------------
 536409    | 21866     | UNION JACK FLAG LUGGAGE TAG      |        1 | 2010-12-01 11:45:00 |     $1.25 |      17908 | United Kingdom |           2
 536409    | 22111     | SCOTTIE DOG HOT WATER BOTTLE     |        1 | 2010-12-01 11:45:00 |     $4.95 |      17908 | United Kingdom |           2
 536409    | 22866     | HAND WARMER SCOTTY DOG DESIGN    |        1 | 2010-12-01 11:45:00 |     $2.10 |      17908 | United Kingdom |           2
 536409    | 22900     |  SET 2 TEA TOWELS I LOVE LONDON  |        1 | 2010-12-01 11:45:00 |     $2.95 |      17908 | United Kingdom |           2
 536412    | 21448     | 12 DAISY PEGS IN WOOD BOX  
 
 
---------------- AS it can be seen that a single prdouct is described by multiple description. FOR mantining the uniqueness of the prduct , the DESCRPTION for each product is replaced with th elongest desccription existed for the product.
SELECT "stockcode", COUNT(DISTINCT "description") AS unique_descriptions FROM online_retail
GROUP BY "stockcode"
HAVING COUNT(DISTINCT "description") > 1
LIMIT 5;
 stockcode | unique_descriptions 
-----------+---------------------
 10002     |                   2
 10080     |                   3
 10123C    |                   2
 10133     |                   2
 15030     |                   2
(5 rows)

WITH longest_descriptions AS (
    SELECT  DISTINCT "stockcode", FIRST_VALUE("description") OVER (PARTITION BY "stockcode" ORDER BY LENGTH("description") DESC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS longest_description
    FROM online_retail
)
UPDATE online_retail
SET "description" = ld.longest_description
FROM longest_descriptions AS ld
WHERE online_retail."stockcode" = ld."stockcode";

SELECT "stockcode", COUNT(DISTINCT "description") AS unique_descriptions FROM online_retail
GROUP BY "stockcode"
HAVING COUNT(DISTINCT "description") > 1
LIMIT 5;

 stockcode | unique_descriptions 
-----------+---------------------
(0 rows)


 

------delete duplicate rows
CREATE TABLE temp_retail(LIKE online_retail);
INSERT INTO temp_retail("invoiceno","stockcode","description","quantity","invoicedate","unitprice","customerid","country")
SELECT DISTINCT *
FROM online_retail;
DROP TABLE online_retail;
ALTER TABLE temp_retail RENAME TO online_retail;



----check missing value 

CREATE OR REPLACE FUNCTION check_missing_values()
RETURNS TABLE (
    col_name      text,
    missing_count bigint
)
LANGUAGE plpgsql
AS $$
DECLARE
    col RECORD;
    cnt bigint;
BEGIN
    FOR col IN
        SELECT c.column_name
        FROM information_schema.columns AS c
        WHERE c.table_name = 'online_retail'
        LOOP
        EXECUTE format(
            'SELECT COUNT(*) FROM online_retail WHERE %s IS NULL',
            col.column_name
        )
        INTO cnt;

        col_name      := col.column_name;
        missing_count := cnt;
        RETURN NEXT;
    END LOOP;
END;
$$;

SELECT * FROM check_missing_values();
  col_name   | missing_count 
-------------+---------------
 invoiceno   |             0
 stockcode   |             0
 description |          1454
 quantity    |             0
 invoicedate |             0
 unitprice   |             0
 customerid  |        135080
 country     |             0
(8 rows)

----------- customer id with multole countries

SELECT "customerid", COUNT(DISTINCT "country") AS total_country
FROM online_retail
GROUP BY "customerid"
HAVING COUNT(DISTINCT "country") > 1;
 customerid | total_country 
------------+---------------
      12370 |             2
      12394 |             2
      12417 |             2
      12422 |             2
      12429 |             2
      12431 |             2
      12455 |             2
      12457 |             2
            |             9


-------further investigation of customer id with multiple countries
SELECT "customerid", "invoicedate", "country", "invoiceno"
FROM online_retail
WHERE "customerid" = '12370';


 customerid |     invoicedate     | country | invoiceno 
------------+---------------------+---------+-----------
 12370      | 2010-12-14 12:58:00 | Cyprus  | 538826
 12370      | 2010-12-17 09:38:00 | Austria | 539330
 12370      | 2011-03-10 12:48:00 | Cyprus  | 546236
 12370      | 2011-10-19 14:51:00 | Cyprus  | 571905



Hence, in uci data descrription country refers to the customer residence. FROM this we can assume that these above customer have multiple residence.
but for designing the daatabase we attact thhe country with invoice number. THUS they posses a many to one relationship among them.



SELECT "invoiceno", COUNT(DISTINCT "country") AS country_count FROM online_retail
GROUP BY "invoiceno"
HAVING COUNT(DISTINCT "country") > 1;
 invoiceno | country_count 
-----------+---------------
(0 rows)



--------------- same product also posses multiple unit price based on time .

WITH duplicates_price AS (
    SELECT "stockcode", "unitprice","invoicedate", "invoiceno",
    count( "unitprice") OVER(PARTITION BY ("stockcode") ORDER BY "unitprice" ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS occurrences
    FROM online_retail
)
SELECT DISTINCT "stockcode", "unitprice", "invoicedate", "invoiceno"
FROM duplicates_price
WHERE occurrences > 1
LIMIT 5;

 stockcode | unitprice |     invoicedate     | invoiceno 
-----------+-----------+---------------------+-----------
 10002     |     $0.00 | 2011-03-30 11:47:00 | 548286
 10002     |     $0.00 | 2011-04-28 15:05:00 | 551429
 10002     |     $0.85 | 2010-12-01 08:45:00 | 536370
 10002     |     $0.85 | 2010-12-01 09:45:00 | 536382
 10002     |     $0.85 | 2010-12-02 14:23:00 | 536756
(5 rows)

_______*** ANALYTICAL QUERIES ***_________


---------top 1o customers with countries by total spending

SELECT * FROM top_customers
LIMIT 10;

 customerid | total_spent |  country_list  
------------+-------------+----------------
      14646 | $280,206.02 | Netherlands
      18102 | $259,657.30 | United Kingdom
      17450 | $194,390.79 | United Kingdom
      16446 | $168,472.50 | United Kingdom
      14911 | $143,711.17 | EIRE
      12415 | $124,914.53 | Australia
      14156 | $117,210.08 | EIRE
      17511 |  $91,062.38 | United Kingdom
      16029 |  $80,850.84 | United Kingdom
      12346 |  $77,183.60 | United Kingdom
(10 rows)

----top 10 sold product (without cancelled)

SELECT p.stockcode, p.product_description, SUM(ipc.quantity) AS total_quantity_sold
FROM invoiceXproductXcustomer AS ipc
JOIN product_table AS p ON ipc.product_id = p.id
JOIN invoice_table AS i ON ipc.invoice_id = i.id
WHERE i."invoiceno" NOT LIKE 'C%'
GROUP BY p.stockcode, p.product_description
ORDER BY total_quantity_sold DESC
LIMIT 10;

-----------+------------------------------------+---------------------
 23843     | PAPER CRAFT , LITTLE BIRDIE        |               80995
 23166     | MEDIUM CERAMIC TOP STORAGE JAR     |               78033
 22197     | SMALL POPCORN HOLDER               |               56898
 84077     | WORLD WAR 2 GLIDERS ASSTD DESIGNS  |               54951
 85099B    | JUMBO BAG RED RETROSPOT            |               48375
 85123A    | WHITE HANGING HEART T-LIGHT HOLDER |               41389
 21212     | PACK OF 72 RETROSPOT CAKE CASES    |               36396
 84879     | ASSORTED COLOUR BIRD ORNAMENT      |               36202
 23084     |                                    |               30705
 22492     | MINI PAINT SET VINTAGE             |               26633
(10 rows)

---top cancelled product

SELECT p.stockcode, p.product_description, SUM(-ipc.quantity) AS total_returned
FROM invoiceXproductXcustomer AS ipc
JOIN product_table AS p ON ipc.product_id = p.id
JOIN invoice_table AS i ON ipc.invoice_id = i.id
WHERE i."invoiceno" LIKE 'C%'
GROUP BY p.stockcode, p.product_description
ORDER BY total_returned DESC
LIMIT 10;
 stockcode |         product_description         | total_returned 
-----------+-------------------------------------+----------------
 23843     | PAPER CRAFT , LITTLE BIRDIE         |          80995
 23166     | MEDIUM CERAMIC TOP STORAGE JAR      |          74494
 84347     | ROTATING SILVER ANGELS T-LIGHT HLDR |           9376
 M         | Manual                              |           4066
 21108     | FAIRY CAKE FLANNEL ASSORTED COLOUR  |           3150
 85123A    | WHITE HANGING HEART T-LIGHT HOLDER  |           2578
 21175     |                                     |           2030
 22920     | HERB MARKER BASIL                   |           1527
 22273     | FELTCRAFT DOLL MOLLY                |           1447
 47566B    | incorrectly credited C550456 see 47 |           1424
(10 rows)

--------REVENUE BY month
SELECT DATE_TRUNC('month', i.invoice_date)::date AS month, SUM(ipc.quantity * ipc.unit_price) AS total_revenue
FROM invoiceXproductXcustomer AS ipc
JOIN invoice_table AS i ON ipc.invoice_id = i.id
GROUP BY month
ORDER BY month;

   month    | total_revenue 
------------+---------------
 2010-12-01 |   $746,723.61
 2011-01-01 |   $558,448.56
 2011-02-01 |   $497,026.41
 2011-03-01 |   $682,013.98
 2011-04-01 |   $492,367.84
 2011-05-01 |   $722,079.25
 2011-06-01 |   $689,977.23
 2011-07-01 |   $680,156.99
 2011-08-01 |   $681,386.46
 2011-09-01 | $1,017,596.68
 2011-10-01 | $1,069,368.23
 2011-11-01 | $1,455,608.80
 2011-12-01 |   $432,701.06
So, it SEEMS that the revenue is highest in November and October, which is expected as it is the holiday season.

----Most repeated customer 
SELECT c.customerid, COUNT(*) AS total_purchases
FROM invoiceXproductXcustomer AS ipc
JOIN customer AS c ON ipc.customer_id = c.id
GROUP BY c.customerid
ORDER BY total_purchases DESC
LIMIT 10;
 customerid | total_purchases 
------------+-----------------
      17841 |            7812
      14911 |            5898
      14096 |            5128
      12748 |            4459
      14606 |            2759
      15311 |            2478
      14646 |            2085
      13089 |            1853
      13263 |            1667
      14298 |            1640
(10 rows)
---- list of customer who orderd once

SELECT c.customerid, COUNT(*) AS total_purchases
FROM invoiceXproductXcustomer AS ipc
JOIN customer AS c ON ipc.customer_id = c.id
GROUP BY c.customerid
HAVING COUNT(*)  =1
ORDER BY total_purchases DESC
LIMIT 10;

 customerid | total_purchases 
------------+-----------------
      18113 |               1
      17331 |               1
      15316 |               1
      14424 |               1
      16990 |               1
      17763 |               1
      15510 |               1
      17752 |               1
      15657 |               1
      12505 |               1
(10 rows)
---------





