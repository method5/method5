Administer Method5
==================

**Contents**

1. [Install Method5 on remote databases.](#install_method5_on_remote_databases)
2. [Reset Method5 password one-at-a-time.](#reset_method5_password)
3. [Ad hoc statements to customize database links.](#customize_database_links)
4. [Access control.](#access_control)
5. [Drop M5_ database links for a user.](#drop_m5_links)
6. [Change Method5 passwords.](#change_method5_passwords)
7. [Add and test database links.](#add_and_test_database_links)
8. [Audit Method5 activity.](#audit_method5_activity)
9. [Configure Target Groups.](#configure_target_groups)

When installing Method5 run only the below steps, in order:

* 4: Access control.  (By default an "ALL" role was created and granted to the user who installed Method5.  You may be able to come back to this step later.)
* 1: Install Method5 on remote databases.  (Only install on a small number of databases to get started.)
* 7: Add and test database links.
* 3: Ad hoc statements to customize database links.  (As needed, to help with previous step.)
* 9: Configure Target Groups.  (This step is optional.)

Method5 administration only needs to be performed by one person.  The configuration automatically applies to other users.

These steps must be run on the master configuration server as a DBA configured to use Method5.  However, the output for "Reset Method5 password one-at-a-time" and "Install Method5 on remote database", must be run on a remote database.

Use a GUI program like Oracle SQL Developer to run these steps.  Method5 displays orders of magnitude more data than typical administration tasks.  Programs like SQL*Plus are not good at displaying that much data.



<a name="install_method5_on_remote_databases"/>

1: Install Method5 on remote databases.
---------------------------------------

Run this command on the management server, as a DBA, to generate a SQL*Plus script.  It's a big script, use a GUI program like Oracle SQL Developer so you can easily save the output.  (If you're using Oracle SQL Developer, use the "Run Statement" button, not the "Run Script" button.)

	select method5.method5_admin.generate_remote_install_script() from dual;

Run that generated script on *every* new database, as SYSDBA.  This is the only step that must be run on every database, and it only needs to be run once.  This may take a while, you can start with a few databases and come back to this step later.

Run these commands on the management server as a DBA and view the results.

	--This will create new database links.
	begin
		m5_proc(p_code => 'select * from dual', p_asynchronous => false);
	end;
	/
	--This will create a SYS key for all database links missing keys.
	select method5.method5_admin.set_all_missing_sys_keys() from dual;
	
	--Or run this to create a SYS key for just one new database.
	begin
		method5.method5_admin.set_local_and_remote_sys_key(p_db_link => '&db_link');
	end;
	/

If there are are errors use step #3 to diagnose link issues.  If you can't solve the problem please create a GitHub issue at https://github.com/method5/method5 or contact jon@jonheller.org for help.


<a name="reset_method5_password"/>

2: Reset Method5 password one-at-a-time.
----------------------------------------

Run this command on the management server as a DBA, but then run the output on the remote server as a DBA.

	select method5.method5_admin.generate_password_reset_one_db() from dual;


<a name="customize_database_links"/>

3: Ad hoc statements to customize database links.
-------------------------------------------------

This command generates PL/SQL blocks to test database links.  Enter the link name, database name, host name, and port number before running it.

You will probably need to modify some of the SQL*Net settings to match your environment.

	select method5.method5_admin.generate_link_test_script('&link_name', '&database', '&host', '&port') from dual;


<a name="access_control"/>

4: Access control.
------------------

(See security.md for a full description of the configuration.)

4A: Add Method5 users.  Use this query to find your precise OS usernames if you don't know them:

	select user oracle_username, sys_context('userenv', 'os_user') os_username from dual;

Then insert the permitted values with a query like this.  Make sure to create at least one user with IS_M5_ADMIN = 'Yes' and a valid email address.

	insert into method5.m5_user(oracle_username, os_username, email_address, is_m5_admin, default_targets,
		can_use_sql_for_targets, can_drop_tab_in_other_schema)
	values(
		'&oracle_username',
		'&os_username',
		'&email_address',
		'&is_m5_admin_Yes_No',
		'&default_targets',
		'&can_use_sql_for_targets_Yes_No',
		'&can_drop_tab_in_other_schema_Yes_No'
	);

Grant new users a role, the ability to create database links, and the ability to write at least a little data.  This gives them the minimum object and system privileges to run Method5.  The privileges are very minor, see install_method5_objects.sql for details.

	grant m5_run to &oracle_username;
	grant create database link to &oracle_username;

	--You can use a quota instead of unlimited if you want.
	alter user &oracle_username quota unlimited on users;

Create a Method5 role, if a relevant role does not already exist:

	insert into method5.m5_role(role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema,
		run_as_m5_or_sandbox, sandbox_default_ts, sandbox_temporary_ts, sandbox_quota, sandbox_profile))
	values(
		'&role_name',
		'&target_string',
		'&can_run_as_sys',
		'&can_run_shell_script',
		'&install_links_in_schema',
		'&run_as_m5_or_sandbox',
		'&sandbox_default_ts',
		'&sandbox_temporary_ts',
		'&sandbox_quota',
		'&sandbox_profile'
	);

Roles can run as either the Method5 user with all privileges, or as a temporary sandbox user with precisely defined privileges.  For sandbox roles, add the Oracle system, object, or role privileges and then associate the role with the user:

	insert into method5.m5_role_priv(role_name, privilege)
	values(
		'&role_name',
		'&privilege'
	);

	insert into method5.m5_user_role(oracle_username, role_name)
	values(
		'&oracle_username',
		'&role_name'
	);

4B: (OPTIONAL) Check the assigned Method5 privileges, as well as all available users, roles, and role privileges.

	select * from method5.m5_priv_vw;
	select * from method5.m5_user;
	select * from method5.m5_role;
	select * from method5.m5_role_priv;
	select * from method5.m5_user_role;

4C: (OPTIONAL) Disable one or more access control steps.  *This is strongly discouraged.*

	update method5.m5_config set string_value = 'DISABLED' where config_name = 'Access Control - User is not locked';
	update method5.m5_config set string_value = 'DISABLED' where config_name = 'Access Control - User has expected OS username';
	commit;


<a name="drop_m5_links"/>

5: Drop M5_ database links for a user.
--------------------------------------

Drop all links for a user who should no longer have access to Method5.

	begin
		method5.method5_admin.drop_m5_db_links_for_user('&USER_NAME');
	end;
	/


<a name="change_method5_passwords"/>

6: Change Method5 passwords.
----------------------------

6A: Method5 does not know or display the schema password.  It's effectively passwordless.  If you just need to avoid security findings on "password age", these commands will do that in a few seconds:

	begin
		method5.method5_admin.refresh_m5_ptime(p_targets => '%');
	end;
	/

	select database_name, to_char(result) from m5_results;
	select * from m5_metadata;
	select * from m5_errors;

If you're not comfortable with that workaround, and truly need to change the passwords, use the below, more difficult procedures.


**OR**


Follow the below steps to change the Method5 passwords on all databases.  For individual problems with remote databases see the section "Reset Method5 password one-at-a-time.".

6B: Change the Method5 user password on the management server.

	begin
		method5.method5_admin.change_m5_user_password;
	end;
	/

6C: Change the remote Method5 passwords.

	begin
		method5.method5_admin.change_remote_m5_passwords;
	end;
	/

Check the results below while the background jobs are running.  If there are connection problem you may need to manually fix some passwords later with the steps "Reset Method5 password one-at-a-time" or "Ad hoc statements to customize database links.".

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;

6D: Change the Method5 database link passwords.  This step may take about a minute.

	begin
		method5.method5_admin.change_local_m5_link_passwords;
	end;
	/

6E: Refresh all user Method5 database links.

	select method5.method5_admin.refresh_all_user_m5_db_links() from dual;


<a name="add_and_test_database_links"/>

7: Add and test database links.
-------------------------------

Run a simple query against every database.

	select * from table(m5('select * from dual'));

Check the results, metadata, and errors:

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;

If there are are errors use step #3 to diagnose link issues.  If you can't solve the problem please create a GitHub issue at https://github.com/method5/method5 or contact jon@jonheller.org for help.


<a name="audit_method5_activity"/>

8: Audit Method5 activity.
--------------------------

Use a query like this to display recent Method5 activity.  (The CLOBs are converted to VARCHAR2 to work better in some IDEs.)

	--Display recent Method5 activity.
	--(Convert CLOB into VARCHAR2 because some IDEs don't handle CLOBs well)
	select
		username,
		create_date,
		table_name,
		cast(substr(code, 1, 4000) as varchar2(4000)) code,
		cast(substr(targets, 1, 4000) as varchar2(4000)) targets,
		table_name,
		table_exists_action,
		asynchronous,
		targets_expected,
		targets_completed,
		targets_with_errors,
		num_rows,
		access_control_error
	from method5.m5_audit
	order by create_date desc;


<a name="configure_target_groups"/>

9: Configure Target Groups.
---------------------------

Create Target Groups so you don't have to repeat complicated SQL in the P_TARGETS parameter.

The target group name is defined in the text that comes after "Target Group - ".  The query can be any valid SELECT statement that returns one column with targets.

For example, querying ASM views like V$ASM_DISK is tricky because so many databases may share the same ASM instance.  The query below assumes you have one ASM instance per host for standalones, and one ASM instance per cluster for RAC.

	--Add Target Alias
	insert into method5.m5_config(config_id, config_name, string_value)
	select
		method5.m5_config_seq.nextval,
		'Target Group - ASM',
		q'[
			--ASM - Choose one database per host (for standalone) or per cluster (for RAC).
			select min(database_name) database_name
			from m5_database
			where cluster_name is null
				and lifecycle_status in ('DEV', 'TEST', 'PROD')
			group by host_name
			union
			select min(database_name) database_name
			from m5_database
			where cluster_name is not null
				and lifecycle_status in ('DEV', 'TEST', 'PROD')
		]'
	from dual;
	commit;

To use target groups reference them with a "$" at the beginning of the name in the target parammeter:

	select * from table(m5('select * from dual', '$asm'));
