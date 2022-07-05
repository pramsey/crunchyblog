# Choosing a PostgreSQL Number Format

It should be the easiest thing in the world: you are modelling your data and you need a column for some numbers, what type do you use?

PostgreSQL offers a *lot* of different number types, and they all have advantages and limitations. You want the number type that is going to:

* Store your data using the smallest amout of space
* Represent your data with the smallest amount of error
* Manipulate your data using the correct logic

If your processing needs can be met with a fixed size type (integer or floating point) then choose the type that has enough range to fit your data. 

If you need to process data at extremely high precision, or store with exact precision, then use the `numeric` type, which has no range bounds and exact storage, at the price of size and processing speed.

## Fixed Size Numbers

The smaller the type, the less space the data takes on disk and in memory, which is a big win! At the same time, the smaller the type, the narrower the range of values it can store!

For integer types, smaller types mean smaller ranges:

| type             | size      | range                                       |
|------------------|-----------|---------------------------------------------|
| smallint / int2  | 2 bytes   | -32768 to +32767                            |
| integer / int4   | 4 bytes   | -2147483648 to +2147483647                  |
| bigint / int8    | 8 bytes   | -9223372036854775808 to 9223372036854775807 |

Note that there are both SQL standard names for the types, and also PostgreSQL-specific names that are more precise about the internal storage size: an `int2` takes two bytes.

If you are storing numbers that are guaranteed to be within a bounded range, then using the smallest type that fits is a no-brainer. 

For floating point types, smaller types mean less precision in representation.

![IEEE Floating Point](double.png)

The bits that make up a floating point value in computer internals are used to represent the "sign", the fraction" and the "exponent" -- basically the parts of a number in scientific notation (eg -1.234E10) only in binary.

| type                       | size      | faction   | exponent   | 
|----------------------------|-----------|-----------|------------|
| real / float4              | 4 bytes   | 23 bits   | 8 bits     |
| double precision / float8  | 8 bytes   | 52 bits   | 11 bits    |

The real world precision of a floating point number depends on the magnitude of the exponent. If the exponent is one, then float4 data can be represented with perfect fidelity between the numbers of -2^23 and 2^23 (±8388608). That's a lot of fidelity!


## Variable Sized Numbers

Numbers are supposed to go on forever, but the two categories of types we have talked about have both finite ranges and finite precisions. In return, they offer fixed storage size and fast calculation.

What about those who need to potentially exactly represent any number and calculate with them without loss of precision? For those people there is `numeric`.

The `numeric` type gets its awesome power by being a "variable length type" (short-handed some times as "varlena"). Other varlena types include `text` / `varchar` (can be any length), `bytea` (can be any length) and the PostGIS `geometry` and `geography` types. 

The storage requirement for a `numeric` is two bytes for each group of four decimal digits, plus three to eight bytes overhead. So a minimum of five bytes, even for something as simple as "1". A number like 4 billion, which fits within 4 bytes as an `integer` takes 9 bytes as a `numeric`.

Computation also takes longer with numeric values, though it is still exceedingly fast. Let's run a division on and then sum up 10 million numbers:

```sql
-- Takes 5 seconds
SELECT sum(a::float8 / (a+1)::float8) 
  FROM generate_series(1, 10000000) a;

-- Takes 15 seconds
SELECT sum(a::numeric / (a+1)::numeric) 
  FROM generate_series(1, 10000000) a;
```


## Rounding and Representation

People have a very Dr. Jekyll and Mr. Hyde attitude towards precision and calculations. On the one hand, they can be pretty blasé about precision:

```sql
SELECT 3.0::float8 * (1.0/5.0);

 0.6000000000000001
```

"Oh, that's fine, I'll just round everything for display!" 

But inevitably the result finds its way into some other process and suddenly people get very angry:

```sql
SELECT 3.0::float8 * (1.0/5.0) <= 0.6;

 f
```

"Why is this **stupid database** returning the wrong answer for a **trivial math expression**!"

Harsh reactions about small deviations in calculations and properly rounded representations are particularly acute when the system is dealing with **money**. Exact math yields exact results.

```sql
SELECT 3.0::numeric * (1.0/5.0);

 0.600000000000000000000
```

For this reason the PostgreSQL documentation explicitly recommends: 

> If you require exact storage and calculations (**such as for monetary amounts**), use the numeric type.

The rounding behaviour of the `numeric` type is "away from zero", while the rounding behaviour of `double precision` and `float` are "towards the nearest even value".

```sql
SELECT x, 
  round(x::numeric) AS num_round,
  round(x::double precision) AS dbl_round
FROM generate_series(-3.5, 3.5, 1) as x;
```
```
  x   | num_round | dbl_round 
------+-----------+-----------
 -3.5 |        -4 |        -4
 -2.5 |        -3 |        -2
 -1.5 |        -2 |        -2
 -0.5 |        -1 |        -0
  0.5 |         1 |         0
  1.5 |         2 |         2
  2.5 |         3 |         2
  3.5 |         4 |         4
```

## At the Terminal Prompt

When working at the terminal prompt, it's hard to tell what you're going to get when you type "4.5", but we can see from the rounding behaviour that it's a numeric, because it rounds away from zero.

```sql
SELECT round(-4.5);

 -5
```

We have to be explicit about type in order to get a floating point number that rounds towards the even value.

```sql
SELECT round(-4.5::float8);

 -4
```

## Conclusions

* Choosing the right data type can have a big effect on storage overhead! The smallest types can use as little as 25% of the storage used by the largest, for the same values.
* Choosing the right data type can have a critical effect on correctness! Make sure you know how you are going to be calculating with these values, and what your organizational tolerance for imprecision is.
* Choosing the right data type can have an effect on performance! Exact math can be many times slower than ordinary calculation, so be prepared to pay a price when using exact types.


