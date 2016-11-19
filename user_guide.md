Method5 User Guide
==================

Method5 is a remote execution program for Oracle databases. It lets administrators easily run SQL statements quickly and securely on hundreds of databases.

Running statements simultaneously on all your databases can be as easy as this:  `select * from table(m5('select * from dual'));`  Statements are processed in parallel and will start returning relational data in seconds.  The program works in any SQL IDE and users do not need to worry about agents, plugins, or configuration files.

Some users will only need the `select * from table(m5('...'));` syntax.  For more advanced users, this guide explains all available Method5 features.  These features can be used to precisely control what is run, how it's run, and where it's run.


Why Do You Need Method5?
------------------------

Oracle DBAs have tools to automate pre-defined tasks, like database patching and application deployments.  But those tool are too complex and slow to help with unexpected operational problems that take up so much time.  When DBAs solve a problem they rarely spend the time to find, fix, and prevent the problem from happening on other databases.  SQL, PL/SQL, and the relational model can make the solution easy, but the solution is still stuck inside a single database.  Nobody has time to connect to every database and check for a problem that may not happen again.

The ideal solution is to make it trivial to query and change all databases simultaneously.  Dynamic SQL is sometimes classified as Method 1, 2, 3, or 4, depending on how dynamic it is.  DBAs need a new type of dynamic SQL, a Method 5, that allows them to specify the targets as easily as they specify the code.  A new syntax that allows any statement to run anywhere, in any SQL tool.  Something like the Oracle 12c `CONTAINERS` clause, but much more powerful.  Existing tools have failed to transform the way DBAs work because those tools are slow, insecure, and not relational.

With Method5 you will be able to perform some administration tasks orders of magnitude faster.


Summary of Features
-------------------

Method5 can be called as a function, `M5`, or a procedure, `M5_PROC`.  Each run creates three tables  to hold the results, metadata, and errors.  Those tables can be referenced using the views M5_RESULTS, M5_METADATA, and M5_ERRORS.

Method5 parameters (the function version only supports the first two parameters):

* P_CODE (required) - Any SQL or PL/SQL statement.
* P_TARGETS (optional, defaults to all databases) - Can be either a comma-separated list (of database names, hosts, lifecycles, or lines of business) or a query that returns database names.
* P_TABLE_NAME (optional, defaults to auto-generated name) - The base name for the results, _META, and _ERR tables.
* P_TABLE_EXISTS_ACTION (optional, defaults to ERROR) - One of ERROR, APPEND, DELETE, or DROP.
* P_ASYNCHRONOUS (optional, defaults to TRUE) - Return right away or wait for all results.

For ad hoc statements you can use the `M5_%` database links created in your schema.  There are also some nightly-generated tables with useful data, such as M5_DBA_USERS and M5_V$PARAMETER.

Read below for more thorough details on these features.


Function or Procedure
---------------------

Method5 can be called as either a function or a procedure.  The function is `M5`, and the procedure is `M5_PROC`.

The function `M5` is the simplest method, and can start displaying values in less than a second.  Wrap any statement in this text: `select * from table(m5(q'[  ...  ]'));`.  The function accepts two parameters, `P_CODE` and `P_TARGETS`, which are explained more thoroughly later.

	SQL> select * from table(m5(q'[  select 'Hello, World!' hello_world from dual  ]'));
	
	DATABASE_NAME                  HELLO_WORLD
	------------------------------ -------------
	SOMEDB01                       Hello, World!
	SOMEDB02                       Hello, World!
	...

The procedure `M5_PROC` makes it possible to more programmatically run queries and save results.

	begin
		m5_proc(
			p_code =>                'select * from dual',
			p_targets =>             'pqdwdv01',
			p_table_name =>          'my_results',
			p_table_exists_action => 'DROP',
			p_asynchronous =>        false
		);
	end;
	/

	SQL> select * from my_results;
	
	DATABASE_NAME                  DUMMY
	------------------------------ -----
	SOMEDB01                       X
	SOMEDB02                       X
	...


Simplify Strings with Alternative Quoting Mechanism
---------------------------------------------------

Use the `q'[` syntax to embed SQL statements without needing to escape quotation marks.  In this alternative quoting mechanism, strings begin with `q'[` and end with `]'`.  You can also use `<>`, `()`, or `{}`.  Or if you use another character, simply repeat the character at the end.  For example, `q'! It's not necessary to add extra quotation marks now.!'`.


Where is the data stored?
-------------------------

Every Method5 execution stores data in three tables - results, metadata, and errors.

The result table contains either the results of the query, the DBMS_OUTPUT for a PL/SQL block, or a feedback message for other statement types.  Every row also contains the database name.  The table name can be specified with the parameter `p_table_name`.  If that parameter is left blank, a name will be automatically chosen.

The metadata table contains one row for each execution.  It contains the date started, is the process finished yet, the count of targets expected and completed and with errors, and the code and targets used.  This table has the same name as the results table but with the suffix `_meta`.

The errors table contains any Oracle errors generated during the execution, along with the database name.  With a large enough number of databases it's not unusual for at least one of them to be unavailable because of maintenance or an unexpected error.  Tracking errors lets you ignore the troublesome databases and deal with them later.  This table has the same name as the results table but with the suffix `_err`.

Serious errors during a run may make the metadata counts partially incorrect.  For example, if a database crashes in the middle of processing, the error may not be counted.  It's unlikely, but possible, for `IS_COMPLETE` to be `No` even though there are no more jobs running.  When that happens the column `TARGETS_EXPECTED` will not be equal to the sum of `TARGETS_COMPLETED` and `TARGETS_WITH_ERRORS`.

(One unexpected benefit of Method5 is that constantly polling all databases will make you keenly aware of which ones are unreliable.  Some databases are just full of gremlins.)

To simplify queries, Method5 always creates 3 views in your schema that refer to the latest tables.  Instead of worrying about the table names just run these statements:

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;


Parameter: P_CODE (1st parameter, required)
-------------------------------------------

`P_CODE` can be any single SQL or PL/SQL statement.  `SELECT`, `INSERT`, `ALTER USER`, `BEGIN ...`, etc.

For `SELECT`, the tables in the statement must exist on the server running the jobs.  This is necessary in order to get the metadata for the results.  In practice this isn't a big deal because most of the queries will be against the data dictionary, which is very uniform across versions and editions.

PL/SQL blocks are convenient if you want to run multiple statements and package them in one call.  You can use DBMS_OUTPUT.PUT_LINE to display information.

	begin
		m5_proc(q'[  begin dbms_output.put_line('Hello, World!'); end;  ]', 'pqdwdv01');
	end;
	/

	SQL> select * from m5_results;

	DATABASE_NAME                  RESULT
	------------------------------ -------------
	SOMEDB01                       Hello, World!
	...

DML, DDL, and other statement types will return a message similar to their SQL*Plus feedback message.

	SQL> select * from table(m5('alter user jheller profile some_profile'));

	DATABASE_NAME                  RESULT
	------------------------------ -------------
	SOMEDB01                       User altered.
	...


Parameter: P_TARGETS (2nd parameter, optional)
----------------------------------------------

`P_TARGETS` identifies which databases to run the code on.  If it is not set it will default to run against all configured databases.  This parameter can either be a SELECT statement or a comma-separated list.

If the value is a SELECT statement it must return only one column that contains the database names.  You may want to use the table M5_DATABASE to find relevant database names.

	select * from table(m5(
		q'[ select * from dual; ]',
		q'[
			select database_name
			from m5_database
			where lifecycle_status = 'QA'
				and lower(database_name) like 'p%'
		]'
	));

	DATABASE_NAME                  D
	------------------------------ -
	porcl123                       X
	porcl234                       X
	...

If the value is not a SELECT statement then it will be evaluated as a comma-separated list of values.  The values will match any database that shares the same name, host name, line of business, lifecycle status, or cluster name.  Those columns are all configured in M5_DATABASE, and may be derived from Oracle Enterprise Manager.

The value may also use the Oracle pattern matching syntax, `%` and `_`.

For example, if you want all development databases, as well as ones on the ACME contract (line of business), and some other custom databases:

	p_targets => 'dev,acme,coyote%'

The value may also use an optional Target Group, which is identified by starting with a `$`.  Target Groups are pre-defined queries so complicated logic doesn't need to be repeated.

For example, it can be tricky to query only one database per ASM instance.  Once you set up the target group with the name `ASM`, it can be used like this:

	select * from table(m5('select * from v$asm_disk', '$asm'));

See `administer_method5.md` for how to setup a Target Group.


Parameter: P_TABLE_NAME (3rd parameter, optional)
-------------------------------------------------

`P_TABLE_NAME` specifies the table name to store the results.  Tables with the suffixes `_meta` and `_err` will also be created to store the metadata and errors.

If this parameter is not specified then a sequence will be used to generate a unique name.  If the sequence is used, all but the last of those temporary tables will be dropped by a nightly job.


Parameter: P_TABLE_EXISTS_ACTION (4th parameter, optional)
----------------------------------------------------------

One of these values:

* ERROR - (DEFAULT) Raise an error if the table already exists.  This doesn't apply to functions, they always have a unique name.
* APPEND - Add new rows to the existing table.
* DELETE - Delete existing rows and then add new rows.
* DROP - Drop existing tables and re-create them for new results.


Parameter: P_ASYNCHRONOUS (5th parameter, optional)
---------------------------------------------------

By default, `P_ASYNCHRONOUS` is set to TRUE, which means the procedure will return immediately even if the results are not finished yet.

This lets you examine some of the results before a slow database is finished processing.


M5_ Links
---------

Method5 automatically creates database links in your schema to all databases that it connects to.  The links are named like `M5_` plus the database name.  Those links can be useful for ad hoc statements.


Global Data Dictionary
----------------------

Method5 automatically gathers data for some common data dictionary tables.  These tables can be useful for rapid troubleshooting.  For example, if you're not sure which database contains a schema you can quickly query `select * from m5_dba_users` to look at the users for all databases.

* M5_DBA_USERS
* M5_V$PARAMETER
* M5_DBA_TAB_PRIVS, M5_DBA_ROLE_PRIVS, M5_DBA_SYS_PRIVS
* M5_USER$

You can add your own easily by following the examples in `code/install_method5_global_data_dictionary.sql`.


Creating services for non-DBA users
-----------------------------------

Method5 goes to great lengths to protect access and ensure that only configured DBAs can use it.  But sometimes it may be useful to provide other users with a limited, carefully controlled access to Method5.

Read-only access to specific query results is fairly straight-forward.  Create a job with DBMS_SCHEDULER to gather results into a specific table, then grant access on that table to roles or users.  The job should probably set `P_TABLE_EXISTS_ACTION` to either `DELETE` or `APPEND`, to ensure that the privileges are not dropped with the object.

DDL and write access is more complicated.  It requires creating a scheduled job to pass authentication and authorization checks, a custom procedure that alters the JOB_ACTION based on input from a user, running the job with `use_current_session => false`, and then waiting and checking the _META table for it to complete.  See the script "Lock User Everywhere.sql" for an example.  *TODO - add script.*

Keep in mind that scheduled jobs must be owned by a configured DBA.  Method5 always runs as an individual user, never a generic account.  If that DBA's account is de-activated, their jobs must be dropped and re-created by an active DBA.


Security
--------

Method5 is a great tool to help comply with security policies.  It enables rapid scanning and configuration on a large number of databases.  It allows security jobs to be stored and managed in a single location instead of scattered across hundreds of databases and crontabs.

It's important that Method5 itself does not create any security issues.  To keep your systems secure, Method5 includes the below features by default.  This list might be helpful if you need to demonstrate to an auditor why Method5 is safe.

1. **No password sharing.**  Although Method5 creates a schema, the password for that schema is never displayed or known by anyone.
2. **Password hash management.**  Method5 makes it easy to periodically change the password hashes and removes the insecure DES password hashes when possible.
3. **Prevent direct logons.**  Authorized users can only connect through the Method5 application.  A trigger prevents the Method5 schema from directly connecting.  This means that even if somebody hacks into one of your databases, steals a password hash, and decrypts it, there's not much they can do with it.
4. **Auditing.**  Auditing is performed on the management and target databases, through the database audit trail and the application.  You can always figure out who did what, when.
5. **Multi-step authentication.**  Authentication requires an existing database account, as well as the proper role, profile, account name, account status, and operating system username.
6. **Intrusion detection.**  Un-authorized access attempts will send an email to an administrator.  Even in the worst-case scenario, where someone gains root access to your central management host, they would likely generate an alert.
7. **Open Source.**  All code is available for inspection.  Method5 does not rely on security through obscurity.


Possible Uses
-------------

Method5 was built to help database administrators change their approach to solving database problems.

Many good DBAs spend most of their time fighting fires one-database-at-a-time.  We say to ourselves, "it probably hasn't happened on other databases and it probably won't happen again".  When what we really mean is "it's not worth the effort to check every other database".

With Method5 that extra effort is trivial and there are no more excuses to avoid root cause analysis.  Every time you encounter a problem, ask yourself if you can find it and prevent it on all other databases.

Here are a few examples of ways that Method5 is already used:

* Account Management - Lock, unlock, create accounts, etc.
* Root Cause Analysis - Track down rare problems by checking for them on all databases.
* Space Management - Save a few gigabytes here and there and it can add up to terabytes.
* Security Rules - Enforce security rules more easily by keeping databases consistent, such as through standard profiles.
* Performance Tuning - Check the queries running on all databases on the same host.
* Environment Comparisons - Compare parameters or objects across all databases at the same time.
* Global Data Dictionary - Store common data used for rapid troubleshooting, such as a list of users.
* Preventive Maintenance - Save common diagnostic steps and periodically re-run them against all databases.
* Global Jobs - Run jobs from a single database instead of managing hundreds of crontabs or database jobs.
* Monitoring - Check database status with simple SQL statements.

There are a few DBA tasks that Method5 cannot fully automate.  However, Method5 can still assist with these tasks.

* Upgrading and Patching - These tasks need to be handled by a specialized tool; or they may be too fragile to automate at all.  Method5 can still help you verify the database state after patches and upgrades.
* Host and SYSDBA actions - Activities like installing software and starting a database won't work since Method5 only exists inside a database.  Method5 can still be used to check the status afterwards.
* Deployments - Developers will want to use their own specialized tools for this.  But Method5 can help harmonize environments and can compare all objects, in all databases, in a single view.

At least one DBA on your team should use Method5 if your organization is serious about database automation.
