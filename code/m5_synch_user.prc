create or replace procedure method5.m5_synch_user(
	p_username                    varchar2,
	p_targets                     varchar2,
	p_table_name                  varchar2 default 'SYNCH_USER',
	p_create_user_if_not_exists   boolean,
	p_create_user_clause          varchar2,
	p_synch_password_from_this_db varchar2,
	p_unlock_if_locked            boolean,
	p_profile                     varchar2,
	p_role_privs                  varchar2,
	p_sys_privs                   varchar2
) authid current_user
/*
	Purpose: Create a PL/SQL block to synchronize a user's account with specific settings.

	Warning: Do not directly modify this function.  The code is version controlled in the file "m5_synch_user.prc".
*/
is
	type string_nt is table of varchar2(32767);
	v_strings string_nt;

	v_code varchar2(32767) := q'[
declare
	v_count number;
	v_feedback varchar2(32767);
begin
	#CREATE_USER_IF_NOT_EXISTS#
	#SYNCH_PASSWORD#
	#UNLOCK_IF_LOCKED#
	#PROFILE#
	#ROLE_PRIVS#
	#SYS_PRIVS#

	dbms_output.put_line(rtrim(v_feedback, chr(10)));
end;
]';


	-------------------------------------------------------------------------------
	--Split a comma-separated string into a nested table.
	-------------------------------------------------------------------------------
	function get_nt_from_csv(p_csv in varchar2) return string_nt is
		v_index number := 0;
		v_item varchar2(32767);
		v_results string_nt := string_nt();
	begin
		--Split.
		loop
			v_index := v_index + 1;
			v_item := regexp_substr(p_csv, '[^,]+', 1, v_index);
			exit when v_item is null;
			v_results.extend;
			v_results(v_results.count) := v_item;		
		end loop;

		return v_results;
	end;


	-------------------------------------------------------------------------------
	--Validate the comma-separated list and split it into a nested table.
	-------------------------------------------------------------------------------
	function validate_and_get_nt_from_csv(p_csv in varchar2, p_parameter_name in varchar2) return string_nt is
		v_strings string_nt;
		v_standard_advice varchar2(100) := '  Change the parameter and try the program again.';
	begin
		--Detect problems with input string.
		if instr(p_csv, ',,') > 0 then
			raise_application_error(-20000, 'Empty value detected in '||p_parameter_name||' comma-separated list.'||v_standard_advice);
		elsif regexp_like(p_csv, '^,.*') then
			raise_application_error(-20000, 'Empty value detected at beginning of '||p_parameter_name||' comma-separated list.'||v_standard_advice);
		elsif regexp_like(p_csv, '.*,$') then
			raise_application_error(-20000, 'Empty value detected at end of '||p_parameter_name||' comma-separated list.'||v_standard_advice);
		end if;

		--Split it.
		v_strings := get_nt_from_csv(p_csv);

		--Check for empty values made of just spaces.
		for i in 1 .. v_strings.count loop
			if trim(v_strings(i)) is null then
				raise_application_error(-20000, 'Whitespace-only value detected in '||p_parameter_name||' comma-separated list.'||v_standard_advice);
			end if;
		end loop;

		return v_strings;
	end;


	-------------------------------------------------------------------------------
	-- Validate that a username was supplied and is not just whitespace.
	-------------------------------------------------------------------------------
	procedure validate_username_and_parms(
		p_username                    varchar2,
		p_create_user_if_not_exists   boolean,
		p_create_user_clause          varchar2
	) is
	begin
		if p_username is null then
			raise_application_error(-20000, 'P_USERNAME cannot be null.  Set a value and try again.');
		elsif trim(p_username) is null then
			raise_application_error(-20000, 'P_USERNAME cannot be only whitespace.  Set a value and try again.');
		elsif (p_create_user_if_not_exists is null or not p_create_user_if_not_exists) and trim(p_create_user_clause) is not null then
			raise_application_error(-20000, 'P_CREATE_USER_CLAUSE should not be set if P_CREATE_USER_IF_NOT_EXISTS is not TRUE.');
		end if;
	end validate_username_and_parms;


	-------------------------------------------------------------------------------
	-- add_create_if_not_exists
	-------------------------------------------------------------------------------
	procedure add_create_user_if_not_exists(
			p_create_if_not_exists in     boolean,
			p_code                 in out varchar2)
	is
		v_template varchar2(32767) := replace(q'[
			--Create user if it does not exist.
			declare
				v_random_password varchar2(30) :=
					replace(replace(dbms_random.string('p', 26), '"', null), '''', null) || 'zZ9#';
			begin
				select count(*) into v_count from dba_users where username = '#USERNAME#';
				if v_count = 0 then
					execute immediate 'create user #USERNAME# identified by "'||v_random_password||'" #CREATE_USER_CLAUSE#';
					v_feedback := v_feedback || 'User created' || chr(10);
				else
					v_feedback := v_feedback || 'User already exists' || chr(10);
				end if;
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if p_create_if_not_exists then
			p_code := replace(p_code, '#CREATE_USER_IF_NOT_EXISTS#', v_template);
		else
			p_code := replace(p_code, '#CREATE_USER_IF_NOT_EXISTS#', '--Create user block skipped.');
		end if;
	end add_create_user_if_not_exists;


	-------------------------------------------------------------------------------
	-- Unlock the user if it's already locked.
	-------------------------------------------------------------------------------
	procedure add_unlock_if_locked(
		p_unlock_if_locked in     boolean,
		p_code             in out varchar2)
	is
		v_template varchar2(32767) := replace(q'[
			--Unlock user if it is locked.
			declare
				v_account_status varchar2(4000);
			begin
				select max(account_status) into v_account_status from dba_users where username = '#USERNAME#';
				if v_account_status is null then
					v_feedback := v_feedback || 'Unlock skipped - user does not exist' || chr(10);
				elsif lower(v_account_status) like '%lock%' then
					execute immediate 'alter user #USERNAME# account unlock';
					v_feedback := v_feedback || 'User unlocked' || chr(10);
				else
					v_feedback := v_feedback || 'User already unlocked' || chr(10);
				end if;
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if p_unlock_if_locked then
			p_code := replace(p_code, '#UNLOCK_IF_LOCKED#', v_template);
		else
			p_code := replace(p_code, '#UNLOCK_IF_LOCKED#', '--Unlock skipped.');
		end if;
	end add_unlock_if_locked;


	-------------------------------------------------------------------------------
	-- Set the profile.
	-------------------------------------------------------------------------------
	procedure add_profile(
		p_profile in     varchar2,
		p_code    in out varchar2)
	is
		v_template varchar2(32767) := replace(q'[
			--Set profile to a specific value if it's not already set.
			declare
				v_profile varchar2(4000);
			begin
				select count(*) into v_count from dba_profiles where profile = '#PROFILE#';
				if v_count = 0 then
					v_feedback := v_feedback || 'Profile skipped - profile does not exist' || chr(10);
				else
					select max(profile) into v_profile from dba_users where username = '#USERNAME#';
					if v_profile is null then
						v_feedback := v_feedback || 'Profile skipped - user does not exist' || chr(10);
					elsif v_profile = '#PROFILE#' then
						v_feedback := v_feedback || 'Profile already set' || chr(10);
					else
						execute immediate 'alter user #USERNAME# profile #PROFILE#';
						v_feedback := v_feedback || 'Profile set' || chr(10);
					end if;
				end if;
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if trim(p_profile) is not null then
			p_code := replace(p_code, '#PROFILE#', v_template);
		else
			p_code := replace(p_code, '#PROFILE#', '--Profile skipped.');
		end if;
	end add_profile;


	-------------------------------------------------------------------------------
	-- Get the password hashes from another database.
	-------------------------------------------------------------------------------
	procedure get_password_hashes(
		p_synch_password_from_this_db in     varchar2,
		p_username                    in     varchar2,
		p_hash_for_10g                in out varchar2,
		p_hash_for_11g                in out varchar2,
		p_hash_for_12c                in out varchar2)
	is
	begin
		--Get the password hashes for the user.
		execute immediate
		replace(replace(q'[
			select hash_10g, hash_11g, hash_12c
			from table(m5(
				p_code => 
					q'~
						select
							des_hash hash_10g,
							trim(';' from s_hash || ';' || des_hash) hash_11g,
							regexp_replace(trim(';' from s_hash || ';' || h_hash || ';' || t_hash || ';' || des_hash), ';+', ';') hash_12c
						from
						(
							select
								name,
								password des_hash,
								regexp_substr(spare4, 'S:[^;]+') s_hash,
								regexp_substr(spare4, 'H:[^;]+') h_hash,
								regexp_substr(spare4, 'T:[^;]+') t_hash,
								password,
								spare4
							from sys.user$
							where (password is not null or spare4 is not null)
								and (password is null or password not in ('EXTERNAL', 'GLOBAL', 'anonymous'))
								and name = trim(upper('#USERNAME#'))
						)
					~',
				p_targets => '#TARGET#'
			))
		]'
		, '#USERNAME#', p_username)
		, '#TARGET#', p_synch_password_from_this_db)
		into p_hash_for_10g, p_hash_for_11g, p_hash_for_12c;

	exception when no_data_found then
		raise_application_error(-20000,
			'ERROR - Could not find the user '||p_username||' on database '||p_synch_password_from_this_db||'.');
	end get_password_hashes;


	-------------------------------------------------------------------------------
	-- Synchronize password using a password hash from another database.
	-------------------------------------------------------------------------------
	procedure add_synch_password(
		p_synch_password_from_this_db in     varchar2,
		p_username                    in     varchar2,
		p_code                        in out varchar2)
	is
		v_hash_for_10g varchar2(4000);
		v_hash_for_11g varchar2(4000);
		v_hash_for_12c varchar2(4000);

		v_template varchar2(32767) := replace(q'[
			--Synchronize a password using the password hash from another server.
			begin
				select count(*) into v_count from dba_users where username = '#USERNAME#';

				if v_count = 0 then
					v_feedback := v_feedback || 'Password synchronization skipped - user does not exist' || chr(10);
				else
					declare
						v_old_hash_10g varchar2(4000);
						v_old_hash_11g varchar2(4000);
						v_old_hash_12c varchar2(4000);
						v_cannot_reuse_password exception;
						pragma exception_init(v_cannot_reuse_password, -28007);
					begin
						select
							max(des_hash) hash_10g,
							max(trim(';' from s_hash || ';' || des_hash)) hash_11g,
							max(regexp_replace(trim(';' from s_hash || ';' || h_hash || ';' || t_hash || ';' || des_hash), ';+', ';')) hash_12c
						into v_old_hash_10g, v_old_hash_11g, v_old_hash_12c
						from
						(
							select
								name,
								password des_hash,
								regexp_substr(spare4, 'S:[^;]+') s_hash,
								regexp_substr(spare4, 'H:[^;]+') h_hash,
								regexp_substr(spare4, 'T:[^;]+') t_hash,
								password,
								spare4
							from sys.user$
							where (password is not null or spare4 is not null)
								and (password is null or password not in ('EXTERNAL', 'GLOBAL', 'anonymous'))
								and name = trim(upper('#USERNAME#'))
						);

						$if dbms_db_version.ver_le_10 $then
							--10g has not been tested!
							if '#10G_HASH#' is null then
								v_feedback := v_feedback || 'Password not synchronized - no 10g hash available' || chr(10);
							elsif '#10G_HASH#' = v_old_hash_10g then
								v_feedback := v_feedback || 'Password already synchronized' || chr(10);
							else
								execute immediate 'alter user #USERNAME# identified by values ''#10G_HASH#''';
								v_feedback := v_feedback || 'Password synchronized' || chr(10);
							end if;
						$elsif dbms_db_version.ver_le_11 $then
							if '#11G_HASH#' is null then
								v_feedback := v_feedback || 'Password not synchronized - no 11g hash available' || chr(10);
							elsif '#11G_HASH#' = v_old_hash_11g then
								v_feedback := v_feedback || 'Password already synchronized' || chr(10);
							else
								execute immediate 'alter user #USERNAME# identified by values ''#11G_HASH#''';
								v_feedback := v_feedback || 'Password synchronized' || chr(10);
							end if;
						$else
							if '#12C_HASH#' is null then
								v_feedback := v_feedback || 'Password not synchronized - no 12c hash available' || chr(10);
							elsif '#12C_HASH#' = v_old_hash_12c then
								v_feedback := v_feedback || 'Password already synchronized' || chr(10);
							else
								execute immediate 'alter user #USERNAME# identified by values ''#12C_HASH#''';
								v_feedback := v_feedback || 'Password synchronized' || chr(10);
							end if;
						$end
					--Sometimes not all parts of the hash match but the password is still the same.
					exception when v_cannot_reuse_password then
						v_feedback := v_feedback || 'Password cannot be reused' || chr(10);
					end;
				end if;
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if trim(p_synch_password_from_this_db) is not null then
			get_password_hashes(p_synch_password_from_this_db, p_username, v_hash_for_10g, v_hash_for_11g, v_hash_for_12c);
			p_code := replace(p_code, '#SYNCH_PASSWORD#', 
				replace(replace(replace(v_template
					, '#10G_HASH#', v_hash_for_10g)
					, '#11G_HASH#', v_hash_for_11g)
					, '#12C_HASH#', v_hash_for_12c));
		else
			p_code := replace(p_code, '#SYNCH_PASSWORD#', '--Synch password skipped.');
		end if;
	end add_synch_password;


	-------------------------------------------------------------------------------
	-- Add role privileges.
	-------------------------------------------------------------------------------
	procedure add_role_privs(
		p_role_privs in     varchar2,
		p_code       in out varchar2)
	is
		v_roles_nt string_nt;
		v_role_list varchar2(32767);
		v_template varchar2(32767) := replace(q'[
			--Add roles.
			declare
				v_role_feedback varchar2(4000);
			begin
				for roles in
				(
					select distinct
						roles_expected.role_name,
						case when dba_roles.role is not null then 'Yes' else 'No' end does_role_exist,
						case when dba_role_privs.grantee is not null then 'Yes' else 'No' end is_role_granted
					from
					(
						select column_value role_name
						from table(sys.odcivarchar2list(#ROLE_LIST#))
					) roles_expected
					left join dba_roles
						on roles_expected.role_name = dba_roles.role
					left join dba_role_privs
						on roles_expected.role_name = dba_role_privs.granted_role
						and dba_role_privs.grantee = '#USERNAME#'
					order by role_name
				) loop
					if roles.does_role_exist = 'No' then
						v_role_feedback := v_role_feedback || chr(10) || 'Role '||roles.role_name||' does not exist';
					elsif roles.is_role_granted = 'Yes' then
						v_role_feedback := v_role_feedback || chr(10) || 'Role '||roles.role_name||' already granted';
					else
						execute immediate 'grant '||roles.role_name||' to #USERNAME#';
						v_role_feedback := v_role_feedback || chr(10) || 'Role '||roles.role_name||' granted';
					end if;
				end loop;

				v_feedback := v_feedback || substr(v_role_feedback, 2) || chr(10);
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if trim(p_role_privs) is not null then
			--Validate and transform the role list.
			v_roles_nt := validate_and_get_nt_from_csv(p_role_privs, 'P_ROLE_PRIVS');
			for i in 1 .. v_roles_nt.count loop
				v_role_list := v_role_list || ',''' || upper(v_roles_nt(i)) || '''';
			end loop;
			v_role_list := substr(v_role_list, 2);

			p_code := replace(replace(p_code
				, '#ROLE_PRIVS#', v_template)
				, '#ROLE_LIST#', v_role_list);
		else
			p_code := replace(p_code, '#ROLE_PRIVS#', '--Role privs skipped.');
		end if;
	end add_role_privs;


	-------------------------------------------------------------------------------
	-- Add system privileges.
	-------------------------------------------------------------------------------
	procedure add_sys_privs(
		p_sys_privs in     varchar2,
		p_code       in out varchar2)
	is
		v_sys_privs_nt string_nt;
		v_sys_privs_list varchar2(32767);
		v_template varchar2(32767) := replace(q'[
			--Add system privileges.
			declare
				v_sys_privs_feedback varchar2(4000);
			begin
				for sys_privs in
				(
					select distinct
						sys_privs_expected.sys_priv,
						case when all_sys_privs.privilege is not null then 'Yes' else 'No' end does_sys_priv_exist,
						case when dba_sys_privs.grantee is not null then 'Yes' else 'No' end is_sys_priv_granted
					from
					(
						select column_value sys_priv
						from table(sys.odcivarchar2list(#SYS_PRIVS_LIST#))
					) sys_privs_expected
					left join
					(
						select distinct name privilege
						from system_privilege_map
					) all_sys_privs
						on sys_privs_expected.sys_priv = all_sys_privs.privilege
					left join dba_sys_privs
						on sys_privs_expected.sys_priv = dba_sys_privs.privilege
						and dba_sys_privs.grantee = '#USERNAME#'
					order by sys_priv
				) loop
					if sys_privs.does_sys_priv_exist = 'No' then
						v_sys_privs_feedback := v_sys_privs_feedback || chr(10) || 'Sys priv '||sys_privs.sys_priv||' does not exist';
					elsif sys_privs.is_sys_priv_granted = 'Yes' then
						v_sys_privs_feedback := v_sys_privs_feedback || chr(10) || 'Sys priv '||sys_privs.sys_priv||' already granted';
					else
						execute immediate 'grant '||sys_privs.sys_priv||' to #USERNAME#';
						v_sys_privs_feedback := v_sys_privs_feedback || chr(10) || 'Sys priv '||sys_privs.sys_priv||' granted';
					end if;
				end loop;

				v_feedback := v_feedback || substr(v_sys_privs_feedback, 2) || chr(10);
			end;
		]', chr(10)||chr(9)||chr(9)||chr(9), chr(10)||chr(9));
	begin
		--Add the block if necessary.
		if trim(p_sys_privs) is not null then
			--Validate and transform the role list.
			v_sys_privs_nt := validate_and_get_nt_from_csv(p_sys_privs, 'P_SYS_PRIVS');
			for i in 1 .. v_sys_privs_nt.count loop
				v_sys_privs_list := v_sys_privs_list || ',''' || trim(upper(v_sys_privs_nt(i))) || '''';
			end loop;
			v_sys_privs_list := substr(v_sys_privs_list, 2);

			p_code := replace(replace(p_code
				, '#SYS_PRIVS#', v_template)
				, '#SYS_PRIVS_LIST#', v_sys_privs_list);
		else
			p_code := replace(p_code, '#SYS_PRIVS#', '--Sys privs skipped.');
		end if;
	end add_sys_privs;


	-------------------------------------------------------------------------------
	-- Run the code
	-------------------------------------------------------------------------------
	procedure run_method5(v_code in varchar2, p_targets in varchar2, p_table_name in varchar2) is
	begin
		m5_proc(
			p_code                => v_code,
			p_targets             => p_targets,
			p_table_name          => p_table_name,
			p_table_exists_action => 'drop'
		);
	end run_method5;


--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
begin
	validate_username_and_parms(p_username, p_create_user_if_not_exists, p_create_user_clause);
	add_create_user_if_not_exists(p_create_user_if_not_exists, v_code);
	add_synch_password(p_synch_password_from_this_db, p_username, v_code);
	add_unlock_if_locked(p_unlock_if_locked, v_code);
	add_profile(p_profile, v_code);
	add_role_privs(p_role_privs, v_code);
	add_sys_privs(p_sys_privs, v_code);

	--Replace variables.
	v_code := replace(replace(replace(v_code,
		'#USERNAME#', trim(upper(p_username))),
		'#CREATE_USER_CLAUSE#', p_create_user_clause),
		'#PROFILE#', trim(upper(p_profile)));

	--Run the code
	run_method5(v_code, p_targets, p_table_name);

end m5_synch_user;
/
