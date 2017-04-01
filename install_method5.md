Install Method5
===============

Installing Method5 is a one-time, semi-automated process.  Pick one person to install and administer Method5.  That person should have intermediate DBA skills, and preferably some development background.

Testing Method5 only requires a single database.  A multi-database environment can be simulated by inserting fake values in step 4, "Configure M5_DATABASE".  Create rows with fake database names but set the connect strings to use the same database.

If there are problems with the installation please submit an issue to the GitHub repository, or send an email to Jon Heller at hjon@VentechSolutions.com.


1: Check pre-requisites.
------------------------

Run these steps on the management server by a user with the DBA role.

1. There must be a central management server that can connect to all databases.

2. The management server should be at least version 11.2.0.3.  Lower versions have security issues with database links.

3. You must have SYSDBA access to all databases to install and administer Method5, although most steps only require DBA.  Access requirements are labeled on each step.

4. Run this SQL to ensure the PURGE_LOG job exists, is enabled, and is scheduled in the near future.  This is necessary because there are a large number of jobs and you don't want to keep their history forever.

		select
			case
				when has_job_scheduled_soon = 1 then 'PASS - The job PURGE_LOG is enabled and set to run in the near future.'
				when has_purge_log_job = 0 then 'FAIL - The job PURGE_LOG does not exist.  Without this job the DBMS_SCHEDULER log will grow too large.'
				when has_enabled_purge_log_job = 0 then 'FAIL - The job PURGE_LOG is not enabled.  Without this job the DBMS_SCHEDULER log will grow too large.'
				when has_job_scheduled_soon = 0 then 'FAIL - The job PURGE_LOG is not scheduled in the near future.  Without this job the DBMS_SCHEDULER log will grow too large.'
			end purge_log_status
		from
		(
			select
				sum(case when job_name = 'PURGE_LOG' then 1 else 0 end) has_purge_log_job,
				sum(case when job_name = 'PURGE_LOG' and enabled = 'TRUE' then 1 else 0 end) has_enabled_purge_log_job,
				sum(case when job_name = 'PURGE_LOG' and enabled = 'TRUE' and abs(cast(next_run_date as date)-sysdate) < 10 then 1 else 0 end) has_job_scheduled_soon
			from dba_scheduler_jobs
		);

5. Run this SQL to check that JOB_QUEUE_PROCESSES is adequate for DBMS_SCHEDULER parallelism.

		select
			case
				when to_number(value) >= 50 then 'PASS - job_queue_processes is sufficient.'
				else 'FAIL - the parameter job_queue_processes should be set to at least 50 to ensure sufficient parallelism.'
			end job_queue_processes_check
		from v$parameter
		where name = 'job_queue_processes';

6. Run this SQL to check that UTL_MAIL is installed.

	select case when count(*) = 0 then 'FAIL - you must install UTL_MAIL' else 'PASS' end utl_mail_check
	from dba_objects
	where object_name = 'UTL_MAIL';

If it's missing, run these steps as SYS to install it:

	SQL> @?/rdbms/admin/utlmail.sql
	SQL> @?/rdbms/admin/prvtmail.plb

7. Run this SQL to check that SMTP_OUT_SERVER is set.

	select
		case
			when value is null then
				'FAIL - You must set system parameter SMTP_OUT_SERVER.'
			else
				'PASS - SMTP_OUT_SERVER is set.'
			end value
	from v$parameter
	where name = 'smtp_out_server';


2: Install SYS components.
--------------------------

Run this script on the management server as SYS.  It's a small script, you can either copy and paste the statements or run it in SQL*Plus.  It should not generate any errors.  For example:

	C:\> cd Method5
	C:\Method5> sqlplus / as sysdba
	...
	SQL> @code/install_method5_sys_components.sql
	SQL> quit


3: Install Method5 objects.
---------------------------

Run this script on the management server as a user with the DBA role, in SQL*Plus.  It should not generate any errors.

	SQL> @code/install_method5_objects.sql
	SQL> quit


4: Configure M5_DATABASE.
-------------------------

Run this step on the management server as a user with the DBA role.

Manually add rows to the main configuration table, METHOD5.M5_DATABASE.  This table is critical to the configuration of the system, it is used for filtering databases and creating links.  Pay close attention to the details.

*TIP* Four sample rows were inserted by default, use them to get started.  Don't worry about adding all your databases or getting it 100% perfect right away.  Come back to this step later after you've used Method5 for a while.


5: Configure default targets.
-----------------------------

Run this code on the management server as a user with the DBA role.

By default, Method5 runs against all targets.  This default can be changed from `%` to some other string like this:

	update method5.m5_config
	set string_value = 'DEV,TEST,PROD'  --Change this line
	where config_name = 'Default Targets';
	commit;


6: Set Method5 profile.
-----------------------

Run this optional code on the management server as a user with the DBA role.

You probably want to use a meaningful profile for Method5.  Whatever you select here will be used in remote databases.

	alter user method5 profile &PROFILE_NAME ;


7: Run steps in administer_method5.md.
--------------------------------------

See the file administer_method5.md for details.


8: Install Method5 housekeeping jobs and global data dictionary.
----------------------------------------------------------------

Run these scripts on the management server as a user with the DBA role, in SQL*Plus.  They must NOT be run by SYS.  They should not generate any errors.

	SQL> @code/install_method5_housekeeping_jobs.sql
	SQL> @code/install_method5_global_data_dictionary.sql


9: Run integration tests to verify installation.
------------------------------------------------

Run this code on the management server, as a user with the DBA role who is authorized to use Method5.

Replace `&database1` and `&database2` with two configured databases.  (If possible, pick two databases that use a different version of Oracle - that will more thoroughly test all features.)  Replace '&other_user' with another valid user name.  The tests should output "PASS".

	--The tests will run for about a minute and print either "PASS" or "FAIL".
	set serveroutput on;
	begin
		method5.method5_test.run(p_database_name_1 => '&database1', p_database_name_2 => '&database2', p_other_schema_name => '&other_user');
	end;
	/


10: Configure M5_DATABASE job (optional).
----------------------------------------

Run this code on the management server as a user with the DBA role.

This step is optional and is only useful if you want to automatically populate M5_DATABASE from a source like Oracle Enterprise Manager (OEM).

**DO NOT** run the below PL/SQL block without modifying the `INSERT` statement to make it fit your environment.

This may be the trickiest part of the installation, especially if you have duplicate or inconsistent names.

Run these data dictionary queries to get detailed information about the table and each column:

	SQL> select comments from dba_tab_comments where table_name = 'M5_DATABASE';
	SQL> select column_name, comments from dba_col_comments where table_name = 'M5_DATABASE';

Example job:

	--Create job to periodically refresh M5_DATABASE and M5_DATABASE_HIST.
	begin
		dbms_scheduler.create_job
		(
			job_name        => 'method5.refresh_m5_database_job',
			job_type        => 'PLSQL_BLOCK',
			start_date      => systimestamp,
			repeat_interval => 'freq=hourly; byminute=0; bysecond=0;',
			enabled         => true,
			comments        => 'Refreshes M5_DATABASE and M5_DATABASE_HIST from OEM tables.',
			job_action      => q'<
				--Refresh M5_DATABASE and save history.
				declare
					v_max_refresh_date date;
				begin
					--Get latest refresh date.
					select max(refresh_date)
					into v_max_refresh_date
					from method5.m5_database_hist;

					--Delete old results.
					delete from method5.m5_database;

					--Insert new results.
					-- **CONFIGURE THIS**  This should probably be different for your environment. **
					insert into method5.m5_database
					select
						target_guid,
						host_name,
						database_name,
						instance_name,
						lifecycle_status,
						line_of_business,
						target_version,
						operating_system,
						user_comment,
						cluster_name,
						lower(replace(replace(
								'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SID=$instance_name))) ',
								--service_name may work better for some organizations: '$instance_name=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$global_name))) ',
							'$instance_name', instance_name)
							,'$host_name', host_name)
						) as connect_string,
						refresh_date
					from
					(
						--Data from Oracle Enterprise Manager.
						select
							instance.target_guid,
							instance.host_name,
							instance.database_name,
							instance.instance_name, --may be case sensitive!
							properties.lifecycle_status,
							properties.line_of_business,
							properties.target_version,
							properties.operating_system,
							properties.user_comment,
							rac_topology.cluster_name,
							sysdate refresh_date
						from sysman.mgmt$db_dbninstanceinfo instance
						join sysman.em_global_target_properties properties
							on instance.target_guid = properties.target_guid
						left join
						(
							select distinct cluster_name, db_instance_name
							from sysman.mgmt$rac_topology
						) rac_topology
							on instance.target_name = rac_topology.db_instance_name
						where instance.target_type = 'oracle_database'
						order by instance.host_name, instance.database_name, instance.instance_name
					) oem_data
					order by host_name, database_name, instance_name;

					--For 12c+: Convert CDBs to PDB names.
					-- **CONFIGURE THIS**  This should probably be different for your environment.
					-- (TODO, if you use containers)

					--Save history daily.
					if v_max_refresh_date is null or sysdate - v_max_refresh_date > 1 then
						insert into method5.m5_database_hist
						select * from method5.m5_database;
					end if;

					commit;
				end;
			>'
		);
	end;
	/

If you need to drop the job to re-create it:

	begin
		dbms_scheduler.drop_job('method5.refresh_m5_database');
	end;
	/

Run the job immediately after it's configured:

	begin
		dbms_scheduler.run_job('method5.refresh_m5_database');
	end;
	/

Check that it was successful and take a look at the data:

	select status, additional_info
	from dba_scheduler_job_run_details
	where job_name = 'REFRESH_M5_DATABASE'
		and log_date > systimestamp - interval '1' hour
	order by log_date desc;

	select * from method5.m5_database;
