--Purpose: Contains multiple account maintenance scripts.
--How to use:
--  Run #1 - #4 to perform different account maintenance operations.  Remember to replace all $$VARIABLES$$.
--  Run #5 to install the synchronization function (only needed one time).
--Version: 3.0.0



--------------------------------------------------------------------------------
--#1: Synchronize and unlock account.
--------------------------------------------------------------------------------
--#1A: Ask the user to update their password on one database.

--#1B: Modify and run this code to synchronize passwords based on that one new password hash.
begin
	method5.synch_password_and_unlock(
		p_username        => '$$USERNAME$$',
		p_source_database => '$$DATABASE_NAME$$',
		--Leave this NULL to synchronize on all databases.
		p_targets         => null
	);
end;
/

--#1C: Check the output.
--(You may see an error like "ORA-28007: the password cannot be reused".)
select database_name, to_char(result) from password_synch order by database_name;
select * from password_synch_meta order by date_started;
select * from password_synch_err order by database_name;



--------------------------------------------------------------------------------
--#2: Check account existance and status.
--------------------------------------------------------------------------------
select *
from m5_dba_users
where username like '%$$USERNAME$$%';



--------------------------------------------------------------------------------
--#3: Set a temporary password on all databases.
--------------------------------------------------------------------------------
--#3a: Modify variables and then run this step to unlock, change password, and expire password. 
begin
	m5_proc(
		p_code => q'<
			declare
				v_count number;
			begin
				select count(*)
				into v_count
				from dba_users
				where username = '$$USERNAME$$';

				if v_count = 1 then
					execute immediate 'alter user $$USERNAME$$ account unlock';
					execute immediate 'alter user $$USERNAME$$ identified by "$$TEMP_PASSWORD$$"';
					execute immediate 'alter user $$USERNAME$$ password expire';
					dbms_output.put_line('Account modified.');
				end if;
			end;
		>',
		--Use a list of DBs, lifecycles, host names, etc.
		p_targets => '$$DB1$$,$$DB2$$, ...',
		p_table_name => 'PW_CHANGE',
		p_table_exists_action => 'DROP',
		p_asynchronous => true
	);
end;
/

--#3b: Check the results.  If there are errors you may need to manually fix something.
select database_name, to_char(result) result from pw_change order by database_name;
select * from pw_change_meta order by date_started;
select * from pw_change_err order by database_name;

--Find jobs that have not finished yet:
select * from sys.dba_scheduler_running_jobs where owner = user;

--Stop all jobs from this run (commented out so you don't run it by accident):
-- begin
--     method5.m5_pkg.stop_jobs(p_owner => user, p_table_name => 'pw_change');
-- end;
-- /



--------------------------------------------------------------------------------
--#4: Lock account everywhere.
--------------------------------------------------------------------------------
--#4A: Lock the accounts.
begin
	m5_proc(
		p_code =>
		q'<
			begin
				execute immediate 'alter user $$USERNAME$$ account lock';
			end;
		>',
		--Use a list of DBs, lifecycles, host names, etc.
		--p_targets => '$$DB1$$,$$DB2$$, ...',
		p_table_name => 'LOCK_ACCOUNT',
		p_table_exists_action => 'DROP',
		p_asynchronous => true
	);
end;
/


--#4B: Check the results.  If a database is unavailable you may need to re-run later.
select * from lock_account_meta;
select * from lock_account_err;



--------------------------------------------------------------------------------
--#5: Install synchronization function.  (Only run once by the administrator.)
--------------------------------------------------------------------------------
create or replace procedure method5.synch_password_and_unlock(
	p_username varchar2,
	p_source_database varchar2,
	p_targets varchar2
) authid current_user
/*
	Purpose: Create a PL/SQL block to synchronize a user's password.

	Warning: Do not directly modify this function.  The code is version controlled in the file "Account Maintenance.sql".
*/
is
	v_hash_for_11g varchar2(4000);
	v_hash_for_12c varchar2(4000);
begin
	--Get the password hashes for the user.
	begin
		execute immediate
		replace(replace(q'[
			select
				case
					when generated_from = '12c' then
						regexp_substr(spare4, 'S:[^;]*')
					when generated_from = '11g' then
						case when spare4 is not null and password is not null then
							spare4||';'||password
						else
							spare4||password
						end
				end hash_for_11g,
				case
					when generated_from = '12c' then
						spare4
					when generated_from = '11g' then
						spare4
				end hash_for_12c
			from sys.user$@m5_#SOURCE_DATABASE#
			cross join
			(
				--Detect the version.
				select
					case
						when banner like '%11g%' then '11g'
						when banner like '%12c%' then '12c'
						else 'Unsupported version!'
					end generated_from
				from v$version@m5_#SOURCE_DATABASE#
				where banner like 'Oracle Database%'
			)
			where (password is not null or spare4 is not null)
				and name = trim(upper('#USERNAME#'))
		]'
		, '#SOURCE_DATABASE#', p_source_database)
		, '#USERNAME#', p_username)
		into v_hash_for_11g, v_hash_for_12c;
	exception when no_data_found then
		raise_application_error(-20000,
			'ERROR - Could not find the user '||p_username||' on database '||p_source_database||'.');
	end;

	--Run PL/SQL block to copy the hashes to other database.
	execute immediate
		replace(replace(replace(replace(replace(
		q'[
			begin
				m5_proc(
					p_code =>
					q'!
						begin
							execute immediate 'alter user ##USERNAME## account unlock';

							$if dbms_db_version.ver_le_10 $then
								raise_application_error(-20000, '10g is not yet supported.' );
							$elsif dbms_db_version.ver_le_11 $then
								execute immediate 'alter user ##USERNAME## identified by values ''##11G_HASH##''';
							$elsif dbms_db_version.ver_le_12 $then
								execute immediate 'alter user ##USERNAME## identified by values ''##12C_HASH##''';
							$end

							dbms_output.put_line('Account unlocked and password synchronized.');
						end;
					!',
					p_targets => '##TARGETS##',
					p_table_name => 'PASSWORD_SYNCH',
					p_table_exists_action => 'DROP'
				);
			end;
		]'
	, '##USERNAME##', p_username)
	, '##11G_HASH##', v_hash_for_11g)
	, '##12C_HASH##', v_hash_for_12c)
	, '##TARGETS##', p_targets)
	, chr(10)||'			', chr(10));
end synch_password_and_unlock;
/

