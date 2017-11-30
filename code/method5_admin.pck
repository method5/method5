create or replace package method5.method5_admin authid current_user is
	function generate_remote_install_script(p_allow_run_as_sys varchar2 default 'YES', p_allow_run_shell_script varchar2 default 'YES') return clob;
	procedure set_local_and_remote_sys_key(p_db_link in varchar2);
	function set_all_missing_sys_keys return clob;
	function generate_password_reset_one_db return clob;
	function generate_link_test_script(p_link_name varchar2, p_database_name varchar2, p_host_name varchar2, p_port_number number) return clob;
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
--Copyright (C) 2016 Jon Heller, Ventech Solutions, and CMS.  This program is licensed under the LGPLv3.
--See http://method5.github.io/ for more information.


/******************************************************************************
 * See administer_method5.md for how to use these methods.
 ******************************************************************************/


--------------------------------------------------------------------------------
--Purpose: Generate a script to install Method5 on remote databases.
function generate_remote_install_script(p_allow_run_as_sys varchar2 default 'YES', p_allow_run_shell_script varchar2 default 'YES') return clob
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
		]', '			', null)||chr(10);
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
			/]'||chr(10)||chr(10)
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
		, chr(10)||'			', chr(10))||chr(10)||chr(10);
	end;

	function create_grants return clob is
	begin
		return replace(replace(q'[
				--REQUIRED: Create and grant role of minimum Method5 remote target privileges.
				--Do NOT remove or change this block or Method5 will not work properly.
				declare
					v_role_conflicts exception;
					pragma exception_init(v_role_conflicts, -1921);
				begin
					begin
						execute immediate 'create role m5_minimum_remote_privs';
					exception when v_role_conflicts then null;
					end;

					execute immediate 'grant m5_minimum_remote_privs to method5';

					execute immediate 'grant create session to m5_minimum_remote_privs';
					execute immediate 'grant create table to m5_minimum_remote_privs';
					execute immediate 'grant create procedure to m5_minimum_remote_privs';
					execute immediate 'grant execute on sys.dbms_sql to m5_minimum_remote_privs';
				end;
				#SLASH#

				--REQUIRED: Grant Method5 unlimited access to the default tablespace.
				--You can change the quota or tablespace but Method5 must have at least a little space. 
				declare
					v_default_tablespace varchar2(128);
				begin
					select property_value
					into v_default_tablespace
					from database_properties
					where property_name = 'DEFAULT_PERMANENT_TABLESPACE';

					execute immediate 'alter user method5 quota unlimited on '||v_default_tablespace;
				end;
				#SLASH#

				--REQUIRED: Create and grant role for additional Method5 remote target privileges.
				--Do NOT remove or change this block or Method5 will not work properly.
				declare
					v_role_conflicts exception;
					pragma exception_init(v_role_conflicts, -1921);
				begin
					begin
						execute immediate 'create role m5_optional_remote_privs';
					exception when v_role_conflicts then null;
					end;

					execute immediate 'grant m5_optional_remote_privs to method5';
				end;
				#SLASH#

				--OPTIONAL, but recommended: Grant DBA to Method5 role.
				--WARNING: The privilege granted here is the upper-limit applied to ALL users.
				--  If you only want to block specific users from having DBA look at the table M5_USER_CONFIG.
				--
				--If you don't trust Method5 or are not allowed to grant DBA, you can manually modify this block.
				--Simply removing it would make Method5 worthless.  But you may want to replace it with something
				--less powerful.  For example, you could make a read-only Method5 with these two commented out lines:
				--	grant select any table to m5_optional_remote_privs;
				--	grant select any dictionary to m5_optional_remote_privs;
				grant dba to m5_optional_remote_privs;

				--OPTIONAL, but recommended: Grant access to a table useful for password management and synchronization.
				grant select on sys.user$ to m5_optional_remote_privs;

				--OPTIONAL, but recommended: Direct grants for objects that are frequently revoked from PUBLIC, as
				--recommended by the Security Technical Implementation Guide (STIG).
				--Use "with grant option" since these will probably also need to be granted to users.
				begin
					for packages in
					(
						select 'grant execute on '||column_value||' to m5_optional_remote_privs with grant option' v_sql
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
				/]'||chr(10)||chr(10)
			,'				', null)
			,'#SLASH#', '/');
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
				--The ORA-600 also generates an alert log entry and may warn an admin.
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
			/]'||chr(10)||chr(10)
		,'#HOST#', lower(sys_context('userenv', 'server_host')))
		,'			', null);
	end;

	function create_sys_m5_runner return clob is
	begin
		return replace(replace(replace(
		q'[
			--Create table to hold Session GUIDs.
			create table sys.m5_sys_session_guid
			(
				session_guid raw(16),
				constraint m5_sys_session_guid_pk primary key(session_guid)
			);
			comment on table sys.m5_sys_session_guid is 'Session GUID to prevent Method5 SYS replay attacks.';


			--Create package to enable remote execution of commands as SYS.
			create or replace package sys.m5_runner is

			--Copyright (C) 2017 Jon Heller, Ventech Solutions, and CMS.  This program is licensed under the LGPLv3.
			--Version 1.0.1
			--Read this page if you're curious about this program or concerned about security implications:
			--https://github.com/method5/method5/blob/master/user_guide.md#security
			procedure set_sys_key(p_sys_key in raw);
			procedure run_as_sys(p_encrypted_command in raw);
			procedure get_column_metadata
			(
				p_plsql_block                in     varchar2,
				p_encrypted_select_statement in     raw,
				p_has_column_gt_30           in out number,
				p_has_long                   in out number,
				p_explicit_column_list       in out varchar2,
				p_explicit_expression_list   in out varchar2
			);

			end;
			#SLASH#


			create or replace package body sys.m5_runner is

			/******************************************************************************/
			--Throw an error if the connection is not remote and not from an expected host. 
			procedure validate_remote_connection is
				procedure check_module_for_link is
				begin
					--TODO: This is not tested!
					if sys_context('userenv','module') not like 'oracle@%' then
						raise_application_error(-20200, 'This procedure was called incorrectly.');
					end if;
				end;
			begin
				--Check that the connection comes from the management server.
				if sys_context('userenv', 'session_user') = 'METHOD5'
					and lower(sys_context('userenv', 'host')) not like '%#HOST#%' then
						raise_application_error(-20201, 'This procedure was called incorrectly.');
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
						raise_application_error(-20203, 'This procedure was called incorrectly.');
					end if;
				$end
			end validate_remote_connection;

			/******************************************************************************/
			--Set LINK$ to contain the secret key to control SYS access, but ONLY if the key
			--is not currently set.
			--LINK$ is a special table that not even SELECT ANY DICTIONARY can select from
			--since 10g.
			procedure set_sys_key(p_sys_key in raw) is
				v_count number;
			begin
				--Only allow specific remote connections.
				validate_remote_connection;

				--Disable bind variables so nobody can spy on keys.
				execute immediate 'alter session set statistics_level = basic';

				--Throw error if the remote key already exists.
				select count(*) into v_count from dba_db_links where owner = 'SYS' and db_link like 'M5_SYS_KEY%';
				if v_count = 1 then
					raise_application_error(-20204, 'The SYS key already exists on the remote database.  '||
						'If you want to reset the SYS key, run these steps:'||chr(10)||
						'1. On the remote database, as SYS: DROP DATABASE LINK M5_SYS_KEY;'||chr(10)||
						'2. On the local database: re-run this procedure.');
				end if;

				--Create database link.
				execute immediate q'!
					create database link m5_sys_key
					connect to not_a_real_user
					identified by "Not a real password"
					using 'Not a real connect string'
				!';

				--Modify the link to store the sys key.
				update sys.link$
				set passwordx = p_sys_key
				--The name may be different because of GLOBAL_NAMES setting.
				where name like 'M5_SYS_KEY%'
					and userid = 'NOT_A_REAL_USER'
					and owner# = (select user_id from dba_users where username = 'SYS');

				commit;
			end set_sys_key;

			/******************************************************************************/
			--Only allow connections from the right place, with the right encryption key,
			--and the right session id.
			function authenticate_and_decrypt(p_encrypted_command in raw) return varchar2 is
				v_sys_key raw(32);
				v_command varchar2(32767);
				v_guid raw(16);
				v_count number;
				pragma autonomous_transaction;
			begin
				--Only allow specific remote connections.
				validate_remote_connection;

				--Disable bind variables so nobody can spy on keys.
				execute immediate 'alter session set statistics_level = basic';

				--Get the key.
				begin
					select passwordx
					into v_sys_key
					from sys.link$
					where owner# = (select user_id from dba_users where username = 'SYS')
						and name like 'M5_SYS_KEY%';
				exception when no_data_found then
					raise_application_error(-20205, 'The SYS key was not installed correctly.  '||
						'See the file administer_method5.md for help.'||chr(10)||
						sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
				end;

				--Decrypt the command.
				begin
					v_command := utl_i18n.raw_to_char(
						dbms_crypto.decrypt
						(
							src => p_encrypted_command,
							typ => dbms_crypto.encrypt_aes256 + dbms_crypto.chain_cbc + dbms_crypto.pad_pkcs5,
							key => v_sys_key
						),
						'AL32UTF8'
					);
				exception when others then
					raise_application_error(-20206, 'There was an error during decryption, the SYS key is probably '||
						'installed incorrectly.  See the file administer_method5.md for help.'||chr(10)||
						sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
				end;

				--Remove the GUID at the front.
				v_guid := hextoraw(substr(v_command, 1, 32));
				v_command := substr(v_command, 33);

				--Check that the GUID is new, to prevent a replay attack.
				select count(*) into v_count from sys.m5_sys_session_guid where session_guid = v_guid;
				if v_count >= 1 then
					raise_application_error(-20207, 'The SESSION_ID has already been run.  '||
						'This procedure can only be called from Method5 and cannot reuse a SESSION_ID.');
				end if;

				--Store the GUID, which acts as a session ID.
				--This is why the function is an autonomous transaction - the session ID must
				--be saved even if everything else fails.
				insert into sys.m5_sys_session_guid values(v_guid);
				commit;

				return v_command;
			end authenticate_and_decrypt;

			/******************************************************************************/
			--Run a (properly encrypted) command as SYS.
			procedure run_as_sys(p_encrypted_command in raw) is
				v_command varchar2(32767);
			begin
				v_command := authenticate_and_decrypt(p_encrypted_command);

				--Run the command.
				execute immediate v_command;

				--Do NOT commit.  The caller must commit to preserve the rowcount for the feedback message.
			end;

			/******************************************************************************/
			--Get column metadata as SYS.  This procedure is only meant to work with the
			--private procedure Method5.m5_pkg.get_column_metadata, using input encrypted
			--with Method5.m5_pkg.get_encrypted_raw.
			procedure get_column_metadata
			(
				p_plsql_block                in     varchar2,
				p_encrypted_select_statement in     raw,
				p_has_column_gt_30           in out number,
				p_has_long                   in out number,
				p_explicit_column_list       in out varchar2,
				p_explicit_expression_list   in out varchar2
			) is
				v_select_statement varchar2(32767);
			begin
				v_select_statement := authenticate_and_decrypt(p_encrypted_select_statement);

				execute immediate p_plsql_block
				using v_select_statement
					,out p_has_column_gt_30
					,out p_has_long
					,out p_explicit_column_list
					,out p_explicit_expression_list;
			end get_column_metadata;

			end;
			#SLASH#


			grant execute on sys.m5_runner to method5;]'||chr(10)||chr(10)
		, chr(10)||'			', chr(10))
		,'#HOST#', lower(sys_context('userenv', 'server_host')))
		,'#SLASH#', '/');
	end create_sys_m5_runner;

	function create_sys_m5_run_shell_script return clob is
	begin
		return replace(replace(
		q'[
			create or replace procedure sys.m5_run_shell_script(p_script in clob, p_table_name in varchar2) is
			--------------------------------------------------------------------------------
			--Purpose: Execute a shell script and store results in a table.
			--Parameters:
			--	p_script - A shell script that starts with a shebang and will be
			--		run by the Oracle software owner.
			--	p_table_name - The table to store the results.
			--Side-Effects: Creates the table P_TABLE_NAME in the Method5 schema, with results.
			--Requires:
			--	Must be run as SYS because only SYS jobs are run as the Oracle owner.
			--	Only works on Unix and Linux.
			--	Oracle software owner must be able to read and write to /tmp/
			--Notes:
			--	The scheduler overhead always adds a few seconds to the run time.
			--
			--Copyright (C) 2017 Jon Heller, Ventech Solutions, and CMS.  This program is licensed under the LGPLv3.
			--Version 1.0.3
			--Read this page if you're curious about this program or concerned about security implications:
			--https://github.com/method5/method5/blob/master/user_guide.md#security

				--This unique string prevents operating system duplicates.
				c_unique_string varchar2(100) := to_char(sysdate, 'YYYY_MM_DD_HH24_MI_SS_')||rawtohex(sys_guid());
				--This random number prevents Oracle duplicates.
				c_random_number varchar2(100) := to_char(trunc(dbms_random.value*100000000));

				c_script_file_name constant varchar2(100) := 'm5_script_'||c_unique_string||'.sh';
				c_redirect_file_name constant varchar2(100) := 'm5_redirect_'||c_unique_string||'.sh';
				c_output_file_name constant varchar2(100) := 'm5_output_'||c_unique_string||'.out';

				c_temp_path constant varchar2(100) := '/tmp/method5/';
				c_directory constant varchar2(100) := 'M5_TMP_DIR';

				v_job_failed exception;
				pragma exception_init(v_job_failed, -27369);

				pragma autonomous_transaction;


				------------------------------------------------------------------------------
				procedure create_file(p_directory varchar2, p_file_name varchar2, p_text clob) is
					v_file_type utl_file.file_type;
				begin
					v_file_type := utl_file.fopen(p_directory, p_file_name, 'W', 32767);
					utl_file.put(v_file_type, p_text);
					utl_file.fclose(v_file_type);
				end create_file;


				------------------------------------------------------------------------------
				--Purpose: Check if the directory /tmp/method5 exists.
				function does_tmp_method5_dir_not_exist return boolean is
					v_file_type utl_file.file_type;
					v_invalid_file_operation exception;
					pragma exception_init(v_invalid_file_operation, -29283);
				begin
					--Try to create a test file on the directory.
					--If it fails, then the directory does not exist.
					create_file(
						p_directory => c_directory,
						p_file_name => 'test_if_method5_directory_exists.txt',
						p_text      => 'This file only exists to quickly check the existence of a file.'
					);

					--The directory exists if we got this far.
					return false;
				exception when v_invalid_file_operation then
					return true;
				end does_tmp_method5_dir_not_exist;


				------------------------------------------------------------------------------
				--Purpose: Create the Method5 operating system directory.
				procedure create_os_directory is
				begin
					--Create program.
					dbms_scheduler.create_program (
						program_name        => 'M5_TEMP_MKDIR_PROGRAM_'||c_random_number,
						program_type        => 'EXECUTABLE',
						program_action      => '/usr/bin/mkdir',
						number_of_arguments => 1,
						comments            => 'Temporary program created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Create program arguments.
					dbms_scheduler.define_program_argument(
						program_name      => 'M5_TEMP_MKDIR_PROGRAM_'||c_random_number,
						argument_position => 1,
						argument_name     => 'M5_TEMP_MKDIR_ARGUMENT_1',
						argument_type     => 'VARCHAR2'
					);

					dbms_scheduler.enable('M5_TEMP_MKDIR_PROGRAM_'||c_random_number);

					--Create job.
					dbms_scheduler.create_job (
						job_name     => 'M5_TEMP_MKDIR_JOB_'||c_random_number,
						program_name => 'M5_TEMP_MKDIR_PROGRAM_'||c_random_number,
						comments     => 'Temporary job created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Create job argument values.
					dbms_scheduler.set_job_argument_value(
						job_name       => 'M5_TEMP_MKDIR_JOB_'||c_random_number,
						argument_name  => 'M5_TEMP_MKDIR_ARGUMENT_1',
						argument_value => '/tmp/method5/'
					);

					--Run job synchronously.  This works even if JOB_QUEUE_PROCESSES=0.
					begin
						dbms_scheduler.run_job('M5_TEMP_MKDIR_JOB_'||c_random_number);
					exception when others then
						--Ignore errors if the file exists.
						if sqlerrm like '%File exists%' then
							null;
						else
							raise;
						end if;
					end;

				end create_os_directory;


				------------------------------------------------------------------------------
				--Purpose: Create the Oracle directory, if it does not exist.
				procedure create_ora_dir_if_not_exists is
					v_count number;
				begin
					--Check for existing directory.
					select count(*)
					into v_count
					from all_directories
					where directory_name = c_directory
						and directory_path = c_temp_path;

					--Create if it doesn't exist.
					if v_count = 0 then
						execute immediate 'create or replace directory '||c_directory||' as '''||c_temp_path||'''';
					end if;
				end create_ora_dir_if_not_exists;


				------------------------------------------------------------------------------
				--Parameters:
				--	p_mode: The chmod mode, for example: u+x
				--	p_file: The full path to a single file.  Cannot include multiple files
				--		or any globbing.  E.g., no "*" in the file name.
				procedure chmod(p_mode varchar2, p_file varchar2) is
				begin
					--Create program.
					dbms_scheduler.create_program (
						program_name        => 'M5_TEMP_CHMOD_PROGRAM_'||c_random_number,
						program_type        => 'EXECUTABLE',
						program_action      => '/usr/bin/chmod',
						number_of_arguments => 2,
						comments            => 'Temporary program created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Create program arguments.
					dbms_scheduler.define_program_argument(
						program_name      => 'M5_TEMP_CHMOD_PROGRAM_'||c_random_number,
						argument_position => 1,
						argument_name     => 'M5_TEMP_CHMOD_ARGUMENT_1',
						argument_type     => 'VARCHAR2'
					);
					dbms_scheduler.define_program_argument(
						program_name      => 'M5_TEMP_CHMOD_PROGRAM_'||c_random_number,
						argument_position => 2,
						argument_name     => 'M5_TEMP_CHMOD_ARGUMENT_2',
						argument_type     => 'VARCHAR2'
					);

					dbms_scheduler.enable('M5_TEMP_CHMOD_PROGRAM_'||c_random_number);

					--Create job.
					dbms_scheduler.create_job (
						job_name     => 'M5_TEMP_CHMOD_JOB_'||c_random_number,
						program_name => 'M5_TEMP_CHMOD_PROGRAM_'||c_random_number,
						comments     => 'Temporary job created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Create job argument values.
					dbms_scheduler.set_job_argument_value(
						job_name       => 'M5_TEMP_CHMOD_JOB_'||c_random_number,
						argument_name  => 'M5_TEMP_CHMOD_ARGUMENT_1',
						argument_value => p_mode
					);
					dbms_scheduler.set_job_argument_value(
						job_name       => 'M5_TEMP_CHMOD_JOB_'||c_random_number,
						argument_name  => 'M5_TEMP_CHMOD_ARGUMENT_2',
						argument_value => p_file
					);

					--Run job synchronously.  This works even if JOB_QUEUE_PROCESSES=0.
					dbms_scheduler.run_job('M5_TEMP_CHMOD_JOB_'||c_random_number);
				end chmod;


				------------------------------------------------------------------------------
				procedure run_script(p_full_path_to_file varchar2) is
				begin
					--Create program.
					dbms_scheduler.create_program (
						program_name   => 'M5_TEMP_RUN_PROGRAM_'||c_random_number,
						program_type   => 'EXECUTABLE',
						program_action => p_full_path_to_file,
						enabled        => true,
						comments       => 'Temporary program created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Create job.
					dbms_scheduler.create_job (
						job_name     => 'M5_TEMP_RUN_JOB_'||c_random_number,
						program_name => 'M5_TEMP_RUN_PROGRAM_'||c_random_number,
						comments     => 'Temporary job created for Method5.  Created on: '||to_char(systimestamp, 'YYYY-MM-DD HH24:MI:SS')
					);

					--Run job synchronously.  This works even if JOB_QUEUE_PROCESSES=0.
					dbms_scheduler.run_job('M5_TEMP_RUN_JOB_'||c_random_number);
				end run_script;


				------------------------------------------------------------------------------
				procedure create_external_table(p_directory varchar2, p_script_output_file_name varchar2) is
				begin
					execute immediate '
					create table sys.m5_temp_output_'||c_random_number||'(output varchar2(4000))
					organization external
					(
						type oracle_loader default directory '||p_directory||'
						access parameters
						(
							records delimited by newline
							fields terminated by ''only_one_line_never_terminate_fields''
							missing field values are null
						)
						location ('''||p_script_output_file_name||''')
					)
					reject limit unlimited';
				end create_external_table;


				------------------------------------------------------------------------------
				--Purpose: Drop new jobs, programs, and tables so they don't clutter the data dictionary.
				procedure drop_new_objects is
				begin
					--Note how the "M5_TEMP" is double hard-coded.
					--This ensure we will never, ever, drop the wrong SYS object.

					--Drop new jobs.
					for jobs_to_drop in
					(
						select replace(job_name, 'M5_TEMP') job_name
						from user_scheduler_jobs
						where job_name like 'M5_TEMP%'||c_random_number
						order by job_name
					) loop
						dbms_scheduler.drop_job('M5_TEMP'||jobs_to_drop.job_name);
					end loop;

					--Drop new programs.
					for programs_to_drop in
					(
						select replace(program_name, 'M5_TEMP') program_name
						from user_scheduler_programs
						where program_name like 'M5_TEMP%'||c_random_number
						order by program_name
					) loop
						dbms_scheduler.drop_program('M5_TEMP'||programs_to_drop.program_name);
					end loop;

					--Drop new tables.
					for tables_to_drop in
					(
						select replace(table_name, 'M5_TEMP') table_name
						from user_tables
						where table_name like 'M5_TEMP%'||c_random_number
						order by table_name
					) loop
						--Hard-code the M5_TEMP_STD to ensure that we never, ever, ever drop the wrong table.
						execute immediate 'drop table M5_TEMP'||tables_to_drop.table_name||' purge';
					end loop;
				end drop_new_objects;


				------------------------------------------------------------------------------
				--Purpose: Drop old jobs, programs, and tables that may not have been properly dropped before.
				--  This may happen if previous runs did not end cleanly.
				procedure cleanup_old_objects is
				begin
					--Note how the "M5_TEMP" is double hard-coded.
					--This ensure we will never, ever, drop the wrong SYS object.

					--Delete all non-running Method5 temp jobs after 2 days.
					for jobs_to_drop in
					(
						select replace(job_name, 'M5_TEMP') job_name
						from user_scheduler_jobs
						where job_name like 'M5_TEMP%'
							and replace(comments, 'Temporary job created for Method5.  Created on: ') < to_char(systimestamp - interval '2' day, 'YYYY-MM-DD HH24:MI:SS')
							and job_name not in (select job_name from user_scheduler_running_jobs)
						order by job_name
					) loop
						dbms_scheduler.drop_job('M5_TEMP'||jobs_to_drop.job_name);
					end loop;

					--Delete all Method5 temp programs after 2 days.
					for programs_to_drop in
					(
						select replace(program_name, 'M5_TEMP') program_name
						from user_scheduler_programs
						where program_name like 'M5_TEMP%'
							and replace(comments, 'Temporary program created for Method5.  Created on: ') < to_char(systimestamp - interval '2' day, 'YYYY-MM-DD HH24:MI:SS')
						order by program_name
					) loop
						dbms_scheduler.drop_program('M5_TEMP'||programs_to_drop.program_name);
					end loop;

					--Drop old tables after 7 days.
					--The tables don't use any space and are unlikely to ever be noticed
					--so it doesn't hurt to keep them around for a while.
					for tables_to_drop in
					(
						select replace(object_name, 'M5_TEMP') table_name
						from user_objects
						where object_type = 'TABLE'
							and object_name like 'M5_TEMP_STD%'
							and created < systimestamp - interval '7' day
						order by object_name
					) loop
						execute immediate 'drop table M5_TEMP'||tables_to_drop.table_name||' purge';
					end loop;
				end cleanup_old_objects;
			begin
				--Create directories if necessary.
				create_ora_dir_if_not_exists;

				if does_tmp_method5_dir_not_exist then
					create_os_directory;
					chmod('700', c_temp_path);
					--Drop some objects now because chmod will be called again later.
					drop_new_objects;
				end if;

				--Create empty output file in case nothing gets written later.  External tables require a file to exist.
				create_file(c_directory, c_output_file_name, null);

				--Create script file, that will write data to standard output.
				create_file(c_directory, c_script_file_name, p_script);

				--Create script redirect file, that executes script and redirects output to the output file.
				--This is necessary because redirection does not work in Scheduler.
				create_file(c_directory, c_redirect_file_name,
					'#!/bin/sh'||chr(10)||
					'chmod 700 '||c_temp_path||c_script_file_name||chr(10)||
					'chmod 600 '||c_temp_path||c_output_file_name||chr(10)||
					c_temp_path||c_script_file_name||' > '||c_temp_path||c_output_file_name||' 2>'||chr(38)||'1'
				);

				--Chmod the redirect file.
				--The CHMOD job is slow, so most chmoding is done inside the redirect script.
				--Unfortunately CHMOD through the scheduler does not support "*", it would throw this error:
				--ORA-27369: job of type EXECUTABLE failed with exit code: 1 chmod: WARNING: can't access /tmp/method5/m5*.out
				chmod('700', c_temp_path||c_redirect_file_name);

				--Run script and redirect output and error to other files.
				--(External table preprocessor script doesn't work in our environments for some reason.)
				begin
					run_script(c_temp_path||c_redirect_file_name);
				exception when v_job_failed then
					null;
				end;

				--Create external tables to read the output.
				create_external_table(c_directory, c_output_file_name);

				--Create table with results.
				--(A view would have some advantages here, but would also require a lot of
				--extra permissions on the underlying tables and directories.)
				execute immediate replace(replace(
				q'!
					create table method5.#TABLE_NAME# nologging pctfree 0 as
					select rownum line_number, cast(output as varchar2(4000)) output from M5_TEMP_OUTPUT_#RANDOM_NUMBER#
				!', '#RANDOM_NUMBER#', c_random_number), '#TABLE_NAME#', p_table_name);

				--Cleanup.
				drop_new_objects;
				cleanup_old_objects;
			end m5_run_shell_script;
			#SLASH#
		]'||chr(10)||chr(10)
		, chr(10)||'			', chr(10))
		,'#SLASH#', '/'); --'--Fix PL/SQL Developer parser bug.
	end create_sys_m5_run_shell_script;


	function create_privilege_limiter return clob is
	begin
		return null;
	end create_privilege_limiter;


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
	--Validate input.
	if trim(p_allow_run_as_sys) is null or lower(trim(p_allow_run_as_sys)) not in ('yes', 'no') then
		raise_application_error(-20000, 'P_ALLOW_RUN_AS_SYS must be either "YES" or "NO".');
	end if;
	if trim(p_allow_run_shell_script) is null or lower(trim(p_allow_run_shell_script)) not in ('yes', 'no') then
		raise_application_error(-20000, 'P_ALLOW_RUN_SHELL_SCRIPT must be either "YES" or "NO".');
	end if;
	if lower(trim(p_allow_run_as_sys)) = 'no' and lower(trim(p_allow_run_shell_script)) = 'yes' then
		raise_application_error(-20000, 'The RUN_AS_SYS feature must be enabled in order to use the shell script feature.');
	end if;

 	v_script := v_script || create_header;
	v_script := v_script || create_profile;
	v_script := v_script || create_user;
	v_script := v_script || create_grants;
	v_script := v_script || create_audits;
	v_script := v_script || create_trigger;
	if lower(trim(p_allow_run_as_sys)) = 'yes' then
		v_script := v_script || create_sys_m5_runner;
	end if;
	if lower(trim(p_allow_run_shell_script)) = 'yes' then
		v_script := v_script || create_sys_m5_run_shell_script;
	end if;
	v_script := v_script || create_privilege_limiter;
	v_script := v_script || create_footer;

	return v_script;
end generate_remote_install_script;


--------------------------------------------------------------------------------
--Create a local and remote key for SYS access.
procedure set_local_and_remote_sys_key(p_db_link in varchar2) is
	v_count number;
	v_clean_db_link varchar2(128) := trim(upper(p_db_link));
	v_sys_key raw(32);
begin
	--Throw error if the sys key already exists locally.
	select count(*) into v_count from method5.m5_sys_key where db_link = v_clean_db_link;
	if v_count = 1 then
		raise_application_error(-20208, 'The SYS key for this DB_LINK already exists on the master database.  '||
			'If you want to reset the SYS keys, run these steps:'||chr(10)||
			'1. On the local database: DELETE FROM METHOD5.M5_SYS_KEY WHERE DB_LINK = '''||	v_clean_db_link||''';'||chr(10)||
			'2. On the remote database, as SYS: DROP DATABASE LINK M5_SYS_KEY;'||chr(10)||
			'3. On the local database: re-run this procedure.');
	end if;

	--Create new SYS key.
	v_sys_key := dbms_crypto.randombytes(number_bytes => 32);

	--Save the sys key locally.
	insert into method5.m5_sys_key values(v_clean_db_link, v_sys_key);

	--Set the sys key remotely.
	execute immediate replace('
		begin
			sys.m5_runner.set_sys_key@#DB_LINK#(:sys_key);
		end;
	', '#DB_LINK#', v_clean_db_link)
	using v_sys_key;

	--Commit changes.
	commit;

exception when others then
	rollback;
	raise;
end set_local_and_remote_sys_key;


--------------------------------------------------------------------------------
--Set all the missing SYS keys and return the status of the keys.
function set_all_missing_sys_keys return clob is
	type string_nt is table of varchar2(32767);
	type string_aat is table of string_nt index by varchar2(32767);
	v_status string_aat;
	v_report clob := q'[
----------------------------------------
-- Status of all SYS keys.
--
-- For more specific error information try to set a specific key like this:
--  begin
--    method5.method5_admin.set_local_and_remote_sys_key('M5_MYLINK');
--  end;
--  /
----------------------------------------

]';
	v_status_index varchar2(32767);
	pragma autonomous_transaction;

	--Convert a nested table into a comma-separated and indented list.
	function get_list_with_newlines(p_list string_nt) return clob is
		v_list clob;
	begin
		--Concatenate list.
		if p_list is null or p_list.count = 0 then
			v_list := '<none>';
		else
			--Start with the second item and ignore the "<none>" if there are more items.
			for i in 1 .. p_list.count loop
				--Skip the first "<none>" if there are more than one rows.
				if i = 1 and p_list.count > 1 and p_list(i) = '<none>' then
					null;
				else
					v_list := v_list || ',' || p_list(i);
					if i <> p_list.count and mod(i, 10) = 0 then
						v_list := v_list || chr(10) || '	';
					end if;
				end if;
			end loop;
			v_list := substr(v_list, 2);
		end if;

		--Return the list.
		return v_list;
	end get_list_with_newlines;

begin
	--Set some existing statuses.  Remove them later if they're not needed.
	v_status('Keys Previously Set') := string_nt('<none>');
	v_status('Keys Set') := string_nt('<none>');

	--Add status for each link to the report.
	for missing_links in
	(
		select
			dba_db_links.db_link,
			case when m5_sys_key.db_link is not null then 'Yes' else 'No' end sys_key_exists
		from dba_db_links
		left join method5.m5_sys_key
			on dba_db_links.db_link = m5_sys_key.db_link
		where owner = 'METHOD5'
			and dba_db_links.db_link like 'M5%'
			and lower(replace(dba_db_links.db_link, 'M5_')) in
				(select lower(database_name) from m5_database)
			and dba_db_links.db_link <> 'M5_INSTALL_DB_LINK'
		order by dba_db_links.db_link
	) loop
		begin
			if missing_links.sys_key_exists = 'Yes' then
				v_status('Keys Previously Set') := v_status('Keys Previously Set') multiset union string_nt(missing_links.db_link);
			else
				method5.method5_admin.set_local_and_remote_sys_key(missing_links.db_link);
				v_status('Keys Set') := v_status('Keys Set') multiset union string_nt(missing_links.db_link);
			end if;
		exception when others then
			if v_status.exists('Error ORA'||sqlcode) then
				v_status('Error ORA'||sqlcode) := v_status('Error ORA'||sqlcode) multiset union string_nt(missing_links.db_link);
			else
				v_status('Error ORA'||sqlcode) := string_nt(missing_links.db_link);
			end if;
		end;
	end loop;

	--Create report of statuses.
	v_status_index := v_status.first;
	while v_status_index is not null
	loop
		v_report := v_report || v_status_index || chr(10) || '	' || get_list_with_newlines(v_status(v_status_index)) || chr(10) || chr(10);
		v_status_index := v_status.next(v_status_index);
	end loop;

	--Return report.
	return v_report;
end set_all_missing_sys_keys;


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
function generate_link_test_script(p_link_name varchar2, p_database_name varchar2, p_host_name varchar2, p_port_number number) return clob is
	v_plsql clob;
begin
	--Check for valid link name to ensure naming standard is maintained.
	if trim(upper(p_link_name)) not like 'M5\_%' escape '\' then
		raise_application_error(-20000, 'All Method5 links must start with M5_.');
	end if;

	--Create script.
	v_plsql := replace(replace(replace(replace(replace(replace(q'[
		----------------------------------------
		--#1: Test a Method5 database link.
		----------------------------------------

		--#1A: Create a temporary procedure to test the database link on the Method5 schema.
		create or replace procedure method5.temp_procedure_test_link(p_link_name varchar2) is
			v_number number;
		begin
			execute immediate 'select 1 from dual@'||p_link_name into v_number;
		end;
		$$SLASH$$

		--#1B: Run the temporary procedure to check the link.  This should run without errors.
		begin
			method5.temp_procedure_test_link('$$LINK_NAME$$');
		end;
		$$SLASH$$

		--#1C: Drop the temporary procedure.
		drop procedure method5.temp_procedure_test_link;


		----------------------------------------
		--#2: Drop, create, and test a Method5 database link.
		----------------------------------------

		--#2A: Create a temporary procedure to drop, create, and test a custom Method5 link.
		create or replace procedure method5.temp_procedure_test_link2
		(
			p_link_name     varchar2,
			p_database_name varchar2,
			p_host_name     varchar2,
			p_port_number   number
		) is
			v_dummy varchar2(4000);
			v_database_link_not_found exception;
			pragma exception_init(v_database_link_not_found, -2024);
		begin
			--Check for valid link name to ensure naming standard is maintained.
			if trim(upper(p_link_name)) not like 'M5\_%' escape '\' then
				raise_application_error(-20000, 'All Method5 links must start with M5_.');
			end if;

			begin
				execute immediate 'drop database link '||p_link_name;
			exception when v_database_link_not_found then null;
			end;

			execute immediate replace(replace(replace(replace(
			'
				create database link #LINK_NAME#
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
			, '#LINK_NAME#', p_link_name)
			, '#DATABASE_NAME#', p_database_name)
			, '#HOST_NAME#', p_host_name)
			, '#PORT_NUMBER#', p_port_number)
			;

			sys.m5_change_db_link_pw(
				p_m5_username     => 'METHOD5',
				p_dblink_username => 'METHOD5',
				p_dblink_name     => p_link_name);
			commit;

			execute immediate 'select * from dual@'||p_link_name into v_dummy;
		end;
		$$SLASH$$

		--#2B: Test the custom link.  This should run without errors.
		begin
			method5.temp_procedure_test_link2('$$LINK_NAME$$', '$$DATABASE_NAME$$', '$$HOST_NAME$$', '$$PORT_NUMBER$$');
		end;
		$$SLASH$$

		--#2C: Drop the temporary procedure.
		drop procedure method5.temp_procedure_test_link2;
	]'
	, '$$SLASH$$', '/')
	, '$$LINK_NAME$$', p_link_name)
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
	, '#DATABASE_NAME#', lower(sys_context('userenv', 'db_name')));

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

	v_admin_email_sender varchar2(4000);
	v_admin_email_recipients varchar2(4000);

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
			<h4>1: Duplicate Configuration Data</h4>
		##DUPLICATES##
			<h4>2: Housekeeping Jobs</h4>
		##HOUSEKEEPING##
			<h4>3: Global Data Dictionary Jobs</h4>
		##GLOBAL_DATA_DICTIONARY##
			<h4>4: Invalid Access Attempts</h4>
		##INVALID_ACCESS_ATTEMPTS##
			<h4>5: Timed-Out Jobs</h4>
		##TIMED_OUT_JOBS##
			<h4>6: Serious Errors</h4>
		##SERIOUS_ERRORS##
			<h4>7: Statistics</h4>
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
	procedure get_admin_email_addresses(p_sender_address out varchar2, p_recipient_addresses out varchar2)
	is
	begin
		--Get configuration information.
		select min(string_value) sender_address
			,listagg(string_value, ',') within group (order by string_value) recipients
		into p_sender_address, p_recipient_addresses
		from method5.m5_config
		where config_name = 'Administrator Email Address';
	end get_admin_email_addresses;

	---------------------------------------
	procedure add_duplicate_check(p_email_body in out clob) is
		v_duplicates varchar2(4000);
		v_html varchar2(32767);
	begin
		begin
			--Get duplicates, if any.
			with m5_databases as
			(
				--Only select INSTANCE_NUMBER = 1 to avoid RAC duplicates.
				select database_name, host_name, lifecycle_status, line_of_business, cluster_name
				from
				(
					select
						database_name,
						host_name,
						lifecycle_status,
						line_of_business,
						cluster_name,
						to_char(row_number() over (partition by database_name order by instance_name)) instance_number
					from method5.m5_database
				)
				where instance_number = 1
			)
			--Concatenate duplicates.
			select listagg(object_name, ', ') within group (order by object_name) object_names
			into v_duplicates
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
			);

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
			'		DIRECT_M5_GRANTS_JOB: '         ||case when direct_grants  = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||direct_grants ||'</span>' end||'<br>'||chr(10)||
			'		STOP_TIMED_OUT_JOBS_JOB: '      ||case when timed_out_jobs = 'SUCCEEDED' then '<span class="ok">SUCCEEDED</span>' else '<span class="error">'||timed_out_jobs||'</span>' end||'<br>'||chr(10)
			job_status
		into v_job_status
		from
		(
			--Last job status, with missing values.
			select
				nvl(max(case when job_name = 'CLEANUP_M5_TEMP_TABLES_JOB'    then status else null end), 'Job did not run') temp_tables,
				nvl(max(case when job_name = 'CLEANUP_M5_TEMP_TRIGGERS_JOB'  then status else null end), 'Job did not run') temp_triggers,
				nvl(max(case when job_name = 'CLEANUP_REMOTE_M5_OBJECTS_JOB' then status else null end), 'Job did not run') remote_objects,
				nvl(max(case when job_name = 'DIRECT_M5_GRANTS_JOB'          then status else null end), 'Job did not run') direct_grants,
				nvl(max(case when job_name = 'STOP_TIMED_OUT_JOBS_JOB'       then status else null end), 'Job did not run') timed_out_jobs
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
						'DIRECT_M5_GRANTS_JOB',
						'STOP_TIMED_OUT_JOBS_JOB'
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
	procedure add_timed_out_jobs(p_email_body in out clob) is
		v_html varchar2(32767);
		v_count number;
	begin
		--Count the number of timeouts.
		select count(*)
		into v_count
		from method5.m5_job_timeout
		where stop_date > systimestamp - 1;

		--If there are none then there is nothing to display.
		if v_count = 0 then
			v_html := '		<span class="ok">None</span><br>';
		--Else display some of the timeouts.
		else
			--Print number of timed out jobs.
			v_html := '		<span class="error">'||v_count||' jobs took too long and timed out.  '||
				'You may want to check the jobs or the databases.<br><br>'||chr(10)||chr(10);

			--Print Top N warning if necessary.
			if v_count > 10 then
				v_html := v_html || '		Only the last 10 stopped jobs are displayed below:<br><br>'||chr(10)||chr(10);
			end if;

			--Table header.
			v_html := v_html||'		<table border="1">'||chr(10);
			v_html := v_html||'			<tr>'||chr(10);
			v_html := v_html||'				<th>Job Name</th>'||chr(10);
			v_html := v_html||'				<th>Owner</th>'||chr(10);
			v_html := v_html||'				<th>Database Name</th>'||chr(10);
			v_html := v_html||'				<th>Table Name</th>'||chr(10);
			v_html := v_html||'				<th>Start Date</th>'||chr(10);
			v_html := v_html||'				<th>Stop Date</th>'||chr(10);
			v_html := v_html||'			</tr>'||chr(10);

			--Table data.
			for rows in
			(
				--Last 10 timed-out jobs.
				--
				--#3: Add HTML.
				select '<tr><td>'||job_name||'</td><td>'||owner||'</td><td>'||database_name||
					'</td><td>'||table_name||'</td><td>'||start_date||'</td><td>'||stop_date||'</td></tr>' v_row
				from
				(
					--#2: Top 10 timed out jobs.
					select job_name, owner, database_name, table_name, start_date, stop_date
					from
					(
						--#1: Timed out jobs.
						select job_name, owner, database_name, table_name
							,to_char(start_date, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') start_date
							,to_char(stop_date, 'YYYY-MM-DD HH24:MI:SS TZH:TZM') stop_date
							,row_number() over (order by stop_date desc) rownumber
						from method5.m5_job_timeout
						where stop_date > systimestamp - 1
					)
					where rownumber <= 10
				)
				order by stop_date desc
			) loop
				v_html := v_html||'			'||rows.v_row||chr(10);
			end loop;

			--Table footer.
			v_html := v_html||'		</table>'||chr(10);

			--End the ERROR.
			v_html := v_html || '		</span>'||chr(10);
		end if;

		--Add the HTML.
		p_email_body := replace(p_email_body, '##TIMED_OUT_JOBS##', v_html);

	end add_timed_out_jobs;


	---------------------------------------
	procedure add_serious_errors(p_email_body in out clob) is
		v_html varchar2(32767);
		type error_rec is record(database_name varchar2(128), error_date date, error_message varchar2(4000));
		type error_tab is table of error_rec;
		v_errors error_tab;
		v_error_count number := 0;
	begin
		--Loop through all recent error tables and look for errors.
		for error_tables in
		(
			--Tables from the audit trail.
			select
				--Check for a "." because tables may be stored in a different schema.
				case
					when instr(table_name, '.') > 0 then
						regexp_substr(table_name, '[^\.]*')
					else
						username
				end owner,
				case
					when instr(table_name, '.') > 0 then
						substr(table_name, instr(table_name, '.') + 1)
					else
						table_name
				end || '_ERR' table_name
			from method5.m5_audit
			where create_date > sysdate - 1
			---------
			intersect
			---------
			--Tables with all 3 Method5 error columns.
			select owner, table_name
			from
			(
				--Tables that contain the relevant Method5 error columns.
				select owner, table_name, count(*) column_count
				from dba_tab_columns
				where table_name like '%\_ERR' escape '\'
					and column_name in ('DATABASE_NAME', 'DATE_ERROR', 'ERROR_STACK_AND_BACKTRACE')
				group by owner, table_name
				order by owner, table_name
			) tables_with_m5_err_columns
			where column_count = 3
			order by 1, 2
		) loop
			--Reset error collection;
			v_errors := error_tab();

			--Look for recent errors.
			execute immediate replace(replace(
				q'[
					select
						database_name,
						date_error,
						case
							when error_stack_and_backtrace like '%ORA-00600%' then 'ORA-00600 (internal error) '
							when error_stack_and_backtrace like '%ORA-07445%' then 'ORA-07445 (internal error) '
							when error_stack_and_backtrace like '%ORA-00257%' then 'ORA-00257 (archiver error) '
							when error_stack_and_backtrace like '%ORA-04031%' then 'ORA-04031 (shared memory error) '
						end error_message
					from #OWNER#.#TABLE_NAME#
					where date_error > sysdate - 1 and
						(
							error_stack_and_backtrace like '%ORA-00600%' or
							error_stack_and_backtrace like '%ORA-07445%' or
							error_stack_and_backtrace like '%ORA-00257%' or
							error_stack_and_backtrace like '%ORA-04031%'
						)
					order by error_message desc
				]'
				, '#OWNER#', error_tables.owner)
				, '#TABLE_NAME#', error_tables.table_name)
			bulk collect into v_errors;

			--Print errors.
			for i in 1 .. v_errors.count loop
				--Count the errors.
				v_error_count := v_error_count + 1;

				--Display a special message for the first error.
				if v_error_count = 1 then
					--Start message.
					v_html := v_html || '		<span class="error">These serious database errors were detected in a Method5 execution '||
						'in the past day.  (Only the last 5 are displayed.)';

					--End the span.
					v_html := v_html || '</span>'||chr(10);

					--Table header.
					v_html := v_html||'		<table border="1">'||chr(10);
					v_html := v_html||'			<tr>'||chr(10);
					v_html := v_html||'				<th>Database Name</th>'||chr(10);
					v_html := v_html||'				<th>Error Date</th>'||chr(10);
					v_html := v_html||'				<th>Error Code</th>'||chr(10);
					v_html := v_html||'				<th>Error Table</th>'||chr(10);
					v_html := v_html||'				<th>Meta Table</th>'||chr(10);
					v_html := v_html||'			</tr>'||chr(10);
				end if;

				--Only display the first 5 errors.
				if v_error_count > 5 then
					exit;
				end if;

				--Print the error: Database Name|Error Date|Error Code|Error Table|Meta Table
				v_html := v_html||'			<tr>'||chr(10);
				v_html := v_html||'				<td>'||v_errors(i).database_name||'</td>'||chr(10);
				v_html := v_html||'				<td>'||to_char(v_errors(i).error_date, 'YYYY-MM-DD HH24:MI')||'</td>'||chr(10);
				v_html := v_html||'				<td>'||v_errors(i).error_message||'</td>'||chr(10);
				v_html := v_html||'				<td>'||error_tables.owner||'.'||error_tables.table_name||'</td>'||chr(10);
				v_html := v_html||'				<td>'||replace(error_tables.owner||'.'||error_tables.table_name, '_ERR', '_META')||'</td>'||chr(10);
				v_html := v_html||'			</tr>'||chr(10);
			end loop;
		end loop;

		--End table, if there were errors.
		if v_error_count > 0 then
			v_html := v_html||'		</table>';
		--Display "OK" if there were no errors
		else
			v_html := v_html||'		<span class="ok">None</span><br>';
		end if;

		--Add the HTML.
		p_email_body := replace(p_email_body, '##SERIOUS_ERRORS##', v_html);
	end add_serious_errors;


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
	add_timed_out_jobs(v_email_body);
	add_serious_errors(v_email_body);
	add_statistics(v_email_body);

	--Send the email.
	get_admin_email_addresses(v_admin_email_sender, v_admin_email_recipients);
	utl_mail.send(
		sender => v_admin_email_sender,
		recipients => v_admin_email_recipients,
		subject => get_subject_line(v_email_body),
		message => v_email_body,
		mime_type => 'text/html'
	);
end send_daily_summary_email;


end;
/
