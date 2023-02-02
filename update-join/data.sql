
DROP TABLE customers, invoices, items;

CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
    );

CREATE TABLE invoices (
    invoice_id SERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES customers (customer_id)
    );

CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    invoice_id BIGINT REFERENCES invoices (invoice_id),
    name TEXT NOT NULL
    );

INSERT INTO customers (name) 
    VALUES ('Peter'), ('Paul'), ('Mary'), ('Ben');

UPDATE customers 
  SET name = 'Jen'
  WHERE name = 'Ben';

DELETE FROM customers 
  WHERE name = 'Jen';




WITH i AS (
    -- Add a fresh invoice and return the newly created id
    INSERT INTO invoices (customer_id) 
        SELECT invoice_id FROM customers WHERE name = 'Mary'
        RETURNING invoice_id
)
-- Add items, using the new invoice id
INSERT INTO items (name, invoice_id) 
    SELECT n.name, i.invoice_id
    FROM i 
    CROSS JOIN 
    (VALUES ('Purple Plane'), 
            ('Yellow Plane')) AS n(name);


WITH i AS (
    -- Insert three new invoices for each customer
    -- returning the invoice_id for each one
    INSERT INTO invoices (customer_id)
        SELECT customer_id 
        FROM customers
        CROSS JOIN generate_series(1,3)
        RETURNING invoice_id
)
-- Insert three new items for each invoice
-- Each items is a "colored vehicle", with a
-- distinct color for each item on an invoice, 
-- and a single kind of vehicle for each invoice
INSERT INTO items (invoice_id, name)
    SELECT i.invoice_id, 
        Format('%s %s', 
            c, 
            (ARRAY['Train', 'Plane', 'Automobile'])[i.invoice_id % 3 + 1]) AS name
    FROM unnest(ARRAY['Red', 'Blue', 'Green']) AS c
    CROSS JOIN i;



SELECT * 
FROM customers
JOIN invoices USING (customer_id)
JOIN items USING (invoice_id)
WHERE customers.name = 'Paul'
ORDER BY customers.name, invoice_id;



SELECT DISTINCT 
    customers.name, 
    split_part(items.name, ' ', 2) AS vehicle
FROM customers
JOIN invoices USING (customer_id)
JOIN items USING (invoice_id);




UPDATE items
SET name = replace(items.name, 'Blue', 'Purple')
FROM customers, invoices
WHERE customers.customer_id = invoices.customer_id
AND invoices.invoice_id = items.invoice_id
AND customers.name = 'Mary'
AND items.name ~ '^Blue';


WITH rel AS (
    SELECT items.item_id, 
        items.name AS item_name, 
        customers.name AS customer_name
    FROM customers
    JOIN invoices USING (customer_id)
    JOIN items USING (invoice_id)
)
UPDATE items
SET name = replace(items.name, 'Red', 'Orange')
FROM rel
WHERE items.item_id = rel.item_id
AND rel.customer_name = 'Mary'
AND rel.item_name ~ '^Red';


SELECT * 
FROM customers
JOIN invoices USING (customer_id)
JOIN items USING (invoice_id)
WHERE customers.name = 'Mary'
ORDER BY customers.name, invoice_id;


DELETE FROM items
USING invoices, customers
WHERE items.invoice_id = invoices.invoice_id
AND invoices.invoice_id = customers.customer_id
AND customers.name = 'Peter'
AND items.name ~ 'Red';



