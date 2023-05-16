DROP TABLE IF EXISTS cat_tags;
DROP TABLE IF EXISTS cats;
DROP TABLE IF EXISTS tags;

CREATE TABLE cats (
	cat_id serial primary key,
	cat_name text
);

CREATE TABLE cat_tags (
	cat_id integer,
	tag_id integer,
	unique(cat_id, tag_id)
);

CREATE TABLE tags (
	tag_id serial primary key,
	tag_name text not null,
	unique(tag_name)
);

--------------------------------------------------------------------------------

INSERT INTO cats (cat_name) 
WITH 
hon AS (
	SELECT * 
	FROM unnest(ARRAY['mr', 'ms', 'miss', 'doctor', 'frau', 'fraulein', 'missus', 'governer']) WITH ORDINALITY AS hon(n, i)
),
fn AS (
	SELECT * 
	FROM unnest(ARRAY['flopsy', 'mopsey', 'whisper', 'fluffer', 'tigger', 'softly']) WITH ORDINALITY AS fn(n, i)
),
mn AS (
	SELECT * 
	FROM unnest(ARRAY['biggles', 'wiggly', 'mossturn', 'leaflittle', 'flower', 'nonsuch']) WITH ORDINALITY AS mn(n, i)
),
ln AS (
	SELECT * 
	FROM unnest(ARRAY['smithe-higgens', 'maclarter', 'ipswich', 'essex-howe', 'glumfort', 'pigeod']) WITH ORDINALITY AS ln(n, i)
)
SELECT initcap(concat_ws(' ', hon.n, fn.n, mn.n, ln.n)) AS name 
FROM hon, fn, mn, ln, generate_series(1,1000)
ORDER BY random();


INSERT INTO tags (tag_name) VALUES 
	('soft'), ('cuddly'), ('brown'), ('red'), ('scratches'), ('hisses'), ('friendly'), ('aloof'), ('hungry'), ('birder'), ('mouser');


INSERT INTO cat_tags 
WITH tag_ids AS (
	SELECT DISTINCT tag_id FROM tags
),
tag_count AS (
	SELECT Count(*) AS c FROM tags 
)
SELECT cat_id, tag_id
FROM cats, tag_ids, tag_count
WHERE random() < 0.25;

CREATE INDEX cat_tags_x ON cat_tags (tag_id);

--------------------------------------------------------------------------------


EXPLAIN ANALYZE
SELECT tag_name 
FROM tags 
JOIN cat_tags USING (tag_id) 
WHERE cat_id = 444;


EXPLAIN ANALYZE
SELECT Count(*)
FROM cats 
JOIN cat_tags a ON (cats.cat_id = a.cat_id)
JOIN tags ta ON (a.tag_id = ta.tag_id)
WHERE ta.tag_name = 'brown';

EXPLAIN ANALYZE
SELECT Count(*)
FROM cats 
JOIN cat_tags a ON (cats.cat_id = a.cat_id)
JOIN tags ta ON (a.tag_id = ta.tag_id)
WHERE ta.tag_name IN ('brown', 'aloof');


EXPLAIN ANALYZE
SELECT Count(*)
FROM cats 
JOIN cat_tags a ON (cats.cat_id = a.cat_id)
JOIN cat_tags b ON (a.cat_id = b.cat_id)
JOIN tags ta ON (a.tag_id = ta.tag_id)
JOIN tags tb ON (b.tag_id = tb.tag_id)
WHERE ta.tag_name = 'brown'
AND tb.tag_name = 'aloof';

EXPLAIN ANALYZE
SELECT Count(*)
FROM cats 
JOIN cat_tags a ON (cats.cat_id = a.cat_id)
JOIN cat_tags b ON (a.cat_id = b.cat_id)
JOIN cat_tags c ON (b.cat_id = c.cat_id)
JOIN tags ta ON (a.tag_id = ta.tag_id)
JOIN tags tb ON (b.tag_id = tb.tag_id)
JOIN tags tc ON (c.tag_id = tc.tag_id)
WHERE ta.tag_name = 'brown'
AND tb.tag_name = 'aloof'
AND tc.tag_name = 'red';

EXPLAIN ANALYZE
SELECT Count(*)
FROM cats 
JOIN cat_tags a ON (cats.cat_id = a.cat_id)
JOIN cat_tags b ON (a.cat_id = b.cat_id)
JOIN cat_tags c ON (b.cat_id = c.cat_id)
JOIN cat_tags d ON (c.cat_id = d.cat_id)
JOIN tags ta ON (a.tag_id = ta.tag_id)
JOIN tags tb ON (b.tag_id = tb.tag_id)
JOIN tags tc ON (c.tag_id = tc.tag_id)
JOIN tags td ON (d.tag_id = td.tag_id)
WHERE ta.tag_name = 'brown'
AND tb.tag_name = 'aloof'
AND tc.tag_name = 'red'
AND td.tag_name = 'mouser';

--------------------------------------------------------------------------------

DROP TABLE IF EXISTS cats_array;
CREATE TABLE cats_array (
	cat_id serial primary key,
	cat_name text not null,
	cat_tags integer[]
);

INSERT INTO cats_array 
SELECT cat_id, cat_name, array_agg(tag_id) AS cat_tags
FROM cats 
JOIN cat_tags USING (cat_id)
GROUP BY cat_id, cat_name;

CREATE INDEX cats_array_x ON cats_array USING GIN (cat_tags);

EXPLAIN ANALYZE
WITH tags AS MATERIALIZED (
	SELECT array_agg(tag_id) AS tag_ids
	FROM tags
	WHERE tag_name IN ('red', 'brown', 'aloof', 'mouser')
	)
SELECT Count(*) -- cat_id, cat_tags, cat_name
FROM cats_array
CROSS JOIN tags
WHERE cat_tags @> tags.tag_ids;

EXPLAIN ANALYZE
SELECT Count(*) -- cat_id, cat_tags, cat_name
FROM cats_array
WHERE cat_tags @> ARRAY[3,4,8,11];

EXPLAIN ANALYZE
SELECT cat_name, cat_id, tag_name
FROM cats_array, tags
WHERE cat_id = 779
AND cats_array.cat_tags @> ARRAY[tags.tag_id];

EXPLAIN ANALYZE
WITH the_cat AS (
	SELECT cat_name, cat_id, unnest(cat_tags) AS tag_id
	FROM cats_array
	WHERE cat_id = 779
)
SELECT the_cat.*, tag_name
FROM the_cat JOIN tags USING (tag_id);

--------------------------------------------------------------------------------

DROP TABLE IF EXISTS cats_array_text;
CREATE TABLE cats_array_text (
	cat_id serial primary key,
	cat_name text not null,
	cat_tags text[]
);

INSERT INTO cats_array_text 
SELECT cat_id, cat_name, array_agg(tag_name) AS cat_tags
FROM cats 
JOIN cat_tags USING (cat_id)
JOIN tags USING (tag_id)
GROUP BY cat_id, cat_name;

CREATE INDEX cats_array_text_x ON cats_array_text USING GIN (cat_tags);

SELECT Count(*) -- cat_id, cat_tags, cat_name
FROM cats_array_text
WHERE cat_tags @> ARRAY['red', 'brown', 'aloof', 'mouser'];

