# Faster JSON generation with PostgreSQL

PostgreSQL has [built-in JSON generators](https://www.postgresql.org/docs/current/functions-json.html) that can be used to create structured JSON output right in the database, upping performance and radically simplifying web tiers.

Too often, web tiers are full of boiler plate, that does nothing except convert a result set into JSON. A middle tier could be as simple as a function call that returns JSON, all we need is an easy way to convert result sets into JSON in the database. 

Fortunately, PostgreSQL **has such functions**, that run right next to the data, for better performance and lower bandwidth usage.


## Some example data

To try out these examples, load this tiny database:

```sql
CREATE TABLE employees (
  employee_id serial primary key,
  department_id integer references departments(department_id),
  name text, 
  start_date date, 
  fingers integer, 
  geom geometry(point, 4326)
  );

CREATE TABLE departments (
  department_id bigint primary key,
  name text
  );

INSERT INTO departments 
 (department_id, name)
VALUES 
 (1, 'spatial'),
 (2, 'cloud');

INSERT INTO employees 
 (department_id, name, start_date, fingers, geom)
VALUES
 (1, 'Paul',   '2018/09/02', 10, 'POINT(-123.32977 48.40732)'),
 (1, 'Martin', '2019/09/02',  9, 'POINT(-123.32977 48.40732)'),
 (2, 'Craig',  '2019/11/01', 10, 'POINT(-122.33207 47.60621)'),
 (2, 'Dan',    '2020/10/01',  8, 'POINT(-122.33207 47.60621)');
```

Four employees, arranged into two departments, with some detail information about each employee.


## Easy JSON using row_to_json

The simplest JSON generator is `row_to_json()` which takes in a tuple value and returns the equivalent JSON dictionary.

```sql
SELECT row_to_json(employees)
FROM employees
WHERE employee_id = 1;
```

The resulting JSON uses the column names for keys, so you get a neat dictionary.

```json
{
  "employee_id": 1,
  "department_id": 1,
  "name": "Paul",
  "start_date": "2018-09-02",
  "fingers": 10,
  "geom": {
    "type": "Point",
    "coordinates": [
      -123.329773,
      48.407326
    ]
  }
}
```

And look what happens to the geometry column! Because PostGIS includes a cast from geometry to JSON, the geometry column is automatically mapped into [GeoJSON](https://geojson.org/) in the conversion. This is a useful trick with any custom type: define a cast to JSON and you automatically integrate with the native PostgreSQL JSON generators.


## Full result sets using json_agg

Turning a single row into a dictionary is fine for basic record access, but queries frequently require multiple rows to be converted. 

Fortunately, there's an [aggregate function](https://www.postgresql.org/docs/10/functions-aggregate.html) for that, `json_agg`, which carries out the JSON conversion and converts the multiple results into a JSON list. 

```sql
SELECT json_agg(e) 
FROM (
    SELECT employee_id, name 
    FROM employees
    WHERE department_id = 1
    ) e;
```

Note that in order to strip down the data in the record, we use a subquery to make a narrower input to `json_agg`.

```json
[
  {
    "employee_id": 1,
    "name": "Paul"
  },
  {
    "employee_id": 2,
    "name": "Martin"
  }
]
```


## Nested results using subqueries

So far, all this is pretty easy to replicate in middleware, but things get more interesting when you start dumping structured results. 

Using aggregation, and converting the results to JSON in stages, it's possible to build up nested JSON outputs that reflect table relationships.

```sql
WITH 
-- strip down employees table
employees AS (
  SELECT department_id, name, start_date
  FROM employees
),
-- join to departments table and aggregate
departments AS (
  SELECT d.name AS department_name, 
         json_agg(e) AS employees
  FROM departments d
  JOIN employees e
  USING (department_id)
  GROUP BY d.name
)
-- output as one json list
SELECT json_agg(departments)
FROM departments;
```

And the result has one entry for each department, which each contains its two employees.

```json
[
  {
    "department_name": "cloud",
    "employees": [
      {
        "department_id": 2,
        "name": "Craig",
        "start_date": "2019-11-01"
      },
      {
        "department_id": 2,
        "name": "Dan",
        "start_date": "2020-10-01"
      }
    ]
  },
  {
    "department_name": "spatial",
    "employees": [
      {
        "department_id": 1,
        "name": "Paul",
        "start_date": "2018-09-02"
      },
      {
        "department_id": 1,
        "name": "Martin",
        "start_date": "2019-09-02"
      }
    ]
  }
]
```

If you would prefer your output to be an associative array instead of a list, replace the final `json_agg` with `json_object_agg`.


## All your tables in JSON

Ever wanted to quickly extract a definition of your table structures from the database? With the JSON formatters and the PostgreSQL system tables, all that info is right at hand.

```sql
WITH rows AS (
  SELECT c.relname, a.attname, a.attnotnull, a.attnum, t.typname
  FROM pg_class c
  JOIN pg_attribute a 
    ON c.oid = a.attrelid and a.attnum >= 0
  JOIN pg_type t
    ON t.oid = a.atttypid
  JOIN pg_namespace n
    ON c.relnamespace = n.oid
  WHERE n.nspname = 'public'
    AND c.relkind = 'r'
),                                  
agg AS (     
  SELECT rows.relname, json_agg(rows ORDER BY attnum) AS attrs
  FROM rows
  GROUP BY rows.relname
)                           
SELECT json_object_agg(agg.relname, agg.attrs)
FROM agg;
```

Here's the entry for the "departments" table.

```json
{
  "departments": [
    {
      "relname": "departments",
      "attname": "department_id",
      "attnotnull": true,
      "attnum": 1,
      "typname": "int8"
    },
    {
      "relname": "departments",
      "attname": "name",
      "attnotnull": false,
      "attnum": 2,
      "typname": "text"
    }
  ],
  ...
}
```


## Conclusion

* PostgreSQL JSON emitters can turn any result set into JSON right in the database
* Web tiers can be vastly simplified by pushing JSON creation further down the stack
* Custom types can emit custom JSON if a cast to json is defined on them



