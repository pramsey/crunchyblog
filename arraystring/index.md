# Postgres strings to arrays and back again

One of my favourite (in an ironic sense) data formats is the "CSV in the CSV", a CSV file in which one or more of the column is itself structured as CSV. 

Putting CSV-formatted columns in your CSV file is a low tech approach to shipping a multi-table relational data structure in a single file. The file can be read by anything that can read CSV (which is everything?) and ships around the related data in a very readable form. 

```
Station North,"-1,-4,-14,-15,-16,-15,-12,-9,-3,0,1,2"
Station West,"2,4,5,6,9,10,15,16,13,12,10,9,5,3,1"
Station East,"5,3,2,4,5,6,9,10,15,16,13,12,10,9,5,4,2,1"
Station South,"12,18,22,25,29,30,33,31,30,29,28,25,24,23,14"
```

But how can we interact with that extra data?

## Example Data

Here's a table to load the data into.

```sql
CREATE TABLE weather_data (
    station text,
    temps text
);
```

Happily, the PostgreSQL CSV importer will correctly consume the "[csv in csv](weatherdata.csv)" file.

```
COPY weather_data FROM 'weather_data.csv' WITH (FORMAT csv);
```

For this example, it might be easier to just INSERT the data directly.

```sql
INSERT INTO weather_data VALUES
('Station North','-1,-4,-14,-15,-16,-15,-12,-9,-3,0,1,2'),
('Station West','2,4,5,6,9,10,15,16,13,12,10,9,5,3,1'),
('Station East','5,3,2,4,5,6,9,10,15,16,13,12,10,9,5,4,2,1'),
('Station South','12,18,22,25,29,30,33,31,30,29,28,25,24,23,14');
```


## Arrays to the Rescue

With the data in the table, the next question is: what to do with that silly comma-separated list of temperatures? First, make it more usable by converting it to an array with the `split_to_array(string,separator)` function.

```sql
-- Split to array
SELECT 
	station,
	string_to_array(temps,',') AS array 
FROM weather_data;
```

<details><summary>Query Result</summary>
```
    station    |                     array                      
---------------+------------------------------------------------
 Station North | {-1,-4,-14,-15,-16,-15,-12,-9,-3,0,1,2}
 Station West  | {2,4,5,6,9,10,15,16,13,12,10,9,5,3,1}
 Station East  | {5,3,2,4,5,6,9,10,15,16,13,12,10,9,5,4,2,1}
 Station South | {12,18,22,25,29,30,33,31,30,29,28,25,24,23,14}
```
</details>

Having an array instead of a string doesn't *look* much more useful, but we can show that in fact we now have structured data by doing "array-only" things to the data, like returning the array length.

```sql
-- Split to array, analyze array
SELECT 
	station,
	cardinality(string_to_array(temps,',')) AS array_size 
FROM weather_data;
```

<details><summary>Query Result</summary>
```
    station    | array_size 
---------------+------------
 Station North |         12
 Station West  |         15
 Station East  |         18
 Station South |         15
```
</details>

## Expanding and Analyzing the Array

However, by far the most fun you can have with an array like this is to `unnest(array)` it! The `unnest(array)` function is a "set returning function" which means it can return more than one row. How does that work? All the other parts of the incoming row are duplicated, so that each row has a full collection of data, like this.

```sql
-- Split to array, unnest
SELECT 
	station,
	unnest(string_to_array(temps,',')) AS temps 
FROM weather_data ;
```

<details><summary>Query Result</summary>
```
    station    | temps 
---------------+-------
 Station North | -1
 Station North | -4
 Station North | -14
 Station North | -15
 Station North | -16
 Station North | -15
 Station North | -12
 Station North | -9
 Station North | -3
 Station North | 0
 Station North | 1
 Station North | 2
 Station West  | 2
 Station West  | 4
 Station West  | 5
 Station West  | 6
 Station West  | 9
 Station West  | 10
 Station West  | 15
 Station West  | 16
 Station West  | 13
 Station West  | 12
 Station West  | 10
 Station West  | 9
 Station West  | 5
 Station West  | 3
 Station West  | 1
 Station East  | 5
 Station East  | 3
 Station East  | 2
 Station East  | 4
 Station East  | 5
 Station East  | 6
 Station East  | 9
 Station East  | 10
 Station East  | 15
 Station East  | 16
 Station East  | 13
 Station East  | 12
 Station East  | 10
 Station East  | 9
 Station East  | 5
 Station East  | 4
 Station East  | 2
 Station East  | 1
 Station South | 12
 Station South | 18
 Station South | 22
 Station South | 25
 Station South | 29
 Station South | 30
 Station South | 33
 Station South | 31
 Station South | 30
 Station South | 29
 Station South | 28
 Station South | 25
 Station South | 24
 Station South | 23
 Station South | 14
```
</details>

The data now looks a lot like something we might get by joining tables together in a standard data model, and we can actually do standard analytical things now, like figure out the temperature range at each station.

```sql
-- Split to array, unnest and analyze temps
WITH unnested_data AS (
	SELECT 
		station,
		unnest(string_to_array(temps,',')) AS temps 
	FROM weather_data
)
SELECT 
	station,
	max(temps) AS max_temp,
	min(temps) AS min_temp 
FROM unnested_data 
GROUP BY station;
```

<details><summary>Query Result</summary>
```
    station    | max_temp | min_temp 
---------------+----------+----------
 Station North | 2        | -1
 Station West  | 9        | 1
 Station East  | 9        | 1
 Station South | 33       | 12
```
</details>

## Reductio ad Absurdum

Finally, for completeness, if you want to keep your associated tables in a string, but just don't like commas, here's how to split and re-join your data, using a new delimiter.

```sql
-- Split to array, join to string
SELECT 
	station,
	array_to_string(string_to_array(temps,','),'|') AS temps 
FROM weather_data
```

<details><summary>Query Result</summary>
```
    station    |                    temps                     
---------------+----------------------------------------------
 Station North | -1|-4|-14|-15|-16|-15|-12|-9|-3|0|1|2
 Station West  | 2|4|5|6|9|10|15|16|13|12|10|9|5|3|1
 Station East  | 5|3|2|4|5|6|9|10|15|16|13|12|10|9|5|4|2|1
 Station South | 12|18|22|25|29|30|33|31|30|29|28|25|24|23|14
```
</details>
