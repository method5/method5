prompt Checking Method5 prerequisites...


--#0: Check the user.
@code/check_user must_run_as_sys



--#1: Check the prerequisites.
set serveroutput on;
set feedback off;

declare
	v_problem_count number := 0;

	--------------------------------------
	procedure check_10g_password_hash is
		v_user_does_not_exist exception;
		pragma exception_init(v_user_does_not_exist, -1918);
		v_password varchar2(4000);
		v_message varchar2(4000);
	begin
		--Drop temporary user if it exists.
		begin
			execute immediate 'drop user m5_temp_fake_user_drop_me';
		exception when v_user_does_not_exist then null;
		end;

		--Create a temporary user.
		execute immediate 'create user m5_temp_fake_user_drop_me identified by "asdfasdfQWERQWER#1234!$%^"';

		--Check for the 10g password hash.
		--("password" is not really the password.)
		select password
		into v_password
		from sys.user$
		where name = 'M5_TEMP_FAKE_USER_DROP_ME';

		--Raise error depending on the version.
		if v_password is null then
			v_problem_count := v_problem_count + 1;

			--The exact instructions depend on the version.
			declare
				v_first_version_number number;
				v_parameter varchar2(4000);
			begin
				select to_number(regexp_replace(version, '\..*')) first_number
				into v_first_version_number
				from v$instance;

				if v_first_version_number <= 11 then
					v_parameter := 'SQLNET.ALLOWED_LOGON_VERSION';
				else
					v_parameter := 'SQLNET.ALLOWED_LOGON_VERSION_SERVER';
				end if;

			v_message := '*WARNING* - 10g password hash: The 10g password hash was not generated in SYS.USER$.PASSWORD.'||chr(10)||
				'Without that password hash Method5 cannot connect to any database where SEC_CASE_SENSITIVE_LOGON is false.'||chr(10)||
				'If you need to connect to those databases, set '||v_parameter||' in $ORACLE_HOME/network/admin/sqlnet.ora to 11 or lower, '||chr(10)||
				'restart the listener, and reconnect to the database.';
			end;
		else
			v_message := '*PASS* - 10g password hash: The hash exists.';
		end if;

		dbms_output.put_line(v_message);
	end check_10g_password_hash;

	--------------------------------------
	procedure sql_checks is
	begin
		for checks in
		(
			--VERSION
			select 1 check_number,
				case
					when
					(
						first_number <= 11 or
						version like '11.1%' or
						version like '11.2.0.1%' or
						version like '11.2.0.2%'
					) then
						'*FAIL* - Version: The management server should be version 11.2.0.3 or later to avoid database link security problems.'
					else
						'*PASS* - Version: The management server version is sufficient.'
				end value
			from
			(
				select version, to_number(regexp_replace(version, '\..*')) first_number
				from v$instance
			)
			union all
			--PURGE_LOG
			select 2 check_number,
				case
					when has_job_scheduled_soon = 1 then '*PASS* - PURGE_LOG: The job is enabled and set to run in the near future.'
					when has_purge_log_job = 0 then '*FAIL* - PURGE_LOG: The job PURGE_LOG does not exist.  Without this job the DBMS_SCHEDULER log will grow too large.'
					when has_enabled_purge_log_job = 0 then '*FAIL* - PURGE_LOG: The job PURGE_LOG is not enabled.  Without this job the DBMS_SCHEDULER log will grow too large.'
					when has_job_scheduled_soon = 0 then '*FAIL* - PURGE_LOG: The job PURGE_LOG is not scheduled in the near future.  Without this job the DBMS_SCHEDULER log will grow too large.'
				end value
			from
			(
				select
					sum(case when job_name = 'PURGE_LOG' then 1 else 0 end) has_purge_log_job,
					sum(case when job_name = 'PURGE_LOG' and enabled = 'TRUE' then 1 else 0 end) has_enabled_purge_log_job,
					sum(case when job_name = 'PURGE_LOG' and enabled = 'TRUE' and abs(cast(next_run_date as date)-sysdate) < 10 then 1 else 0 end) has_job_scheduled_soon
				from dba_scheduler_jobs
			)
			union all
			--JOB_QUEUE_PROCESSES
			select 3 check_number,
				case
					when to_number(value) >= 50 then '*PASS* - JOB_QUEUE_PROCESSES: The value provides sufficient parallelism.'
					when to_number(value) = 0 then '*FAIL* - JOB_QUEUE_PROCESSES: Jobs cannot run if the value is set to 0.  You may want to run something like: alter system set job_queue_processes=1000;'
					else '*WARNING* - JOB_QUEUE_PROCESSES: The value should be set to at least 50 to ensure sufficient parallelism.  You may want to run something like: alter system set job_queue_processes=1000;'
				end value
			from v$parameter
			where name = 'job_queue_processes'
			union all
			--UTL_MAIL
			select 4 check_number,
				case when count(*) = 0
					then '*FAIL* - UTL_MAIL: UTL_MAIL must be installed to send emails.  Run steps like this, as SYS, to install it:'||chr(10)||
						'SQL> @?/rdbms/admin/utlmail.sql'||chr(10)||
						'SQL> @?/rdbms/admin/prvtmail.plb'
					else '*PASS* - UTL_MAIL: The package is installed.'
				end value
			from dba_objects
			where object_name = 'UTL_MAIL'
			union all
			--SMTP_OUT_SERVER
			select 5 check_number,
				case
					when value is null then
						'*FAIL* - SMTP_OUT_SERVER: This value must be set to send emails.  Run a command like this: alter system set smtp_out_server = ''your_email_server'';'
					else
						'*PASS* - SMTP_OUT_SERVER: The value is set.'
					end value
			from v$parameter
			where name = 'smtp_out_server'
			union all
			--DBMS_SCHEDULER
			select 6 check_number,
				case
					when count(*) >= 1 then '*PASS* - DBMS_SCHEDULER: The package is granted to PUBLIC.'
					else '*WARNING* - DBMS_SCHEDULER: The package is not granted to PUBLIC.  '||chr(10)||
						'The installation automatically grants it to PUBLIC but check your audit/security/hardening scripts to ensure it will not be revoked later.'||chr(10)||
						'DBMS_SCHEDULER is granted to PUBLIC by default.  Some *OLD* versions of the DoD STIG (secure technical implementation guidelines) suggest '||chr(10)||
						'revoking that privilege, but it is a good idea anymore.'
				end value
			from dba_tab_privs
			where grantee = 'PUBLIC'
				and table_name = 'DBMS_SCHEDULER'
			order by 1
		) loop
			--Display value.
			if checks.value like '%*FAIL*%' or checks.value like '%*WARNING*%' then
				v_problem_count := v_problem_count + 1;
			end if;
			dbms_output.put_line(checks.value);
		end loop;
	end sql_checks;

----------------------------------------
begin
	dbms_output.new_line;
	dbms_output.new_line;
	check_10g_password_hash;
	sql_checks;

	dbms_output.new_line;
	dbms_output.new_line;
	if v_problem_count = 0 then
		dbms_output.put_line('All prerequisites are met.');
	else
		dbms_output.put_line(' ______  _____   _____    ____   _____   ');
		dbms_output.put_line('|  ____||  __ \ |  __ \  / __ \ |  __ \  ');
		dbms_output.put_line('| |__   | |__) || |__) || |  | || |__) | ');
		dbms_output.put_line('|  __|  |  _  / |  _  / | |  | ||  _  /  ');
		dbms_output.put_line('| |____ | | \ \ | | \ \ | |__| || | \ \  ');
		dbms_output.put_line('|______||_|  \_\|_|  \_\ \____/ |_|  \_\ ');
		dbms_output.new_line;
		dbms_output.put_line('Please fix the above issues and re-run this script.');
		dbms_output.new_line;
	end if;
end;
/

set feedback on;
