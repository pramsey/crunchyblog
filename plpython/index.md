
# Don't Trust, and Verify

PostgreSQL is a pretty unique database, in that it has multiple available server-side languages for writing server functions and triggers. Some of those languages are built-in, such as
[PL/PgSQL](https://www.postgresql.org/docs/current/plpgsql.html),
[PL/Python](https://www.postgresql.org/docs/current/plpython.html),
[PL/TCL](https://www.postgresql.org/docs/current/pltcl.html), and
[PL/Perl](https://www.postgresql.org/docs/current/plperl.html).

And (here is the amazing part) there are also lots of languages that are run-time add-ons, like
[PL/Java](https://tada.github.io/pljava/),
[PL/V8](https://github.com/plv8/plv8),
[PL/R](https://github.com/postgres-plr/plr),
[PL/Rust](https://github.com/tcdi/plrust), and
[PL/Go](https://gitlab.com/microo8/plgo).

Most database engines are happy to have one procedural language, PostgreSQL has dozens!


## Do you Trust Me?

Read into the introductions of these various languages, and you will quickly come across the concept of "trust". Is this language "trusted" or not? Some languages are, like PL/PgSQL. Some are not, like PL/Python. And some can be either, like PL/Perl.

A trusted language is one that you would feel confident in allowing any of your users to write a function with.  It plays entirely within the database access control system, and there is no way of breaking out of it. 

An un-trusted language is... not that. Functions in an un-trusted language have the potential to access capabilities outside the database itself. PL/Python is untrusted, and as we will see, it allows easy access to the filesystem of the database host. Functions written in C can access memory throughout the PostgreSQL system. 

Sounds scary! Fortunately, untrusted languages have a big safety net under them: by default, only the PostgreSQL super user is allowed to create functions in an untrusted language.


## Untrusted Functions and Permission

What can you do with untrusted functions? Things both terrible and amazing.

You will have to be a super user to try out these functions, which usually means connecting to the database as the `postgres` user.

```sql
CREATE EXTENSION plpython3u;

CREATE OR REPLACE FUNCTION df()
RETURNS text AS $$

    import subprocess

    try:
        output = subprocess.check_output(["df"], stderr=subprocess.STDOUT, shell=True, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        output = str(e.output)

    return output.strip()
    
$$ LANGUAGE 'plpython3u' VOLATILE;
```

This function returns the output of the `df` command, providing a summary of disk usage for the system the database is running on. 

If you connect as a lower privilege user, like the `application` user in Crunchy Bridge, you will find that you cannot create the `df()` function.

```
ERROR:  permission denied for language plpython3u
```

However you **will** find that you can **run** the function if the `postgres` user has already created it for you!

The `df()` function is a simple function with no parameters, and limited scope for abuse. But if you wanted to secure it, you would:

```sql
-- Remove the default grant of EXECUTE that all database users
-- have.
REVOKE EXECUTE ON FUNCTION df FROM public;

-- Remove any explicit grant of EXECUTE that the application user
-- might have
REVOKE EXECUTE ON FUNCTION df FROM application;
```

Now when you try to run the function as `application`, you will be denied.

```
ERROR:  permission denied for function df
```


## Cry Havoc! and Let Slip the Functions of War

Now that we can secure our functions, what kind of crazy things can we get up to with untrusted functions?

All of them! Check out this function, which will run any UNIX command you want and return the output back to you.

```sql
CREATE OR REPLACE FUNCTION shell(cmd text)
RETURNS text AS $$

    import subprocess

    try:
        output = subprocess.check_output([cmd], stderr=subprocess.STDOUT, shell=True, universal_newlines=True)
    except subprocess.CalledProcessError as e:
        output = str(e.output)

    return output.strip()
    
$$ LANGUAGE 'plpython3u' VOLATILE;
```

The commands are all run using the system user account the database runs as. Usually this is **also** named `postgres` just like the in-database super user, but it's important to note that the system user is distinct.

Unlike the database super user, the system user is usually deliberately created with relatively privilege and scope of access, precisely because the database super use is able to do what we are demonstrating here: run any command it wants on the system.

```sql
SELECT shell('ls');
```
```
        shell         
----------------------
 PG_VERSION          +
 base                +
 global              +
 logfile             +
 pg_commit_ts        +
 pg_dynshmem         +
 pg_hba.conf         +
 pg_ident.conf       +
 pg_logical          +
 ...
 pg_wal              +
 pg_xact             +
 postgresql.auto.conf+
 postgresql.conf     +
 postmaster.opts     +
 postmaster.pid

```

The database backend is running with the database cluster directory as the working directory, so running `ls` shows us the the files and directory that make up the cluster.

Can you hose your system very easily from here? Oh yes you can. These are the real files under your database, and if you remove them, your database will begin to fall apart. 

However, system access does not necessarily need to be used for **evil**, sometimes it can be used for good.


## Powering up Python

One of my favourite Python modules is the [nameparser](https://pypi.org/project/nameparser/) module, which is only marginally less cool than the [addressparser](https://pypi.org/project/addressparser/). Unfortunately, neither of them are part of a default Python install, so they are not available for me to access using PL/Python.

Can we change that? From inside the database? Yes we can.

Here is a function that checks for Python, adds the PIP package manager if necessary, and then installs the requested Python module. 

```sql
CREATE OR REPLACE FUNCTION install_python_module(name text)
RETURNS boolean AS $$

    import subprocess

    # 
    # Function to run a system command and return the 
    # resulting message string
    #
    errcode = 0
    def run_command(cmd):
        global errcode
        try:
            output = subprocess.check_output([cmd], stderr=subprocess.STDOUT, shell=True, universal_newlines=True)
        except subprocess.CalledProcessError as e:
            errcode = 1
            output = str(e.output)
        return output.strip()
    #
    # Do we even have python on the path?
    #
    plpy.notice(run_command("which python3"))
    if errcode > 0:
        return False
    #
    # Does python have the PIP package manager?
    #
    plpy.notice(run_command("python3 -m ensurepip --version"))
    if errcode > 0:
        plpy.notice(run_command("python3 -m ensurepip --default-pip"))
        if errcode > 0:
            return False 
    #
    # Make sure PIP is working
    #
    plpy.notice(run_command("python3 -m pip --version"))
    if errcode > 0:
        return False
    #
    # Install the requested module
    #
    plpy.notice(run_command("python3 -m pip install " + name))
    if errcode > 0:
        return False
    else:
        return True
    
$$ LANGUAGE 'plpython3u' VOLATILE;
```

This is a ridiculously invasive function to leave exposed, so we make sure that nobody is accidentally granted execution rights except the super user.

```sql
REVOKE EXECUTE ON FUNCTION install_python_module FROM public;
REVOKE EXECUTE ON FUNCTION install_python_module FROM application;
```

However, when run as super user, it does what we want.

```sql
SELECT install_python_module('nameparser');
```
```
NOTICE:  /usr/bin/python3
NOTICE:  pip 21.3.1
NOTICE:  pip 21.3.1 from /var/lib/pgsql/.local/lib/python3.9/site-packages/pip (python 3.9)
NOTICE:  Defaulting to user installation because normal site-packages is not writeable
Requirement already satisfied: nameparser in /var/lib/pgsql/.local/lib/python3.9/site-packages (1.1.3)
WARNING: You are using pip version 21.3.1; however, version 24.0 is available.
You should consider upgrading via the '/usr/bin/python3 -m pip install --upgrade pip' command.
 install_python_module 
-----------------------
 t
```

Now it's an easy thing to write a function that takes in a name string, and parses out all the parts.

```sql
CREATE OR REPLACE FUNCTION parse_name(name text)
RETURNS TABLE(title text, first text, middle text, last text, suffix text) 
AS $$

    import sys
    sys.path.append('/var/lib/pgsql/.local/lib/python3.9/site-packages/')

    from nameparser import HumanName
    name_obj = HumanName(name)
    return [(
        name_obj.title, 
        name_obj.first, 
        name_obj.middle, 
        name_obj.last, 
        name_obj.suffix
        )]

$$ LANGUAGE 'plpython3u' 
IMMUTABLE STRICT;

SELECT * FROM parse_name('john, mark lewis');
```
```
 title | first | middle | last | suffix 
-------+-------+--------+------+--------
       | mark  | lewis  | john | 
```

## Be Careful Out There

Remember, playing with your underlying system carries some non-trivial risks and complications!

* If your database moves to another server, the changes you made will not be there anymore.
* Replicas will not necessarily have the changes you have made.
* You have to be extremely careful to avoid privilege leakage, make sure untrusted functions run by ordinary users do not have escape hatches.
* Use SQL permissions controls liberally to ensure only the users you want to run functions have the access to run functions.





