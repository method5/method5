Install Method5
===============

Installing Method5 is a one-time, semi-automated process.  Pick one person to install and administer Method5.  That person should have intermeidate DBA skills, and preferrably some development background.

If there are problems with the installation please submit an issue to the Github repository, or send an email to Jon Heller at hjon@VentechSolutions.com.


1: Check pre-requisites.
------------------------

These steps must be run on the management server by a user with the DBA role.

1. There must be a central management server that can connect to all databases.

2. The management server should be at least version 11.2.0.3.  Lower versions have security issues with database links.

3. You must have SYSDBA access to all databases to install and administer Method5, although most steps only require DBA.  Access requirements are labeled on each step.

4. Check that PURGE_LOG job exists, is enabled, and scheduled in the near future.  This is necessary because there are a large number of jobs and you don't want to keep their history forever.

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

5. Check that JOB_QUEUE_PROCESSES is adaquate for DBMS_SCHEDULER parallelism.

		select
			case
				when to_number(value) >= 50 then 'PASS - job_queue_processes is sufficient.'
				else 'FAIL - the parameter job_queue_processes should be set to at least 50 to ensure sufficient parallelism.'
			end job_queue_processes_check
		from v$parameter
		where name = 'job_queue_processes';

6. Check that UTL_MAIL is installed.

	select case when count(*) = 0 then 'FAIL - you must install UTL_MAIL' else 'PASS' end utl_mail_check
	from dba_objects
	where object_name = 'UTL_MAIL';

If it's missing, run these steps as SYS to install it:

	SQL> @$ORACLE_HOME/rdbms/admin/utlmail.sql
	SQL> @$ORACLE_HOME/rdbms/admin/prvtmail.plb

7. Check that SMTP_OUT_SERVER is set.

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

This script must be run on the management server by the user SYS.  It's a small script, you can either copy and paste the statements or run it in SQL*Plus.  It should not generate any errors.  For example:

	C:\> cd Method5
	C:\Method5> sqlplus / as sysdba
	...
	SQL> @code/install_method5_sys_components.sql
	SQL> quit


3: Install Method5 objects.
---------------------------

These scripts must be run on the management server by a user with the DBA role, in SQL*Plus.  It should not generate any errors.

	SQL> @code/install_method5_objects.sql
	SQL> quit


4: Configure M5_DATABASE job.
-----------------------------

This code must be run on the management server by a user with the DBA role.

This step is optional and is only useful if you want to populate M5_DATABASE from a source like Oracle Enterprise Manager (OEM).

**DO NOT** run this PL/SQL block without modifying the `INSERT` and `UPDATE` statement and have them fit your environment.

This may be the trickiest part of the installation, especially if you have duplicate or inconsistent names.

	--Create job to periodically refresh M5_DATABASE and M5_DATABASE_HIST.
	begin
		dbms_scheduler.create_job
		(
			job_name        => 'method5.refresh_m5_database',
			job_type        => 'PLSQL_BLOCK',
			start_date      => systimestamp,
			repeat_interval => 'freq=hourly; byminute=0; bysecond=0;',
			enabled         => true,
			comments        => 'Refreshes M5_DATABASE and M5_DATABASE_HIST from OEM tables.',
			job_action      => q'<
				--Refresh M5_DATABASE and save history every 24 hours.
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
					order by instance.host_name, instance.database_name, instance.instance_name;

					--Convert CDBs to PDB names.
					-- **CONFIGURE THIS**  This should probably be different for your environment. **
					update method5.m5_database
					set database_name = replace(replace(database_name, 'CDB', null), 'cdb', null),
						instance_name = replace(replace(instance_name, 'CDB', null), 'cdb', null)
					where lower(database_name) like '%cdb' or lower(instance_name) like '%cdb';

					--If the old max refresh date is null or older than 1 day, save history.
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


Run the job immediately after it's configured and check that it was successful:

	begin
		dbms_scheduler.run_job('method5.refresh_m5_database');
	end;
	/

	select status, additional_info
	from dba_scheduler_job_run_details
	where job_name = 'REFRESH_M5_DATABASE'
		and log_date > systimestamp - interval '1' hour;

	select * from method5.m5_database;


5: Configure Database Name query.
---------------------------------

This code must be run on the management server by a user with the DBA role.

**DO NOT** run this PL/SQL block without modifying the `INSERT` statement to fit your environment.

This may be the trickiest part of the installation, especially if you have duplicate or inconsistent names.


	insert into method5.m5_config(config_id, config_name, string_value)
	values(method5.m5_config_seq.nextval, 'Database Name Query', q'[
		--Method5 uses this query to determine all possible database links and configuration.
		--It's OK if this query returns some extra databases - they can be filtered out later.
		--It's OK if the CONNECT_STRING is not perfect - if there's a problem with some of
		-- them they can manually adjusted later.

		--This query must return 5 columns: DATABASE_NAME, CONNECT_STRING,
		--INSTANCE_NUMBER, HOST_NAME, LIFECYCLE_STATUS, and LINE_OF_BUSINESS.
		--
		--(Your organization may have different names for those items.  For example,
		-- you might call it "Environment" instead of "LIFECYCLE_STATUS".  But for this
		-- query to work you must use those pre-defined names.)
		--
		--DATABASE_NAME: Used for the link name.  Cannot be null.
		--CONNECT_STRING: Used to create the link.  Cannot be null.
		--INSTANCE_NUMBER: Used to only select one database in a cluster.  Cannot be null.
		--HOST_NAME/LIFECYCLE_STATUS/LINE_OF_BUSINESS/CLUSTER_NAME: Used to identify
		--  databases by an atribute.  These can  be null.  There should not be any
		--  duplicates between the columns.  For example, you should not have a database
		--  called "prod" as well as a LIFECYCLE_STATUS named "prod" with other databases.
		--
		select
			database_name
			,connect_string
			,instance_number
			,host_name
			,lifecycle_status
			,line_of_business
			,cluster_name
		from
		(
			select
				database_name
				,lower(replace(replace(
						'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SID=$instance_name))) ',
						--service_name does not always work :'$instance_name=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$global_name))) ',
					'$instance_name', instance_name)
					--Use CNAME for single-instance, use host_name for RAC since RACs don't have CNAMEs.
					,'$host_name', case when lower(instance_name) = lower(database_name) then database_name||'_mgt' else host_name end)
					) as connect_string
				,to_char(row_number() over (partition by database_name order by instance_name)) instance_number
				,host_name
				,lifecycle_status
				,line_of_business
				,cluster_name
			from method5.m5_database
			where lower(database_name) not in
				(
					select lower(database_name) from method5.m5_database_not_queried
				)
		)
	]');

	commit;


6: Configure default targets.
-----------------------------

This code must be run on the management server by a user with the DBA role.

By default, Method5 runs against all targets.  This default can be changed from `%` to some other string like this:

	update method5.m5_config
	set string_value = 'DEV,TEST,PROD'  --Change this line
	where config_name = 'Default Targets';
	commit;


7: Set Method5 profile.
-----------------------

This optional code must be run on the management server by a user with the DBA role.

You probably want to use a meaningful profile for Method5.  Whatever you select here will be used in remote databases.

	alter user method5 profile &PROFILE_NAME ;


8: Run steps in administer_method5.md.
--------------------------------------


9: Install Method5 housekeeping jobs and global data dictionary.
----------------------------------------------------------------

These scripts must be run on the management server by a user with the DBA role, in SQL*Plus.  They must NOT be run by SYS.  They should not generate any errors.

	SQL> @code/install_method5_housekeeping_jobs.sql
	SQL> @code/install_method5_global_data_dictionary.sql


10: Run integration tests to verify installation.
------------------------------------------------

This code must be run on the management server, by a user with the DBA role, who is authorized to use Method5.

Replace `&database1` and `&database2` with two configured databases.  Replace '&other_user' with another valid user name.  The tests should output "PASS".

	--The tests will run for about a minute and print either "PASS" or "FAIL".
	set serveroutput on;
	begin
		method5.method5_test.run(p_database_name_1 => '&database1', p_database_name_2 => '&database2', p_other_schema_name => '&other_user');
	end;
	/
