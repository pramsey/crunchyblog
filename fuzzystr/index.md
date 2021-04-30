# Fuzzy Name Matching in PostgreSQL

A surprisingly common problem in both application development and analysis is, "given an input name, find the database record it most likely refers to". It's common because databases of names and people are common, and it's a problem because names are an incredibly irregular identifying tokens. 

The page "Falsehoods Programmers Believe About Names" covers some of the ways names are hard to deal with in programming. This post will ignore most of those complexities, and deal with the still-difficult problem of matching up loose user input to a database of names.

## Sample Data

The data for this post are 50,000 Westernized names created by the [Fake Name Generator](https://www.fakenamegenerator.com/), then loaded into PostgreSQL using the COPY command.

```sql
CREATE TABLE names (
    number integer primary key, 
    givenname text, 
    middleinitial text, 
    surname text
    );

\COPY names FROM 'FakeNameGenerator.csv' WITH (FORMAT csv, HEADER true);

```

The names are a mix of common American given names and surnames.

```
SELECT * FROM names LIMIT 10;

 number | givenname | middleinitial |  surname   
--------+-----------+---------------+------------
      1 | Helen     | S             | Godinez
      2 | Sabrina   | L             | Glanz
      3 | Tiffany   | P             | Hernandez
      4 | Willie    | C             | Williams
      5 | Michael   | S             | Jones
      6 | Jaime     | L             | Sanderson
      7 | Luis      | L             | Broderick
      8 | Debby     | R             | Thorp
      9 | Cynthia   | N             | Figueroa
     10 | Amanda    | K             | Schnieders
```

## Prefix Matching

So, suppose we are working with a form input field, and want to return names that match user keystrokes in real time: if a user types "Back" what query can find all the surnames that start with "Back"?

Easy, a "LIKE" query:

```sql
SELECT * FROM names WHERE surname LIKE 'Back%';
```

On the test data of 50,000 names, the query returns **8 names, in about 11ms**.

```
 number | givenname | middleinitial | surname  
--------+-----------+---------------+----------
   6788 | Milton    | E             | Backer
   7748 | Earl      | L             | Backlund
  11787 | Estela    | J             | Backlund
  28516 | Lillian   | J             | Backus
  31087 | John      | F             | Backer
  35760 | Joyce     | D             | Backman
  43301 | Ronald    | S             | Backman
  44967 | Lisa      | J             | Backman
```

So far we have no indexes, so what happens if we index the "surnames" column?

```sql
CREATE INDEX names_surname_txt ON names (surname);
```

Now, when we run the "LIKE" query, the resutl is ... **8 names in about 11ms**. Wait, what? The index didn't make the query any faster!

The problem is that the default [operator class](https://www.postgresql.org/docs/current/indexes-opclass.html) for the "text" data type does not support pattern matching. If you are going to do prefix matching, you need to create an index using the "text_pattern_ops" operator class.

```sql
CREATE INDEX names_surname_txt ON names (surname text_pattern_ops);
```

Now the same prefix query returns **8 names in about 1ms**. Much better!

### Case Insensitivity

You cannot count on users applying any particular rules to upper- and lower-case characters in the input, so the only sensible thing to do is coerce all input into a single casing. 

```sql
SELECT * FROM names WHERE lower(surname) LIKE lower('Back%');
```

Unfortunately, now our text prefix index is no longer being used. 

PostgreSQL supports "functional" indexes, where the index is built on a functional transformation of the stored data. As long as the query uses the same transformation as the function, you can index transforms of your data without having to store them directly in your table.

```sql
CREATE INDEX names_surname_txt ON names (lower(surname) text_pattern_ops);
```

Now, the query is back to returning **8 names in about 1ms** again, but is fully case-insensitive.

### Levenshtein Matching

So far, our imaginary user has been very good at entering data that match the database. But what if they are looking for "Robert Harrington" and type in "Robert Harington" (one "r")... is there a way to still find them the name(s) they are looking for, without sacrificing performance?

Enter the PostgreSQL [fuzzystrmatch](https://www.postgresql.org/docs/current/fuzzystrmatch.html) extension! This extension provides some utility functions for matching similar-but-not-quite-the-same strings.

The first function we will use calculates the [Levenshtein distance](https://en.wikipedia.org/wiki/Levenshtein_distance) between two strings. The Levenshtein distance is the sum of the number of character transpositions and the number of character insertions/deletions.

* levenshtein('mister','mister') == 0
* levenshtein('mister','master') == 1
* levenshtein('mister','maser') == 2
* levenshtein('mister','laser') == 3

We can use Levenshtein distance to write a query that finds al the database entries that are within one character of the input string ("Robert Harington"). To keep things simpler we compare the "full name", a concatenation of the surname and given name.

```sql
WITH q AS (
  SELECT 'Robert' AS qgn, 'Harington' AS qsn
)
SELECT  
  levenshtein(lower(concat(surname,givenname)),lower(concat(qsn, qgn))) AS leven,
  names.*
FROM names, q
WHERE levenshtein(lower(concat(surname,givenname)),lower(concat(qsn, qgn))) < 2
ORDER BY leven;
```

And we get back the two "Harrington" records!

```
 leven | number | givenname | middleinitial |  surname   
-------+--------+-----------+---------------+------------
     1 |   1186 | Robert    | H             | Harrington
     1 |  21256 | Robert    | B             | Harrington
```

The only trouble is, it's really slow (**over 100ms**), because it is calculating Levenshtein distances between our candidate string and **every name in the database**. This approach will not scale without some indexing help.

### Soundex Indexing

What we want to do is use an index filter to reduce the number of candidate records to a manageable size, and then only perform the expensive Levenshtein calculation on those records. 

Fortunately the [fuzzystrmatch](https://www.postgresql.org/docs/current/fuzzystrmatch.html) has a perfect answer: [Soundex](https://en.wikipedia.org/wiki/Soundex)!

The Soundex algorithm reduces a word to a "phonetic code", basically a short string that approximates the pronounciation of the initial syllable. This allows us to avoid all kinds of common misspelling mistakes, since the Soundex is the same as long as the pronounciation of the mistake is similar.

* soundex('Harrington') = H652
* soundex('Harington') = H652
* soundex('Herington') = H652
* soundex('Heringtan') = H652

Our full database is 50,000 records: how big is the set of records that match the soundex of the last name?

```sql
SELECT count(*) 
  FROM names 
  WHERE soundex(surname) = soundex('Harrington');
```

Only **46** records match the soundex! 

### Soundex + Levenshtein

So we can add a soundex functional index, and re-write our Levenshtein query to make use of soundex as a prefilter, to get a levenshtein calculation at fully indexed speed.

```sql
CREATE INDEX surname_soundex ON names (soundex(surname));
```

With a functional index, we can add a soundex clause and re-run the query.

```sql
WITH q AS (
  SELECT 'Robert' AS qgn, 'Harington' AS qsn
)
SELECT  
  levenshtein(lower(concat(surname,givenname)),lower(concat(qsn, qgn))) AS leven,
  names.*
FROM names, q
WHERE soundex(surname) = soundex(qsn)
AND levenshtein(lower(concat(surname,givenname)),lower(concat(qsn, qgn))) < 2
```

Now we get the same answer as before, but in **just 1 ms**, one hundred times faster.

### Conclusion

With the right indexes, and the [fuzzystrmatch](https://www.postgresql.org/docs/current/fuzzystrmatch.html) toolkit, it's possible to build very fast loose text matching queries.

* Remember `text_pattern_ops` for indexed prefix filtering.
* Use `lower()` and functional indexes for case-insensitive queries.
* Combine indexes on `soundex()` with expensive tests like `levenshtein()` to get fast searches for fuzzy queries.

