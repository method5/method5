--Purpose: Contains multiple account maintenance scripts.
--How to use:
--  #1 is a pre-built procedure that satifsy 90% of your account maintenance requirements.
--  #2, #3, and #4 demonstrate that you can still use regular Method5 functionality for custom account maintenance.
--  Remember to replace all &VARIABLES before running.
--Version: 4.0.0



--------------------------------------------------------------------------------
--#1: Synchronize accounts.  90% of account maintenance can be handled by this program.
--------------------------------------------------------------------------------

-- Synchronize user across any number of databases.
begin
	m5_synch_user(
		p_username                    => '&USERNAME',  -- The name of the database account, required.
		p_targets                     => '&TARGETS',   -- A comma-separated list of databases, environments, etc.  NULL means all targets.
		p_table_name                  => 'SYNCH_USER', -- The name of the table to store results, metadata, and errors from Method5 execution.
		p_create_user_if_not_exists   => false,        -- Create the account if it does not exist.  A random password will be used if P_SYNCH_PASSWORD is set to FALSE.
		p_create_user_clause          => '',           -- Anything additional you would like to specify when creating the user, like 'quota unlimited on users'.
		p_synch_password_from_this_db => '&DB_NAME',   -- Synchronize the password and use this database as the source of the password hash.
		p_unlock_if_locked            => false,        -- Unlock the account if it is locked.
		p_profile                     => '&PROFILE',   -- Set the account to this profile if the profile is available.
		p_role_privs                  => '',           -- Grant a comma-separated list of roles granted to the user, if they exist.  For example: 'role1,role2'.
		p_sys_privs                   => ''            -- Grant a comma-separated list of system privileges to the user, if they exist.  For example: 'create session,create table'.
	);
end;
/

--Check the results, metadata, and errors.
--Remember results are asynchronous and may still be generating.
select database_name, to_char(result) from synch_user order by database_name;
select * from synch_user_meta order by date_started;
select * from synch_user_err order by database_name;

--Jobs that have not finished:
select * from sys.dba_scheduler_running_jobs where owner = user;

--Stop all jobs from this run (commented out so you don't run it by accident):
-- begin
--   method5.m5_pkg.stop_jobs(p_owner=> user, p_table_name=> 'synch_user');
-- end;
-- /



--------------------------------------------------------------------------------
--#2: Check account existance and status with global data dictionary.
--------------------------------------------------------------------------------
select *
from m5_dba_users
where username like '%&USERNAME%';



--------------------------------------------------------------------------------
--#3: Use M5_PROC to set a temporary password.
--  DANGER!  AVOID THIS AND USE M5_SYNCH_USER INSTEAD WHENEVER POSSIBLE.
--  Sending passwords over cleartext is a horrible security practice.
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
				where username = '&USERNAME$$';

				if v_count = 1 then
					execute immediate 'alter user &USERNAME account unlock';
					execute immediate 'alter user &USERNAME identified by "&TEMP_PASSWORD"';
					execute immediate 'alter user &USERNAME password expire';
					dbms_output.put_line('Account modified.');
				end if;
			end;
		>',
		--Use a list of DBs, lifecycles, host names, etc.
		p_targets => '&DB1,&DB2, ...',
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
--#4: Use M5 function to lock account everywhere.
--------------------------------------------------------------------------------

--#4A: Lock the accounts.
select * from table(m5('alter user &USERNAME account lock'));


--#4B: Check results, metadata, and errors after the run is complete.
select * from m5_results;
select * from m5_metadata;
select * from m5_errors;
