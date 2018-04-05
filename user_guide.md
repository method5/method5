Method5 User Guide
==================

**Contents**

1. [Quick Start](#quick_start)
2. [Introduction to Method5](#introduction)
3. [Function or Procedure](#function_or_procedure)
4. [Alternative Quoting Mechanism](#alternative_quoting_mechanism)
5. [Where is the Data Stored?](#where_is_the_data_stored)
6. [Parameter: P_CODE](#parameter_p_code)
7. [Parameter: P_TARGETS](#parameter_p_targets)
8. [Parameter: P_TABLE_NAME](#parameter_p_table_name)
9. [Parameter: P_TABLE_EXISTS_ACTION](#parameter_p_table_exists_action)
10. [Parameter: P_ASYNCHRONOUS](#parameter_p_asynchronous)
11. [Parameter: P_RUN_AS_SYS](#parameter_p_run_as_sys)
12. [M5 Links](#m5_links)
13. [Global Data Dictionary](#global_data_dictionary)
14. [Version Star - Column Differences Between Versions](#version_star)
15. [DBMS_XMLGEN.GETXML - Table Differences Between Versions](#dbms_xmlgen.getxml)
16. [Services for non-Method5 users](#services_for_non_users)
17. [Job Timeout](#job_timeout)
18. [LONG to CLOB conversion](#long_to_clob_conversion)
19. [Account Maintenance with M5_SYNCH_USER](#m5_synch_user)
20. [Administrator Daily Status Email](#administrator_daily_status_email)
21. [Security and User Configuration](#security)
22. [Possible Uses](#possible_uses)


<a name="quick_start"/>

## Quick Start

Method5 can be called as a function, `M5`, or a procedure, `M5_PROC`.  Each run creates three tables to hold the results, metadata, and errors.  Those tables can be referenced using the views M5_RESULTS, M5_METADATA, and M5_ERRORS.  DBMS_OUTPUT will also display some useful information about the run.

For example, to run as a function and get the results immediately:

	select * from table(m5(p_code => 'select * from dual', p_targets => 'database1'));

Or to run as a procedure and get the results asynchronously:

	--Start running the command on many databases.
	begin
		m5_proc(
			p_code => 'alter system set job_queue_processes = 1000',
			p_targets => 'dev,qa'
		);
	end;
	/
	
	--View results, metadata, and errors.  It may take a while for all data to appear.
	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;

Method5 parameters (the function version supports P_CODE, P_TARGETS, and P_RUN_AS_SYS):
* P_CODE (required) - Any SQL statement, PL/SQL statement, or Linux/Unix shell script.
* P_TARGETS (optional, default is configured per user) - Can be either a comma-separated list (of database names, hosts, lifecycles, or lines of business), a query that returns database names, or a pre-defined target group.
* P_TABLE_NAME (optional, defaults to auto-generated name) - The base name for the results, _META, and _ERR tables.
* P_TABLE_EXISTS_ACTION (optional, defaults to ERROR) - One of ERROR, APPEND, DELETE, or DROP.
* P_ASYNCHRONOUS (optional, defaults to TRUE) - Return right away or wait for all results.
* P_RUN_AS_SYS (optional, defaults to FALSE) - Run the command as SYS.

For ad hoc statements you can use the `M5_%` database links created in your schema.

The global data dictionary contains several useful tables that are gathered every night: M5_DBA_USERS, M5_V$PARAMETER, M5_DBA_ROLE_PRIVS, M5_DBA_SYS_PRIVS, M5_DBA_TAB_PRIVS.

Some useful tables and views in the Method5 schema are: M5_DATABASE (list of all databases), M5_AUDIT (history of runs), and M5_USER/M5_ROLE/M5_ROLE_PRIV/M5_USER_ROLE/M5_PRIV_VW (user configuration).

There are several pre-built solutions in the examples directory, such as multi-database schema comparisons and synchronizing accounts.

Read below for more thorough details on these features.


<a name="introduction"/>

## Introduction to Method5

Method5 extends Oracle SQL to allow parallel remote execution.  It lets users easily run SQL statements, PL/SQL blocks, and Unix shell commands quickly and securely on hundreds of databases.

Method5 is ideal for supporting a large number of Oracle databases.  Just as code should not update tables one-row-at-a-time, administration should not be done one-database-at-a-time.  Method5 is the only *relational* remote execution program and helps you perform some tasks orders of magnitude faster.

Running statements simultaneously on all your databases can be as easy as this:  `select * from table(m5('select * from dual'));`  Statements are processed in parallel and will start returning relational data in seconds.  The program works in any SQL IDE and users do not need to worry about agents, plugins, or configuration files.

Some users will only need the `select * from table(m5('...'));` syntax.  For more advanced users, this guide explains all Method5 features.  These features can precisely control what is run, how it's run, and where it's run.


<a name="function_or_procedure"/>

## Function or Procedure

Method5 can be called as either a function or a procedure.  The function is `M5`, and the procedure is `M5_PROC`.

The function `M5` is the simplest interface, and can start displaying values in less than a second.  Wrap any statement in this text: `select * from table(m5(q'[  ...  ]'));`.  The function accepts two parameters, `P_CODE` and `P_TARGETS`, which are explained more thoroughly later.

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
			p_targets =>             'somedb%',
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


<a name="alternative_quoting_mechanism"/>

## Simplify Strings with Alternative Quoting Mechanism

Use the `q'[` syntax to embed SQL statements without needing to escape quotation marks.  In this alternative quoting mechanism, strings begin with `q'[` and end with `]'`.  You can also use `<>`, `()`, or `{}`.  Or if you use another character, simply repeat the character at the end.  For example, `q'! It's not necessary to add extra quotation marks now.!'`.


<a name="where_is_the_data_stored"/>

## Where is the data stored?

Every Method5 execution stores data in three tables - results, metadata, and errors.

The result table contains either the results of the query, the DBMS_OUTPUT for a PL/SQL block, a feedback message for other statement types, or the standard output and standard error of a host command.  Every row also contains the database name (for SQL and PL/SQL) or host name (for shell commands).  The table name can be specified with the parameter `p_table_name`.  If that parameter is left blank, a name will be automatically chosen.

The metadata table contains one row for each execution.  It contains the date started, is the process finished yet, the count of targets expected and completed and with errors, and the code and targets used.  This table has the same name as the results table but with the suffix `_meta`.

The errors table contains any Oracle errors generated during the execution, along with the target name.  With a large enough number of targets it's not unusual for at least one of them to be unavailable because of maintenance or an unexpected error.  Tracking errors lets you ignore the troublesome targets and deal with them later.  This table has the same name as the results table but with the suffix `_err`.

Serious errors during a run may make the metadata counts partially incorrect.  For example, if a database crashes in the middle of processing, the error may not be counted.  It's unlikely, but possible, for `IS_COMPLETE` to be `No` even though there are no more jobs running.  When that happens the column `TARGETS_EXPECTED` will not be equal to the sum of `TARGETS_COMPLETED` and `TARGETS_WITH_ERRORS`.

(One unexpected benefit of Method5 is that constantly polling all databases will make you keenly aware of which ones are unreliable.  Some databases are just full of gremlins.)

To simplify queries, Method5 always creates 3 views in your schema that refer to the latest tables.  Instead of worrying about the table names just run these statements:

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;


<a name="parameter_p_code"/>

## Parameter 1: P_CODE (required)

`P_CODE` is the most important parameter, it defines what code to run.  It can be any SQL statement, PL/SQL block, or *nix shell command.

**`SELECT`**

For most `SELECT` statements everything will automatically work fine.  Method5 will handle any expression list, stars, un-aliased columns, terminated or un-terminated statements, etc.  It automatically determines the column names, column order, and data types.

In practice that almost always works because most Method5 queries are run against data dictionary tables.  The data dictionary is usually pretty uniform across versions and editions.

Things get trickier when the column metadata is not the same across all databases.  Method5 first tries the query on the management database, and then on up to 100 remote databases.  If some databases have different column data they may fail with "not enough values", "too many values", or a data type conversion error.

Those problems can normally be avoided by explicitly listing the columns that are common to all databases.  The [version star](#version_star) feature can often help with these situations.  And there are other workarounds, such as [DBMS_XMLGEN.GETXML](#dbms_xmlgen.getxml)

**PL/SQL**

PL/SQL blocks let you run multiple statements and package them in one call.  Use `DBMS_OUTPUT.PUT_LINE` to display information.

	begin
		m5_proc(q'[  begin dbms_output.put_line('Hello, World!'); end;  ]', 'somedb%');
	end;
	/

	SQL> select * from m5_results;

	DATABASE_NAME                  RESULT
	------------------------------ -------------
	SOMEDB01                       Hello, World!
	...

**DDL, DML, System Control**

Commands like `DROP`, `INSERT`, or `ALTER SYSTEM` will return a message identical to the SQL*Plus feedback message.  (But Method5 does not use SQL*Plus.)

	SQL> select * from table(m5('alter user jheller profile some_profile'));

	DATABASE_NAME                  RESULT
	------------------------------ -------------
	SOMEDB01                       User altered.
	...

**Shell Command**

Linux or Unix shell commands and scripts must start with a shebang.  For example:

	begin
		m5_proc(
			p_code => '#!/bin/sh
				uptime
			',
			p_targets => 'dev'
		);
	end;
	/

	SQL> select * from m5_results;

	HOST_NAME  LINE_NUMBER OUTPUT
	---------  ----------- ------------------------------------------------------------------------
	dev1                 1   3:29am  up 39 day(s),  7:12,  0 users,  load average: 2.34, 2.04, 1.79
	dev2                 1  03:28:09 up 73 days, 15:08,  0 users,  load average: 0.00, 0.03, 0.05
	dev3                 1   3:29am  up 39 day(s), 10:54,  0 users,  load average: 0.41, 0.41, 0.42
	...

There are some limitations when running shell commands.  Method5 is great at running small commands for rapid troubleshooting and fixes.  But it is not meant to be a full operating system deployment tool like Fabric, Salt, or Ansible.

- Shell commands require a running Oracle database.  This means your scripts cannot shutdown and startup databases, which means this feature can't be used for patching and upgrades.
- Shell commands are always run as the user that installed the Oracle software.
- $HOME and "~" do not work.  The path to the Oracle user and software home must be hard-coded.
- Shell commands run once per host, not once per-database.  This is almost always what you want to do, but in a few rare cases it would be nice to run once for each database.


<a name="parameter_p_targets"/>

## Parameter 2: P_TARGETS (optional)

`P_TARGETS` identifies which databases to run the code on.  If it is not set it will use the default targets set for your user or the global default.  This parameter can either be a SELECT statement or a comma-separated list.

The values in a comma-separated list will match any database that shares the same name, host name, line of business, lifecycle status, or cluster name.

The value may also use the Oracle pattern matching syntax, `%` and `_`.

All target values must exist in M5_DATABASE.  And the row in M5_DATABASE must have IS_ACTIVE set to "Yes" (the default value).

For example, if you want all development databases, as well as ones on the ACME contract (line of business), and some other custom databases:

	p_targets => 'dev,acme,coyote%'

For advanced target list logic you can use a SQL query that returns database names.  You may want to use the table M5_DATABASE to find relevant database names.  For example:

	select * from table(m5(
		'select * from dual;',
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

The value may also use an optional Target Group, which is identified by starting with a `$`.  Target Groups are pre-defined queries so complicated logic doesn't need to be repeated.

For example, it can be tricky to query only one database per ASM instance.  Once you set up the target group with the name `ASM`, it can be used like this:

	select * from table(m5('select * from v$asm_disk', '$asm'));

See `administer_method5.md` for how to setup a Target Group.

Method5 will generate the error ORA-20404 if the target list does not match any configured databases.  If it is acceptable for your processes to occasionally not match any targets you can catch and ignore the exception like this:

	declare
		v_no_targets_were_found exception;
		pragma exception_init(v_no_targets_were_found, -20404);
	begin
		m5_proc('select * from dual', 'thisDoesntMatchAnything');
	exception when v_no_targets_were_found then
		null;
	end;
	/

For shell scripts `P_TARGETS` identifies which host to run the script on.


<a name="parameter_p_table_name"/>

## Parameter 3: P_TABLE_NAME (optional)

`P_TABLE_NAME` specifies the table name to store the results.  Tables with the suffixes `_meta` and `_err` are created to store the metadata and errors.

If this parameter is not specified then a sequence will be used to generate a unique name.  If the sequence is used, all but the last of those temporary tables will be dropped by a nightly job.


<a name="parameter_p_table_exists_action"/>

## Parameter 4: P_TABLE_EXISTS_ACTION (optional)

One of these values:

* ERROR - (DEFAULT) Raise an error if the table already exists.  This doesn't apply to functions, they always have a unique name.
* APPEND - Add new rows to the existing table.
* DELETE - Delete existing rows and then add new rows.
* DROP - Drop existing tables and re-create them for new results.


<a name="parameter_p_asynchronous"/>

## Parameter 5: P_ASYNCHRONOUS (optional)

By default, `P_ASYNCHRONOUS` is set to TRUE, which means the procedure will return immediately even if the results are not finished yet.

This lets you examine some of the results before a slow database is finished processing.


<a name="parameter_p_run_as_sys"/>

## Parameter 6: P_RUN_AS_SYS (optional)

By default, `P_RUN_AS_SYS` is set to FALSE and commands are run by either the Method5 schema or a sandbox schema.  When this parameter is set to TRUE the command is run as SYS.

This parameter should only be set to TRUE when necessary.  Almost all operations can be performed without SYS access.

Due to Oracle's lack of a BOOLEAN data type, the parameter is TRUE or FALSE in the procedure M5_PROC, and is "Yes" or "No" for the function M5.

If you are nervous about running remotely as SYS see the security section below for an explanation of how this feature is protected.

If you are still nervous about this feature you can disable access to certain users or not install it.  See administer_method5.md for more details.


<a name="m5_links"/>

## M5_ Links

Method5 automatically creates database links in your schema to all databases that it connects to.  The links are named like `M5_` plus the database name.  Those links can be useful for ad hoc statements.


<a name="global_data_dictionary"/>

## Global Data Dictionary

Method5 automatically gathers data for some common data dictionary tables.  These tables can be useful for rapid troubleshooting.  For example, if you're not sure which database contains a schema you can quickly query `select * from m5_dba_users` to look at the users for all databases.

* M5_DBA_USERS
* M5_V$PARAMETER
* M5_DBA_TAB_PRIVS, M5_DBA_ROLE_PRIVS, M5_DBA_SYS_PRIVS
* M5_USER$

You can add your own easily by following the examples in `code/install_method5_global_data_dictionary.sql`.


<a name="version_star"/>

## Version Star - Column Differences Between Versions

Using `**` instead of `*` when querying targets that include multiple versions of Oracle can avoid problems with column differences:

	SQL> select * from table(m5('select ** from v$parameter'));

Querying the data dictionary can be tricky when the targets include multiple versions of Oracle.  A regular `*` will return different columns depending on the version.  Which means the process may throw either "not enough values" or "too many values" depending on which version is used to determine the column list.

When Method5 sees the version star, `**`, it will automatically scan all the databases in the target list, look at databases using the lowest version, and use one of them to generate the column list.

The data dictionary is almost always backwards compatible.  The most likely version difference is the `CON_ID` column introduced in 12c.  If there is a mix of 11g and 12c databases, using the version star will ignore the `CON_ID` and other new columns.


<a name="dbms_xmlgen.getxml"/>

## DBMS_XMLGEN.GETXML - Table Differences Between Versions

Rarely a version difference makes it necessary to query different tables depending on the database version.  This complex situation can be solved with DBMS_XMLGEN.GETXML.

The below code reads the latest patch from each database.  Due to an Oracle bug the data is not available in the same tables in 11g and 12c.  The function DBMS_XMLGEN.GETXML provides a way to conditionally run SQL.

	begin
		m5_proc(
			p_table_name           => 'patch_data',
			p_targets              => 'DEV',
			p_table_exists_action  => 'drop',
			p_code                 => q'[
				--Get patch data from any version of Oracle.
				--Due to bug 25269268 the table DBA_REGISTRY_HISTORY is not populated in 12c.
				--To work around this we must query the 12c-only table DBA_REGISTRY_SQLPATCH.
				--That requires using DBMS_XMLGEN.GETXML which can handle non-existing objects.

				--11g table always exists, but may be empty in 12c.
				select comments description, action_time
				from dba_registry_history

				union all

				--12c table doesn't exist in 11g.  Only query it when it's available.
				select description, to_date(action_time, 'YYYY-MM-DD HH24:MI:SS') action_time
				from
				(
					select xmltype(dbms_xmlgen.getxml(q'!
						select
							description,
							to_char(action_time, 'YYYY-MM-DD HH24:MI:SS') action_time
						from dba_registry_sqlpatch
					!')) xml_results
					from dba_views
					where owner = 'SYS' and view_name = 'DBA_REGISTRY_SQLPATCH'
				) cross join
				xmltable
				(
					'/ROWSET/ROW'
					passing xml_results
					columns
						description varchar2(4000) path 'DESCRIPTION',
						action_time varchar2(4000) path 'ACTION_TIME'
				)
			]'
		);
	end;
	/


<a name="#job_timeout"/>

## Job Timeout

Method5 jobs will automatically timeout and be stopped after 23 hours.  When querying a large number of databases it's not uncommon for one of them to be so broken that even a trivial query will never finish.  Identifying and stopping these jobs will help daily jobs that need to re-run even if some databases are broken.

If you need queries to run longer than 23 hours you can configure the timeout like this:

	update method5.m5_config
	set number_value = $NEW_NUMBER
	where config_name = 'Job Timeout (seconds)';

When jobs time out they are recorded in the table METHOD5.M5_JOB_TIMEOUT.  That table can be useful for identifying misbehaving databases.


<a name="services_for_non_users"/>

## Services for non-Method5 users

Method5 goes to great lengths to protect access and ensure that only configured users can run it.  But sometimes it may be useful to provide other users with a limited, carefully controlled access to Method5.

Read-only access to specific query results is fairly straight-forward.  Create a job with DBMS_SCHEDULER to gather results into a specific table, then grant access on that table to roles or users.  The job should probably set `P_TABLE_EXISTS_ACTION` to either `DELETE` or `APPEND`, to ensure that the privileges are not dropped with the object.

DDL and write access is more complicated.  It requires creating a scheduled job to pass authentication and authorization checks, a custom procedure that alters the JOB_ACTION based on input from a user, running the job with `use_current_session => false`, and then waiting and checking the _META table for it to complete.  See the script "Lock User Everywhere.sql" for an example.  *TODO - add script.*

Keep in mind that scheduled jobs must be owned by a configured user.  Method5 always runs as an individual user, never a generic account.  If that user's account is de-activated, their jobs must be dropped and re-created by an active user.


<a name="long_to_clob_conversion"/>

## LONG to CLOB conversion

LONG columns are automatically converted to CLOBs.  This can make some data dictionary querying simpler since LONGs are so difficult to use.

For example, `DBA_TAB_COLS.DATA_DEFAULT` is a LONG and difficult to query.  Gather the data like this:

	begin
		m5_proc(
			p_code       => 'select * from dba_tab_cols where data_default is not null',
			p_targets    => 'SOME_DB',
			p_table_name => 'columns_with_defaults'
		);
	end;
	/

Now use the results table to more easily query and filter the `DATA_DEFAULT` column:

	select database_name, owner, table_name, column_name, to_char(data_default)
	from columns_with_defaults
	where to_char(data_default) = '0'
	order by 1,2,3,4;


<a name="m5_synch_user"/>

## Account Maintenance with M5_SYNCH_USER

The pre-built procedure `M5_SYNCH_USER` can help with many account maintenance and synchronization issues.  A single procedure call can create accounts, synch passwords, unlock, set profile, and grant role and system privileges.


<a name="administrator_daily_status_email"/>

## Administrator Daily Status Email

An email is sent to the Method5 administrators every day.  This email contains information about potential problems with Method5 configuration, access, and jobs.  This can be a good extra way to monitor the environment.  Since Method5 connects as a regular user from a remote system it occasionally finds problems that monitoring applications like Oracle Enterprise Manager may miss.


<a name="security"/>

## Security and User Configuration

Method5 is a great tool for database security.  See `security.md` for examples of how to use Method5 to improve security, the ways that Method5 is hardened to prevent abuse, and how to precisely configure Method5 security.

See the bottom of `security.md` for a complete guide to adding and configuring users and limiting their privileges.


<a name="possible_uses"/>

## Possible Uses

Method5 was built to help database administrators change their approach to solving database problems.

Many good DBAs spend most of their time fighting fires one-database-at-a-time.  We say to ourselves, "it probably hasn't happened on other databases and it probably won't happen again".  When what we really mean is "I don't have the time to check every other database".

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

* Upgrading and Patching - Method5 can run database and host commands but it requires a running database.  Upgrading and patching requires their own specialized tools.  (And in practice, in most environments those tasks are too fragile to fully automate anyway.)
* Deployments - Developers will want to use their own specialized tools for this.  But Method5 can help harmonize environments and can compare all objects, in all databases, in a single view.

At least one DBA, developer, or analyst in your organization should use Method5 if your organization is serious about database automation.
