--Purpose: Synchronize accounts, passwords, and some privileges for DBAs.
--How to use: Run steps #2 and #3 and #4 to install, Run step #1 to periodically check job status.
--Prerequisites:
--	1. The central management database must be 11g.  12c will require a few minor changes to password hash algorithms.
--	2. The user running this script must be able to use Method5.
--	3. The user running the script must have been granted SELECT on SYS.USER$.
--Version: 2.0.0



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
	v_table_name varchar2(30);
	v_des_password_hash varchar2(4000);
	v_sha1_password_hash varchar2(4000);

	type string_table is table of varchar2(4000);
	v_users string_table := string_table();

begin
	--Check version.  Raise error if management database is 12c or above.
	--This script does not yet support a 12c management database, but it will work with 12c targets.
	$if DBMS_DB_VERSION.VER_LE_11_2 $then
		null;
	$else
		raise_application_error(-20000, 'This script does not yet work with a 12c management database.');
	$end

	--Gather DBA usernames.  Use dynamic SQL to enable role access.
	execute immediate
	q'[
		select trim(upper(username)) username
		from method5.dba_synch_username
		order by 1
	]'
	bulk collect into v_users;

	--Loop through all relevant DBAs.
	for i in 1 .. v_users.count
	loop
		--Verify account name exists and get password hashes and tablename.
		begin
			execute immediate q'[
				select 'SYNCH_'||name, password, spare4
				from sys.user$
				where name = :username
			]'
			into v_table_name, v_des_password_hash, v_sha1_password_hash
			using v_users(i);
		exception when no_data_found then
			raise_application_error(-20000, 'The user '||v_users(i)||' was not found.  That user must '||
				'first exist on '||sys_context('userenv', 'server_host')||' before it can be copied to other servers.');
		end;

		--Throw error if the user does not have a DES hash.
		--A SHA1 hash is still required for a few databases.
		if v_des_password_hash is null then
			raise_application_error(-20000, 'The user '||v_users(i)||' does not have a DES password hash.'||
				'  Databases with SEC_CASE_SENSITIVE_LOGON=false still require a DES password hash.');
		end if;

		--Maintain account.
		m5_proc(
			p_table_name			=> v_table_name,
			p_table_exists_action	=> 'DROP',
			p_asynchronous			=> false,
			--Example of how to run on only a subset of databaes.
			--p_targets 	=> 'pqdwdv01',
			p_code					=> 
			replace(replace(replace(q'{
				--DBA account management.
				declare
					v_sec_case_sensitive_logon varchar2(4000);

					v_new_password varchar2(4000);
					v_username varchar2(128) := upper('#USERNAME#');

					v_old_password varchar2(4000);
					v_account_status varchar2(4000);
					v_profile varchar2(4000);
					v_has_dba_role number;
				begin
					--Find if this database supports case-sensitive passwords.
					select upper(trim(value))
					into v_sec_case_sensitive_logon
					from v$parameter
					where name = 'sec_case_sensitive_logon';

					--Use SHA1 only if possible
					if v_sec_case_sensitive_logon = 'TRUE' then
						v_new_password := '#SPARE4#';

						select spare4, account_status, profile
						into v_old_password, v_account_status, v_profile
						from sys.user$ join dba_users on sys.user$.name = dba_users.username
						where user$.name = v_username;

					--Else use both.
					else
						v_new_password := '#SPARE4#;#DES#';

						select spare4||';'||user$.password, account_status, profile
						into v_old_password, v_account_status, v_profile
						from sys.user$ join dba_users on sys.user$.name = dba_users.username
						where user$.name = v_username;
					end if;

					--Reset password.
					if nvl(v_old_password, 'NULL') <> v_new_password then
						declare
							v_pw_cannot_be_reused exception;
							pragma exception_init(v_pw_cannot_be_reused, -28007);
						begin
							execute immediate 'alter user '||v_username||' identified by values '''||v_new_password||'''';
							dbms_output.put_line('Password reset.');
						exception when v_pw_cannot_be_reused then
							dbms_output.put_line('Password not changed - password cannot be reused.');
						end;
					end if;

					--Unlock account.
					if v_account_status like '%LOCK%' then
						dbms_output.put_line('Account unlocked.');
						execute immediate 'alter user '||v_username||' account unlock';
					end if;

					--Fix profile.
					if v_profile <> 'DBA_PROFILE' then
						dbms_output.put_line('Profile altered.');
						execute immediate 'alter user '||v_username||' profile dba_profile';
					end if;

					--Grant DBA.
					select count(*)
					into v_has_dba_role
					from dba_role_privs
					where grantee = v_username
						and granted_role = 'DBA';

					if v_has_dba_role = 0 then
						dbms_output.put_line('DBA granted.');
						execute immediate 'grant dba to '||v_username;
					end if;

				--If no account, create one.
				exception when no_data_found then
					execute immediate 'create user '||v_username||' identified by values '''||v_new_password||'''';
					execute immediate 'grant dba to '||v_username;
					execute immediate 'alter user '||v_username||' profile dba_profile';
					dbms_output.put_line('Account created.');
				end;
			}', '#USERNAME#', v_users(i)), '#DES#', v_des_password_hash), '#SPARE4#', v_sha1_password_hash)
		);
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
