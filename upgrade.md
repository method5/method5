Upgrade Method5
===============

Follow the below steps to upgrade your installation.  The steps are incremental.

Almost every installation starts with these two steps:
1. Download and unzip the latest file from https://github.com/method5/method5.
2. CD to the Method5 directory.



9.3.1 --> 9.3.2: Bug fixes for 18c support.
-------------------------------------

As a DBA user, run the below commands on the master server, in SQL*Plus.  Change the "1521" below to the master database port.
	alter session set current_schema=method5;
	@code/plsql_lexer/packages/plsql_lexer.plsql
	@code/plsql_lexer/packages/statement_classifier.plsql
	alter table method5.m5_user add constraint m5_user_username_cannot_be_m5 check(lower(oracle_username) <> 'm5');
	@code/method5_admin.pck
	@code/m5_pkg.pck
	@code/addons/install_compare_everything_everywhere.sql
	@code/m5_database_trg.trg 1521
	comment on table method5.m5_database is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.  Changes to M5_DEFAULT_CONNECT_STRING will cause the database links to be automatically regenerated on the next run.';
	comment on column method5.m5_database.m5_default_connect_string  is 'Change this value to modify the database links.  When this value is changed Method5 will reset the database and host link the next time Method5 is run for those targets.  The initial value for this column is set by the trigger METHOD5.M5_DATABASE_TRG, which makes guesses based on the database name, host name, and original port.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column.  (Remember to use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect initially, problems can be manually adjusted later.';

9.2.4 --> 9.3.1: Added Snare and DB_DOMAIN bug fixes.
-------------------------------------

1. Run this command, on the master server, in SQL*Plus, to install the Snare objects:

		@code/install_snare.sql

2. Run these files, on the master server, to install new packages: code/snare.pck, code/m5_pkg.pck.


9.2.3 --> 9.2.4: Bug fixes for remote installation.
-------------------------------------

1. Run these files, on the master server, to install new packages: code/m5_pkg.pck, code/method5_admin.pck.


9.2.2 --> 9.2.3: Bug fixes for SQL*Plus abbreviated commands.
-------------------------------------

1. Run these files, on the master server, to install new packages: code/m5_pkg.pck.


9.2.0 --> 9.2.2: Bug fixes and simpler installation.
-------------------------------------

1. Run these files, on the master server, to install new packages: code/m5_pkg.pck and code/method5_admin.pck.

2. Replace all the .md documentation files in the top directory with the latest files.

3. Run this command on the master server, as SYS:

	create or replace procedure sys.get_method5_hashes
	--Purpose: Method5 administrators need access to the password hashes.
	--But the table SYS.USER$ is hidden in 12c, we only want to expose this one hash.
	--
	--TODO 1: http://www.red-database-security.com/wp/best_of_oracle_security_2015.pdf
	--	The 12c hash is incredibly insecure.  Is it safe to remove the "H:" hash?
	--TODO 2: Is there a way to derive the 10g hash from the 12c H: hash?
	--	Without that, 12c local does not support remote 10g or 11g with case insensitive passwords.
	(
		p_12c_hash in out varchar2,
		p_11g_hash_without_des in out varchar2,
		p_11g_hash_with_des in out varchar2,
		p_10g_hash in out varchar2
	) is
	begin
		--10 and 11g.
		$if dbms_db_version.ver_le_11_2 $then
			select
				spare4,
				spare4 hash_without_des,
				spare4||';'||password hash_with_des,
				password
			into p_12c_hash, p_11g_hash_without_des, p_11g_hash_with_des, p_10g_hash
			from sys.user$
			where name = 'METHOD5';
		--12c.
		$else
			select
				spare4,
				regexp_substr(spare4, 'S:.{60}'),
				regexp_substr(spare4, 'S:.{60}')||';'||password hash_with_des,
				password
			into p_12c_hash, p_11g_hash_without_des, p_11g_hash_with_des, p_10g_hash
			from sys.user$
			where name = 'METHOD5';
		$end
	end;
	/

4. Run these commands on the master server, as a DBA:

	alter table method5.m5_database modify host_name varchar2(15);
	alter table method5.m5_database modify database_name varchar2(15);
	alter table method5.m5_database add constraint m5_database_ck_hostname check (regexp_like(host_name, '^[a-zA-Z]+[a-zA-Z0-9#\_\$]*$'));
	alter table method5.m5_database add constraint m5_database_ck_dbname check (regexp_like(database_name, '^[a-zA-Z]+[a-zA-Z0-9#\_\$]*$'));

	comment on column method5.m5_database.host_name                  is 'The name of the machine the database instance runs on.  The name will be used for links and other schema objects so it must be small and follow schema object naming rules.  (These limits do not apply to host names used in connection strings.)';

	comment on column method5.m5_database.database_name              is 'The DB_NAME (for traditional architecture) or the container name (for multi-tenant architecture).  This short string will identify the database and will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.  The name must follow schema object naming rules.';

	begin
		m5_proc('grant select on sys.v_$instance to method5', '%', p_run_as_sys => true, p_asynchronous => false);

		m5_proc('grant select on sys.v_$database to method5', '%', p_run_as_sys => true, p_asynchronous => false);

		m5_proc(
			p_code => q'[
	create or replace view method5.db_name_or_con_name_vw as
	select
		case
			--Old version:
			when v$instance.version like '9.%' or v$instance.version like '10.%' or v$instance.version like '11.%' then
				sys_context('userenv', 'db_name')
			--New version but with old architecture:
			when sys_context('userenv', 'cdb_name') is null then
				sys_context('userenv', 'db_name')
			--New version, with multi-tenant, on the CDB$ROOT:
			when sys_context('userenv', 'con_name') = 'CDB$ROOT' then
				v$database.name
			--New version, with multi-tenant, on the PDB:
			else
				sys_context('userenv', 'con_name')
		end database_name,
		v$database.platform_name
	from v$database cross join v$instance;]',
			p_targets => '%', p_asynchronous => false);

		m5_proc(
			p_code => q'[comment on table method5.db_name_or_con_name_vw is 'Get either the DB_NAME (for traditional architecture) or the CON_NAME (for multi-tenant architecture).  This is surprisingly difficult to do across all versions and over a database link.']',
			p_targets => '%',
			p_asynchronous => false
		);
	end;
	/


9.1.1 --> 9.2.0: Bug fixes and simpler installation.
-------------------------------------

1. Run these files, on the master server, to install new packages: code/m5_pkg.pck, code/method5_admin.pck, and code/tests/method5_test.pck.
2. Run the PL/SQL block "--#3: Create SYS procedure to change database link password hashes." from code/install_method5_sys_components.sql, on the master server.
3. Replace all the .md documentation files in the top directory with the latest files.
4. Run these commands:
	comment on column method5.m5_user.os_username                  is 'Individual operating system account used to access Method5.  Depending on your system and network configuration enforcing this username may also ensure two factor authentication.  Do not use a shared account.  If NULL then the OS_USERNAME will not be checked.';
	delete from method5.m5_config where config_name = 'Access Control - User has expected OS username';
	commit;


9.0.4 --> 9.1.1: Bug fixes and simpler installation.
-------------------------------------

1. Run these files, on the master server, to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck, and code/m5_synch_user.prc.
2. Replace administer_method5.md with the latest file.


8.8.4 --> 9.0.0: Security enhancements.
-------------------------------------

This is the first incompatible version change.  The API is the same but there configuration tables are very different (and more robust).  I recommend you backup the existing tables, uninstall, and then reinstall.

If that's not an option for you, please let me know and I'll create an upgrade script.


8.7.2 --> 8.8.4: Added Run Shell Script feature.
-------------------------------------

1. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck, /code/method4_m5_poll_table_ot.typ, /code/tests/method5_test.pck

2. Install SYS.M5_RUN_SHELL_SCRIPT on every remote host.
2a. Run this command on the management database:
	select method5.method5_admin.generate_remote_install_script from dual;
2b. Copy the procedure M5_RUN_SHELL_SCRIPT from the output.
2c. Run that on every server, as SYS.  (Hint: Use Method5 to install it quickly.)

3. Run these commands on the management database:
	alter table method5.m5_2step_authentication add can_run_shell_script varchar2(3);
	update method5.m5_2step_authentication set can_run_shell_script = 'Yes';
	alter table method5.m5_2step_authentication modify can_run_shell_script not null;
	alter table method5.m5_2step_authentication
		add constraint can_run_shell_script_ck
		check (can_run_shell_script in ('Yes', 'No'));


8.6.1 --> 8.7.2: Added Run as SYS feature.
-------------------------------------

1. Install the new remote package SYS.M5_RUNNER.
1a. Run this command on the management database:
	select method5.method5_admin.generate_remote_install_script from dual;
1b. Copy everything from "--Create table to hold Session GUIDs." and below and save that as a SQL script.
1c. Run that file on every server, as SYS, to setup the P_RUN_AS_SYS feature.

2. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck, /code/method4_m5_poll_table_ot.typ, /code/tests/method5_test.pck

3. In the file install_method5_objects.sql, re-run the function method5.m5 and the procedure method5.m5_proc.

4. Run these commands:


	--Change authentication table:
	alter table method5.m5_2step_authentication add can_run_as_sys varchar2(3);
	alter table method5.m5_2step_authentication add constraint can_run_as_sys_ck check(can_run_as_sys in ('Yes', 'No'));
	update method5.m5_2step_authentication set can_run_as_sys = 'Yes';
	commit;
	alter table method5.m5_2step_authentication modify can_run_as_sys not null;

	--Add new column and temp columns to move existing columns to the right.
	alter table method5.m5_audit add (run_as_sys                 varchar2(3));
	alter table method5.m5_audit add (targets_expected_temp      number);
	alter table method5.m5_audit add (targets_completed_temp     number);
	alter table method5.m5_audit add (targets_with_errors_temp   number);
	alter table method5.m5_audit add (num_rows_temp              number);
	alter table method5.m5_audit add (access_control_error_temp  varchar2(4000));
	--Set the temp columns;
	update method5.m5_audit set
	targets_expected_temp     = targets_expected,
	targets_completed_temp    = targets_completed,
	targets_with_errors_temp  = targets_with_errors,
	num_rows_temp             = num_rows,
	access_control_error_temp = access_control_error;
	--Drop the original columns.
	alter table method5.m5_audit drop column targets_expected;
	alter table method5.m5_audit drop column targets_completed;
	alter table method5.m5_audit drop column targets_with_errors;
	alter table method5.m5_audit drop column num_rows;
	alter table method5.m5_audit drop column access_control_error;
	--Rename the new columns.
	alter table method5.m5_audit rename column targets_expected_temp     to targets_expected;
	alter table method5.m5_audit rename column targets_completed_temp    to targets_completed;
	alter table method5.m5_audit rename column targets_with_errors_temp  to targets_with_errors;
	alter table method5.m5_audit rename column num_rows_temp             to num_rows;
	alter table method5.m5_audit rename column access_control_error_temp to access_control_error;
	--Add constraint.
	update method5.m5_audit set run_as_sys = 'No';
	alter table method5.m5_audit add constraint m5_audit_ck3 check (run_as_sys in ('Yes', 'No'));

	create table method5.m5_sys_key
	(
		db_link varchar2(128),
		sys_key raw(32)
	);
	comment on table method5.m5_sys_key is 'Private keys used for encrypting and decrypting Method5 commands to run as SYS.';


8.6.0 --> 8.6.1: Bug fix for column expressions more than 30 bytes long.
-------------------------------------

1. Run these files to install new packages: /code/m5_pkg.pck, /code/tests/method5_test.pck.


8.5.1 --> 8.6.0: Added M5_SYNCH_USER.
-------------------------------------

1. Run these files to install new packages: /code/m5_synch_user.prc
2. Run this command to create a public synonym:
	create public synonym m5_synch_user for method5.m5_synch_user;


8.4.0 --> 8.5.1: Added 12.2 support.
------------------------------------

1. Download new code and run these commands to install new versions of the components METHOD4 and PLSQL_LEXER:

	alter session set current_schema=method5;

	@code\plsql_lexer\packages\plsql_lexer.plsql
	@code\plsql_lexer\packages\statement_classifier.plsql
	@code\plsql_lexer\packages\statement_feedback.plsql

	@code\method4\method4.spc
	@code\method4\method4_dynamic_ot.tpb
	@code\method4\method4_ot.tpb

8.3.0 --> 8.4.0: Add version star.
----------------------------------

1. Run these files to install new packages: /code/m5_pkg.pck, /code/tests/method5_test.pck.


8.2.0 --> 8.3.0: Improve admin email, simplify installation.
------------------------------------------------------------

1. Run these commands as-is:

	--Add new columns.
	alter table method5.m5_database add (connect_string varchar2(4000));
	alter table method5.m5_database add (refresh_date_temp date);
	update method5.m5_database set refresh_date_temp = refresh_date;
	alter table method5.m5_database drop column refresh_date;
	alter table method5.m5_database rename column refresh_date_temp to refresh_date;

	alter table method5.m5_database_hist add (connect_string varchar2(4000));
	alter table method5.m5_database_hist add (refresh_date_temp date);
	update method5.m5_database_hist set refresh_date_temp = refresh_date;
	alter table method5.m5_database_hist drop column refresh_date;
	alter table method5.m5_database_hist rename column refresh_date_temp to refresh_date;

	--Add new constraints.
	alter table method5.m5_database modify database_name not null;
	alter table method5.m5_database modify connect_string not null;
	alter table method5.m5_database add constraint m5_database_ck_numbers_only check (regexp_like(target_version, '^[0-9\.]*$'))

	--Add new comments to explain configuration table.
	comment on table method5.m5_database                   is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.';
	comment on column method5.m5_database.target_guid      is 'This GUID may be useful for matching to the Oracle Enterprise Manager GUID.';
	comment on column method5.m5_database.host_name        is 'The name of the machine the database instance runs on.';
	comment on column method5.m5_database.database_name    is 'A short string to identify a database.  This name will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.';
	comment on column method5.m5_database.instance_name    is 'A short string to uniquely identify a database instance.  For standalone databases this will probably be the same as the DATABASE_NAME.  For a Real Application Cluster (RAC) database this will probably be DATABASE_NAME plus a number at the end.';
	comment on column method5.m5_database.lifecycle_status is 'A value like "DEV" or "PROD".  (Your organization may refer to this as the "environment" or "tier".)';
	comment on column method5.m5_database.line_of_business is 'A value to identify a database by business unit, contract, company, etc.';
	comment on column method5.m5_database.target_version   is 'A value like "11.2.0.4.0" or "12.1.0.2.0".  This value may be used to select the lowest or highest version so only use numbers.';
	comment on column method5.m5_database.operating_system is 'A value like "SunOS" or "Windows".';
	comment on column method5.m5_database.user_comment     is 'Any additional comments.';
	comment on column method5.m5_database.cluster_name     is 'The Real Application Cluster (RAC) name for the cluster.';
	comment on column method5.m5_database.connect_string   is 'Used to create the database link.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column (for each entry, use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.';
	comment on column method5.m5_database.refresh_date     is 'The date this row was last refreshed.';

2. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.

3. Save this result for later: 

	select job_action from dba_scheduler_jobs where job_name = 'REFRESH_M5_DATABASE_JOB';

4. Delete the old job and data:

	delete from method5.m5_config where config_name = 'Database Name Query';

	begin
		dbms_scheduler.drop_job('method5.refresh_m5_database');
	end;
	/

5. Recreate the job REFRESH_M5_DATABASE_JOB based on the string from step 3 above, and the hints from step 10 of install_method5.md.new based on install document.

6. Drop this table if you're not using it.  If you are using it, use a different LIFECYCLE_STATUS instead of this table.

	drop table method5.m5_database_not_queried;


8.1.0 --> 8.2.0: Performance improvement.
-----------------------------------------

1. Run the INSERT statement for "Job Timeout (seconds)" and create the table M5_JOB_TIMEOUT, from install_method5_objects.sql.

2. Run the section "Create JOB to stop timed out jobs." in install_method5_housekeeping_jobs.sql.

3. Re-create the procedure "SYS.GET_METHOD5_HASHES" from install_method5_sys_components.sql.

4. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.


8.0.2 --> 8.1.0: Added Target Groups and CLUSTER_NAME.
------------------------------------------------------

Run all these steps on the central management server.

1. Change M5_DATABASE and M5_DATABASE_HIST tables to support a new column:

	alter table method5.m5_database add (cluster_name varchar2(1024));
	alter table method5.m5_database add (refresh_date_temp date);
	update method5.m5_database set refresh_date_temp = refresh_date;
	alter table method5.m5_database drop column refresh_date;
	alter table method5.m5_database rename column refresh_date_temp to refresh_date;

	alter table method5.m5_database_hist add (cluster_name varchar2(1024));
	alter table method5.m5_database_hist add (refresh_date_temp date);
	update method5.m5_database_hist set refresh_date_temp = refresh_date;
	alter table method5.m5_database_hist drop column refresh_date;
	alter table method5.m5_database_hist rename column refresh_date_temp to refresh_date;


2. Find the DDL to generate the job that refreshes the M5_DATABASE table.

	select replace(dbms_metadata.get_ddl('PROCOBJ', 'REFRESH_M5_DATABASE', 'METHOD5'), '"REFRESH_M5_DATABASE"', 'METHOD5.REFRESH_M5_DATABASE') from dual;

3. SAVE the output from the above step for later but make one change to it - add the CLUSTER_NAME column logic.  See install_method5.md for an example.

4. Drop the old job.

	begin
		dbms_scheduler.drop_job('METHOD5.REFRESH_M5_DATABASE');
	end;
	/

5. Run the code saved in step #3.

6. Test job and check the new CLUSTER_NAME column.

	begin
		dbms_scheduler.run_job('METHOD5.REFRESH_M5_DATABASE');
	end;
	/

	select * from m5_database;

7. Change the database name query.  Look at your existing value in METHOD5.M5_CONFIG and also look at "5: Configure Database Name query." in install_method5.md for the new `CLUSTER_NAME` column.  Modify your query and then update the configuration table with a SQL like this:

	update method5.m5_config
	set string_value = q'[
		--ENTER NEW QUERY HERE
	]'
	where config_name = 'Database Name Query';
	commit;

8. Run "10: Configure Target Groups." in administer_method5.md.

9. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.

