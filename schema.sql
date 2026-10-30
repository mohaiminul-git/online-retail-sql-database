-- In this SQL file, write (and comment!) the schema of your database, including the CREATE TABLE, CREATE INDEX, CREATE VIEW, etc. statements that compose itCREATE TABLE IF NOT EXISTS online_retail (
CREATE TABLE IF NOT EXISTS online_retail (
    invoiceno varchar(20),
    stockcode varchar(20),
    description text,
    quantity int,
    invoicedate timestamp,
    unitprice money,
    customerid varchar(20),
    country varchar(50)
);




ALTER TABLE online_retail ALTER COLUMN "customerid"  TYPE integer USING "customerid"::numeric::integer;
------- inject CSV data into the table
COPY online_retail(invoiceno, stockcode, description, quantity, invoicedate, unitprice, customerid, country)
FROM '/tmp/retail.csv'
DELIMITER ','
CSV HEADER;



CREATE TABLE country(
    id serial PRIMARY KEY,
    country_name varchar(30) NOT NULL UNIQUE
);




CREATE TABLE customer(
    id serial PRIMARY KEY,
    customerid varchar(20) NOT NULL UNIQUE
);

ALTER TABLE customer ALTER COLUMN "customerid"  TYPE integer USING "customerid"::integer;


CREATE TABLE product_table(
    id serial PRIMARY KEY,
    stockcode varchar(20) NOT NULL UNIQUE,
    product_description text
);



CREATE TABLE invoice_table(
    id serial PRIMARY KEY,
    invoiceno varchar(20) NOT NULL,
    invoice_date timestamp NOT NULL,
    country_id int,
    FOREIGN KEY (country_id) REFERENCES country(id)
);

CREATE TABLE invoiceXproductXcustomer(
    id serial PRIMARY KEY,
    invoice_id int NOT NULL,
    product_id int NOT NULL,
    customer_id int,
    quantity int NOT NULL,
    unit_price money NOT NULL,
    FOREIGN KEY (invoice_id) REFERENCES invoice_table(id),
    FOREIGN KEY (product_id) REFERENCES product_table(id),
    FOREIGN KEY (customer_id) REFERENCES customer(id)
);


------------populate these table from online_retail table

INSERT INTO country(country_name)   
SELECT DISTINCT  "country" FROM online_retail;

-----
INSERT INTO customer (customerid)
SELECT DISTINCT customerid
FROM online_retail 
WHERE customerid IS NOT NULL;

-------populate the product description with logest descriptiomn.
INSERT INTO product_table(stockcode, product_description)
SELECT  DISTINCT "stockcode", "description"
FROM online_retail;



-----populate invoice table

INSERT INTO invoice_table("invoiceno", "invoice_date", "country_id")
SELECT DISTINCT ON ("invoiceno") 
    "invoiceno", "invoicedate", c.id
FROM online_retail AS o
JOIN country AS c
    ON o.country = c.country_name;


---------populate invoiceXproductXcustomer table

INSERT INTO invoiceXproductXcustomer(invoice_id, product_id, customer_id, quantity, unit_price)
SELECT i.id, p.id, c.id, o.quantity, o.unitprice   
FROM online_retail AS o
JOIN invoice_table AS i ON o.invoiceno = i.invoiceno
JOIN product_table AS p ON o.stockcode = p.stockcode
LEFT JOIN customer AS c ON o.customerid = c.customerid;



--- AS i have found out there are multriple custer with with multiple countries. So i have Aggregate the customer countries and then tried to find the total spending of a customer ,
irrespective of the country they are from.--- Thus, i have create a view to contain the top 10 customers by total spending, along with the list of countries they are from.


WITH CTE AS (
    SELECT c.customerid, SUM(ipc.quantity * ipc.unit_price) AS total_spent, COUNT(DISTINCT i.country_id) AS total_country,
    STRING_AGG( DISTINCT con.country_name, ', ') AS country_list
    FROM invoiceXproductXcustomer AS ipc
    JOIN customer AS c ON ipc.customer_id = c.id
    JOIN invoice_table AS i ON ipc.invoice_id = i.id
    JOIN country AS con ON i.country_id = con.id
    GROUP BY c.customerid
    HAVING count(DISTINCT i.country_id) > 1
    ORDER BY total_spent DESC
)
SELECT customerid, country_list, total_spent  
FROM CTE
ORDER BY total_spent DESC;

 customerid |      country_list      | total_spent 
------------+------------------------+-------------
      12431 | Australia, Belgium     |   $6,348.89
      12429 | Austria, Denmark       |   $3,750.40
      12417 | Belgium, Spain         |   $3,578.80
      12370 | Austria, Cyprus        |   $3,541.94
      12455 | Cyprus, Spain          |   $2,466.86
      12457 | Cyprus, Switzerland    |   $1,917.78
      12394 | Belgium, Denmark       |   $1,272.48
      12422 | Australia, Switzerland |     $803.56
(8 rows)


CREATE VIEW top_customers AS(
    SELECT c.customerid, SUM(ipc.quantity * ipc.unit_price) AS total_spent,
    STRING_AGG( DISTINCT con.country_name, ', ') AS country_list
    FROM invoiceXproductXcustomer AS ipc
    JOIN customer AS c ON ipc.customer_id = c.id
    JOIN invoice_table AS i ON ipc.invoice_id = i.id
    JOIN country AS con ON i.country_id = con.id
    WHERE i."invoiceno"  NOT LIKE 'C%'
    GROUP BY c.customerid
    ORDER BY total_spent DESC
);

------------------------------NOW for demonstrationg a complete dbms system. 
---i am going to create a new inventory table which will containe the stockcode, product description and quantitu in the inventory and 
--another table which will contain the sales of the product and then i will create a view to show the current inventory 
---of the product after deducting the sales from the inventory.

CREATE TABLE inventory (
    stockcode varchar(20) PRIMARY KEY,
    product_description text,
    quantity_in_inventory int NOT NULL CHECK (quantity_in_inventory >= 0)
);


CREATE TABLE order_table (
    id serial PRIMARY KEY,
    order_date timestamp NOT NULL,
    customer_id varchar(20) NOT NULL,
    stock_code varchar(20),
    quantity int NOT NULL,
    FOREIGN KEY (stock_code) REFERENCES inventory(stockcode)
);



CREATE OR REPLACE FUNCTION update_inventory_after_sale()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE inventory
    SET quantity_in_inventory = quantity_in_inventory - NEW.quantity
    WHERE stockcode = NEW.stock_code;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;    

CREATE TRIGGER update_inventory_trigger
AFTER INSERT ON order_table 
FOR EACH ROW
EXECUTE FUNCTION update_inventory_after_sale();

------populate these table
INSERT INTO inventory(stockcode, product_description, quantity_in_inventory)
SELECT DISTINCT "stockcode", "description", 1000
FROM online_retail; 


---AS the trigger is created ..now if i add a new order in the order table the inventory should 
---reflect it.

SELECT * FROM inventory LIMIT 5;
 stockcode |         product_description         | quantity_in_inventory 
-----------+-------------------------------------+-----------------------
 23048     | SET OF 10 LANTERNS FAIRY LIGHT STAR |                  1000
 84031B    | CHARLIE LOLA BLUE HOT WATER BOTTLE  |                  1000
 35095A    | BLUE VICTORIAN FABRIC OVAL BOX      |                  1000
 22233     | JIGSAW RABBIT AND BIRDHOUSE         |                  1000
 90163A    | PINK ROSEBUD & PEARL NECKLACE       |                  1000

INSERT INTO order_table(order_date, customer_id, stock_code, quantity)
VALUES (now(), '12345', '22233', 30);

SELECT * FROM inventory 
WHERE stockcode = '22233';
postgres=# SELECT * FROM inventory 
WHERE stockcode = '22233';

 stockcode |     product_description     | quantity_in_inventory 
-----------+-----------------------------+-----------------------
 22233     | JIGSAW RABBIT AND BIRDHOUSE |                   970

HENCE, after after placing a arder the quantity is inventory is update.
SAme can be done when , an order is cancelled.



