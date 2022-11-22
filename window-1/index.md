
# One-pass Percentage Calculations

Back when I first learned SQL, calculating percentages over a set of individual contributions was an ungainly business:

* First calculate the denominator of the percentage,
* Then join that denominator back to the original table to calculate the percentage.

This requires two passes of the table: once for the denominator and once for the percentage. For BI queries over large tables (that is, for most BI queries) more passes over the table slow performance significantly.

Also, the SQL was really ugly!

With modern PostgreSQL, you can **calculate complex percentages over different groups in a single pass**, using "[window functions](https://www.postgresql.org/docs/current/functions-window.html)".

## Example Data

Here's our pretend data, a small table of seven musicians who perform in two bands.

```sql
CREATE TABLE musicians (
    band text,
    name text,
    earnings numeric(10,2)
);

INSERT INTO musicians VALUES
    ('PPM',  'Paul',   2.2),
    ('PPM',  'Peter',  4.5),
    ('PPM',  'Mary',   1.1),
    ('CSNY', 'Crosby', 4.2),
    ('CSNY', 'Stills', 6.3),
    ('CSNY', 'Nash',   0.3),
    ('CSNY', 'Young',  2.2);
```


## Percentage Total Earnings per Musician

Back in the "olden days", before [WITH](https://www.postgresql.org/docs/current/queries-with.html) statments and [window functions](https://www.postgresql.org/docs/current/functions-window.html), the query might look like this:

```sql
SELECT 
    band, name, 
    round(100 * earnings/sums.sum,1) AS percent
FROM musicians
CROSS JOIN (
    SELECT Sum(earnings)
    FROM musicians
    ) AS sums
ORDER BY percent;
```

In addition to specific windowing-only functions like `row_number()`, the PostgreSQL aggregate functions can also be used in a windowing mode. So we can re-write the query above like this:

```sql
SELECT 
    band, name, 
    round(100 * earnings / 
        Sum(earnings) OVER (),
        1) AS percent
FROM musicians
ORDER BY percent;
```

Here, we get a sum of all earnings, by using the `sum()` function with the `OVER` keyword to indicate a windowing context.

Since we provide no restrictions on `OVER` the effect is a **sum over all rows** in the result relation. Which is what we need!


## Percentage of Band Earnings per Musician

Percentage earnings over all earnings is only one way to slice up the earnings pie: maybe we want to know which musicians made the most money relative to their band earnings?

Doing this the old fashioned way, the SQL is getting a lot hairier!

```sql
WITH sums AS (
    SELECT Sum(earnings), band
    FROM musicians
    GROUP BY band
)
SELECT 
    band, name, 
    round(100 * earnings/sums.sum, 1) AS percent
FROM musicians
JOIN sums USING (band)
ORDER BY band, percent;
```

With the window function, on the other hand, we just need to change the characteristic of the denominator. Rather than a sum of all earnings, we want the sum calculated **per band**, which we get by adding a `PARTITION` to the `OVER` clause of the window function.

```sql
SELECT 
    band, name, 
    round(100 * earnings / 
        Sum(earnings) OVER (PARTITION BY band), 
        1) AS percent
FROM musicians
ORDER BY band, percent;
```


## Percentage of Total Earnings per Band

Finally, for completeness, here's the single-scan approach to getting the per-band percentage of total earnings:

```sql
SELECT 
    band,
    round(100 * earnings / 
        Sum(earnings) OVER (),
        1) AS percent
FROM (
    SELECT band, 
        Sum(earnings) AS earnings
    FROM musicians
    GROUP BY band
    ) bands;
```

Note that I've been forced into using a sub-query here, because embedding a window query within an aggregate is not allowed. 

However, if you check the `EXPLAIN` for this query, you'll find it still **only has a single scan** of the main data table, which is mostly what we are trying to avoid, since these kind of BI queries are usually run against very large fact tables, and scans are the expensive bit.

