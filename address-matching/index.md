# Quick and Dirty Address Matching with LibPostal

Most businesses have databases of previous customers, and data analysts will frequently be asked to join arbitrary data to the customer tables in order to provide analysis.

Unfortunately joining address data together is notoriously difficult:

* The same address can be expressed in many ways
* The parts of addresses are not always clear
* There are valid lexically very similar addresses very nearby any given address

One way of doing quick and dirty categorization of address data to find duplicates or join tables is to apply "address normalization" to the address data.

Address normalization attempts to convert an arbitrary input address string into a finite number of standard forms that the input might intend to represent.

It's not hard to imagine writing your own normalizer in python or another scripting language: convert standard abbreviations to fully spelled out words, deal with equivalencies like "first" and "1st" and "1", strip out lexical quirks like capitalization and diacritics. But what if you had to do it for a second language and region? And then another? You might be bi-lingual, but are you tri-lingual? Quad?

Enter [libpostal](https://github.com/openvenues/libpostal), a natural language processing library trained on over 1B address records in the international [OpenStreetMap](https://openstreetmap.org/) database. For use inside PostgreSQL, you can use the [pgsql-postal](https://github.com/pramsey/pgsql-postal) extension to call the library directly from SQL.

libpostal only has two operations, "address normalization" and "address parsing", that are exposed by pgsql-postal with the postal_normalize() and postal_parse() functions.

Normalization takes an address string and converts it to all the standard forms that "make sense". For example:

```sql
SELECT unnest(postal_normalize('390 Greenwich St., New york, ny, 10013'));
```
```
390 greenwich saint new york ny 10013
390 greenwich saint new york new york 10013
390 greenwich street new york ny 10013
390 greenwich street new york new york 10013
```

Parsing takes apart a string into address components and returns a [JSONB](https://www.postgresql.org/docs/current/datatype-json.html) of those components:

```sql
SELECT jsonb_pretty(postal_parse('390 Greenwich St., New york, ny, 10013'));
```
```json
{                           
"city": "new york",     
"road": "greenwich st.",
"state": "ny",          
"postcode": "10013",    
"house_number": "390"   
}
```

We can use normalization to create a table of text searchable address strings, and then use full text search to efficiently search that table for potential matches for new addresses.

## International Normalization

As we saw above, normalization takes raw address strings and turns them into "possible standard forms", which are suitable for searching against. They aren't necessarily the best forms, more regionally-aware parsing can do a better job of standard North American parsing and formatting, but where libpostal shines is being a ready-to-run fully international solution that doesn't even need to be told what language it is working on.

For example, this address in Berlin:
```sql
SELECT unnest(postal_normalize('Potsdamer Straße 3, 10785 Berlin, Germany'));
```
```
potsdamer strasse 3 10785 berlin germany
```
The diacritics are stripped out, but otherwise it is not heavily changed. The same address with an abbreviation:
```sql
SELECT unnest(postal_normalize('POTSDAMER STR. 3, 10785 BERLIN'));
```
```
potsdamer strasse 3 10785 berlin
```
The library recognizes based on nothing but context that it is working in German, and that 'STR' is short for 'strasse', not 'street'.

## Build and Install LibPostal

* Download or clone the libpostal
* Build and install the library

    ```
    cd libpostal 
    ./bootstrap.sh 
    sudo mkdir /opt/libpostal 
    ./configure --datadir=/opt/libpostal 
    make 
    sudo make install 
    ```
* Download or clone the pgsql-postal extension
* Build and install the extension
    ```
    cd pgsql-postal 
    make 
    sudo make install 
    ```

* Create a working database
    ```
    createdb postal 
    ```

* Create the extensions
    ```
    psql -d postal -c 'create extension postal' psql -d postal -c 'create extension fuzzystrmatch' 
    ```

## Load and Prepare the Addresses

For this example, we will load a CSV file of New York addresses.

* Download and unzip the [addresses for the US Northeast](https://s3.amazonaws.com/data.openaddresses.io/openaddr-collected-us_northeast.zip) from [OpenAddresses](https://results.openaddresses.io/):
* Unzip the address file

Now we need a table to load the addresses into:
```sql
DROP TABLE IF EXISTS addresses; 
CREATE TABLE addresses (
    pk serial primary key,
    lon double precision, 
    lat double precision, 
    number varchar, 
    street varchar, 
    unit varchar, 
    city varchar, 
    district varchar, 
    region varchar, 
    postcode varchar, 
    id double precision, 
    hash varchar
);
```

Copy the New York data into the empty table:

```sql
COPY addresses (
    lon,
    lat,
    number,
    street,
    unit,
    city,
    district,
    region,
    postcode,
    id,
    hash
)
FROM 'us/ny/city_of_new_york.csv' WITH (format csv, header true);
```

## Create the Normalized Address Table

The New York address table has addresses already split out into components, but we want to feed them to the normalizer as one string, so we actually stick them back together again.

```sql
SELECT concat_ws(', ', concat_ws(' ', unit, number, street), 'NEW YORK', postcode)
FROM addresses
LIMIT 5;
```
```
1458 36 ST, NEW YORK, 11218
927 80 ST, NEW YORK, 11228<
2116 73 ST, NEW YORK, 11204
2168 73 ST, NEW YORK, 11204
105 E  32 ST, NEW YORK, 11226
```

We are also going to want to search the normalized address using the PostgreSQL full-text search engine, so while creating the normalized form we'll also build a tsvector of the normalized text.

```sql
DROP TABLE IF EXISTS addresses_normalized; 

CREATE TABLE addresses_normalized AS 
  SELECT pk, 
         na, -- normalized address 
         to_tsvector('simple', na) AS ts -- tsearch address 
  FROM ( 
    SELECT pk, 
           unnest(
            postal_normalize(
              concat_ws(', ', 
              concat_ws(' ', unit, number, street), 
              'NEW YORK', postcode))) AS na 
    FROM addresses
    ) AS subq;
```

Now we have a search table that we can join back to the original addresses via the primary key, pk.

```sql
SELECT * FROM addresses_normalized LIMIT 5;
```
```
     pk   |                na                 |                            ts             
  --------+-----------------------------------+-----------------------------------------------------------
   817072 | 410 liberty avenue new york 11207 | '11207':6 '410':1 'avenue':3 'liberty':2 'new':4 'york':5
   817073 | 5006 snyder avenue new york 11203 | '11203':6 '5006':1 'avenue':3 'new':4 'snyder':2 'york':5
   817074 | 586 liberty avenue new york 11207 | '11207':6 '586':1 'avenue':3 'liberty':2 'new':4 'york':5
   817075 | 45 hewitt avenue new york 10301   | '10301':6 '45':1 'avenue':3 'hewitt':2 'new':4 'york':5
   817076 | 88 coventry road new york 10304   | '10304':6 '88':1 'coventry':2 'new':4 'road':3 'york':5
```

## Search Using the Normalized Address Table

To search the addresses with a single input, we need to keep a few things in mind:

* A single search term can generate multiple normalized forms that we will want to search with
* We will need to turn those normalized forms into text search queries
* Order matters in addresses, so we need to run a phrase search

We start the query using WITH to create a set of text search queries to join to the search table, then join them and add the levenshtein distance to get a feel for how lexically close each potential match is.

```sql
WITH normalized AS (
    SELECT unnest(postal_normalize('388 Greenwich st, ny')) AS na
), tsqueries as (
    SELECT phraseto_tsquery('simple', na) AS ts, na
    FROM normalized
)
SELECT DISTINCT ON (pk)
    addresses.*,
    addresses_normalized.na AS addresses_normalized_na,
    tsqueries.na AS tsqueries_na,
    levenshtein(tsqueries.na, addresses_normalized.na) AS levenshtein
FROM addresses
JOIN addresses_normalized USING (pk)
JOIN tsqueries ON (addresses_normalized.ts @@ tsqueries.ts)
ORDER BY pk;
```

With 1M New York addresses and 1.7M normalized candidates, the search takes about 90ms or less.

## Join Using the Normalized Address Table

We can use the normalized address table and the normalizer to do a bulk join of another address table to the master table the New York addresses.

* Download the New York open data Health Centers data
* Create a table for the data
    
    ```sql
    CREATE TABLE health_centers (
        name text,
        address text,
        postal text,
        telephone text,
        lat double precision,
        lon double precision,
        board text,
        council text,
        censustract text,
        bin text,
        bbl text,
        nta text,
        borough text
    );
    ```

* Load the data
    
    ```sql
    COPY health_centers FROM 'rows.csv' WITH (format csv, header true);
    ```
    
* The health center data has quite different form for addresses from the base New York address table, but we can still get a lot of joins.
    
    ```sql
    WITH queries AS (
        SELECT
            name as health_name,
            address as health_address,
            phraseto_tsquery('simple', unnest(postal_normalize(concat_ws(', ', address, 'new york')))) AS tsq
        FROM health_centers
    )
    SELECT
        addresses.*,
        addresses_normalized.*,
        queries.health_name,
        queries.health_address
    FROM addresses
    JOIN addresses_normalized using (pk)
    JOIN queries ON (addresses_normalized.ts @@ queries.tsq);
    ```

Here's one example of a matched record. Note the difference between the ’street’ and ’number’ from the address table to the ‘health_address’ from the health center table. We are able to match lexically quite dissimilar data.

```
    pk             | 485629
    lon            | -74.0091443
    lat            | 40.645177
    number         | 514
    street         | 49 ST
    unit           | 
    city           | NEW YORK
    district       | 
    region         | NEW YORK
    postcode       | 11220
    id             | 3017183
    hash           | a373b8e9e014c4b4
    geog           | 0101000020E6100000785CF9D1958052C0D190F12895524440
    pk             | 485629
    na             | 514 49 street new york 11220
    ts             | '11220':6 '49':2 '514':1 'new':4 'street':3 'york':5
    health_name    | Sunset Park Family Health Center
    health_address | 514 49th Street
```

And another:

```
    pk             | 902117
    lon            | -73.9440892
    lat            | 40.7911112
    number         | 212
    street         | E  106 ST
    unit           | 
    city           | NEW YORK
    district       | 
    region         | NEW YORK
    postcode       | 10029
    id             | 9106834
    hash           | 9802bcab491efb2a
    geog           | 0101000020E61000006FA01BF56B7C52C0EABFBD2143654440
    pk             | 902117
    na             | 212 east 106 street new york 10029
    ts             | '10029':7 '106':3 '212':1 'east':2 'new':5 'street':4 'york':6
    health_name    | Settlement Health & Medical Services
    health_address | 212 East 106th Street
```
    
## Conclusion

* While it is not a 100% solution, using normalized addresses and full text search provides a relatively fast (less than 100ms) matching approach for loose address matching.
