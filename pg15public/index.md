# Strict public in PostgreSQL 15

The end is nigh! PostgreSQL has substantially tightened restrictions on the use of the "public" schema.

For developers and experimenters, one of the long-time joys of PostgreSQL has been the free-and-easy security policy that PostgreSQL has shipped with for the "public" schema.

* "public" is in the default search_path, so you can always find things in it; and,
* any user can create new objects in "public"; so,
* "just throw it in public!" has been an easy collaboration trick.

However, for anyone using a database for more than 15 minutes, the implications of "loosy goosey public" are pretty clear:

* "public" ends up as a garbage pile of temporary and long-abandoned tables,
* "public" is a quiet security hole, as it tends to stay on the default search_path, sometimes in front of other schemas.

## The Wild West

Setting up a fresh database and experimenting should be fun! 

The easiest thing is to just give everybody the "postgres" super-user password. Infinite privileges and complete transparency for all! 

However, this approach is limited to the earliest days of experimentation. You will need something more.

## Separating User Data

Eventually you will have production data, and limited access to that data, but also temporary data and experimental data and users. How to easily segment that?

PostgreSQL makes it very easy to keep user data separate, because the default `search_path` starts with a "user schema":

```
postgres=> show search_path;

   search_path   
-----------------
 "$user", public
```

* First, make a basic login user. 

  ```
  -- as 'postgres'
  CREATE USER luser1;
  ```

* Then, make a "user schema" for that user.

  ```
  -- as 'postgres'
  CREATE SCHEMA luser1 WITH AUTHORIZATION luser1;
  ```

* Now, when `luser1` creates a table without specifying the schema, the table will be created in the first schema on their `search_path`. That schema is `$user` which expands to their user name, and there is now a schema that matches their user name.

  ```
  -- as 'luser1'
  CREATE TABLE my_test_data (id integer);
  ```

  ```
              List of relations
     Schema |     Name     | Type  | Owner 
    --------+--------------+-------+-------
    luser1  | my_test_data | table | luser1
  ```

If you simply **create a user schema for each new login user you create**, you can neatly separate user data from other data, as each user will end up creating new tables and object inside their user schema by default.

## Sharing User Data

Even back in PostgreSQL 14, in order to share data between user-owned tables in the `public` schema, it was necessary to `GRANT SELECT` on those tables to the roles you wanted to access them.

With a "user schema" setup, the same principle applies, except you also have to `GRANT USAGE` on your user schema to any roles you want to access your table.

  ```
  -- as 'luser1'
  GRANT USAGE ON SCHEMA luser1 TO luser2;
  GRANT SELECT ON my_test_data TO luser2;
  ```

## Sharing with Roles

Rather than individually granting `USAGE` and `SELECT` to every user who might want to work with their data, a user can grant to an entire class of users. If the database administrator sets of up role, that includes all the relevant users:

```
-- as 'postgres'
CREATE USER luser1 LOGIN;
CREATE USER luser2 LOGIN;
CREATE ROLE lusers;
GRANT lusers TO luser1, luser2;

-- as 'luser1'
GRANT USAGE ON SCHEMA luser1 TO lusers;
GRANT SELECT ON my_test_data TO lusers;
```

Now as new accounts are added to the `lusers` role, they will automagically be able to access the tables that `luser1` has shared.

## Conclusions

* PostgreSQL 15 removes the global write privilege from the `public` schema!
* But, it's **really easy** to provide the same level of collaboration to users, by making use of user schemas, and role-based access.

