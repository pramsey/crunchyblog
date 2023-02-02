import psycopg2



conn = psycopg2.connect(
    host="localhost",
    database="pramsey",
    user="pramsey",
    password="")


def record_sale(conn, customer, items):
    # begin a transaction
    with conn.cursor() as cur:
        
        # add a new invoice
        sql = """INSERT INTO invoices (customer_id) 
                SELECT id FROM customers WHERE name = %s
                RETURNING id AS invoice_id"""

        cur.execute(sql, (customer,))
        # recover invoice number
        invoice_id = cur.fetchone()[0]

        # add items to the invoice
        sql = "INSERT INTO items (name, invoice_id) VALUES (%s, %s)"
        for item in items:
            cur.execute(sql, (item, invoice_id))
    # exit with block: transaction commits, cursor closes


record_sale(conn, "Mary", ["Purple Automobile", "Yellow Automobile"])

