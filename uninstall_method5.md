Uninstall Method5
=================

These steps will permanently remove *ALL* Method5 data, configuration, and objects from the management server and any remote targets.  However it will not remove any user-generated data that was given a custom name.

First, let's make sure that nobody accidentally runs this as a script:
	exit;
	exit;

Finally, when you're done uninstalling, I'd like to know what went wrong and what we can do to improve things for others.  I'd appreciate it if you could create a GitHub issue or send me an email at jon@jonheller.org.


Remove from Management Server
-----------------------------

Run these steps as a DBA on the management server.  To make sure you really want to do this, the step is commented out.  Remove the multiline comment and unindent before running.

/*
	--Stop current jobs:
	begin
		method5.m5_pkg.stop_jobs;
	end;
	/

	--Drop house-keeping and global data dictionary jobs:
	declare
		procedure drop_job_not_exists(p_job_name varchar2) is
			v_unknown_job exception;
			pragma exception_init(v_unknown_job, -27475);
		begin
			dbms_scheduler.drop_job(p_job_name);
		exception when v_unknown_job then null;
		end;
	begin
		drop_job_not_exists('method5.cleanup_m5_temp_triggers_job');
		drop_job_not_exists('method5.cleanup_m5_temp_tables_job');
		drop_job_not_exists('method5.direct_m5_grants_job');
		drop_job_not_exists('method5.email_m5_daily_summary_job');
		drop_job_not_exists('method5.stop_timed_out_jobs_job');
		drop_job_not_exists('method5.backup_m5_database_job');

		for jobs in
		(
			select owner, job_name
			from dba_scheduler_jobs
			where job_name in (
				--Housekeeping job that must be run by a user
				'CLEANUP_REMOTE_M5_OBJECTS_JOB',
				--Global data dictionary.
				'M5_DBA_USERS_JOB', 'M5_V$PARAMETER_JOB', 'M5_PRIVILEGES_JOB', 'M5_USER$_JOB',
				--Refreshes links in user schemas.
				'M5_LINK_REFRESH_JOB'
			)
			order by 1,2
		) loop
			drop_job_not_exists(jobs.owner||'.'||jobs.job_name);
		end loop;

	end;
	/

	--Kill any remaining Method5 user sessions:
	begin
		for sessions in
		(
			select 'alter system kill session '''||sid||','||serial#||''' immediate' kill_sql
			from gv$session
			where schemaname = 'METHOD5'
		) loop
			execute immediate sessions.kill_sql;
		end loop;
	end;
	/

	--Remove all user links:
	begin
		for users in
		(
			select distinct owner
			from dba_db_links
			where db_link like 'M5_%'
				and owner not in ('METHOD5', 'SYS')
			order by owner
		) loop
			method5.method5_admin.drop_m5_db_links_for_user(users.owner);
		end loop;
	end;
	/

	--Drop the ACL used for sending emails:
	begin
		dbms_network_acl_admin.drop_acl(acl => 'method5_email_access.xml');
	end;
	/

	--Drop the user.
	drop user method5 cascade;

	--Drop a global context used for Method4:
	drop context method4_context;

	--Drop public synonyms:
	begin
		for synonyms in
		(
			select 'drop public synonym '||synonym_name v_sql
			from dba_synonyms
			where table_owner = 'METHOD5'
			order by 1
		) loop
			execute immediate synonyms.v_sql;
		end loop;
	end;
	/

	--Drop temporary tables that hold Method5 data retrieved from targets:
	begin
		for tables in
		(
			select 'drop table '||owner||'.'||table_name||' purge' v_sql
			from dba_tables
			where table_name like 'M5_TEMP%'
			order by 1
		) loop
			execute immediate tables.v_sql;
		end loop;
	end;
	/
*/

If you are only uninstalling to re-install, make sure you completely log out of all sessions before installing anything.


Remove from Remote Targets
--------------------------

Login to each remote target as SYS and run the below command.  THERE'S NO TURNING BACK FROM THIS!  To make sure you really want to do this, the step is commented out.  Remove the multiline comment and unindent before running.

/*
	--Kill any active Method5 sessions
	begin
		for sessions in
		(
			select 'alter system kill session '''||sid||','||serial#||',@'||inst_id||'''' v_sql
			from gv$session
			where username = 'METHOD5'
		) loop
			execute immediate sessions.v_sql;
		end loop;
	end;
	/
	drop user method5 cascade;
	drop table sys.m5_sys_session_guid;
	drop package sys.m5_runner;
	drop procedure sys.m5_run_shell_script;
	drop database link m5_sys_key;
	drop role m5_minimum_remote_privs;
	drop role m5_optional_remote_privs;
	drop role m5_user_role;
*/
