--Stop and print an error message if the user is not logged on as the appropriate user.
--Parameters: &1 - Can be one of "must_run_as_sys", "must_not_run_as_sys_and_has_dba", or "must_be_m5_user".

whenever sqlerror exit;
set serveroutput on format truncated verify off;
prompt Checking user...;
declare
	v_count number;

	--Print an error message.
	--This is a bit trickier than you might think.  It's hard to get the text
	--to always line up in SQL*Plus.
	procedure print_error is
	begin
		dbms_output.put_line(' ______  _____   _____    ____   _____   ');
		dbms_output.put_line('|  ____||  __ \ |  __ \  / __ \ |  __ \  ');
		dbms_output.put_line('| |__   | |__) || |__) || |  | || |__) | ');
		dbms_output.put_line('|  __|  |  _  / |  _  / | |  | ||  _  /  ');
		dbms_output.put_line('| |____ | | \ \ | | \ \ | |__| || | \ \  ');
		dbms_output.put_line('|______||_|  \_\|_|  \_\ \____/ |_|  \_\ ');
	end print_error;
begin

	if '&1' = 'must_run_as_sys' then
		if user <> 'SYS' then
			print_error;
			raise_application_error(-20000, 
				'This step must be run as SYS.'||chr(13)||chr(10)||
				'Logon as SYS and re-run.');
		end if;

	elsif '&1' = 'must_not_run_as_sys_and_has_dba' then
		--Ensure the user is not SYS.
		if user = 'SYS' then
			print_error;
			raise_application_error(-20000, 
				'This step must not be run as SYS.'||chr(13)||chr(10)||
				'Logon with a personal DBA account and re-run.');
		end if;

		--Ensure the user has DBA role.
		select count(*) into v_count from dual where sys_context('SYS_SESSION_ROLES', 'DBA') = 'TRUE';

		if v_count = 0 then
			print_error;
			raise_application_error(-20000, 
				'This step must be run as a user with the DBA role.'||chr(13)||chr(10)||
				'Logon with a personal DBA account and re-run.');
		end if;

	elsif '&1' = 'must_be_m5_user' then
		execute immediate 'select count(*) from method5.m5_user where upper(oracle_username) = user'
		into v_count;

		if v_count = 0 then
			print_error;
			raise_application_error(-20000, 
				'This step must be run as a user configured to use Method5.'||chr(13)||chr(10)||
				'Logon with an account registered in METHOD5.M5_USER and re-run.');
		end if;

	else
		print_error;
		raise_application_error(-20000, 'Unexpected parameter.');
	end if;
end;
/
whenever sqlerror continue;
set verify on;
