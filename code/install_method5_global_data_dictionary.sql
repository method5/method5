prompt Creating jobs for global data dictionary...;

--These jobs collect information every day for commonly used data dictionary objects.
--These steps must be run on the central management server, as a DBA.
--Although they are jobs, they must be owned by an active, configured user.
--If that user's account is terminated you will have to recreate the jobs.
--
--Feel free to add your own commonly used tables.


---------------------------------------
--#0: Check the user.
@code/check_user must_be_m5_user


---------------------------------------
--#1: DBA_USERS.
begin
	dbms_scheduler.create_job(
		job_name        => 'M5_DBA_USERS_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => systimestamp at time zone 'US/Eastern',
		enabled         => true,
		repeat_interval => 'freq=daily; byhour=3; byminute=0; bysecond=0',
		job_action      =>
		q'<
			begin
				m5_proc(
					p_code                => '
						--All 11gR2 columns.
						select
							username, user_id, password, account_status, lock_date, expiry_date,
							default_tablespace, temporary_tablespace, created, profile, initial_rsrc_consumer_group, 
							external_name, cast(password_versions as varchar2(12)) password_versions,
							editions_enabled, authentication_type
						from dba_users
					',
					p_table_name          => 'method5.m5_dba_users',
					p_table_exists_action => 'DELETE',
					p_asynchronous        => false,
					p_targets             => '%'
				);
			end;
		>'
	);
end;
/


---------------------------------------
--#2: V$PARAMETER.
begin
	dbms_scheduler.create_job(
		job_name        => 'M5_V$PARAMETER_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => systimestamp at time zone 'US/Eastern',
		enabled         => true,
		repeat_interval => 'freq=daily; byhour=3; byminute=5; bysecond=0',
		job_action      =>
		q'<
			begin
				--Gather data in a user schema.
				m5_proc(
					p_code                 => '
						--All 11gR2 columns.
						select
							num, name, type, value, display_value, isdefault, isses_modifiable,
							issys_modifiable, isinstance_modifiable, ismodified, isadjusted,
							isdeprecated, isbasic, description, update_comment, hash
						from v$parameter;
					',
					p_table_name           => 'method5.m5_v$parameter',
					p_table_exists_action  => 'DELETE',
					p_asynchronous         => false,
					p_targets             => '%'
				);
			end;
		>'
	);
end;
/


---------------------------------------
--#3: Privileges.
begin
	dbms_scheduler.create_job(
		job_name        => 'M5_PRIVILEGES_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => systimestamp at time zone 'US/Eastern',
		enabled         => true,
		repeat_interval => 'freq=daily; byhour=3; byminute=10; bysecond=0',
		job_action      =>
		q'<
			begin
				--These queries include all 11g columns.
				m5_proc(
					p_code                => 'select grantee, owner, table_name, grantor, privilege, grantable, hierarchy from dba_tab_privs',
					p_table_name          => 'method5.m5_dba_tab_privs',
					p_table_exists_action => 'DELETE',
					p_asynchronous        => false,
					p_targets             => '%'
				);
				m5_proc(
					p_code                => 'select grantee, granted_role, admin_option, default_role from dba_role_privs',
					p_table_name          => 'method5.m5_dba_role_privs',
					p_table_exists_action => 'DELETE',
					p_asynchronous        => false,
					p_targets             => '%'
				);
				m5_proc(
					p_code                => 'select grantee, privilege, admin_option from dba_sys_privs',
					p_table_name          => 'method5.m5_dba_sys_privs',
					p_table_exists_action => 'DELETE',
					p_asynchronous        => false,
					p_targets             => '%'
				);
			end;
		>'
	);
end;
/


---------------------------------------
--#4: USER$.
begin
	dbms_scheduler.create_job(
		job_name        => 'M5_USER$_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => systimestamp at time zone 'US/Eastern',
		enabled         => true,
		repeat_interval => 'freq=daily; byhour=3; byminute=15; bysecond=0',
		job_action      =>
		q'<
			begin
				--Gather data in a user schema.
				m5_proc(
					p_code                => '
						--All 11g columns.
						select
							user#, name, type#, password, datats#, tempts#, ctime, ptime, exptime, ltime, 
							resource$, audit$, defrole, defgrp#, defgrp_seq#, astatus, lcount, defschclass, 
							ext_username, spare1, spare2, spare3, spare4, spare5, spare6
						from sys.user$
					',
					p_table_name          => 'method5.m5_user$',
					p_table_exists_action => 'DELETE',
					p_asynchronous        => false,
					p_targets             => '%'
				);
			end;
		>'
	);
end;
/


---------------------------------------
--#5: Force job to run first time.
prompt Running jobs.  This may take a few minutes to gather all the data...;
--No need to see the M5_PROC output.
set serveroutput off;

begin
	dbms_scheduler.run_job('M5_DBA_USERS_JOB');
	dbms_scheduler.run_job('M5_V$PARAMETER_JOB');
	dbms_scheduler.run_job('M5_PRIVILEGES_JOB');
	dbms_scheduler.run_job('M5_USER$_JOB');
end;
/

prompt All jobs should say "SUCCEEDED"...
select job_name, status, to_char(log_date, 'YYYY-MM-DD HH24:MI') log_date
from
(
	select job_name, status, log_date, row_number() over (partition by job_name order by log_date desc) last_when_1
	from dba_scheduler_job_run_details
	where job_name like 'M5_%JOB'
	order by log_date desc
)
where last_when_1 = 1
order by job_name;


---------------------------------------
--#6: Create public synonyms on the tables.
prompt Registering global data dictionary tables...
insert /*+ ignore_row_on_dupkey_index(m5_global_data_dictionary, m5_global_data_dictionary_uq) */
into method5.m5_global_data_dictionary
select 'METHOD5' owner, 'M5_DBA_USERS'      table_name from dual union all
select 'METHOD5' owner, 'M5_V$PARAMETER'    table_name from dual union all
select 'METHOD5' owner, 'M5_DBA_TAB_PRIVS'  table_name from dual union all
select 'METHOD5' owner, 'M5_DBA_ROLE_PRIVS' table_name from dual union all
select 'METHOD5' owner, 'M5_DBA_SYS_PRIVS'  table_name from dual union all
select 'METHOD5' owner, 'M5_USER$'          table_name from dual;
commit;


---------------------------------------
--#7: Create public synonyms on the tables.
prompt Creating public synonyms for global data dictionary...

create or replace public synonym m5_dba_users for method5.m5_dba_users;
create or replace public synonym m5_dba_users_meta for method5.m5_dba_users_meta;
create or replace public synonym m5_dba_users_err for method5.m5_dba_users_err;

create or replace public synonym m5_v$parameter for method5.m5_v$parameter;
create or replace public synonym m5_v$parameter_meta for method5.m5_v$parameter_meta;
create or replace public synonym m5_v$parameter_err for method5.m5_v$parameter_err;

create or replace public synonym m5_dba_tab_privs for method5.m5_dba_tab_privs;
create or replace public synonym m5_dba_tab_privs_meta for method5.m5_dba_tab_privs_meta;
create or replace public synonym m5_dba_tab_privs_err for method5.m5_dba_tab_privs_err;

create or replace public synonym m5_dba_role_privs for method5.m5_dba_role_privs;
create or replace public synonym m5_dba_role_privs_meta for method5.m5_dba_role_privs_meta;
create or replace public synonym m5_dba_role_privs_err for method5.m5_dba_role_privs_err;

create or replace public synonym m5_dba_sys_privs for method5.m5_dba_sys_privs;
create or replace public synonym m5_dba_sys_privs_meta for method5.m5_dba_sys_privs_meta;
create or replace public synonym m5_dba_sys_privs_err for method5.m5_dba_sys_privs_err;

create or replace public synonym m5_user$ for method5.m5_user$;
create or replace public synonym m5_user$_meta for method5.m5_user$_meta;
create or replace public synonym m5_user$_err for method5.m5_user$_err;


prompt Done.
