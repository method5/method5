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

8. Ensure that DBMS_SCHEDULER is granted to PUBLIC.  (This is the default privilege.  It is revoked by some old DoD STIG (secure technical implementation guidelines), but not the most recent version.  However a lot of security programs still flag this important privilege.)

	select
		case
			when count(*) >= 1 then 'PASS - DBMS_SCHEDULER is granted to PUBLIC.'
			else 'FAIL - DBMS_SCHEDULER will be automatically granted to PUBLIC.'||chr(10)||
				'Check your audit/security/hardening scripts to ensure it is not removed later or SANDBOX accounts will break.'
		end dbms_scheduler_grant_check
	from dba_tab_privs
	where grantee = 'PUBLIC'
		and table_name = 'DBMS_SCHEDULER';


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

Run this script on the management server as a user with the DBA role, in SQL*Plus.  This user will be the default Method5 administrator so you should use a personal account.  Ths script should not generate any errors.

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

You probably want to use a meaningful profile for Method5.  Whatever you select here will also be used in remote databases.

	alter user method5 profile &PROFILE_NAME ;


7: Run steps in administer_method5.md.
--------------------------------------

See the file administer_method5.md for details.


8: Install Method5 housekeeping jobs and global data dictionary.
----------------------------------------------------------------

Run these scripts on the management server as a user with the DBA role, in SQL*Plus.  They must NOT be run by SYS.  They should not generate any errors.

	SQL> @code/install_method5_housekeeping_jobs.sql
	SQL> @code/install_method5_global_data_dictionary.sql


9: Run integration tests to verify installation. (optional)
-----------------------------------------------------------

Run this code on the management server, as a user who has the DBA role and is a Method5 administrator.

Replace the "&" values with real values.  If possible, pick two databases that use a different version of Oracle - that will more thoroughly test all features.

	select method5.method5_test.get_run_script(
		p_database_name_1   => '&database1',
		p_database_name_2   => '&database2',
		p_other_schema_name => '&other_user_that_exists_in_both_dbs',
		p_test_run_as_sys   => '&sys_yes_or_no',
		p_test_shell_script => '&shell_yes_or_no',
		p_tns_alias         => '&tns_alias')
	from dual;

That command will output a SQL*Plus script to run to test several temporary users.  Run that script on a command line.  The output should display multiple "PASS" messages, but no "FAIL" messages.


11: Populate M5_DATABASE with OEM data. (optional)
--------------------------------------------------

If you use Oracle Enterprise Manager (OEM) and want to use it to populate the table M5_DATABASE see the file examples/Load OEM data into M5_DATABASE.sql.
