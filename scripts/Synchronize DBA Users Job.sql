--Purpose: Synchronize accounts, passwords, and some privileges for DBAs.
--How to use: Run steps #2 and #3 and #4 to install, Run step #1 to periodically check job status.
--Prerequisites: The user running this script must be able to use Method5.
--Version: 3.0.0



--------------------------------------------------------------------------------
--#1: Check job status (check periodically)
--------------------------------------------------------------------------------
--Check job status.
select * from dba_scheduler_job_run_details where job_name = 'SYNCH_DBA_USERS_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'SYNCH_DBA_USERS_JOB';

--Check table outputs.  Run this to generate SQL statements to check results.
select 'select * from '||table_name||';' v_sql
from dba_tables
where owner = user
	and table_name like 'SYNCH\_%ERR' escape '\'
order by 1;


--------------------------------------------------------------------------------
--#2: Create table of DBA names.  (Run once to install, add users when necessary.)
--------------------------------------------------------------------------------

--Create the table.
create table method5.dba_synch_username
(
	username varchar2(128),
	constraint dba_synch_username_pk primary key (username)
);

--Add users.
insert into method5.dba_synch_username values('ADD NAME HERE');
commit;


--------------------------------------------------------------------------------
--#3: Create procedure (one-time step)
--------------------------------------------------------------------------------
create or replace procedure synch_dba_users authid current_user is
/*
	Purpose: Synchronize passwords and user settings for some DBAs.

	WARNING: Do not directly modify this procedure.  The official copy is in the repository.

*/

	type v_users_tables_rec is record(username varchar2(128), table_name varchar2(128));
	type v_users_tables_nt is table of v_users_tables_rec;

	v_users_tables v_users_tables_nt := v_users_tables_nt();
begin

	--Avoid DMBS_OUTPUT overflow from repeatedly calling M5_PROC.
	dbms_output.disable;

	--Gather DBA usernames and table names.
	execute immediate
	q'[
		select username, 'SYNCH_'||username table_name
		from
		(
			--Users in both config table and DBA_USERS.
			select trim(upper(dba_synch_username.username)) username
			from method5.dba_synch_username
			join dba_users
				on trim(upper(dba_synch_username.username)) = dba_users.username
			order by 1
		)
	]'
	bulk collect into v_users_tables;

	--Loop through all relevant DBAs.
	for i in 1 .. v_users_tables.count
	loop
		execute immediate
		q'[
			begin
				--Maintain account.
				m5_synch_user(
					p_username                    => :username,
					p_targets                     => '',
					p_table_name                  => :table_name,
					p_create_user_if_not_exists   => true,
					p_create_user_clause          => 'quota unlimited on users',
					p_synch_password_from_this_db => sys_context('userenv', 'db_name'),
					p_unlock_if_locked            => true,
					p_profile                     => 'DBA_PROFILE',
					p_role_privs                  => 'DBA',
					p_sys_privs                   => ''
				);
			end;
		]'
		using v_users_tables(i).username, v_users_tables(i).table_name;

	end loop;
end synch_dba_users;
/


--------------------------------------------------------------------------------
--#4: Create, test, and verify job (one-time step)
--------------------------------------------------------------------------------
begin
	dbms_scheduler.create_job
	(
		job_name        => 'SYNCH_DBA_USERS_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => trunc(systimestamp+1) + interval '20' minute,
		enabled         => true,
		repeat_interval => 'FREQ=DAILY',
		job_action      => 'begin synch_dba_users; end;'
	);
end;
/

/*
begin
	dbms_scheduler.drop_job('SYNCH_DBA_USERS_JOB');
end;
/
*/

/*
begin
	dbms_scheduler.run_job('SYNCH_DBA_USERS_JOB');
end;
/
*/

--Check job status.
select * from dba_scheduler_job_run_details where job_name = 'SYNCH_DBA_USERS_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'SYNCH_DBA_USERS_JOB';

--Check table outputs.  See step #1.
