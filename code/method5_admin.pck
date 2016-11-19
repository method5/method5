create or replace package method5.method5_admin authid current_user is
	function generate_remote_install_script return clob;
	function generate_password_reset_one_db return clob;
	function generate_link_test_script(p_database_name varchar2, p_host_name varchar2, p_port_number number) return clob;
	procedure create_and_assign_m5_acl;
	procedure drop_m5_db_links_for_user(p_username varchar2);
	function refresh_all_user_m5_db_links return clob;
	procedure change_m5_user_password;
	procedure change_remote_m5_passwords;
	procedure change_local_m5_link_passwords;
	procedure send_daily_summary_email;
end;
/
create or replace package body method5.method5_admin is
--Copyright (C) 2016 Ventech Solutions, CMS, and Jon Heller.  This program is licensed under the LGPLv3.

/******************************************************************************
 * See administer_method5.md for how to use these methods.
 ******************************************************************************/


--------------------------------------------------------------------------------
--Purpose: Generate a script to install Method5 on remote databases.
function generate_remote_install_script return clob
is
	v_script clob;

	function create_header return clob is
	begin
		return replace(
		q'[
			----------------------------------------
			--Install Method5 on remote target.
			--Run this script as SYS.
			--Do NOT save this output - it contains password hashes and should be regenerated each time.
			----------------------------------------
		]', '			', null);
	end;

	function create_profile return clob is
		v_profile varchar2(128);
	begin
		--Find the current Method5 profile.
		select profile
		into v_profile
		from dba_users
		where username = 'METHOD5';

		--Create profile if it doesn't exist.
		return replace(replace(q'[
			--Create the profile that Method5 uses on the management server, if it doesn't exist.
			declare
				v_count number;
			begin
				select count(*) into v_count from dba_profiles where profile = '#PROFILE#';
				if v_count = 0 then
					execute immediate 'create profile #PROFILE# limit cpu_per_call unlimited';
				end if;
			end;
			/]'||chr(10)
		, '#PROFILE#', v_profile)
		, '			', null);
	end;

	function create_user return clob is
		v_12c_hash varchar2(4000);
		v_11g_hash_without_des varchar2(4000);
		v_11g_hash_with_des varchar2(4000);
		v_profile varchar2(4000);
	begin
		sys.get_method5_hashes(v_12c_hash, v_11g_hash_without_des, v_11g_hash_with_des);

		select profile
		into v_profile
		from dba_users
		where username = 'METHOD5';

		return replace(replace(replace(replace(replace(replace(
		q'[
			--Create the Method5 user with the appropriate hash.
			declare
				v_sec_case_sensitive_logon varchar2(4000);
			begin
				select upper(value)
				into v_sec_case_sensitive_logon
				from v$parameter
				where name = 'sec_case_sensitive_logon';

				--Do nothing if this is the management database - the user already exists.
				if lower(sys_context('userenv', 'db_name')) = '#DB_NAME#' then
					null;
				else
					--Change the hash for 10g and 11g.
					$if dbms_db_version.ver_le_11_2 $then
						if v_sec_case_sensitive_logon = 'TRUE' then
							execute immediate q'!create user method5 profile #PROFILE# identified by values '#11G_HASH_WITHOUT_DES#'!';
						else
							if '#11G_HASH_WITH_DES#' is null then
								raise_application_error(-20000, 'The 10g hash is not available.  You must set '||
									'the target database sec_case_sensitive_logon to TRUE for this to work.');
							else
								execute immediate q'!create user method5 profile #PROFILE# identified by values '#11G_HASH_WITH_DES#'!';
							end if;
						end if;
					--Change the hash for 12c.
					$else
						execute immediate q'!create user method5 profile #PROFILE# identified by values '#12C_HASH#'!';
					$end				
				end if;
			end;
			/]'
		, '#12C_HASH#', nvl(v_12c_hash, v_11g_hash_without_des))
		, '#11G_HASH_WITHOUT_DES#', v_11g_hash_without_des)
		, '#11G_HASH_WITH_DES#', v_11g_hash_with_des)
		, '#PROFILE#', v_profile)
		, '#DB_NAME#', lower(sys_context('userenv', 'db_name')))
		, chr(10)||'			', chr(10))||chr(10);
	end;

	function create_grants return clob is
	begin
		return replace(q'[
				--Grant DBA to method5.
				grant dba to method5;

				--Direct grants for objects that are frequently revoked from PUBLIC, as
				--recommended by the Security Technical Implementation Guide (STIG).
				--Use "with grant option" these will probably also need to be granted to users.
				begin
					for packages in
					(
						select 'grant execute on '||column_value||' to method5 with grant option' v_sql
						from table(sys.odcivarchar2list(
							'DBMS_ADVISOR','DBMS_BACKUP_RESTORE','DBMS_CRYPTO','DBMS_JAVA','DBMS_JAVA_TEST',
							'DBMS_JOB','DBMS_JVM_EXP_PERMS','DBMS_LDAP','DBMS_LOB','DBMS_OBFUSCATION_TOOLKIT',
							'DBMS_PIPE','DBMS_RANDOM','DBMS_SCHEDULER','DBMS_SQL','DBMS_SYS_SQL','DBMS_XMLGEN',
							'DBMS_XMLQUERY','HTTPURITYPE','UTL_FILE','UTL_HTTP','UTL_INADDR','UTL_SMTP','UTL_TCP'
						))
					) loop
						begin
							execute immediate packages.v_sql;
						exception when others then null;
						end;
					end loop;
				end;
				/]'||chr(10)
			,'				', null);
	end;

	function create_audits return clob is
	begin
		return replace(q'[
			--Audit everything done by Method5.
			audit all statements by method5;]'||chr(10)
		,'			', null);
	end;

	function create_trigger return clob is
	begin
		return replace(replace(q'[
			--Prevent Method5 from connecting directly.
			create or replace trigger sys.m5_prevent_direct_logon
			after logon on method5.schema
			/*
				Purpose: Prevent anyone from connecting directly as Method5.
					All Method5 connections must be authenticated by the Method5
					program and go through a database link.

				Note: These checks are not foolproof and it's possible to spoof some
					of these values.  The primary protection of the Method5 comes from
					only using password hashes and nobody ever knowing the password.
					This trigger is another layer of protection, but not a great one.
			*/
			declare
				--Only an ORA-600 error can stop logons for users with either
				--"ADMINISTER DATABASE TRIGGER" or "ALTER ANY TRIGGER".
				--The ORA-600 alsos generate an alert log entry and may warn an adin.
				internal_exception exception;
				pragma exception_init( internal_exception, -600 );

				procedure check_module_for_link is
				begin
					--TODO: This is not tested!
					if sys_context('userenv','module') not like 'oracle@%' then
						raise internal_exception;
					end if;
				end;
			begin
				--Check that the connection comes from the management server.
				if sys_context('userenv', 'session_user') = 'METHOD5'
				   and lower(sys_context('userenv', 'host')) not like '%#HOST#%' then
					raise internal_exception;
				end if;

				--Check that the connection comes over a database link.
				$if dbms_db_version.ver_le_9 $then
					check_module_for_link;
				$elsif dbms_db_version.ver_le_10 $then
					check_module_for_link;
				$elsif dbms_db_version.ver_le_11_1 $then
					check_module_for_link;
				$else
					if sys_context('userenv', 'dblink_info') is null then
						raise internal_exception;
					end if;
				$end
			end;
			/]'||chr(10)
		,'#HOST#', lower(sys_context('userenv', 'server_host')))
		,'			', null);
	end;

	function create_footer return clob is
	begin
		return replace(
		q'[
			----------------------------------------
			--End of Method5 remote target install.
			----------------------------------------]'||chr(10)
		, '			', null);
	end;

begin
 	v_script := v_script ||create_header;
	v_script := v_script ||create_profile;
	v_script := v_script ||create_user;
	v_script := v_script ||create_grants;
	v_script := v_script ||create_audits;
	v_script := v_script ||create_trigger;
	v_script := v_script ||create_footer;

	return v_script;
end generate_remote_install_script;


--------------------------------------------------------------------------------
--Purpose: Generate a script to reset the password of one remote database.
function generate_password_reset_one_db return clob is
	v_12c_hash varchar2(4000);
	v_11g_hash_without_des varchar2(4000);
	v_11g_hash_with_des varchar2(4000);
	v_plsql clob;
begin
	--Get the appropriate hashes.
	sys.get_method5_hashes(v_12c_hash, v_11g_hash_without_des, v_11g_hash_with_des);

	--Create PL/SQL block to apply new password hash.
	v_plsql := replace(replace(replace(replace(q'[
		----------------------------------------
		--Reset Method5 password on one remote database.
		--
		--Do NOT save this output.  It contains password hashes that should be kept
		--secret and need to be regenerated each time.
		----------------------------------------
		declare
			v_profile_name varchar2(128);
			v_password_reuse_max_before  varchar2(100);
			v_password_reuse_time_before varchar2(100);
			v_sec_case_sensitive_logon varchar2(100);
		begin
			--Save profile values before the changes.
			select
				profile,
				max(case when resource_name = 'PASSWORD_REUSE_MAX' then limit else null end),
				max(case when resource_name = 'PASSWORD_REUSE_TIME' then limit else null end)
			into v_profile_name, v_password_reuse_max_before, v_password_reuse_time_before
			from dba_profiles
			where profile in
			(
				select profile
				from dba_users
				where username = 'METHOD5'
			)
			group by profile;

			--Find out if the good hash can be used.
			select upper(value)
			into v_sec_case_sensitive_logon
			from v$parameter
			where name = 'sec_case_sensitive_logon';

			--Change the profile resources to UNLIMITED.
			--The enables password changes even if it's a re-use.
			execute immediate 'alter profile '||v_profile_name||' limit password_reuse_max unlimited';
			execute immediate 'alter profile '||v_profile_name||' limit password_reuse_time unlimited';

			--Unlock the account.
			execute immediate 'alter user method5 account unlock';

			--Change the hash for 10g and 11g.
			$if dbms_db_version.ver_le_11_2 $then
				if v_sec_case_sensitive_logon = 'TRUE' then
					execute immediate q'!alter user method5 identified by values '#11G_HASH_WITHOUT_DES#'!';
				else
					if '#11G_HASH_WITH_DES#' is null then
						raise_application_error(-20000, 'The 10g hash is not available.  You must set '||
							'the target database sec_case_sensitive_logon to TRUE for this to work.');
					else
						execute immediate q'!alter user method5 identified by values '#11G_HASH_WITH_DES#'!';
					end if;
				end if;
			--Change the hash for 12c.
			$else
				execute immediate q'!alter user method5 identified by values '#12C_HASH#'!';
			$end				

			--Change the profile back to their original values.
			execute immediate 'alter profile '||v_profile_name||' limit password_reuse_max '||v_password_reuse_max_before;
			execute immediate 'alter profile '||v_profile_name||' limit password_reuse_time '||v_password_reuse_time_before;

			exception when others then
				--Change the profiles back to their original values.
				execute immediate 'alter profile '||v_profile_name||' limit password_reuse_max '||v_password_reuse_max_before;
				execute immediate 'alter profile '||v_profile_name||' limit password_reuse_time '||v_password_reuse_time_before;

				raise_application_error(-20000, 'Error resetting password: '||dbms_utility.format_error_stack||dbms_utility.format_error_backtrace);
		end;
		/]'
		, '#12C_HASH#', v_12c_hash)
		, '#11G_HASH_WITHOUT_DES#', v_11g_hash_without_des)
		, '#11G_HASH_WITH_DES#', v_11g_hash_with_des)
		, chr(10)||'		', chr(10));

	return v_plsql;
end;


--------------------------------------------------------------------------------
--Purpose: Drop all Method5 database links for a specific user.
function generate_link_test_script(p_database_name varchar2, p_host_name varchar2, p_port_number number) return clob is
	v_plsql clob;
begin
	v_plsql := replace(replace(replace(replace(replace(q'[
		----------------------------------------
		--#1: Test a Method5 database link.
		----------------------------------------

		--#1A: Create a temporary procedure to test the database link on the Method5 schema.
		create or replace procedure method5.temp_procedure_test_db_link(p_database_name varchar2) is
			v_number number;
		begin
			execute immediate 'select 1 from dual@m5_'||p_database_name into v_number;
		end;
		$$SLASH$$

		--#1B: Run the temporary procedure to check the link.  This should run without errors.
		begin
			method5.temp_procedure_test_db_link('$$DATABASE_NAME$$');
		end;
		$$SLASH$$

		--#1C: Drop the temporary procedure.
		drop procedure method5.temp_procedure_test_db_link;


		----------------------------------------
		--#2: Drop, create, and test a Method5 database link.
		----------------------------------------

		--#2A: Create a temporary procedure to drop, create, and test a custom Method5 link.
		create or replace procedure method5.temp_procedure_test_db_link2
		(
			p_database_name varchar2,
			p_host_name     varchar2,
			p_port_number   number
		) is
			v_dummy varchar2(4000);
			v_database_link_not_found exception;
			pragma exception_init(v_database_link_not_found, -2024);
		begin
			begin
				execute immediate 'drop database link M5_'||p_database_name;
			exception when v_database_link_not_found then null;
			end;

			execute immediate replace(replace(replace(
			'
				create database link M5_#DATABASE_NAME#
				connect to METHOD5 identified by not_a_real_password_yet

				--   _____ _    _          _   _  _____ ______    _______ _    _ _____  _____
				--  / ____| |  | |   /\   | \ | |/ ____|  ____|  |__   __| |  | |_   _|/ ____|  _
				-- | |    | |__| |  /  \  |  \| | |  __| |__        | |  | |__| | | | | (___   (_)
				-- | |    |  __  | / /\ \ | . ` | | |_ |  __|       | |  |  __  | | |  \___ \
				-- | |____| |  | |/ ____ \| |\  | |__| | |____      | |  | |  | |_| |_ ____) |  _
				--  \_____|_|  |_/_/    \_\_| \_|\_____|______|     |_|  |_|  |_|_____|_____/  (_)
				--
				--The SQL*Net connect string will be different for every everyone.
				--You will have to figure out what works in your environment.

				using ''
				(
					description=
					(
						address=
							(protocol=tcp)
							(host=#HOST_NAME#)
							(port=#PORT_NUMBER#)
					)
					(
						connect_data=
							(service_name=#DATABASE_NAME#)
					)
				) ''
			'
			, '#DATABASE_NAME#', p_database_name)
			, '#HOST_NAME#', p_host_name)
			, '#PORT_NUMBER#', p_port_number)
			;

			sys.m5_change_db_link_pw(
				p_m5_username     => 'METHOD5',
				p_dblink_username => 'METHOD5',
				p_dblink_name     => 'M5_'||p_database_name);
			commit;

			execute immediate 'select * from dual@M5_'||p_database_name into v_dummy;
		end;
		$$SLASH$$

		--#2B: Test the custom link.  This should run without errors.
		begin
			method5.temp_procedure_test_db_link2('$$DATABASE_NAME$$', '$$HOST_NAME$$', '$$PORT_NUMBER$$');
		end;
		$$SLASH$$

		--#2C: Drop the temporary procedure.
		drop procedure method5.temp_procedure_test_db_link2;
	]'
	, '$$SLASH$$', '/')
	, '$$DATABASE_NAME$$', p_database_name)
	, '$$HOST_NAME$$', p_host_name)
	, '$$PORT_NUMBER$$', p_port_number)
	, chr(10)||'		', chr(10));

	return v_plsql;
end generate_link_test_script;


--------------------------------------------------------------------------------
--Purpose: Create and assign an ACL so Method5 can send emails from definer's
--	rights objects.
--
--This code is mostly from this site:
--	http://qdosmsq.dunbar-it.co.uk/blog/2013/02/cannot-send-emails-or-read-web-servers-from-oracle-11g/
procedure create_and_assign_m5_acl is
	v_smtp_out_server varchar2(4000);
begin
	select value
	into v_smtp_out_server
	from v$parameter where name = 'smtp_out_server';

	execute immediate
	q'[
		begin
			dbms_network_acl_admin.create_acl(
				acl         => 'method5_email_access.xml',
				description => 'Allows access to UTL_HTTP, UTL_SMTP etc',
				principal   => 'METHOD5',
				is_grant    => true,
				privilege   => 'connect',
				start_date  => systimestamp,
				end_date    => null
			);
			commit;
		end;
	]';

	execute immediate
	q'[
		begin
			dbms_network_acl_admin.assign_acl(
				acl        => 'method5_email_access.xml',
				host       => :v_smtp_out_server,
				lower_port => 25,
				upper_port => 25);
			commit;
		end;
	]'
	using v_smtp_out_server;
end create_and_assign_m5_acl;


--------------------------------------------------------------------------------
--Purpose: Drop all Method5 database links for a specific user.
--	This may be a good idea when someone leaves your organization or chanes roles.
procedure drop_m5_db_links_for_user(p_username varchar2) is
	v_temp_procedure clob;
begin
	--Loop through the links for specific users.
	for links in
	(
		select dba_db_links.*
			,row_number() over (partition by owner order by db_link) first_when_1
			,row_number() over (partition by owner order by db_link desc) last_when_1
		from dba_db_links
		where db_link like 'M5!_%' escape '!'
			and db_link <> 'M5_INSTALL_DB_LINK'
			and owner = trim(upper(p_username))
		order by 1,2
	) loop
		--Begin procedure.
		if links.first_when_1 = 1 then
			v_temp_procedure := 'create or replace procedure '||links.owner||'.temp_drop_m5_links is'||chr(10)||
				'begin'||chr(10);
		end if;

		--Add execute immediate to drop a link.
		v_temp_procedure := v_temp_procedure || '   execute immediate ''drop database link '||links.db_link||''';'||chr(10);

		--End procedure and run it.
		if links.last_when_1 = 1 then
			--End procedure.
			v_temp_procedure := v_temp_procedure || 'end;';

			--Run statement to create the procedure.
			execute immediate v_temp_procedure;

			--Run the procedure.
			execute immediate 'begin '||links.owner||'.temp_drop_m5_links; end;';

			--Drop the procedure.
			execute immediate 'drop procedure '||links.owner||'.temp_drop_m5_links';
		end if;
	end loop;
end drop_m5_db_links_for_user;


--------------------------------------------------------------------------------
--Purpose: Change the Method5 user password, as well as the install link.
--	This should almost always be followed up by change_remote_m5_passwords.
procedure change_m5_user_password is
	--Password contains mixed case, number, and special characters.
	--This should meet most password complexity requirements.
	--It uses multiple sources for a truly random password.
	v_password_youll_never_know varchar2(30) :=
		replace(replace(dbms_random.string('p', 10), '"', null), '''', null)||
		rawtohex(dbms_crypto.randombytes(5))||
		substr(to_char(systimestamp, 'FF9'), 1, 6)||
		'#$*@';
	v_count number;
begin
	--Change the user password.
	execute immediate 'alter user method5 identified by "'||v_password_youll_never_know||'"';

	--Does the database link exist?
	select count(*)
	into v_count
	from dba_db_links
	where db_link = 'M5_INSTALL_DB_LINK'
		and owner = 'METHOD5';

	--If the link exists, drop it by creating and executing a procedure on that schema
	if v_count = 1 then
		execute immediate '
			create or replace procedure method5.temp_proc_manage_db_link1 is
			begin
				execute immediate ''drop database link m5_install_db_link'';
			end;
			';
		execute immediate 'begin method5.temp_proc_manage_db_link1; end;';
		execute immediate 'drop procedure method5.temp_proc_manage_db_link1';
	end if;

	--Create database link for retrieving the database link hash.
	execute immediate replace(
	q'[
		create or replace procedure method5.temp_proc_manage_db_link2 is
		begin
			execute immediate '
				create database link m5_install_db_link
				connect to method5
				identified by "$$PASSWORD$$"
				using '' (invalid name since we do not need to make a real connection) ''
			';
		end;
	]', '$$PASSWORD$$', v_password_youll_never_know);
	execute immediate 'begin method5.temp_proc_manage_db_link2; end;';
	execute immediate 'drop procedure method5.temp_proc_manage_db_link2';

	--Clear shared pool in case the password is stored anywhere.
	execute immediate 'alter system flush shared_pool';
end change_m5_user_password;


--------------------------------------------------------------------------------
--Purpose: Change the Method5 password on remote databases.
--	This should be run after change_local_method5_password.
procedure change_remote_m5_passwords is
	v_12c_hash varchar2(4000);
	v_11g_hash_without_des varchar2(4000);
	v_11g_hash_with_des varchar2(4000);
	v_password_change_plsql varchar2(4000);
begin
	--Get the password hashes.
	sys.get_method5_hashes(v_12c_hash, v_11g_hash_without_des, v_11g_hash_with_des);

	--Create statement to change passwords.
	v_password_change_plsql := replace(replace(replace(replace(q'[
		declare
			v_sec_case_sensitive_logon varchar2(100);
		begin
			select value
			into v_sec_case_sensitive_logon
			from v$parameter
			where name = 'sec_case_sensitive_logon';


			--Do nothing if this is the management database - the user already exists.
			if lower(sys_context('userenv', 'db_name')) = '#DB_NAME#' then
				null;
			else
				--Change the hash for 10g and 11g.
				$if dbms_db_version.ver_le_11_2 $then
					if v_sec_case_sensitive_logon = 'TRUE' then
						execute immediate q'!alter user method5 identified by values '#11G_HASH_WITHOUT_DES#'!';
					else
						if '#11G_HASH_WITH_DES#' is null then
							raise_application_error(-20000, 'The 10g hash is not available.  You must set '||
								'the target database sec_case_sensitive_logon to TRUE for this to work.');
						else
							execute immediate q'!alter user method5 identified by values '#11G_HASH_WITH_DES#'!';
						end if;
					end if;
				--Change the hash for 12c.
				$else
					execute immediate q'!alter user method5 identified by values '#12C_HASH#'!';
				$end				
			end if;
		end;
	]'
	, '#12C_HASH#', v_12c_hash)
	, '#11G_HASH_WITHOUT_DES#', v_11g_hash_without_des)
	, '#11G_HASH_WITH_DES#', v_11g_hash_with_des)
	, '#DATABASE_NAME#', sys_context('userenv', 'db_name'));

	--Change password on all databases.
	method5.m5_pkg.run(p_code => v_password_change_plsql);

	--TODO(?): Remove from the audit trail?
end change_remote_m5_passwords;


--------------------------------------------------------------------------------
--Purpose: Change the local Method5 database link passwords.
--	This should be run after change_remote_m5_passwords.
procedure change_local_m5_link_passwords is
	v_sql varchar2(32767);
begin
	--Each Method5 database link.
	for links in
	(
		select *
		from dba_db_links
		where owner = 'METHOD5'
			and db_link <> 'M5_INSTALL_DB_LINK'
		order by db_link
	) loop
		--Build procedure string to drop and recdreate link.
		v_sql := replace(replace(q'<
			create or replace procedure method5.m5_temp_procedure_drop_link is
			begin
				--Drop link.
				execute immediate 'drop database link ##DB_LINK_NAME##';

				--Create link.
				execute immediate q'!
					create database link ##DB_LINK_NAME##
					connect to method5
					identified by not_a_real_password_yet
					using '##CONNECT_STRING##'
				!';
			end;
		>'
		,'##DB_LINK_NAME##', links.db_link)
		,'##CONNECT_STRING##', links.host);

		--Create, execute, and drop the procedure.
		execute immediate v_sql;
		execute immediate 'begin method5.m5_temp_procedure_drop_link; end;';
		execute immediate 'drop procedure method5.m5_temp_procedure_drop_link';

		--Change the password.
		sys.m5_change_db_link_pw(
			p_m5_username => 'METHOD5',
			p_dblink_username => 'METHOD5',
			p_dblink_name => links.db_link);
	end loop;
end change_local_m5_link_passwords;


--------------------------------------------------------------------------------
--Purpose: Drop Method5 database links for all users and refresh them.
--	This might be useful after massive changes, such as resetting the Method5
--	password.  Although Method5.Run automatically updates a user's links, users
--	may also be using links manually, so it may help to update links for them.
function refresh_all_user_m5_db_links return clob is
	v_status clob;
	pragma autonomous_transaction;
begin
	--Add header.
	v_status := substr(replace('
		----------------------------------------
		--Method5 database link refresh.
		----------------------------------------

		Username                          Drop Status   Add Status
		------------------------------    -----------   ----------'
	, '	', null), 2);

	--Loop through all users with M5 database links and the refresh job.
	for users in
	(
		select distinct owner
		from dba_db_links
		where db_link like 'M5\_%' escape '\'
			and owner not in ('METHOD5')
			and owner in
			(
				select owner
				from dba_scheduler_jobs
				where job_name = 'M5_LINK_REFRESH_JOB'
			)
		order by owner
	) loop
		begin
			--Add user to status.
			v_status := v_status||chr(10)||rpad(users.owner, 30, ' ');

			--Drop their links.
			v_status := v_status||'    ';
			drop_m5_db_links_for_user(users.owner);
			v_status := v_status||'Done';

			--Run their refresh job.
			v_status := v_status||'          ';
			dbms_scheduler.run_job(users.owner||'.M5_LINK_REFRESH_JOB', use_current_session => false);
			v_status := v_status||'Running';

		exception when others then
			v_status := v_status||'ERROR: '||
				sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace;
		end;
	end loop;

	--Return a status for each user.
	return v_status||chr(10);
end refresh_all_user_m5_db_links;


--------------------------------------------------------------------------------
--Purpose: Send an email to the administrator to quickly see if Method5 is working.
procedure send_daily_summary_email is

	v_admin_email_address varchar2(4000);
	v_email_body varchar2(32767) := replace(q'[
		<html>
		<head>
			<style type="text/css">
			span.error {color: red; font-weight: bold;}
			span.warning {color: orange; font-weight: bold;}
			span.ok {color: green; font-weight: bold;}
			</style>
		</head>
		<body>
			<h4>1: Duplicate configuration data</h4>
		##DUPLICATES##
			<h4>2: Housekeeping Jobs</h4>
		##HOUSEKEEPING##
			<h4>3: Global Data Dictionary Jobs</h4>
		##GLOBAL_DATA_DICTIONARY##
			<h4>4: Invalid Access Attempts</h4>
		##INVALID_ACCESS_ATTEMPTS##
			<h4>5: Statistics</h4>
				In the past 24 hours:<br><br>
				<table>
					<tr><td>Jobs Ran</td><td>##JOBS_RAN##</td></tr>
					<tr><td>Targets Expected</td><td>##TARGETS_EXPECTED##</td></tr>
					<tr><td>Target Errors</td><td>##TARGET_ERRORS##</td></tr>
					<tr><td>Rows Returned</td><td>##ROWS_RETURNED##</td></tr>
				</table>
		</body>
		</html>]'
	, chr(10)||'		', chr(10));

	---------------------------------------
	function get_admin_email_address return varchar2 is
		v_email_address varchar2(4000);
	begin
		select string_value
		into v_email_address
		from method5.m5_config
		where config_name = 'Administrator Email Address';

		return v_email_address;
	end get_admin_email_address;

	---------------------------------------
	procedure add_duplicate_check(p_email_body in out clob) is
		v_sql clob;
		v_database_name_query varchar2(32767);
		v_duplicates varchar2(4000);
		v_html varchar2(32767);
	begin
		begin
			--Get the database name query.
			select string_value
			into v_database_name_query
			from method5.m5_config
			where config_name = 'Database Name Query';

			--Get duplicates, if any.
			v_sql := replace(
			q'[
				with m5_databases as
				(
					--Only select INSTANCE_NUMBER = 1 to avoid RAC duplicates.
					select database_name, host_name, lifecycle_status, line_of_business, cluster_name
					from
					(
						#DATABASE_NAME_QUERY#
					)
					where instance_number = 1
				)
				--Concatenate duplicates.
				select listagg(object_name, ', ') within group (order by object_name) object_names
				from
				(
					--Find duplicates.
					select object_name
					from
					(
						select distinct trim(upper(database_name))    object_name from m5_databases where database_name    is not null union all
						select distinct trim(upper(host_name))        object_name from m5_databases where host_name        is not null union all
						select distinct trim(upper(lifecycle_status)) object_name from m5_databases where lifecycle_status is not null union all
						select distinct trim(upper(line_of_business)) object_name from m5_databases where line_of_business is not null union all
						select distinct trim(upper(cluster_name))     object_name from m5_databases where cluster_name     is not null union all
						--Duplicate within database names.
						--Unless you're using RAC you cannot have the same database name on different hosts.
						select trim(upper(database_name)) database_name
						from m5_database
						where cluster_name is null
						group by trim(upper(database_name))
						having count(*) >= 2
						--Test data to create an artificial duplicate.
						--union all select 'PQRS' from dual
					)
					group by object_name
					having count(*) > 1
					order by 1
				)
			]', '#DATABASE_NAME_QUERY#', v_database_name_query);

			execute immediate v_sql into v_duplicates;

			--Print duplicates, if any.
			if v_duplicates is null then
				v_html := '		<span class="ok">None</span>';
			else
				v_html := '		<span class="error">ERROR - Check M5_DATABASE for these duplicates - '||v_duplicates||'</span>';
			end if;

		exception when others then
			v_html := '<span class="error">ERROR WITH DUPLICATE CHECK'||chr(10)||dbms_utility.format_error_stack||dbms_utility.format_error_backtrace||'</span>';
		end;

		p_email_body := replace(p_email_body, '##DUPLICATES##', v_html);
	end add_duplicate_check;

	---------------------------------------
	procedure add_housekeeping(p_email_body in out clob) is
		v_job_status varchar2(4000);
	begin
		--Scheduled job status with HTML.
		select
			'		CLEANUP_M5_TEMP_TABLES_JOB: '   ||case when temp_tables    = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||temp_tables   ||'</span>' end||'<br>'||chr(10)||
			'		CLEANUP_M5_TEMP_TRIGGERS_JOB: ' ||case when temp_triggers  = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||temp_triggers ||'</span>' end||'<br>'||chr(10)||
			'		CLEANUP_REMOTE_M5_OBJECTS_JOB: '||case when remote_objects = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||remote_objects||'</span>' end||'<br>'||chr(10)||
			'		DIRECT_M5_GRANTS_JOB: '         ||case when direct_grants  = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||direct_grants ||'</span>' end||'<br>'||chr(10)
			job_status
		into v_job_status
		from
		(
			--Last job status, with missing values.
			select
				nvl(max(case when job_name = 'CLEANUP_M5_TEMP_TABLES_JOB'    then status else null end), 'Job did not run') temp_tables,
				nvl(max(case when job_name = 'CLEANUP_M5_TEMP_TRIGGERS_JOB'  then status else null end), 'Job did not run') temp_triggers,
				nvl(max(case when job_name = 'CLEANUP_REMOTE_M5_OBJECTS_JOB' then status else null end), 'Job did not run') remote_objects,
				nvl(max(case when job_name = 'DIRECT_M5_GRANTS_JOB'          then status else null end), 'Job did not run') direct_grants
			from
			(
				--Job status.
				select job_name, log_date, status, additional_info
					,row_number() over (partition by job_name order by log_date desc) last_when_1
				from dba_scheduler_job_run_details
				where log_date > systimestamp - 2
					and job_name in
					(
						'CLEANUP_M5_TEMP_TABLES_JOB',
						'CLEANUP_M5_TEMP_TRIGGERS_JOB',
						'CLEANUP_REMOTE_M5_OBJECTS_JOB',
						'DIRECT_M5_GRANTS_JOB'
					)
			)
			where last_when_1 = 1
			order by job_name
		);

		--Add the status
		p_email_body := replace(p_email_body, '##HOUSEKEEPING##', v_job_status);
	end add_housekeeping;

	---------------------------------------
	procedure add_global_data_dictionary(p_email_body in out clob) is
		v_date_started date;
		v_targets_completed number;
		v_targets_expected number;
		v_html varchar2(32767);
		v_table_or_view_does_not_exist exception;
		pragma exception_init(v_table_or_view_does_not_exist, -942);
	begin
		--Foreach table in the global data dictionary.
		for tables in
		(
			select owner, table_name
			from method5.m5_global_data_dictionary
			--Test data to create errors.
			--union all select user owner, 'asdf3' table_name from dual
			order by table_name
		) loop
			begin
				--Get metadata.
				execute immediate '
					select date_started, targets_completed, targets_expected
					from '||tables.owner||'.'||tables.table_name||'_meta'
				into v_date_started, v_targets_completed, v_targets_expected;

				--Write message.
				if v_date_started < sysdate - 1 then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="error">'||v_targets_completed||'/'||v_targets_expected||' Last start date: '||to_char(v_date_started, 'YYYY-MM-DD')||'</span><br>'||chr(10);
				elsif v_targets_completed = v_targets_expected then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="ok">'||v_targets_completed||'/'||v_targets_expected||'</span><br>'||chr(10);
				elsif v_targets_completed < v_targets_expected then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="warning">'||v_targets_completed||'/'||v_targets_expected||'</span><br>'||chr(10);
				else
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="error">'||v_targets_completed||'/'||v_targets_expected||' Last start date: '||to_char(v_date_started, 'YYYY-MM-DD')||'</span><br>'||chr(10);
				end if;
			--Write message if there is an error.
			exception
				when v_table_or_view_does_not_exist then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="error">does not exist.</span><br>'||chr(10);
				when no_data_found then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="error">is empty.</span><br>'||chr(10);
				when others then
					v_html := v_html || '		' || upper(tables.table_name)||': <span class="error">could not get data - '||sqlerrm||'.</span><br>||chr(10)';
			end;
		end loop;

		--Add the status
		p_email_body := replace(p_email_body, '##GLOBAL_DATA_DICTIONARY##', v_html);
	end add_global_data_dictionary;

	---------------------------------------
	procedure add_invalid_access_attempts(p_email_body in out clob) is
		v_invalid_access_attempts number;
		v_html varchar2(32767);
	begin
		--Count the attempts.
		select count(*) total
		into v_invalid_access_attempts
		from method5.m5_audit
		where access_control_error is not null
			and create_date > sysdate - 1;

		--Create message.
		if v_invalid_access_attempts = 0 then
			v_html := '		<span class="ok">None</span><br>';
		elsif v_invalid_access_attempts = 1 then
			v_html := '		<span class="error">There was 1 invalid access attempt.  Check M5_AUDIT for details.</span><br>';
		else
			v_html := '		<span class="error">There were '||v_invalid_access_attempts||' invalid access attempt.  Check M5_AUDIT for details.</span><br>';
		end if;

		--Add the HTML.
		p_email_body := replace(p_email_body, '##INVALID_ACCESS_ATTEMPTS##', v_html);
	end add_invalid_access_attempts;

	---------------------------------------
	procedure add_statistics(p_email_body in out clob) is
		v_total_jobs varchar2(100);
		v_expected_targets varchar2(100);
		v_target_errors varchar2(100);
		v_rows_returned varchar2(100);
	begin
		--Get stats for last day.
		select
			trim(to_char(count(*), '999,999,999,999')) total_jobs,
			trim(to_char(sum(targets_expected), '999,999,999,999')) expected_targets,
			trim(to_char(sum(targets_with_errors), '999,999,999,999')) target_errors,
			trim(to_char(sum(num_rows), '999,999,999,999')) rows_returned
		into v_total_jobs, v_expected_targets, v_target_errors, v_rows_returned
		from method5.m5_audit
		where create_date > sysdate - 1;

		--Replace the variables.
		p_email_body := replace(p_email_body, '##JOBS_RAN##', v_total_jobs);
		p_email_body := replace(p_email_body, '##TARGETS_EXPECTED##', v_expected_targets);
		p_email_body := replace(p_email_body, '##TARGET_ERRORS##', v_target_errors);
		p_email_body := replace(p_email_body, '##ROWS_RETURNED##', v_rows_returned);
	end add_statistics;

	---------------------------------------
	function get_subject_line(p_email_body in clob) return varchar2 is
	begin
		if instr(p_email_body, 'class="error"') > 0 or instr(p_email_body, 'class="warning"') > 0 then
			return 'Method5 daily summary report (contains errors)';
		else
			return 'Method5 daily summary report (everything is OK)';
		end if;
	end get_subject_line;

begin
	--Fill out template.
	add_duplicate_check(v_email_body);
	add_housekeeping(v_email_body);
	add_global_data_dictionary(v_email_body);
	add_invalid_access_attempts(v_email_body);
	add_statistics(v_email_body);

	--Send the email.
	v_admin_email_address := get_admin_email_address;
	utl_mail.send(
		sender => v_admin_email_address,
		recipients => v_admin_email_address,
		subject => get_subject_line(v_email_body),
		message => v_email_body,
		mime_type => 'text/html'
	);
end send_daily_summary_email;


end;
/
