# Fast, Flexible Summaries with Aggregate Filters and Windows

PostgreSQL can provide high performance summaries over multi-million record tables, and supports some great SQL sugar to make it concise and readable, in particular aggregate filtering.

A huge amount of reporting is about generating percentages: for a particular condition, what is a value relative to a baseline. 

## Some Sample Data

Here's a quick "sales table" with three categories ("a" and "b" and "c") and one million random values between 0 and 10:

```sql
CREATE TABLE sales 
AS 
SELECT a, b, 
       CASE WHEN random() < 0.4 THEN 'bird' ELSE 'bee' END AS c,
       10 * random() AS value 
FROM generate_series(1,1000) a, 
     generate_series(1,1000) b;
```

## The Olden Days

In the bad-old-days, generating a percentage might involve add in a subquery to generate the total before calculating the percentage. To "find the % of value where c is 'bee'":

```sql
SELECT 
  100.0 * sum(value) / (SELECT sum(value) AS total FROM sales) AS bee_pct
FROM sales
WHERE c = 'bee'
```

This is all very nice, but what if I also want to calculate the percentage of sales with an "a" value > 900? 

Suddenly I'm running two queries, or perhaps building a CTE like this:

```sql
WITH total AS (
  SELECT sum(value) AS total 
  FROM sales
),
bee AS (
  SELECT sum(value) AS bee 
  FROM sales 
  WHERE c = 'bee'
),
a900 AS (
  SELECT sum(value) AS a900 
  FROM sales
  WHERE a > 900
)
SELECT 100.0 * bee / total AS bee_pct,
       100.0 * a900 / total AS a900_pct
FROM total, bee, a900;
```

Yuck! That's ugly! Also, it scans the table **three** times. Is there another way? Sure, there's always another way, but it's not necessarily any nicer.

```sql
SELECT 
  100.0 * sum(CASE WHEN c = 'bee' THEN value ELSE 0.0 END) / 
    sum(value) AS bee_pct,
  100.0 * sum(CASE WHEN a > 900 THEN value ELSE 0.0 END) / 
    sum(value) AS a900_pct
FROM sales;
```

## Aggregate Filters

PostgreSQL has "window functions" but sometimes people forget that aggregate functions are also window functions, so they can accept the same controls as more exciting window functions like `rank()` or `lag()`.

```sql
SELECT 
  100.0 * sum(value) FILTER (WHERE c = 'bee') / sum(value) AS bee_pct,
  100.0 * sum(value) FILTER (WHERE a > 900) / sum(value) AS a900_pct
FROM sales;
```

This is so much clearer than the other alternatives, and it runs faster than them too!

With modern PostgreSQL, this single scan of the table will be parallelized. Even better, you can use any aggregate function at all with a filter condition, which is not really possible with the `CASE` hack. 

```sql
SELECT 
  stddev(value) FILTER (WHERE c = 'bee') AS bee_stddev,
  stddev(value) FILTER (WHERE a > 900) AS a900_stddev
FROM sales;
```

## Fish in your Data Lake

For simple reporting and data analysis in a data lake, there's nothing quite as nice as a good wide materialized view that gathers all the columns of interest into a single flat table, and the liberal application of aggregate filters.

Aggregate filters can even be combined with standard `GROUP` clauses to get a quick break down of statistics within groups.

```sql
SELECT 
  b / 100 AS b_div_100,
  stddev(value) FILTER (WHERE c = 'bee') AS bee_stddev,
  stddev(value) FILTER (WHERE a > 900) AS a900_stddev
FROM sales
GROUP BY 1;
```

## Conclusions

* When building up analytical queries, think about what you can extract in **one pass** through the table, using aggregate filters to strip out just the information you want.
* When building up an analytical lake, consider materializing interesting columns into a query view and using aggregate filters to explore the contents.


