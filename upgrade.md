Upgrade Method5
===============

Follow the below steps to upgrade your installation.  The steps are incremental.


8.8.4 --> 9.0.0: Security enhancements.
-------------------------------------

Incompatible version changes: The incompatible changes are actually quite small and only affect the administrative side of things.
1. M5_AUDIT.TARGETS and _MET.TARGETS now include the default values instead of the actual value entered.  With the new defaults system it's not always obvious what a NULL would be.

2. TODO - Add scripts to upgrade, like this:
delete from method5.m5_config where config_name in
(
	'Access Control - Username has _DBA suffix',
	'Access Control - User has DBA role',
	'Access Control - User has DBA_PROFILE',
	'Administrator Email Address'
);
3. TODO: Add (destructive?) tests for security features.

4. Run these commands on the management database to upgrade M5_DATABASE:

	--Stop existing job.
	begin
		dbms_scheduler.disable('method5.refresh_m5_database_job');
	end;
	/

	--Rename existing tables
	create or replace procedure method5.temp_rename_proc is
	begin
		execute immediate 'alter table method5.m5_database rename constraint m5_database_ck_numbers_only to m5_database_ck_numbers_onl_old';
		execute immediate 'rename m5_database to m5_database_old';
		execute immediate 'rename m5_database_hist to m5_database_hist_old';
	end;
	/
	begin
		method5.temp_rename_proc;
	end;
	/
	drop procedure method5.temp_rename_proc;

	--Drop public synonym.
	drop public synonym m5_database;

	--Create new table and comments.
	create table method5.m5_database
	(
		host_name                  varchar2(256) not null,
		database_name              varchar2(9) not null,
		instance_name              varchar2(16),
		lifecycle_status           varchar2(256),
		line_of_business           varchar2(1024),
		target_version             varchar2(64),
		operating_system           varchar2(256),
		cluster_name               varchar2(1024),
		description                varchar2(4000),
		point_of_contact           varchar2(4000),
		app_connect_string         varchar2(4000),
		m5_default_connect_string  varchar2(4000),
		is_active                  varchar2(3) default 'Yes' not null,
		changed_by                 varchar2(128),
		changed_date               date,
		constraint m5_database_pk primary key (host_name, database_name),
		constraint m5_database_numbers_only_ck check (regexp_like(target_version, '^[0-9\.]*$'))
	);
	comment on table method5.m5_database is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.';

	comment on column method5.m5_database.host_name                  is 'The name of the machine the database instance runs on.';
	comment on column method5.m5_database.database_name              is 'A short string to identify a database.  This name will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.';
	comment on column method5.m5_database.instance_name              is 'A short string to uniquely identify a database instance.  For standalone databases this will probably be the same as the DATABASE_NAME.  For a Real Application Cluster (RAC) database this will probably be DATABASE_NAME plus a number at the end.';
	comment on column method5.m5_database.lifecycle_status           is 'A value like "DEV" or "PROD".  (Your organization may refer to this as the "environment" or "tier".)';
	comment on column method5.m5_database.line_of_business           is 'A value to identify a database by business unit, contract, company, etc.';
	comment on column method5.m5_database.target_version             is 'A value like "11.2.0.4.0" or "12.1.0.2.0".  This value may be used to select the lowest or highest version so only use numbers.';
	comment on column method5.m5_database.operating_system           is 'A value like "SunOS" or "Windows".';
	comment on column method5.m5_database.cluster_name               is 'The Real Application Cluster (RAC) name for the cluster, if any.';
	comment on column method5.m5_database.description                is 'Any additional description or comments about the database.';
	comment on column method5.m5_database.point_of_contact           is 'The persons or teams that own or are responsible for these databases.  This may help with contacting people to get permission for an outage.';
	comment on column method5.m5_database.app_connect_string         is 'The connection string an application would use to connect to this database.';
	comment on column method5.m5_database.m5_default_connect_string  is 'The default connection string Method5 uses to connect to this database.  This value is only used once to create the database link, after that you must follow the steps in administer_method5.md to change database links.  This value is set by the trigger METHOD5.M5_DATABASE_TRG.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column (for each entry, use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.';
	comment on column method5.m5_database.is_active                  is 'Is this target active and available for use in Method5?  Either Yes or No.';
	comment on column method5.m5_database.changed_by                 is 'The last user who changed this row.';
	comment on column method5.m5_database.changed_by                 is 'The last date someone changed this row.';

	--Populate table with existing values.
	insert into method5.m5_database(
		host_name,database_name,instance_name,lifecycle_status,line_of_business,target_version,
		operating_system,cluster_name,description,point_of_contact,app_connect_string,m5_default_connect_string,is_active)
	select
		host_name,database_name,instance_name,lifecycle_status,line_of_business,target_version,operating_system,
		cluster_name,user_comment,null,null,connect_string,'Yes'
	from method5.m5_database_old;

	create table method5.m5_database_hist as
	select sysdate the_date, m5_database.*
	from method5.m5_database;

	insert into method5.m5_database_hist(
		the_date,host_name,database_name,instance_name,lifecycle_status,line_of_business,target_version,
		operating_system,cluster_name,description,point_of_contact,app_connect_string,m5_default_connect_string,is_active)
	select
		refresh_date, host_name,database_name,instance_name,lifecycle_status,line_of_business,target_version,operating_system,
		cluster_name,user_comment,null,null,connect_string,'Yes'
	from method5.m5_database_hist_old;

	commit;

	--Recreate public synonym.
	create public synonym m5_database for method5.m5_database;

	--Recreate grants.
	begin
		for privs in
		(
			select
				'grant '||privilege||' on method5.m5_database to '||grantee||
					case when grantable = 'YES' then ' with grant option' else null end v_sql
			from dba_tab_privs
			where owner = 'METHOD5'
				and table_name = 'M5_DATABASE_OLD'
				and grantee <> user
		) loop
			execute immediate privs.v_sql;
		end loop;
	end;
	/

5. Customize and run the below trigger on the management database.  You only need to customize the default connect string part between the "BEGIN CUSTOMIZE HERE" and "END CUSTOMIZE HERE".

	--Create new trigger to set some values.
	create or replace trigger method5.m5_database_trg
	before insert or update
	on method5.m5_database
	for each row
	--Purpose: Automatically set M5_DEFAULT_CONNECT_STRING, CHANGED_BY, and CHANGED_DATE if they were not set.
	--  You may want to customize the M5_DEFAULT_CONNECT_STRING to match your environment's connection policies.
	begin
		if inserting then
			if :new.m5_default_connect_string is null then
				--
				-- BEGIN CUSTOMIZE HERE
				--
				--You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column
				--(for each entry, use the text after the first equal sign).
				--You may want to remove spaces and newlines, it is easier to compare the strings without them.
				--It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.
				:new.m5_default_connect_string :=
					lower(replace(replace(
							'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SID=$instance_name))) ',
							--service_name may work better for some organizations:
							--'$instance_name=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$global_name))) ',
						'$instance_name', :new.instance_name)
						,'$host_name', :new.host_name)
					);
				--
				-- END CUSTOMIZE HERE
				--
			end if;

			if :new.changed_by is null then
				--Get the user from APEX if it was used.
				:new.changed_by := 	coalesce(
					sys_context('APEX$SESSION','app_user')
					,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
					,sys_context('userenv','session_user'));
			end if;

			if :new.changed_date is null then
				:new.changed_date := sysdate;
			end if;
		end if;

		if not updating('CHANGED_BY') then
			:new.changed_by := 	coalesce(
				--Get the user from APEX if it was used.
				sys_context('APEX$SESSION','app_user')
				,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
				,sys_context('userenv','session_user'));
		end if;
		if not updating('CHANGED_DATE') then
			:new.changed_date := sysdate;
		end if;
	end;
	/


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

