# Deep Dive into Container Apps

We recently launched [Container Apps](https://docs.crunchybridge.com/container-apps/) for [Crunchy Bridge](crunchybridge.com), a new way to spin up database applications in the cloud, and a question many folks have is: **how does this work, exactly**?


## podman

Underneath the covers, we are taking advantage of the fact that every database in Crunchy Bridge has its own virtual machine, and there's no rule that the only thing that can run on a database server is database software. 

As long as you have sufficient resources, you can run lots of things alongside a database, and some of them are very useful! Monitoring software, web user interfaces, and application middleware of all sorts.

The most generic way to open that capability up to our users was to give them access to a container runner, in our case [podman](https://podman.io/). If you can make it into a container, you can run it in podman. And if you can run it in podman, you can run it as a Crunchy [Container App](https://docs.crunchybridge.com/container-apps/).

![architecture](img/architecture.png)


## pgpodman Extension

To access the goodness of podman from inside the database, we've wrapped it in a database extension that exposes a few key functions for [managing containers](https://docs.crunchybridge.com/container-apps/getting-started/#more-with-pgpodman).

* `SELECT run_container()` - Start a container within your database
* `SELECT list_containers(show_all boolean)` - List all containers and status. By default assumes a false flag. With show_all parameter as false it will list only running containers, true will list all containers both running and stopped.
* `SELECT stop_container(<container_id>)` - Stop a running container, but leaves it on the filesystem.
* `SELECT container_status(<container_id>)` - Show status of a container.
* `SELECT container_logs(<container_id>)` - Show the logs from a container.
* `SELECT remove_container(<container_id>)` - Remove a stopped container from the container list.

The first step of working with container apps is installing the `pgpodman` extension in your cluster, in your `postgres` database. You will have to be superuser (`postgres`) to install the extension.

![creds](img/creds.png)

```sql
CREATE EXTENSION pgpodman;
```


## Container Apps

To make it easier to get started, we have a "Container Apps" tab right in the Crunchy Bridge UI.

![header](img/header.png)

Select the tab, and choose "[PgWeb](http://sosedoff.github.io/pgweb/)" from the dropdown of "Quickstart" apps. These are apps we have provided example start-up SQL for. 

![container](img/container.png)

For [PgWeb](http://sosedoff.github.io/pgweb/) the start-up SQL looks like this:

```sql
SELECT run_container('-dt -p 5437:8081/tcp -e DATABASE_URL="postgres://application:xxxxxxxxxxxx@p.yyyyyyyyyyyyyyyy.db.postgresbridge.com:5432/postgres" docker.io/sosedoff/pgweb');
```

There's some magic strings in there, let's talk about them!

* `-dt` is required every time, it means "detach" is it is what allows your container to run in the background while Postgres keeps on doing its thing.
* `-p 5437:8081/tcp` is a port mapping option, which maps port 5437 from the database host server to port 8081 inside the container. Only ports 5433-5442 are opened to the internet, so port mapping is required.
* `-e DATABASE_URL` sets an environment variable to be passed to the container. The [PgWeb](http://sosedoff.github.io/pgweb/) reads the `DATABASE_URL` variable to determine what database to connect the web application to.
* `docker.io/sosedoff/pgweb` is the container image to run, in this case published at the DockerHub repository.


## Trouble Shooting

With so many parameters to fiddle with, occasionally you will get things wrong, so it's important to know how to trouble shoot. Let's intentionally start [PgWeb](http://sosedoff.github.io/pgweb/) with a bad `DATABASE_URL` and see what happens.

```sql
SELECT run_container('-dt -p 5437:8081/tcp -e DATABASE_URL="postgres://application:xxxxxxxxxxxx@p.yyyyyyyyyyyyyyyy.db.postgresbridge.com:5432/WRONG_DATABASE" docker.io/sosedoff/pgweb');
```

```
 run_container 
---------------
 e750887cf920
```

We get a **container_id** back, which is odd since we fed it a connection string with `WRONG_DATABASE` in it!

Check the list of running containers:
```sql
SELECT list_containers();
```

```
                                 list_containers                                 
---------------------------------------------------------------------------------
 CONTAINER ID  IMAGE       COMMAND     CREATED     STATUS      PORTS       NAMES
```

Aha! There's nothing there! But how do we trouble shoot the problem?

The `list_containers()` function takes one parameter, a `show_all` boolean, so set that to true:

```sql
SELECT list_containers(true);
```

```
 CONTAINER ID  IMAGE                            COMMAND               CREATED         STATUS                     PORTS                   NAMES         +
 e750887cf920  docker.io/sosedoff/pgweb:latest  /usr/bin/pgweb --...  20 seconds ago  Exited (1) 19 seconds ago  0.0.0.0:5437->8081/tcp  nervous_swartz
```

So the container isn't running any more. We can get an idea of what went wrong by looking at the logs for the (now stopped) container.

```sql
SELECT container_logs('e750887cf920');
```

```
 Pgweb v0.11.11 (git: db2a7a8aa5bc449e4efa78cada9c76c3fe33bc39) (go: go1.17.6) (build time: 2022-03-30T04:36:12Z)\r+
 Connecting to server...\r                                                                                         +
 Error: pq: database "wrong_database" does not exist
 ```

Aha! So [PgWeb](http://sosedoff.github.io/pgweb/) tried and failed to connect to our bad database name, and then exited.

## Up and Running

Let's clean up, and then run again.

```sql
SELECT remove_container('e750887cf920');

SELECT run_container('-dt -p 5437:8081/tcp -e DATABASE_URL="postgres://application:xxxxxxxxxxxx@p.yyyyyyyyyyyyyyyy.db.postgresbridge.com:5432/postgres" docker.io/sosedoff/pgweb');
```

```
 run_container 
---------------
 3905a7b91124
```

Now the log for the container shows it up and running.

```sql
SELECT container_logs('3905a7b91124');
```

```
 Pgweb v0.11.11 (git: db2a7a8aa5bc449e4efa78cada9c76c3fe33bc39) (go: go1.17.6) (build time: 2022-03-30T04:36:12Z)
 Connecting to server...
 Connected to PostgreSQL 14.3
 Checking database objects...
 Starting server...
 To view database open http://0.0.0.0:8081/ in browser
```

![pgweb](img/pgweb.png)


## Conclusions

* Container Apps can be used to spin up any standard container (though running database-related containers makes more sense).
* Containers run on the same virtual machine as the database.
* Logs and status functions are available to trouble shoot problems with containers.