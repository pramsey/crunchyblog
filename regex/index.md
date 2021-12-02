# Tantric Text with Regular Expressions in PostgreSQL

Regular expressions (also known as "regex") get a bad rap. They're impossible to read, they're inconsistently implemented in different platforms, they can be slow to execute. All of these things may be true, and yet: if you don't know regular expressions yet, you are missing a key skill for data manipulation that you will use throughout your career.

Regular expressions show up in any tool that needs to manipulate string information: scripting languages, text editors, and of course, **databases**.

PostgreSQL includes a [full regular expression engine](https://www.postgresql.org/docs/current/functions-matching.html), so the pull power of regex is available for a number of use cases.

## Quick Regex Refresher

If you don't know regex at all, maybe run through a [tutorial](https://www.regular-expressions.info/tutorial.html) to get a feel for the basics. 

Here's some of the standard pieces of regex, and a few example expressions we'll use in our queries below.

* `.` matches any character
* `\s` matches "empty space" characters like space and tab
* `\S` is the opposite of `\s` so it matches anything that **isn't** a space
* `\d` matches any number character and `\D` does the opposite
* `\w` matches any "word" caracter (a-z, 0-9) and `\W` does the opposite
* `^` binds the pattern to the start of the input
* `$` binds the pattern to the end of the input
* `()` mark out portions of the pattern as "matches" to be made available for further processing
* `*` matches 0-N repetitions of the character preceding it
* `+` matches 1-N repetitions of the character preceding it
* `{N}` matches N repetitions of the character preceding it

So putting all the above together

* `^A+` would match strings that **start** with one-or-more 'A' characters
* `\d+` would match any combination of one-or-more digits in order
* `^\S` would match any string that did **not** start with white space


## True/False Regex Matching with the ~ Operator

The simplest use of regex in PostgreSQL is the `~` operator, and its cousin the `~*` operator. 

* `value ~ regex` tests the value on the left against the regex on the right and returns true if the regex can match within the value. Note that the regex does not have to fully match the whole value, it just has to match a part.
* `value ~* regex` does exactly the same thing, but **case insensitively**.

For example, does an address string contain something like "Avenue"?

```sql
SELECT '100 Byron Avenue' ~ ' Avenue$'
```

Or, does a string start with the letter "T", any case?

```sql
SELECT 'theorem' ~* '^T'
```

Or, more complexly, does a string contain digits to form a North American phone number (3 for area code, 3 for exchange, 4 for local)?

```sql
SELECT '(416) 555-1212' ~* '^\D*\d{3}\D*\d{3}\D*\d{4}\D*$'
```

In words, the regex above is:

* "Starting from the front of the string" (^)
* "Any amount of non-digit garbage" (\D*)
* "then three digits" (\d{3})
* "then any amount of non-digit garbage in between" (\D*)
* "then three digits" (\d{3})
* "then any amount of non-digit garbage in between" (\D*)
* "then three digits" (\d{4})
* "then any amount of non-digit garbage in between" (\D*)
* "all the way to the end of the string." ($)


## Extracting Text with Regex

When extracting text from a string, it's tempting to reach directly for the power of `regexp_match()` but if you are only interested in extracting one piece, it might be easier to use a special form of the `substring()` function.

Here we extract the last four digits of our "phone number" input.

```sql
SELECT substring('(416) 555-1212' from '\d{4}');
```

If you need to provide some anchor text in the pattern, you can still extract just the parts you care about by using the "()" to delineate that part.

```sql
SELECT substring('(416) 555-1212' from '\-(\d{4})');
```


## Substitutions with Regex

The `regexp_replace(value, regex, replacement, flags)` function is a relatively simple function, taking in a value to alter, a pattern to search for, and a replacement string to use whereever the value is found.

For example, to normalize a phone string by stripping out all non-digits:

```sql
SELECT regexp_replace('(416) 555-1212', '\D', '');

 regexp_replace
----------------
 416) 555-1212
```

Hm, this isn't what we wanted, really! The problem is that by default, `regexp_replace()` only operates on the first match found. We want it to operate on every match, so we need the "g" (stands for "global") option.

```
SELECT regexp_replace('(416) 555-1212', '\D', 'g');

 regexp_replace
----------------
 4165551212
```


## Regex Flags

The `regexp_replace()` and `regexp_match()` functions both take in "flags" as an optional final argument. There are a lot of flags, but the ones you are most likely to use are.

* "g" to allow "global" matching, multiple matches
* "i" to allow case-insensitive matching
* "n" to avoid crossing newlines when matching patterns


## Extracting More Text with Regex

As we saw above, it is possible to extract substrings from inputs using the "()" match delimiters in the regex pattern. When you want to extract more-than-one substring, it is time to reach for the `regexp_match()` function.

```sql
SELECT regexp_match('(416) 555-1212', '^\D*(\d{3})\D*(\d{3})\D*(\d{4})\D*$');

  regexp_match  
----------------
 {416,555,1212}
```

This is the same "phone number" pattern as we saw earlier, but this time each component of the number has been surrounded by a "()" match delimiter.

Because the result of `regexp_match()` can potentially contain more than one match result, the return value is an array of text. 

You can pull particular pieces of the match out using the usual array index notation.

```sql
WITH regex AS (
  SELECT regexp_match('(416) 555-1212',  
                      '^\D*(\d{3})\D*(\d{3})\D*(\d{4})\D*$') AS match
  )
SELECT match[1] AS area_code, 
       match[2] AS exchange,
       match[3] AS local
FROM regex;

 area_code | exchange | local 
-----------+----------+-------
 416       | 555      | 1212
```


## Conclusion

* PostgreSQL has a complete, and extremely tunable [regular expression engine](https://www.postgresql.org/docs/current/functions-matching.html) built right in.
* Regular expressions are a more flexible, often high performance alternative to ugly combinations of case statements and substrings.
* Everything you learn about PostgreSQL regular expressions is transferable to other programming environments. Regex is everywhere.

