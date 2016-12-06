Administer Method5
==================

**Contents**

1. [Install Method5 on remote database.](#install_method5_on_remote_database)
2. [Reset Method5 password one-at-a-time.](#reset_method5_password)
3. [Ad hoc statements to customize database links.](#customize_database_links)
4. [Access control.](#access_control)
5. [Drop M5_ database links for a user.](#drop_m5_links)
6. [Change Method5 passwords.](#change_method5_passwords)
7. [Add and test database links.](#add_and_test_database_links)
8. [Audit Method5 activity.](#audit_method5_activity)
9. [Configure administrator email addresses.](#configure_email_addresses)
10. [Configure Target Groups.](#configure_target_groups)

Method5 administration only needs to be performed by one person.  The configuration will automatically apply to all other users.

These steps must be run on the configuration server as a DBA configured to use Method5.  However, the output for "Reset Method5 password one-at-a-time." and "Install Method5 on remote database.", must be run on a remote database.

If you're installing Method5, run these steps in this order:

* 9: Configure administrator email addresses.
* 4: Access control.
* 1: Install Method5 on remote database.  (Run on every remote database - this may take a while.)
* 3: Ad hoc statements to customize database links.  (As needed, to help with previous step.)
* 10: Configure Target Groups.
* 7: Add and test database links.


<a name="install_method5_on_remote_database"/>
1: Install Method5 on remote database.
--------------------------------------

Run this command on the management server as a DBA, but run the output on the remote server as SYSDBA.

	select method5.method5_admin.generate_remote_install_script() from dual;


<a name="reset_method5_password"/>
2: Reset Method5 password one-at-a-time.
----------------------------------------

Run this command on the management server as a DBA, but then run the output on the remote server as a DBA.

	select method5.method5_admin.generate_password_reset_one_db() from dual;


<a name="customize_database_links"/>
3: Ad hoc statements to customize database links.
-------------------------------------------------

This command generates PL/SQL blocks to test database links.  Enter the database name, host name, and port number before running it.

You will probably need to modify some of the SQL*Net settings to match your environment.

	select method5.method5_admin.generate_link_test_script('&database', '&host', '&port') from dual;


<a name="access_control"/>
4: Access control.
------------------

4A: Add users to the 2-step authentication table.  First fine your connect information with a query like this:

	select user, sys_context('userenv', 'os_user') from dual;

Then insert the permitted values into the 2-step authentication table like this:

	insert into method5.m5_2step_authentication(oracle_username, os_username)
	values('&oracle_username1','&os_username1');


4B: (OPTIONAL) Disable one or more access control steps.  *This is strongly discouraged.*

	update method5.m5_config set string_value = 'DISABLED' where config_name = 'Access Control - Username has _DBA suffix';
	update method5.m5_config set string_value = 'DISABLED' where config_name = 'Access Control - User has DBA role';
	update method5.m5_config set string_value = 'DISABLED' where config_name = 'Access Control - User has DBA_PROFILE';
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

Follow the below steps to change the Method5 passwords on all databases.  For individual problems with remote databases see the section "Reset Method5 password one-at-a-time.".

06A: Change the Method5 user password on the management server.

	begin
		method5.method5_admin.change_m5_user_password;
	end;
	/

6B: Change the remote Method5 passwords.

	begin
		method5.method5_admin.change_remote_m5_passwords;
	end;
	/

Check the results below while the background jobs are running.  If there are connection problem you may need to manually fix some passwords later with the steps "Reset Method5 password one-at-a-time" or "Ad hoc statements to customize database links.".

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;

6C: Change the Method5 database link passwords.  This step may take about a minute.

	begin
		method5.method5_admin.change_local_m5_link_passwords;
	end;
	/

6D: Refresh all user Method5 database links.

	select method5.method5_admin.refresh_all_user_m5_db_links() from dual;


<a name="add_and_test_database_links"/>
7: Add and test database links.
-------------------------------

Run a simple against every database.  The first time this is run it may take a few minutes to create the database links.

	select * from table(m5('select * from dual'));

Check the results, metadata, and errors:

	select * from m5_results;
	select * from m5_metadata;
	select * from m5_errors;


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


<a name="configure_email_addresses"/>
9: Configure administrator email addresses.
-------------------------------------------

Create an Access Control List for Method5 so that it can send emails through a definer's rights procedure.

	begin
		method5.method5_admin.create_and_assign_m5_acl;
	end;
	/

Add one or more email addresses for a simple intrusion detection system.  This statement should also generate an email as all changes to M5_CONFIG send an email the administrator.

	insert into method5.m5_config(config_id, config_name, string_value)
	values (method5.m5_config_seq.nextval, 'Administrator Email Address', '&EMAIL_ADDRESS');
	commit;


<a name="configure_target_groups"/>
10: Configure Target Groups.
----------------------------

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
