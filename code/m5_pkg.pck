create or replace package method5.m5_pkg authid definer is
--Copyright (C) 2016 Jon Heller, Ventech Solutions, and CMS.  This program is licensed under the LGPLv3.
--See https://method5.github.io/ for more information.

C_VERSION constant varchar2(10) := '9.0.0';
g_debug boolean := false;

/******************************************************************************
RUN

Purpose:
	Run SQL or PL/SQL on all databases.  The results, metadata, and errors are
	stored in tables on the user's schema.  These three views always refer to
	the latest tables: M5_RESULTS, M5_METADATA, and M5_ERRORS.

Inputs:
	p_code - The SQL or PL/SQL statement to run on all databases.  Use DBMS_OUTPUT
		to return data from PL/SQL.
	p_targets (OPTIONAL) - Either a query or a comma-separated list of values.
		The query must return one column with the database name, you may want to use
		the table M5_DATABASE for that query.
		The comma-separted list of values can match any of the database names, host
		names, lifecycle statuses, or lines of business configured in M5_DATABASE.
		Leave empty to use all databases.  (The definition of "all" is configurable.)
	p_table_name - (OPTIONAL) A table name, without quotation marks.  If null,
		a sequence is used to generate the table name.
	p_table_exists_action (OPTIONAL) - One of these values:
		ERROR - (DEFAULT) Only creates a new table. Raises exception -20017 if the table already exists.
		APPEND - Adds data to the table.  May raise an exception if the column types or names are different.
		DELETE - Deletes current data before inserting new data.  May raise an exception if the column types or names are different.
		DROP - Drops the table if it exists and create a new one.
	p_asynchronous (OPTIONAL) - Does the process return immediately (TRUE, the default)
		or wait for	all jobs to finish (FALSE).
	p_run_as_sys (OPTIONAL) - Does the code run as SYS (TRUE) or as METHOD5 (FALSE, the default).

Outputs:
	DBMS_OUTPUT will display some statements for querying and cleaning up output.

Side-Effects:
	This procedure commits and creates tables, views, and jobs.

Example: SQL query to find invalid components on all DEV and QA databases.
	begin
	    method5.m5_pkg.run(
	        p_code    => q'< select * from dba_registry where status not in ('VALID', 'REMOVED') >',
	        p_targets => 'dev,qa'
	    );
	end;

	select * from m5_results order by 1,2;
	select * from m5_metadata;
	select * from m5_errors order by 1;

Notes:
	- It's not unusual for at least one database to fail.  Always check M5_METADATA and M5_ERRORS.
	- Database names are from OEM, excluding those with an N/A lifecycle, or those in m5_database_not_queried.

*******************************************************************************/
procedure run(
	p_code                varchar2,
	p_targets             varchar2 default null,
	p_table_name          varchar2 default null,
	p_table_exists_action varchar2 default 'ERROR',
	p_asynchronous        boolean default true,
	p_run_as_sys          boolean default false
);


/******************************************************************************
GET_ENCRYPTED_RAW

Purpose:
	Encrypt a command before sending it be executed remotely as SYS.

Inputs:
	p_database_name - The name of the database as used in the database link.
	p_command - The command to be encrypted.

Returns:
	The encrypted command, as a RAW type.
	(Encryption is performed using AES 256, CBC, and PKCS5 padding.
	Keys are generated using a cryptographic pseudo-random number
	generator, and are unique for each database.  The keys are stored
	remotely in SYS.LINK$, a special table that only SYS can read.
	The command is padded with a GUID, to prevent replay attacks.)

Notes:
	This function should only be called from a Method5 temporary procedure.
	It doesn't make sense to call this function in any other context.

*******************************************************************************/
function get_encrypted_raw(
	p_database_name varchar2,
	p_command varchar2
) return raw;


/******************************************************************************
GET_AND_REMOVE_PIPE_DATA

Purpose:
	Get and remove the pipe data generates and runs the Method5 commands on
	remote databases.  This is necessary beceause the jobs may be created as
	the calling user, but the pipes are private to Method5.  The definer-rights
	functions allows the user to get the specific pipe data for their run.

Inputs:
	p_target_name - The target for the pipe.
	p_sequence - The unique sequence number for the pipe.
	p_pipe_count - The number of pipes.

Returns:
	The data stored in the pipe.

Notes:
	This function should only be called from a Method5 job.
	It doesn't make sense to call this function in any other context.

*******************************************************************************/
function get_and_remove_pipe_data(
	p_target_name varchar2,
	p_sequence    varchar2,
	p_pipe_count  number
) return varchar2;


/******************************************************************************
STOP_JOBS

Purpose:
	Stop Method5 jobs that are collecting data from databases.  There can be a
	large number of jobs, especially if some databases are not responding well.
	This only stops jobs called FROM Method5, not jobs calling Method5.

Side-Affects:
	Stops Method5 jobs.

Inputs:
	p_owner - The user running the jobs.  The default, NULL, means all users.
	p_table_name - The name of the table being inserted into.  This matches the
		comments of the jobs.  The default, NULL, means any table name.
	p_elapsed_minutes - Only drop jobs that have been running for at least this
		many minutes.  The default, NULL, means any number of minutes.

Example: Stop jobs for the current user for a specific run:
	begin
		m5_pkg.stop_jobs(p_owner => user, p_table_name = 'M5_TEMP_12345');
	end;
*******************************************************************************/
procedure stop_jobs
(
	p_owner varchar2 default null,
	p_table_name varchar2 default null,
	p_elapsed_minutes number default null
);


/******************************************************************************
GET_TARGET_TAB_FROM_TARGET_STR

Purpose:
	Get a nested table of target names from a target string.

Side-Affects:
	None

Inputs:
	p_target_string - Same syntax as the P_TARGETS parameter for RUN.
	p_database_or_host - Return either the database names or the host names.

Example: View all databases in the lifecycle DEV or with a database name like ACME%:
	select * from table(method5.m5_pkg.get_target_tab_from_target_str('dev,acme%'));

	COLUMN_VALUE
	------------
	devdb1
	devdb2
	devdb3
	...
*******************************************************************************/
function get_target_tab_from_target_str(
	p_target_string    in varchar2,
	p_database_or_host in varchar2 default 'database'
) return method5.string_table;

end;
/
create or replace package body method5.m5_pkg is


/******************************************************************************/
--(See specification for description.)
procedure stop_jobs
(
	p_owner varchar2 default null,
	p_table_name varchar2 default null,
	p_elapsed_minutes number default null
) is
	v_must_be_a_job exception;
	pragma exception_init(v_must_be_a_job, -27475);
begin
	--TODO: What about if the job hasn't even started yet?

	for jobs_to_kill in
	(
		select dba_scheduler_running_jobs.owner, dba_scheduler_running_jobs.job_name, comments, elapsed_time
		from sys.dba_scheduler_running_jobs
		join sys.dba_scheduler_jobs
			on dba_scheduler_running_jobs.job_name = dba_scheduler_jobs.job_name
			and dba_scheduler_running_jobs.owner = dba_scheduler_jobs.owner
		where dba_scheduler_jobs.auto_drop = 'TRUE'
			and dba_scheduler_running_jobs.job_name like 'M5%'
			and (regexp_replace(dba_scheduler_jobs.comments, 'TABLE:(.*)"CALLER:.*', '\1') = upper(p_table_name) or p_table_name is null)
			and (regexp_replace(dba_scheduler_jobs.comments, 'TABLE:.*"CALLER:(.*)', '\1') = upper(trim(p_owner)) or p_owner is null)
			and (dba_scheduler_running_jobs.elapsed_time > p_elapsed_minutes * interval '1' minute or p_elapsed_minutes is null)
		order by dba_scheduler_jobs.owner, dba_scheduler_jobs.job_name
	) loop
		begin
			sys.dbms_scheduler.stop_job(
				job_name => jobs_to_kill.owner||'.'||jobs_to_kill.job_name,
				force => true
			);
		exception when v_must_be_a_job then
			--Ignore errors caused when a job finishes between the query and the STOP_JOB.
			null;
		end;
	end loop;
end stop_jobs;


/******************************************************************************/
--(See specification for description.)
function get_encrypted_raw(p_database_name varchar2, p_command varchar2) return raw is
	v_clean_db_link varchar2(128) := 'M5_'||trim(upper(p_database_name));
	v_sys_key raw(32);
begin
	--Get the SYS key.
	select max(sys_key)
	into v_sys_key
	from method5.m5_sys_key
	where db_link = v_clean_db_link;

	--Throw error if the SYS key does not exist.
	if v_sys_key is null then
		raise_application_error(-20031, 'The SYS key for this database does not exist.  '||
			'Try calling this procedure to generate the key:'||chr(10)||
			'begin'||chr(10)||
			'   method5.method5_admin.set_local_and_remote_sys_key(''m5_'||p_database_name||''');'||chr(10)||
			'end;');
	end if;

	--Return the encrypted command.
	return sys.dbms_crypto.encrypt
	(
		--Add SYS_GUID as a session ID, to prevent replay attakcs.
		src => utl_i18n.string_to_raw (sys_guid() || p_command, 'AL32UTF8'),
		typ => sys.dbms_crypto.encrypt_aes256 + sys.dbms_crypto.chain_cbc + sys.dbms_crypto.pad_pkcs5,
		key => v_sys_key
	);
end get_encrypted_raw;


/******************************************************************************/
--(See specification for description.)
function get_and_remove_pipe_data(
	p_target_name varchar2,
	p_sequence    varchar2,
	p_pipe_count  number
) return varchar2 is
	v_result integer;
	v_code varchar2(32767);
	v_item varchar2(4000);
	v_pipename varchar2(128);
begin
	--Reconstruct procedure DDL.
	for pipe_index in 1 .. p_pipe_count loop
		v_pipename := 'M5_'||p_target_name||'_'||p_sequence||'_'||pipe_index;

		--Receive message; timeout=> ensures procedure will not wait.
		v_result := sys.dbms_pipe.receive_message(v_pipename, timeout => 0);
		if v_result <> 0 then
			raise_application_error(-20023, 'Pipe error.  Result = '||v_result||'.');
		end if;

		--Unpack, put together the string.
		sys.dbms_pipe.unpack_message(v_item);
		v_code := v_code||v_item;

		--Remove the pipe.
		v_result := sys.dbms_pipe.remove_pipe(v_pipename);
		if v_result <> 0 then
			raise_application_error(-20023, 'Pipe error.  Result = '||v_result||'.');
		end if;
	end loop;

	--Return code.
	return v_code;
end get_and_remove_pipe_data;


/******************************************************************************/
--(See specification for description.)
function get_target_tab_from_target_str(
	p_target_string    in varchar2,
	p_database_or_host in varchar2 default 'database'
) return method5.string_table is

	--SQL statements:
	v_clean_select_sql varchar2(32767);
	v_configured_target_query varchar2(32767);

	--Types and variables to hold database configuration attributes.
	type string_table_table is table of string_table;

	v_config_type string_table;
	v_config_key string_table;
	v_config_values string_table_table;

	type string_table_aat is table of string_table index by varchar2(32767);
	v_config_key_values string_table_aat;

	--Holds split list of items.
	v_target_items string_table := string_table();
	v_item varchar2(32767);

	--Final value with databases:
	v_target_tab string_table := string_table();

	--If the input is a SELECT statement, return that statement without a terminator (if any).
	--For example: '/* asdf*/ with asdf as (select 1 a from dual) select * from asdf;' would return
	--	the same string but without the final semicolon.  But 'asdf' would return null.
	function get_unterminated_select(p_sql varchar2) return varchar2 is
		v_category varchar2(32767);
		v_statement_type varchar2(32767);
		v_command_name varchar2(32767);
		v_command_type number;
		v_lex_sqlcode number;
		v_lex_sqlerrm varchar2(32767);

		v_tokens token_table;
	begin
		--Tokenize and remove semicolon if necessary.
		v_tokens := plsql_lexer.lex(p_sql);
		v_tokens := statement_terminator.remove_semicolon(v_tokens);

		--Classify statement.
		statement_classifier.classify(
			p_tokens         => v_tokens,
			p_category       => v_category,
			p_statement_type => v_statement_type,
			p_command_name   => v_command_name,
			p_command_type   => v_command_type,
			p_lex_sqlcode    => v_lex_sqlcode,
			p_lex_sqlerrm    => v_lex_sqlerrm
		);

		--Return SQL if it's a SELECT>
		if v_command_name = 'SELECT' then
			return plsql_lexer.concatenate(v_tokens);
		--Return NULL if it's not a SELECT.
		else
			return null;
		end if;
	end get_unterminated_select;

	procedure add_target_group(p_item varchar2, p_target_items in out string_table) is
		v_query clob;
		v_targets method5.string_table := method5.string_table();
	begin
		--Get query for target group.
		begin
			select string_value query
			into v_query
			from method5.m5_config
			where replace(trim(lower(config_name)), '$') like 'target group -%' || replace(trim(lower(p_item)), '$');
		exception when no_data_found then
			raise_application_error(-20025, 'Could not find the target group "'||p_item||'" in METHOD5.M5_CONFIG.'||
				'  Either fix the target group name or add the target group to the configuration.');
		end;

		--Get the targets
		begin
			execute immediate v_query bulk collect into v_targets;
			exception when others then raise_application_error(-20026,
				'There was an error retrieving the targets for the target group "'||p_item||'".'||
				'  Check the query in METHOD5.M5_CONFIG for valid syntax and sure it only '||
				' returns one column.'||chr(10)||
				sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
		end;

		--Add them to the existing list of targets.
		for i in 1 .. v_targets.count loop
			p_target_items.extend;
			p_target_items(p_target_items.count) := lower(trim(v_targets(i)));
		end loop;
	end add_target_group;

begin
	--Validate input.
	if trim(p_database_or_host) is null or lower(trim(p_database_or_host)) not in ('host', 'database') then
		raise_application_error(-20034, 'P_DATABASE_OR_HOST must be either HOST or DATABASE.');
	end if;

	--Get SQL to run (without a semicolon), if it's a SELECT.
	v_clean_select_sql := get_unterminated_select(p_target_string);

	--Execute P_TARGET_STRING as a SELECT statement if it looks like one.
	if v_clean_select_sql is not null then
		--Try to run query, raise helpful error message if it doesn't work.
		--TODO: SQL injection threat if this function is runnable by unprivileged users.
		begin
			--Add an "intersect" to ensure that only valid rows are returned.
			if lower(trim(p_database_or_host)) = 'database' then
				execute immediate v_clean_select_sql || ' intersect select database_name from method5.m5_database'
				bulk collect into v_target_tab;
			else
				execute immediate v_clean_select_sql || ' intersect select host_name from method5.m5_database'
				bulk collect into v_target_tab;
			end if;
		exception when others then
			dbms_output.put_line('Target Name Query: '||chr(10)||p_target_string);
			raise_application_error(-20006, 'Error executing P_TARGETS.'||chr(10)||
				'Please check that the query is valid and only returns one VARCHAR2 column.'||chr(10)||
				'Check the query stored in M5_CONFIG or check the DBMS_OUTPUT for the query.'||
				sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
		end;

		--Remove duplicates.
		v_target_tab := set(v_target_tab);

		--Force lower-case to simplify comparisons.
		for i in 1 .. v_target_tab.count loop
			v_target_tab(i) := lower(v_target_tab(i));
		end loop;

	--Split P_TARGET_STRING into attributes if it's not a SELECT statement.
	--Else treat P_TARGET_STRING as comma-separated-values that may identify database,
	--host, lifecycle, line of business, or cluster name.
	else
		--Build query to retrieve database attributes as collections of strings.
		v_configured_target_query :=
		q'[
			with config as
			(
				select database_name, instance_name, connect_string, host_name, lifecycle_status, line_of_business, cluster_name
				from method5.m5_database
			)
			select 'database_name' row_type, lower(database_name) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			group by database_name
			union all
			select 'instance_name' row_type, lower(instance_name) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			where instance_name <> database_name
			group by instance_name
			union all
			select 'host_name' row_type, lower(host_name) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			group by host_name
			union all
			select 'lifecycle_status' row_type, lower(lifecycle_status) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			group by lifecycle_status
			union all
			select 'line_of_business' row_type, lower(line_of_business) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			group by line_of_business
			union all
			select 'cluster_name' row_type, lower(cluster_name) row_value, cast(collect(distinct lower(database_name)) as method5.string_table)
			from config
			group by cluster_name
		]';

		--Convert the string to retreive hosts instead of databases for shell scripts.
		if lower(trim(p_database_or_host)) = 'host' then
			v_configured_target_query := replace(
				v_configured_target_query,
				'collect(distinct lower(database_name)',
				'collect(distinct lower(host_name)'
			);
		end if;

		--Gather configuration data.
		begin
			execute immediate v_configured_target_query
			bulk collect into v_config_type, v_config_key, v_config_values;
		exception when others then
			dbms_output.put_line('Configuration query that generated an error: '||v_configured_target_query);
			raise_application_error(-20008, 'Error retrieving database configuration.'||
				'  Check the query stored in M5_CONFIG.  Or check the DBMS_OUTPUT for the query.'||
				chr(10)||sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
		end;

		--Convert configuration data into an associative array.
		for i in 1 .. v_config_key.count loop
			if v_config_key(i) is not null then
				v_config_key_values(v_config_key(i)) := v_config_values(i);
			end if;
		end loop;

		--Convert comma-separated list of targets into nested table.
		declare
			v_target_index number := 0;
		begin
			loop
				v_target_index := v_target_index + 1;
				v_item := regexp_substr(p_target_string, '[^,]+', 1, v_target_index);
				exit when v_item is null;

				--Replace target groups if necessary.
				if trim(v_item) like '$%' then
					add_target_group(v_item, v_target_items);
				--Else use regular name.
				else
					v_target_items.extend();
					v_target_items(v_target_items.count) := lower(trim(v_item));
				end if;
			end loop;
		end;

		--Map target items to configuration items, create a nested table with all data.
		for i in 1 .. v_target_items.count loop
			for j in 1 .. v_config_key.count loop
				if v_config_key(j) like v_target_items(i) then
					v_target_tab := v_target_tab multiset union distinct v_config_values(j);
				end if;
			end loop;
		end loop;
	end if;

	return v_target_tab;
end get_target_tab_from_target_str;


/******************************************************************************/
--(See specification for description.)
procedure run(
	p_code                varchar2,
	p_targets             varchar2 default null,
	p_table_name          varchar2 default null,
	p_table_exists_action varchar2 default 'ERROR',
	p_asynchronous        boolean default true,
	p_run_as_sys          boolean default false
) is

	--All printable ASCII characters, excluding ones that would look confusing (',",@),
	--and ones that match, such as [], <>, (), {}.
	--This is a global constant to avoid being executed with each function call.
	c_delimiter_candidates constant sys.odcivarchar2list := sys.odcivarchar2list(
		'!','#','$','%','*','+',',','-','.','0','1','2','3','4','5','6','7','8','9',
		':',';','=','?','A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
		'P','Q','R','S','T','U','V','W','X','Y','Z','^','_','`','a','b','c','d','e',
		'f','g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v','w','x',
		'y','z','|','~'
	);

	--Constants.
	C_MAX_DATABASE_ATTEMPTS constant number := 100;

	--Collections to hold link data instead of re-fetching the cursor.
	type link_rec is record(
		db_link_name   varchar2(128),
		database_name  varchar2(30),   --Only one of DATABASE_NAME or HOST_NAME can be non-null per row.
		host_name      varchar2(256),
		connect_string varchar2(4000),
		link_exists    number
	);
	type links_nt is table of link_rec;

	type config_data_rec is record(
		admin_email_sender_address   varchar2(4000),
		admin_email_recipients       varchar2(4000),
		access_control_locked        varchar2(4000),
		access_control_os_username   varchar2(4000),
		global_default_targets       varchar2(4000),
		has_valid_db_username        varchar2(3),
		has_valid_db_and_os_username varchar2(3),
		user_default_targets         varchar2(4000)
	);

	type allowed_privs_rec is record(
		os_username              varchar2(128),
		target                   varchar2(4000),
		db_link_name             varchar2(4000),
		default_targets          varchar2(4000),
		run_as_m5_or_temp_user   varchar2(9),
		install_links_in_schema  varchar2(3),
		job_owner                varchar2(128),
		privileges               method5.string_table,
		has_any_install_links    varchar2(3)
	);
	type allowed_privs_nt is table of allowed_privs_rec;

	--Code templates.
	v_select_template constant varchar2(32767) := q'<
create procedure m5_temp_proc_##SEQUENCE## authid current_user is
	v_dummy varchar2(1);
begin
	--Ping database with simple select to create simple error message if link fails.
	execute immediate 'select dummy from sys.dual@##DB_LINK_NAME##' into v_dummy;

	execute immediate q'##QUOTE_DELIMITER2##
		declare
			v_rowcount number;
		begin
			--Create remote temporary table with results.
			##DBA_OR_SYS_RUN_CTAS##

			--Insert data into local tble using database link.
			--Use dynamic SQL - PL/SQL must compile in order to catch exceptions.
			execute immediate q'##QUOTE_DELIMITER1##
				insert into ##TABLE_OWNER##.##TABLE_NAME##
				select '##DATABASE_NAME##', m5_temp_table_##SEQUENCE##.*
				from m5_temp_table_##SEQUENCE##@##DB_LINK_NAME##
			##QUOTE_DELIMITER1##';

			v_rowcount := sql%rowcount;

			--Update _META table.
			update ##TABLE_OWNER##.##TABLE_NAME##_meta
			set targets_completed = targets_completed + 1,
				date_updated = sysdate,
				is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No'),
				num_rows = num_rows + v_rowcount
			where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

			--Drop remote temporary table.
			sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(q'##QUOTE_DELIMITER1##
				drop table m5_temp_table_##SEQUENCE## purge
			##QUOTE_DELIMITER1##');

		end;
	##QUOTE_DELIMITER2##';

--Exception block must be outside of dynamic PL/SQL.
--Exceptions like "ORA-00257: archiver error. Connect internal only, until freed."
--will make the whole block fail and must be caught by higher level block.
exception when others then
	update ##TABLE_OWNER##.##TABLE_NAME##_meta
	set targets_with_errors = targets_with_errors + 1,
		date_updated = sysdate,
		is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No')
	where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

	insert into ##TABLE_OWNER##.##TABLE_NAME##_err
	values ('##DATABASE_NAME##', '##DB_LINK_NAME##'
		, sysdate, sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);

	commit;

	raise;
end;
>';


	v_select_limit_privs_template constant varchar2(32767) := q'<
create procedure m5_temp_proc_##SEQUENCE## authid current_user is
	v_dummy varchar2(1);
begin
	--Ping database with simple select to create simple error message if link fails.
	execute immediate 'select dummy from sys.dual@##DB_LINK_NAME##' into v_dummy;

	execute immediate q'##QUOTE_DELIMITER3##
		declare
			v_rowcount number;
			v_default_permanent_tablespace varchar2(128);
		begin
			--Create temporary user to run function.
			sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##('
				create user m5_temp_user_##SEQUENCE##
				identified by "'||replace(replace(sys.dbms_random.string(opt=> 'p', len=> 26), '''', null), '"', null) || 'aA#1'||'"
				account lock password expire
			');

			--Grant the user tablespace.
			select property_value
			into v_default_permanent_tablespace
			from database_properties@##DB_LINK_NAME##
			where property_name = 'DEFAULT_PERMANENT_TABLESPACE';

			sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##('
				alter user m5_temp_user_##SEQUENCE## quota unlimited on '||v_default_permanent_tablespace
			);

			--Grant the user privileges.
			declare
				v_privs sys.odcivarchar2list := sys.odcivarchar2list('create table'##ALLOWED_PRIVS##);
			begin
				for i in 1 .. v_privs.count loop
					begin
						sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(
							'grant '||v_privs(i)||' to m5_temp_user_##SEQUENCE##'
						);
					exception when others then null;
					end;
				end loop;
			end;

			--Create remote temporary procedure with CTAS.
			##CREATE_CTAS_PROC##

			--Run the procedure.
			execute immediate 'begin m5_temp_user_##SEQUENCE##.m5_temp_proc_##SEQUENCE##@##DB_LINK_NAME##; end;';

			--Insert data into local tble using database link.
			--Use dynamic SQL - PL/SQL must compile in order to catch exceptions.
			execute immediate q'##QUOTE_DELIMITER2##
				insert into ##TABLE_OWNER##.##TABLE_NAME##
				select '##DATABASE_NAME##', m5_temp_table_##SEQUENCE##.*
				from m5_temp_user_##SEQUENCE##.m5_temp_table_##SEQUENCE##@##DB_LINK_NAME##
			##QUOTE_DELIMITER2##';

			v_rowcount := sql%rowcount;

			--Update _META table.
			update ##TABLE_OWNER##.##TABLE_NAME##_meta
			set targets_completed = targets_completed + 1,
				date_updated = sysdate,
				is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No'),
				num_rows = num_rows + v_rowcount
			where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

			--Drop temporary table.
			sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(q'##QUOTE_DELIMITER2##
				drop user m5_temp_user_##SEQUENCE## cascade
			##QUOTE_DELIMITER2##');
		end;
	##QUOTE_DELIMITER3##';

--Exception block must be outside of dynamic PL/SQL.
--Exceptions like "ORA-00257: archiver error. Connect internal only, until freed."
--will make the whole block fail and must be caught by higher level block.
exception when others then
	update ##TABLE_OWNER##.##TABLE_NAME##_meta
	set targets_with_errors = targets_with_errors + 1,
		date_updated = sysdate,
		is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No')
	where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

	insert into ##TABLE_OWNER##.##TABLE_NAME##_err
	values ('##DATABASE_NAME##', '##DB_LINK_NAME##'
		, sysdate, sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);

	commit;

	--Cleanup by dropping the temporary user.
	execute immediate q'##QUOTE_DELIMITER3##
		begin
			sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(q'##QUOTE_DELIMITER2##
				drop user m5_temp_user_##SEQUENCE## cascade
			##QUOTE_DELIMITER2##');
		end;
	##QUOTE_DELIMITER3##';

	raise;
end;
>';


	v_shell_script_template constant varchar2(32767) := q'<
create procedure m5_temp_proc_##SEQUENCE## authid current_user is
	v_database_name varchar2(128);
	v_platform_name varchar2(4000);
begin
	--Ping database with simple select to create simple error message if link fails.
	--Also find out which database is used in the host link, and the platform name.
	execute immediate 'select name, platform_name from v$database@##HOST_LINK_NAME##'
	into v_database_name, v_platform_name;

	--Windows shell commands are not yet supported.
	if lower(v_platform_name) like '%windows%' then
		raise_application_error(-20033, 'The shell command option does not yet support Windows platforms.');
	end if;

	execute immediate replace(q'##QUOTE_DELIMITER3##
		declare
			v_rowcount number;
		begin
			--Create remote temporary table with results.
			sys.m5_runner.run_as_sys@##HOST_LINK_NAME##
			(
				method5.m5_pkg.get_encrypted_raw(
					'##DATABASE_NAME##',
					q'##QUOTE_DELIMITER2##
						begin
							sys.m5_run_shell_script(
								q'##QUOTE_DELIMITER1####CODE####QUOTE_DELIMITER1##'
								,'M5_TEMP_TABLE_##SEQUENCE##');
							commit;
						end;
					##QUOTE_DELIMITER2##'
				)
			);

			--Insert data using database link.
			--Use dynamic SQL - PL/SQL must compile in order to catch exceptions.
			execute immediate q'##QUOTE_DELIMITER1##
				insert into ##TABLE_OWNER##.##TABLE_NAME##
				select '##HOST_NAME##', m5_temp_table_##SEQUENCE##.*
				from m5_temp_table_##SEQUENCE##@##HOST_LINK_NAME##
			##QUOTE_DELIMITER1##';

			v_rowcount := sql%rowcount;

			--Update _META table.
			update ##TABLE_OWNER##.##TABLE_NAME##_meta
			set targets_completed = targets_completed + 1,
				date_updated = sysdate,
				is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No'),
				num_rows = num_rows + v_rowcount
			where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

			--Drop remote temporary table.
			sys.dbms_utility.exec_ddl_statement@##HOST_LINK_NAME##(q'##QUOTE_DELIMITER1##
				drop table m5_temp_table_##SEQUENCE## purge
			##QUOTE_DELIMITER1##');

		end;
	##QUOTE_DELIMITER3##', '##DATABASE_NAME##', v_database_name);

--Exception block must be outside of dynamic PL/SQL.
--Exceptions like "ORA-00257: archiver error. Connect internal only, until freed."
--will make the whole block fail and must be caught by higher level block.
exception when others then
	update ##TABLE_OWNER##.##TABLE_NAME##_meta
	set targets_with_errors = targets_with_errors + 1,
		date_updated = sysdate,
		is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No')
	where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

	insert into ##TABLE_OWNER##.##TABLE_NAME##_err
	values ('##HOST_NAME##', '##HOST_LINK_NAME##'
		, sysdate, sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);

	commit;

	raise;
end;
>';


	v_plsql_template constant varchar2(32767) := q'<
create procedure m5_temp_proc_##SEQUENCE## authid current_user is
begin
	execute immediate q'##QUOTE_DELIMITER4##
		declare
			v_dummy varchar2(1);
			v_return_value varchar2(32767);

			--Exception handling is the same, except it will print a different message if
			--the error was in compiling or running.
			procedure handle_exception(p_compile_or_run varchar2) is
			begin
				update ##TABLE_OWNER##.##TABLE_NAME##_meta
				set targets_with_errors = targets_with_errors + 1,
					date_updated = sysdate,
					is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No')
				where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

				insert into ##TABLE_OWNER##.##TABLE_NAME##_err
				values ('##DATABASE_NAME##', '##DB_LINK_NAME##'
					, sysdate, p_compile_or_run||' error: '||sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);

				commit;

				--Drop the temporary function.
				declare
					v_does_not_exist exception;
					pragma exception_init(v_does_not_exist, -4043);
				begin
					execute immediate '
						begin
							sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(''drop function m5_temp_function_##SEQUENCE##'');
							sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(''drop table m5_temp_table_##SEQUENCE## purge'');
						end;
					';
				exception when v_does_not_exist then null;
				end;
			end handle_exception;
		begin
			--Create a function with the PLSQL block.
			--This is nested because job must still compile even if the block is invalid, and execute immediate allows role privileges.
			declare
				v_rowid rowid;
				v_result varchar2(1000);
			begin
				--Ping database with simple select to create simple error message if link fails.
				execute immediate 'select dummy from sys.dual@##DB_LINK_NAME##' into v_dummy;

				execute immediate q'##QUOTE_DELIMITER3##
					begin
						sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(##SYS_REPLACE_WITH_ENCRYPTED_BEGIN##q'##QUOTE_DELIMITER2##
							create function m5_temp_function_##SEQUENCE## return ##CLOB_OR_VARCHAR2## authid current_user is
								--Required for DDL over database link.
								pragma autonomous_transaction;

								v_lines sys.dbmsoutput_linesarray;
								v_numlines number := 32767;
								v_dbms_output_clob clob;
							begin
								sys.dbms_output.enable(null);

								execute immediate q'##QUOTE_DELIMITER1##
									begin
										##CODE##
									end;
								##QUOTE_DELIMITER1##';

								--Retrieve and concatenate the output.
								sys.dbms_output.get_lines(lines => v_lines, numlines => v_numlines);
								for i in 1 .. v_numlines loop
									v_dbms_output_clob := v_dbms_output_clob || case when i = 1 then null else chr(10) end || v_lines(i);
								end loop;

								return v_dbms_output_clob;
							end;
						##QUOTE_DELIMITER2##'##SYS_REPLACE_WITH_ENCRYPTED_END##);

						--Create remote temporary table with results.
						sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(q'##QUOTE_DELIMITER2##
							create table m5_temp_table_##SEQUENCE## nologging pctfree 0 as
							select m5_temp_function_##SEQUENCE## result from dual
						##QUOTE_DELIMITER2##');
					end;
				##QUOTE_DELIMITER3##';

				--Create local row and get ROWID.
				--(Must use INSERT VALUES and UPDATE because INSERT SUBQUERY doesn't support RETURNING
				-- and INSERT VALUES doesn't support CLOBs.)
				execute immediate q'##QUOTE_DELIMITER3##
					insert into ##TABLE_OWNER##.##TABLE_NAME##(database_name)
					values('##DATABASE_NAME##')
					returning rowid into :v_rowid
				##QUOTE_DELIMITER3##'
				returning into v_rowid;

				--Update local value.
				execute immediate q'##QUOTE_DELIMITER3##
					update ##TABLE_OWNER##.##TABLE_NAME##
					set result = (select result from m5_temp_table_##SEQUENCE##@##DB_LINK_NAME##)
					where rowid = :v_rowid
				##QUOTE_DELIMITER3##'
				using v_rowid;

				--Get part of the result.
				execute immediate q'##QUOTE_DELIMITER3##
					select to_char(substr(result, 1, 1000))
					from ##TABLE_OWNER##.##TABLE_NAME##
					where rowid = :v_rowid
				##QUOTE_DELIMITER3##'
				into v_result
				using v_rowid;

				--Convert return value into a SQL*PLus-like feedback message, if necessary.
				if v_result like 'M5_FEEDBACK_MESSAGE:COMMAND_NAME=%' then
					declare
						v_command_name varchar2(1000);
						v_rowcount number;
						v_success_message varchar2(4000);
						v_compile_warning_message varchar2(4000);
					begin
						v_command_name := regexp_replace(v_result, '.*COMMAND_NAME=(.*);.*', '\1');
						v_rowcount := regexp_replace(v_result, '.*ROWCOUNT=(.*)$', '\1');
						method5.statement_feedback.get_feedback_message(
							p_command_name => v_command_name,
							p_rowcount => v_rowcount,
							p_success_message => v_success_message,
							p_compile_warning_message => v_compile_warning_message
						);
						v_result := v_success_message;

						execute immediate q'##QUOTE_DELIMITER3##
							update ##TABLE_OWNER##.##TABLE_NAME##
							set result = :new_result
							where rowid = :v_rowid
						##QUOTE_DELIMITER3##'
						using v_result, v_rowid;
					end;
				end if;

			exception when others then
				handle_exception('Run');
				raise;
			end;

			--Update _META table.
			update ##TABLE_OWNER##.##TABLE_NAME##_meta
			set targets_completed = targets_completed + 1,
				date_updated = sysdate,
				is_complete = decode(targets_expected, targets_completed+targets_with_errors+1, 'Yes', 'No'),
				num_rows = num_rows + 1
			where date_started = (select max(date_started) from ##TABLE_OWNER##.##TABLE_NAME##_meta);

			--Drop the temporary function and table.
			execute immediate '
				begin
					sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(''drop function m5_temp_function_##SEQUENCE##'');
					sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##(''drop table m5_temp_table_##SEQUENCE## purge'');
				end;
			';
		end;
	##QUOTE_DELIMITER4##';
end;
>';

--TODO: PLSQL limit privileges.


	---------------------------------------------------------------------------
	--Get a sequence value to help ensure uniqueness.
	function get_sequence_nextval return number is
	begin
		return method5.m5_generic_sequence.nextval;
	end get_sequence_nextval;

	---------------------------------------------------------------------------
	--Get configuration data from M5_CONFIG and M5_USER.
	function get_config_data return config_data_rec is
		v_config_data config_data_rec;
	begin
		--User configuration for admin email addresses.
		select
			listagg(email_address, ';') within group (order by lower(email_address)) admin_email_recipients,
			min(email_address) admin_email_sender_address
		into
			v_config_data.admin_email_sender_address,
			v_config_data.admin_email_recipients
		from method5.m5_user
		where is_m5_admin = 'Yes'
			and email_address is not null;

		--M5_CONFIG data.
		select
			max(case when config_name = 'Access Control - User is not locked'            then string_value else null end) user_not_locked,
			max(case when config_name = 'Access Control - User has expected OS username' then string_value else null end) os_username,
			max(case when config_name = 'Default Targets' then string_value else null end) gloal_default_targets
		into
			v_config_data.access_control_locked     ,
			v_config_data.access_control_os_username,
			v_config_data.global_default_targets
		from method5.m5_config;

		--User configuration data for the best match.
		select
			case when nomatch_0_db_1_dbAndOS_2 in (1,2) then 'Yes' else 'No' end has_valid_db_username,
			case when nomatch_0_db_1_dbAndOS_2 in (2)   then 'Yes' else 'No' end has_valid_db_and_os_username,
			default_targets
		into
			v_config_data.has_valid_db_username       ,
			v_config_data.has_valid_db_and_os_username,
			v_config_data.user_default_targets        
		from
		(
			--Find the highest match.
			select oracle_username, os_username, default_targets, nomatch_0_db_1_dbAndOS_2
				,max(nomatch_0_db_1_dbAndOS_2) over () best_match
			from
			(
				select m5_user.oracle_username, os_username, default_targets
					,case
						when lower(m5_user.oracle_username) = lower(sys_context('userenv', 'session_user'))
							and lower(os_username) = lower(sys_context('userenv', 'os_user')) then 2
						when lower(m5_user.oracle_username) = lower(sys_context('userenv', 'session_user'))
							and sys_context('userenv', 'module') = 'DBMS_SCHEDULER' then 2
						when lower(m5_user.oracle_username) = lower(sys_context('userenv', 'session_user'))
							and os_username is null then 1
					end nomatch_0_db_1_dbAndOS_2
				from method5.m5_user
				group by m5_user.oracle_username, os_username, default_targets
				union all
				select null oracle_username, null os_username, null default_targets
					,0 nomatch_0_db_1_dbAndOS_2
				from dual
			)
		)
		where best_match = nomatch_0_db_1_dbAndOS_2;

		return v_config_data;
	end get_config_data;

	---------------------------------------------------------------------------
	--Get the privileges allowed for this user.
	function get_allowed_privs
	(
		p_run_as_sys                 in boolean,
		p_is_shell_script            in boolean,
		p_target_string_with_default in varchar2
	)
	return allowed_privs_nt is
		v_allowed_privs allowed_privs_nt;
		v_run_as_sys varchar2(3) := case when p_run_as_sys then 'Yes' else 'No' end;
		v_is_shell_script varchar2(3) := case when p_is_shell_script then 'Yes' else 'No' end;
		v_database_or_host varchar2(8) := case when p_is_shell_script then 'host' else 'database' end;
	begin
		--Requested and allowed privileges.
		select
			os_username,
			requested_privileges.target,
			'M5_'||upper(requested_privileges.target) db_link_name,
			allowed_privileges.default_targets,
			allowed_privileges.run_as_m5_or_temp_user,
			allowed_privileges.install_links_in_schema,
			case
				when install_links_in_schema = 'Yes' then
					sys_context('userenv', 'session_user')
				else
					'METHOD5'
			end job_owner,
			allowed_privileges.privileges,
			max(case when install_links_in_schema = 'Yes' then 'Yes' else 'No' end) over () has_any_install_links
		bulk collect into v_allowed_privs
		from
		(
			--Requested privileges
			select column_value target, v_run_as_sys run_as_sys, v_is_shell_script run_shell_script
			from table(method5.m5_pkg.get_target_tab_from_target_str
				(
					p_target_string => p_target_string_with_default,
					p_database_or_host => v_database_or_host
				)
			)
			order by column_value
		) requested_privileges
		join method5.m5_allowed_privs_vw allowed_privileges
			on requested_privileges.target = allowed_privileges.target
		where trim(lower(oracle_username)) = lower(sys_context('userenv', 'session_user'))
			and 
			(
				(requested_privileges.run_as_sys = 'Yes' and allowed_privileges.can_run_as_sys = 'Yes')
				or
				requested_privileges.run_as_sys = 'No'
			)
			and
			(
				(requested_privileges.run_shell_script = 'Yes' and allowed_privileges.can_run_shell_script = 'Yes')
				or
				requested_privileges.run_shell_script = 'No'
			)
		order by requested_privileges.target;

		return v_allowed_privs;
	end get_allowed_privs;

	---------------------------------------------------------------------------
	--Set P_TABLE_OWNER and P_TABLE_NAME_WITHOUT_OWNER.
	--Both are trimmed and upper-cased to use in data dictionary queries later.
	--P_TABLE_OWNER defaults to the current user.
	--P_TABLE_NAME defaults to a name with a sequence.
	procedure set_table_owner_and_name(
		p_table_name                in varchar2,
		p_sequence                  in number,
		p_table_owner              out varchar2,
		p_table_name_without_owner out varchar2
	) is
		v_count number;
	begin
		--Defaults.
		if p_table_name is null then
			p_table_owner := sys_context('userenv', 'session_user');
			p_table_name_without_owner := 'M5_TEMP_'||p_sequence;
		else
			--Split into owner and name if there is a period.
			if instr(p_table_name, '.') > 0 then
				p_table_owner := upper(trim(substr(p_table_name, 1, instr(p_table_name, '.') - 1)));
				p_table_name_without_owner := upper(trim(substr(p_table_name, instr(p_table_name, '.') + 1)));

				--Check that the user exists.
				select count(*)
				into v_count
				from all_users
				where username = upper(trim(p_table_owner));

				--Raise error if the user doesn't exist.
				if v_count = 0 then
					raise_application_error(-20024, 'This user specified in P_TABLE_NAME does not exist: '||
						p_table_owner||'.');
				end if;
			--Else use default owner and use table name.
			else
				p_table_owner := sys_context('userenv', 'session_user');
				p_table_name_without_owner := upper(trim(p_table_name));
			end if;
		end if;
	end set_table_owner_and_name;

	---------------------------------------------------------------------------
	--Create an audit row for every run.
	function audit(
		p_code                varchar2,
		p_targets             varchar2,
		p_table_name          varchar2,
		p_asynchronous        boolean,
		p_table_exists_action varchar2,
		p_run_as_sys          boolean
	) return rowid is
		v_asynchronous varchar2(3) := case when p_asynchronous then 'Yes' else 'No' end;
		v_run_as_sys varchar2(3) := case when p_run_as_sys then 'Yes' else 'No' end;
		v_rowid rowid;
	begin
		insert into method5.m5_audit
		values
		(
			sys_context('userenv', 'session_user'),
			sysdate,
			upper(p_table_name),
			p_code,
			p_targets,
			v_asynchronous,
			p_table_exists_action,
			v_run_as_sys,
			null,
			null,
			null,
			null,
			null
		)
		returning rowid into v_rowid;

		commit;

		return v_rowid;
	end audit;

	---------------------------------------------------------------------------
	--Determine if the code is a shell script.
	--Currently only Linux and Unix shell scripts are supported.
	function is_shell_script(p_code varchar2) return boolean is
	begin
		--The shebang must be the very first character.
		if p_code like '#!%' then
			return true;
		--But it's a common mistake to have some spaces, newlines, or tabs in front.
		--Throw a custom error if there are spaces in front.
		elsif replace(replace(replace(replace(p_code, ' '), '	'), chr(10)), chr(13)) like '#!%' then
			raise_application_error(-20032, 'The shell script shebang must be at the '||
				'beginning of the file.  There should not be any whitespace before it.');
		else
			return false;
		end if;
	end is_shell_script;

	---------------------------------------------------------------------------
	--Verify that the user can use Method5.
	--This package has elevated privileges and must only be used by a true DBA.
	procedure control_access(p_audit_rowid rowid, p_config_data config_data_rec) is
		v_account_status varchar2(4000);

		procedure audit_send_email_raise_error(p_message in varchar2) is
		begin
			--Add the message to the audit trail.
			update method5.m5_audit
			set access_control_error = p_message
			where rowid = p_audit_rowid;

			commit;

			--Only try to send an email if there is an address configured.
			if p_config_data.admin_email_sender_address is not null then
				sys.utl_mail.send(
					sender => p_config_data.admin_email_sender_address,
					recipients => p_config_data.admin_email_recipients,
					subject => 'Method5 access denied',
					message => 'The database user '||sys_context('userenv', 'session_user')||
						' (OS user '||sys_context('userenv', 'os_user')||') tried to use Method5.'||
						chr(10)||chr(10)||'Access was denied because: '||p_message
				);
			end if;

			raise_application_error(-20002, 'Access denied and an email was sent to the administrator(s).  '||
				p_message||'  Only authorized users can use this package.');
		end audit_send_email_raise_error;

	begin
		--Check that the database username is correct.
		if p_config_data.has_valid_db_username = 'No' then
			audit_send_email_raise_error('You are not logged into the expected Orace username.');
		end if;

		--Check both database and operating system username, if the configuration requires it.
		if p_config_data.access_control_os_username = 'ENABLED' and p_config_data.has_valid_db_and_os_username = 'No' then
			audit_send_email_raise_error('You are not logged into the expected client OS username.');
		end if;

		--Check that the account is not locked.
		if p_config_data.access_control_locked = 'ENABLED' then
			--Get the account status.
			select account_status
			into v_account_status
			from sys.dba_users
			where username = sys_context('userenv', 'session_user');

			--Check account status.
			if v_account_status like '%LOCKED%' then
				audit_send_email_raise_error('Your account must not be locked.');
			end if;
		end if;

	end control_access;

	---------------------------------------------------------------------------
	--Validate that input is sane.
	procedure validate_input(p_table_exists_action varchar2) is
	begin
		if p_table_exists_action not in ('ERROR', 'APPEND', 'DELETE', 'DROP') then
			raise_application_error(-20005, 'P_TABLE_EXISTS_ACTION must be one of '||
				'ERROR, APPEND, DELETE, or DROP.');
		end if;
	end validate_input;

	---------------------------------------------------------------------------
	--Create a link refresh job for this user if it does not exist and if
	--they are allowed to use any database links directly.
	--These jobs let the administrator automatically update user's links.
	procedure create_link_refresh_job(p_allowed_privs allowed_privs_nt) is
		v_count number;
	begin
		if p_allowed_privs.count >= 1 and p_allowed_privs(1).has_any_install_links = 'Yes' then
			--Look for job.
			select count(*)
			into v_count
			from sys.dba_scheduler_jobs
			where owner = sys_context('userenv', 'session_user')
				and job_name = 'M5_LINK_REFRESH_JOB';

			--Create job if it does not exist.
			if v_count = 0 then
				sys.dbms_scheduler.create_job(
					job_name   => sys_context('userenv', 'session_user')||'.M5_LINK_REFRESH_JOB',
					job_type   => 'PLSQL_BLOCK',
					job_action => q'[ begin m5_proc('select * from dual', '%'); end; ]',
					enabled    => false,
					comments   => 'This job helps refresh the M5 links in this schema.',
					auto_drop  => false
				);
			end if;
		end if;
	end create_link_refresh_job;

	---------------------------------------------------------------------------
	--Add the default targets if null, else return the original string.
	function add_default_targets_if_null(p_targets varchar2, p_config_data config_data_rec) return varchar2 is
	begin
		--Return the string if it's not null.
		if trim(p_targets) is not null then
			return p_targets;
		--Use the per-user default, if it's available.
		else
			--Return per-user default if it exists.
			if p_config_data.user_default_targets is not null then
				return p_config_data.user_default_targets;
			--Return the global default otherwise.
			else
				return p_config_data.global_default_targets;
			end if;
		end if;
	end add_default_targets_if_null;

	---------------------------------------------------------------------------
	--Get database link configuration from M5_DATABASE configuration table.
	function get_links(p_owner varchar2) return links_nt is
		v_link_sql varchar2(32767);
		v_link_query sys_refcursor;
		v_link_results links_nt;
	begin
		--Add link and job data to database name query.
		v_link_sql :=
		q'[
			--Method5 link query.
			select
				link_name,
				database_name,
				host_name,
				connect_string,
				case when my_database_links.db_link is not null then 1 else 0 end link_exists
			from
			(
				--Links for databases.
				select
					'M5_'||upper(database_name) link_name,
					lower(database_name) database_name,
					null host_name,
					connect_string,
					to_char(row_number() over (partition by database_name order by instance_name)) instance_number
				from method5.m5_database
				union all
				--Links for hosts.
				select
					'M5_'||upper(host_name) link_name,
					null database_name,
					lower(host_name) host_name,
					min(connect_string) connect_string,
					'1' instance_number
				from method5.m5_database
				group by host_name
			) database_names
			left join
			(
				--Current user's database links.
				select db_link
				from sys.dba_db_links
				where owner = :owner
			) my_database_links
				on database_names.link_name = db_link
			where instance_number = 1
			order by lower(link_name)
		]';

		--Open, fetch, close, and return results.
		open v_link_query for v_link_sql using p_owner;
		fetch v_link_query bulk collect into v_link_results;
		close v_link_query;
		return v_link_results;

	exception when others then
		sys.dbms_output.put_line(':owner bind variable value: '||p_owner);
		sys.dbms_output.put_line('Database Name Query: '||chr(10)||v_link_sql);
		raise_application_error(-20001, 'Error querying M5_DATABASE.'||
			'  Check that table for configuration errors.  Or check the DBMS_OUTPUT for the query.'||
			chr(10)||sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end get_links;

	---------------------------------------------------------------------------
	--Create database links for the Method5 user.
	procedure create_db_links_in_m5_schema(p_links_owned_by_m5 links_nt, p_sequence number) is
		v_sql varchar2(32767);

		pragma autonomous_transaction;
	begin
		--Create any link that doesn't exist.
		for v_link_index in 1 .. p_links_owned_by_m5.count loop
			if p_links_owned_by_m5(v_link_index).link_exists = 0 then
				--Build procedure to create a link.
				v_sql := replace(replace(replace(q'<
					create or replace procedure method5.m5_temp_procedure_##SEQUENCE## is
					begin
						execute immediate q'!
							create database link ##DB_LINK_NAME##
							connect to method5
							identified by not_a_real_password_yet
							using '##CONNECT_STRING##'
						!';
					end;
				>'
				,'##SEQUENCE##', to_char(p_sequence))
				,'##DB_LINK_NAME##', p_links_owned_by_m5(v_link_index).db_link_name)
				,'##CONNECT_STRING##', p_links_owned_by_m5(v_link_index).connect_string);

				--Create procedure.
				execute immediate v_sql;
				commit;

				--Execute procedure to create the link, then correct the password.
				--No matter what happens, drop the temp procedure since it has a password hash in it.
				begin
					execute immediate 'begin method5.m5_temp_procedure_'||p_sequence||'; end;';
					commit;
					sys.m5_change_db_link_pw(p_m5_username => 'METHOD5', p_dblink_username => 'METHOD5', p_dblink_name => p_links_owned_by_m5(v_link_index).db_link_name);
					commit;
					execute immediate 'drop procedure method5.m5_temp_procedure_'||p_sequence;
					commit;
				exception when others then
					raise_application_error(-20003, 'Error executing or dropping '||
						'method5.m5_temp_procedure_'||p_sequence||'.  Investigate that procedure and drop it when done.'||
						chr(10)||sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
				end;
			end if;
		end loop;
		commit;
	end create_db_links_in_m5_schema;

	---------------------------------------------------------------------------
	--Copy links from package owner to the running user.
	procedure synchronize_links(p_allowed_privs allowed_privs_nt) is
		v_sql varchar2(32767);
		pragma autonomous_transaction;

		--Procedures to create, run, and drop procedures on the user's schema.
		procedure create_temp_proc(p_sql varchar2) is
		begin
			execute immediate replace(replace(q'[
				create or replace procedure #OWNER#.m5_temp_create_db_link is
				begin
					--This is a temporary procedure used by Method5.
					--You may safely drop this procedure.
					execute immediate q'!
						#SQL#
					!';
				end;
			]'
			, '#OWNER#', sys_context('userenv', 'session_user'))
			, '#SQL#', p_sql);
		end;

		procedure run_temp_proc is
		begin
			execute immediate replace(
				'begin #OWNER#.m5_temp_create_db_link; end;'
			, '#OWNER#', sys_context('userenv', 'session_user'));
		end;

		procedure drop_temp_proc is
		begin
			execute immediate replace(
				'drop procedure #OWNER#.m5_temp_create_db_link'
			, '#OWNER#', sys_context('userenv', 'session_user'));
		end;
	begin
		--Only run this if the user is allowed to have links.
		if p_allowed_privs.count >= 1 and p_allowed_privs(1).has_any_install_links = 'Yes' then
			--Create missing links.
			for missing_links in
			(
				--Links that might need to be copied to user's schema:
				--Default links that do not exist or were created after the user's link
				select default_links.db_link default_db_link, user_links.db_link user_db_link
				from
				(
					select db_link, created
					from sys.dba_db_links
					where db_link like 'M5%'
						--Exclude this link only used by Method5 for installation.
						and db_link <> 'M5_INSTALL_DB_LINK'
						and owner = 'METHOD5'
				) default_links
				left join
				(
					select db_link, created
					from sys.dba_db_links
					where db_link like 'M5%'
						and owner = sys_context('userenv', 'session_user')
				) user_links
					on default_links.db_link = user_links.db_link
				where user_links.db_link is null
					or default_links.created > user_links.created
			) loop
				--Only create the link if the user is authorized to have it.
				for i in 1 .. p_allowed_privs.count loop
					if missing_links.default_db_link = p_allowed_privs(i).db_link_name then
						--Drop user link if it exists
						if missing_links.user_db_link is not null then
							create_temp_proc('drop database link '||missing_links.user_db_link);
							commit;
							run_temp_proc;
							commit;
							drop_temp_proc;
							commit;
						end if;

						--Get the link DDL.
						v_sql := sys.dbms_metadata.get_ddl('DB_LINK', missing_links.default_db_link, 'METHOD5');

						--11.2.0.4 use a bind variable instead of putting the hash in the GET_DDL output.
						if v_sql like '%IDENTIFIED BY VALUES '':1''%' then
							--Replace the bind variable with a temporary password.
							v_sql := replace(v_sql, 'IDENTIFIED BY VALUES '':1''', 'identified by not_a_real_password_yet');
							create_temp_proc(v_sql);
							commit;
							run_temp_proc;
							commit;
							drop_temp_proc;
							commit;

							--Reset the temporary password.
							sys.m5_change_db_link_pw(
								p_m5_username => 'METHOD5',
								p_dblink_username => sys_context('userenv', 'session_user'),
								p_dblink_name => missing_links.default_db_link);
						--11.2.0.3 and below can execute as-is
						else
							create_temp_proc(v_sql);
							commit;
							run_temp_proc;
							commit;
							drop_temp_proc;
							commit;
						end if;
					end if;
				end loop;
			end loop;

			commit;
		end if;
	end synchronize_links;

	---------------------------------------------------------------------------
	--Purpose: Convert allowed_privs_nt into a string_table of targets.
	function get_target_tab
	(
		p_allowed_privs allowed_privs_nt
	) return method5.string_table is
		v_targets method5.string_table := method5.string_table();
	begin
		for i in 1 .. p_allowed_privs.count loop
			v_targets.extend;
			v_targets(v_targets.count) := p_allowed_privs(i).target;
		end loop;

		return v_targets;
	end get_target_tab;

	---------------------------------------------------------------------------
	procedure raise_exception_if_no_targets
	(
		p_allowed_privs     in allowed_privs_nt,
		p_original_targets  in varchar2,
		p_processed_targets in varchar2,
		p_is_shell_script   in boolean
	) is
		v_database_or_host        varchar2(8) := case when p_is_shell_script then 'host' else 'database' end;
		v_targets                 method5.string_table;
		v_how_to_fix_message      varchar2(32767) := 'Change P_TARGETS to fix this error.';
		v_allowed_targets_message varchar2(32767);
	begin
		--Only continue if there are no rows.
		if p_allowed_privs.count = 0 then
			--Convert string to table.
			v_targets := get_target_tab_from_target_str(p_processed_targets, v_database_or_host);

			--Raise error because the target string returns nothing.
			if v_targets.count = 0 then
				--Display only one value if they are the same.
				if
				(
					p_original_targets = p_processed_targets
					or
					(
						p_original_targets is null
						and
						p_processed_targets is null
					)
				) then
					raise_application_error(-20404, 'No targets were found.  '||v_how_to_fix_message||'  '||chr(10)||
						'This was the P_TARGETS you asked for: '||p_original_targets||v_allowed_targets_message);
				--Display both values if they are different.
				else
					raise_application_error(-20404, 'No targets were found.  '||v_how_to_fix_message||'  '||chr(10)||
						'This was the P_TARGETS you asked for: '||p_original_targets||chr(10)||
						'This was the default P_TARGETS used: '||p_processed_targets||v_allowed_targets_message);
				end if;
			--Else raise error because the user has no privileges on the requested targets.
			else
				raise_application_error(-20035, 'You do not have access to any of targets requested.'||chr(10)||
					'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
					'Contact your Method5 administrator to change your access.');
			end if;
		end if;
	end raise_exception_if_no_targets;

	---------------------------------------------------------------------------
	procedure check_if_already_running(p_table_name varchar2) is
		v_table_name varchar2(128) := upper(trim(p_table_name));
		v_conflicting_job_count number;
	begin
		--Look for jobs with the same username and table.
		--ASSUMPTION: Jobs are auto-dropped.
		select count(*)
		into v_conflicting_job_count
		from sys.dba_scheduler_jobs
		where job_name like 'M5%'
			and regexp_replace(comments, 'TABLE:(.*)"CALLER:.*', '\1') = v_table_name
			and regexp_replace(comments, 'TABLE:.*"CALLER:(.*)', '\1') = sys_context('userenv', 'session_user');

		--Raise an error if there are any conflicts.
		if v_conflicting_job_count > 0 then
			raise_application_error(-20009,
				'There are already '||v_conflicting_job_count||' jobs writing to '||v_table_name||'.'||chr(10)||
				'Use this statement to find currently running jobs: '||chr(10)||
				q'!select *!'||chr(10)||
				q'!from dba_scheduler_jobs!'||chr(10)||
				q'!where state in ('SCHEDULED', 'RUNNING')!'||chr(10)||
				q'!  and job_name like 'M5_%'!'||chr(10)||
				q'!  and regexp_replace(comments, 'TABLE:.*"CALLER:(.*)', '\1') = sys_context('userenv', 'session_user')!'||chr(10)||
				q'!order by last_start_date desc, job_name;!'||chr(10)||
				'Either wait for those jobs to finish or stop them with this: begin dbms_scheduler.stop_job(job_name => ''$JOB_NAME$'', force => true); end;'
			);
		end if;
	end check_if_already_running;

	---------------------------------------------------------------------------
	--Return an available quote delimiter so there's no conflict with the user's code.
	function find_available_quote_delimiter(p_code in varchar2) return varchar2 is
	begin
		--Find the first available delimiter and return it.
		for i in 1 .. c_delimiter_candidates.count loop
			if instr(p_code, c_delimiter_candidates(i)||'''') = 0 then
				return c_delimiter_candidates(i);
			end if;
		end loop;

		--Exhausting all identifiers is possible, but incredibly unlikely.
		raise_application_error(-20010, 'You have used every possible quote identifier, '||
			'you must remove at least one from the code.');
	end find_available_quote_delimiter;

	---------------------------------------------------------------------------
	--Get column metadata for a SELECT statement on a remote database.
	procedure get_column_metadata
	(
		p_select_statement         in     clob,
		p_run_as_sys               in     boolean,
		p_database_name            in     varchar2,
		p_has_column_gt_30         in out boolean,
		p_has_long                 in out boolean,
		p_explicit_column_list     in out varchar2,
		p_explicit_expression_list in out varchar2
	) is
		v_has_column_gt_30         number;
		v_has_long                 number;
		v_explicit_column_list     varchar2(32767);
		v_explicit_expression_list varchar2(32767);

		v_template                 varchar2(32767) :=
		q'[
			declare
				v_cursor_number    integer;
				v_column_count     number;
				v_columns          sys.dbms_sql.desc_tab2@m5_#DATABASE_NAME#;
				p_code             varchar2(32767);
				v_column_list      varchar2(32767);
				v_expression_list  varchar2(32767);
				v_has_column_gt_30 number := 0;
				v_has_long         number := 0;
			begin
				p_code := :p_transformed_code;

				--Parse statement, get columns.
				v_cursor_number := sys.dbms_sql.open_cursor@m5_#DATABASE_NAME#;
				sys.dbms_sql.parse@m5_#DATABASE_NAME#(v_cursor_number, p_code, sys.dbms_sql.native);
				sys.dbms_sql.describe_columns2@m5_#DATABASE_NAME#(v_cursor_number, v_column_count, v_columns);

				--Gather metadata.
				for i in 1 .. v_column_count loop
					--A LONG cannot also be part of an expression more than 30 characters long.
					if v_columns(i).col_type in (8, 24) then
						v_expression_list := v_expression_list || ',to_lob("'||v_columns(i).col_name || '") as "' || v_columns(i).col_name || '"';
						v_column_list := v_column_list || ',"'||v_columns(i).col_name || '"';
						v_has_long := 1;
					elsif lengthb(v_columns(i).col_name) >= 31 then
						v_column_list := v_column_list || ',"' || substrb(v_columns(i).col_name, 1, 30)|| '"';
						v_expression_list := v_expression_list || ',"' || substrb(v_columns(i).col_name, 1, 30) || '"';
						v_has_column_gt_30 := 1;
					else
						v_column_list := v_column_list || ',"' || v_columns(i).col_name || '"';
						v_expression_list := v_expression_list || ',"' || v_columns(i).col_name || '"';
					end if;
				end loop;

				--Close the cursor.
				sys.dbms_sql.close_cursor@m5_#DATABASE_NAME#(v_cursor_number);

				--Create new SQL statement
				:v_has_column_gt_30 := v_has_column_gt_30;
				:v_has_long := v_has_long;
				:v_column_list := substr(v_column_list, 2);
				:v_expression_list := substr(v_expression_list, 2);

			end;
		]';
	begin
		--Run as Method5 DBA:
		if not p_run_as_sys then
			--Parse the column names on the remote database.
			execute immediate replace(v_template, '#DATABASE_NAME#', p_database_name)
			using to_char(p_select_statement)
				,out v_has_column_gt_30
				,out v_has_long
				,out v_explicit_column_list
				,out v_explicit_expression_list;
		--Run as SYS:
		else
			null;
			execute immediate replace('
				begin
					sys.m5_runner.get_column_metadata@m5_#DATABASE_NAME#(
						:v_template,
						:p_select_statement,
						:v_has_column_gt_30,
						:v_has_long,
						:v_explicit_column_list,
						:v_explicit_expression_list
					);
				end;
			'
			, '#DATABASE_NAME#', p_database_name)
			using replace(v_template, '@m5_#DATABASE_NAME#')
				,method5.m5_pkg.get_encrypted_raw(p_database_name, p_select_statement)
				,in out v_has_column_gt_30
				,in out v_has_long
				,in out v_explicit_column_list
				,in out v_explicit_expression_list;
		end if;

		--Set OUT variables.
		p_has_column_gt_30 := case when v_has_column_gt_30 = 1 then true else false end;
		p_has_long := case when v_has_long = 1 then true else false end;
		p_explicit_column_list := v_explicit_column_list;
		p_explicit_expression_list := v_explicit_expression_list;

	end get_column_metadata;

	---------------------------------------------------------------------------
	--Get a Create Table As SQL (CTAS) for a SELECT statement.
	--This gets tricky because of the version star, LONGs, and unnamed expressions.
	function get_ctas_sql
	(
		p_code                     in varchar2,
		p_owner                    in varchar2,
		p_table_name               in varchar2,
		p_has_version_star         in boolean,
		p_has_column_gt_30         in boolean,
		p_has_long                 in boolean,
		p_column_list              in varchar2,
		p_expression_list          in varchar2,
		p_add_database_name_column in boolean,
		p_copy_data                in boolean
	) return varchar2 is
		v_ctas     varchar2(32767);
		v_db_name  varchar2(100);
		v_filter   varchar2(100);
		v_template varchar2(32767);
	begin
		--Set some components.
		v_ctas := 'create table '||p_owner||'.'||p_table_name||' nologging pctfree 0 as';

		if p_add_database_name_column then
			v_db_name := 'cast(''database name'' as varchar2(30)) database_name, ';
		end if;

		if not p_copy_data then
			v_filter := chr(10) || '				where 1 = 0 and rownum < 0';
		end if;

		--Check for incorrect settings.
		if p_has_long and p_expression_list is null then
			raise_application_error(-20028, 'The expression list is NULL.');
		elsif (p_has_version_star or p_has_column_gt_30 or p_has_long) and p_column_list is null then
			raise_application_error(-20029, 'The column list is NULL.');
		end if;

		--Choose a template based on the options.
		--
		--These are the different types of query formats, depending on if the user specified the query star,
		--if one of the columns is larger than 30 bytes, or if a column has a LONG.
		-- QUERY TYPE      FORMAT
		-- ==========      ======
		-- >30 and LONG*   #CTAS# with cte(#COLUMN_LIST) as (#CODE#) select #DB_NAME_COLUMN##EXPRESSION_LIST from cte #FILTER#
		-- LONG*           #CTAS# select #DB_NAME_COLUMN##EXPRESSION_LIST from (#CODE#) subquery #FILTER#
		-- >30*            #CTAS# with cte(#COLUMN_LIST) as (#CODE#) select #DB_NAME_COLUMN#cte.* from cte #FILTER#
		-- version star    #CTAS# select #DB_NAME_COLUMN##COLUMN_LIST# from (#CODE#) #FILTER#
		-- simple          #CTAS# select #DB_NAME_COLUMN#subquery.* from (#CODE#) subquery #FILTER#
		--
		-- * - Also works for version star.

		if p_has_column_gt_30 and p_has_long then
			v_template := q'[
				#CTAS#
				with cte(#COLUMN_LIST#) as
				(
					#CODE#
				)
				select /*+ no_gather_optimizer_statistics */ #DB_NAME_COLUMN##EXPRESSION_LIST#
				from cte#FILTER#]';
		elsif p_has_long then
			v_template := q'[
				#CTAS#
				select /*+ no_gather_optimizer_statistics */ #DB_NAME_COLUMN##EXPRESSION_LIST#
				from (#CODE#) subquery#FILTER#]';

		elsif p_has_column_gt_30 then
			v_template := q'[
				#CTAS#
				with cte(#COLUMN_LIST#) as
				(
					#CODE#
				)
				select /*+ no_gather_optimizer_statistics */ #DB_NAME_COLUMN#cte.*
				from cte#FILTER#]';
		elsif p_has_version_star then
			v_template := q'[
				#CTAS#
				select /*+ no_gather_optimizer_statistics */ #DB_NAME_COLUMN##COLUMN_LIST#
				from
				(
					#CODE#
				)#FILTER#]';
		else
			v_template := q'[
				#CTAS#
				select /*+ no_gather_optimizer_statistics */ #DB_NAME_COLUMN#subquery.*
				from
				(
					#CODE#
				) subquery#FILTER#]';
		end if;

		--Populate the template.
		v_template := replace(replace(replace(replace(replace(replace(v_template,
			'#CTAS#', v_ctas),
			'#DB_NAME_COLUMN#', v_db_name),
			'#FILTER#', v_filter),
			'#COLUMN_LIST#', p_column_list),
			'#EXPRESSION_LIST#', p_expression_list),
			'#CODE#', p_code
		);

		return v_template;
	end get_ctas_sql;

	---------------------------------------------------------------------------
	--Transform the code so it is ready to run and return if it's SQL or PLSQL.
	--The transformation will remove unnecessary terminators (so it can run in EXECUTE IMMEDIATE).
	--SQL and PL/SQL blocks are ready to run.  Other statement types, like ALTER SYSTEM and
	--UPDATE, must be wrapped in a PL/SQL block, committed, and print a message that returns
	--useful information.  The return message is formatted in a way so that it can be read
	--later and converted into something similar to a SQL*Plus feedback message.
	procedure get_transformed_code_and_type(
		p_original_code            in     clob,
		p_run_as_sys               in     boolean,
		p_is_shell_script          in     boolean,
		p_target_tab               in     string_table,
		p_transformed_code            out clob,
		p_encrypted_code              out clob,
		p_select_plsql_script         out varchar2,
		p_is_first_column_sortable    out boolean,
		p_command_name                out varchar2,
		p_has_version_star         in out boolean,
		p_has_column_gt_30         in out boolean,
		p_has_long                 in out boolean,
		p_explicit_column_list        out varchar2,
		p_explicit_expression_list    out varchar2
	) is

		v_tokens          method5.token_table;

		v_category              varchar2(100);
		v_statement_type        varchar2(100);
		v_command_type          number;
		v_lex_sqlcode           number;
		v_lex_sqlerrm           varchar2(4000);

		v_version_star_position number;

		---------------------------------------------------------------------------
		--Look for the version star, "**", and return the position.
		--Return 0 if it is not found or does not apply.
		function get_version_star_position(p_transformed_code in clob, p_command_name in varchar2, p_tokens method5.token_table)
		return number is
			v_version_star_position number := 0;
		begin
			--Only bother to look for SELECTs.
			if p_command_name = 'SELECT' then
				--Check the CLOB as a string first.
				--This is inaccurate but fast, and can quickly discard most code without a version star.
				if sys.dbms_lob.instr(lob_loc => p_transformed_code, pattern => '**') > 0 then
					--Look for "**" preceeded by "SELECT".  Ignore whitespace and comments.
					--May need to add an extra space around the star.
					for i in 1 .. p_tokens.count-1 loop
						--Look for a SELECT.
						if p_tokens(i).type = method5.plsql_lexer.C_WORD and lower(p_tokens(i).value) = 'select' then
							--Look for the next "**".
							for j in i+1 .. p_tokens.count loop
								--Ignore whitespace and comments.
								if p_tokens(j).type in (method5.plsql_lexer.C_WHITESPACE, method5.plsql_lexer.C_COMMENT) then
									null;
								--Return position if "**" found.
								elsif p_tokens(j).type = method5.plsql_lexer."C_**" then
									v_version_star_position := p_tokens(j).first_char_position;
									exit;
								--Quit this loop if something else was found.
								else
									exit;
								end if;
							end loop;
						end if;
					end loop;
				end if;
			end if;

			return v_version_star_position;
		end get_version_star_position;

		---------------------------------------------------------------------------
		--Replace the "**" with a regular "*".  We'll need to run this version to get the column list first.
		procedure transform_version_star_to_star(p_transformed_code in out clob, p_version_star_position in number) is
		begin
			if p_version_star_position > 0 then
				p_transformed_code :=
					substr(p_transformed_code, 1, p_version_star_position-1) ||
					'*' ||
					substr(p_transformed_code, p_version_star_position + 2);
			end if;
		end transform_version_star_to_star;

		---------------------------------------------------------------------------
		--Get the column metadata (for the lowest version of the database) that may be used instead of a "*" later.
		procedure get_lowest_column_metadata(
			p_transformed_code         in     clob,
			p_run_as_sys               in     boolean,
			p_version_star_position    in     number,
			p_database_names           in     string_table,
			p_has_version_star         in out boolean,
			p_has_column_gt_30         in out boolean,
			p_has_long                 in out boolean,
			p_explicit_column_list     in out varchar2,
			p_explicit_expression_list in out varchar2
		) is
			v_databases_ordered_by_version string_table;
			type number_nt is table of number;
			v_distinct_version_count number_nt;
		begin
			--Only change things if a version star was used.
			if p_version_star_position > 0 then

				--Order the database names by lowest version first.
				execute immediate
				q'[
					select
						database_name, distinct_version_count
					from
					(
						select
							database_name,
							target_version,
							to_number(regexp_substr(target_version, '[0-9]+', 1, 1)) version_1,
							to_number(regexp_substr(target_version, '[0-9]+', 1, 2)) version_2,
							to_number(regexp_substr(target_version, '[0-9]+', 1, 3)) version_3,
							to_number(regexp_substr(target_version, '[0-9]+', 1, 4)) version_4,
							to_number(regexp_substr(target_version, '[0-9]+', 1, 5)) version_5,
							count(distinct target_version) over () distinct_version_count
						from m5_database
						where target_version is not null
							and lower(database_name) in
							(
								select lower(column_value) database_name
								from table(:database_names) database_names
							)
					)
					order by version_1, version_2, version_3, version_4, version_5, database_name
				]'
				bulk collect into v_databases_ordered_by_version, v_distinct_version_count
				using p_database_names;

				--SPECIAL CASE: Do nothing if no targets were specified.
				if v_databases_ordered_by_version.count = 0 then
					return;
				end if;

				--SPECIAL CASE: Don't use version star processing if there is only one version.
				if v_distinct_version_count(1) = 1 then
					p_has_version_star := false;
					return;
				end if;

				--Get column list from lowest version using DBMS_SQL over the database link.
				declare
					v_successful_database_index number;
					v_failed_database_list varchar2(32767);
					v_last_sqlerrm varchar2(32767);
				begin
					--Try to create the temporary table on the first N databases.
					for i in 1 .. least(c_max_database_attempts, v_databases_ordered_by_version.count) loop
						begin
							--Parse the column names on the remote database.
							get_column_metadata(p_transformed_code, p_run_as_sys, v_databases_ordered_by_version(i), p_has_column_gt_30, p_has_long, p_explicit_column_list, p_explicit_expression_list);

							--Record a success and quit the loop if it got this far.
							v_successful_database_index := i;
							exit;

						--If it fails on one database we'll try again on another.
						exception when others then
							v_last_sqlerrm := sqlerrm;
							v_failed_database_list := v_failed_database_list || ',' || v_databases_ordered_by_version(i);
						end;
					end loop;

					--Raise an error if none of the databases worked.
					if v_successful_database_index is null then
						raise_application_error(-20027, 'The SELECT statement was not valid, please check the syntax'||
							' and that the objects exist.  The statement was tested on '||substr(v_failed_database_list,2)||
							'.  If the objects only exist on a small number of'||
							' databases you may want to run Method5 first with P_TARGETS set to one database that has the'||
							' objects.  The SQL raised this error: '||chr(10)||v_last_sqlerrm);
					end if;
				end;
			end if;

		end get_lowest_column_metadata;

		---------------------------------------------------------------------------
		procedure version_star_set_code_and_list
		(
			p_transformed_code         in out clob,
			p_run_as_sys               in     boolean,
			p_command_name             in     varchar,
			p_tokens                   in     method5.token_table,
			p_has_version_star         in out boolean,
			p_has_column_gt_30         in out boolean,
			p_has_long                 in out boolean,
			p_explicit_column_list        out varchar2,
			p_explicit_expression_list    out varchar2,
			p_database_names           in     method5.string_table
		) is
			v_version_star_position number;
		begin
			--Check for the version star, "**".
			v_version_star_position := get_version_star_position(p_transformed_code, p_command_name, p_tokens);
			if v_version_star_position > 0 then
				p_has_version_star := true;
			end if;

			--Convert the version star back into a regular star, if necessary.
			transform_version_star_to_star(p_transformed_code, v_version_star_position);

			--Retrieve column metadata because "*" may need to be converted to an explicit list later.
			get_lowest_column_metadata(p_transformed_code, p_run_as_sys, v_version_star_position, p_database_names, p_has_version_star, p_has_column_gt_30, p_has_long, p_explicit_column_list, p_explicit_expression_list);
		end version_star_set_code_and_list;

	begin
		--Shell scripts don't require any lexical analysis or other processing
		if p_is_shell_script then
			p_transformed_code         := p_code;
			p_encrypted_code           := null;
			p_select_plsql_script      := 'SCRIPT';
			p_is_first_column_sortable := true;
			p_command_name             := null;
			p_has_version_star         := false;
			p_has_column_gt_30         := false;
			p_has_long                 := false;
			p_explicit_column_list     := null;
			p_explicit_expression_list := null;
			return;
		end if;

		--Assume the first column is sortable, unless proven false elsewhere.
		p_is_first_column_sortable := true;

		--Tokenize.
		v_tokens := method5.plsql_lexer.lex(p_original_code);

		--Remove terminator, if any.
		v_tokens := method5.statement_terminator.remove_sqlplus_del_and_semi(v_tokens);

		--Classify.
		method5.statement_classifier.classify(
			v_tokens,v_category,v_statement_type,p_command_name,v_command_type,v_lex_sqlcode,v_lex_sqlerrm
		);

		--Check for any obvious errors.
		if v_lex_sqlerrm is not null then
			raise_application_error(-20013, 'There is a serious syntax error in the '||
				'code you submitted.  Fix the syntax and try again: '||chr(10)||
				'ORA'||v_lex_sqlcode||': '||v_lex_sqlerrm);
		end if;

		--Put tokens back together.
		p_transformed_code := method5.plsql_lexer.concatenate(v_tokens);

		--Handle version star by transforming the code from "**" to "*" and setting column metadata.
		version_star_set_code_and_list(p_transformed_code, p_run_as_sys, p_command_name, v_tokens, p_has_version_star, p_has_column_gt_30, p_has_long, p_explicit_column_list, p_explicit_expression_list, p_target_tab);

		--Change the output depending on the type.
		--
		--Do nothing to SELECT.
		if p_command_name = 'SELECT' then
			p_select_plsql_script := 'SELECT';
		--Do nothing to PL/SQL (unless it's to be run as SYS).
		elsif p_command_name = 'PL/SQL EXECUTE' then
			p_select_plsql_script := 'PLSQL';
			p_is_first_column_sortable := false;

			if p_run_as_sys then
				p_encrypted_code := replace(
					q'[, '$$ENCRYPTED_RAW$$', method5.m5_pkg.get_encrypted_raw('##DATABASE_NAME##', q'##QUOTE_DELIMITER2## ##CODE## ##QUOTE_DELIMITER2##'))]'
					, '##CODE##', p_transformed_code);

				p_transformed_code :=
					replace(replace(
						q'[
							begin
								sys.m5_runner.run_as_sys('$$ENCRYPTED_RAW$$');
								commit;
							end;
						]'
						, '##QUOTE_DELIMITER##', find_available_quote_delimiter(p_transformed_code))
						, '##CODE##', p_transformed_code);
			end if;

		--CALL METHOD needs to be wrapped in PL/SQL.
		elsif p_command_name = 'CALL METHOD' then
			p_select_plsql_script := 'PLSQL';
			p_is_first_column_sortable := false;

			if not p_run_as_sys then
				p_transformed_code :=
					replace(replace(
						q'[
							begin
								execute immediate q'##QUOTE_DELIMITER## ##CODE## ##QUOTE_DELIMITER##';
								commit;
							end;
						]'
						, '##QUOTE_DELIMITER##', find_available_quote_delimiter(p_transformed_code))
						, '##CODE##', p_transformed_code);
			else
				p_encrypted_code := replace(
					q'[, '$$ENCRYPTED_RAW$$', method5.m5_pkg.get_encrypted_raw('##DATABASE_NAME##', q'##QUOTE_DELIMITER2## ##CODE## ##QUOTE_DELIMITER2##'))]'
					, '##CODE##', p_transformed_code);

				p_transformed_code :=
					replace(replace(
						q'[
							begin
								sys.m5_runner.run_as_sys('$$ENCRYPTED_RAW$$');
								commit;
							end;
						]'
						, '##QUOTE_DELIMITER##', find_available_quote_delimiter(p_transformed_code))
						, '##CODE##', p_transformed_code);
			end if;
		--Raise error if unexpected statement type.
		elsif p_command_name in ('Invalid', 'Nothing') then
			--Raise special error if the user makes the somewhat common mistake of submitting SQL*Plus commands.
			for i in 1 .. v_tokens.count loop
				--Ignore whitespace and comments.
				if v_tokens(i).type in (plsql_lexer.c_whitespace, plsql_lexer.c_comment) then
					null;
				--Look at concrete tokens for SQL*Plus keywords.
				elsif upper(v_tokens(i).value) in
				(
					'@','@@','ACCEPT','APPEND','ARCHIVE','ATTRIBUTE','BREAK','BTITLE','CHANGE',
					'CLEAR','COLUMN','COMPUTE','CONNECT','COPY','DEFINE','DEL','DESCRIBE',
					'DISCONNECT','EDIT','EXECUTE','EXIT','GET','HELP','HISTORY','HOST','INPUT',
					'LIST','PASSWORD','PAUSE','PRINT','PROMPT','RECOVER','REMARK','REPFOOTER',
					'REPHEADER','RUN','SAVE','SET','SHOW','SHUTDOWN','SPOOL','START','STARTUP',
					'STORE','TIMING','TTITLE','UNDEFINE','VARIABLE','WHENEVER','XQUERY'
				) then
					raise_application_error(-20004, 'The code is not a valid SQL or PL/SQL statement.'||
						'  It looks like a SQL*Plus command and Method5 does not yet run SQL*Plus.'||
						'  Try wrapping the script in a PL/SQL block, like this: begin <statements> end;');
					exit;
				--Not SQL*Plus, exit and raise generic error message later.
				else
					exit;
				end if;
			end loop;

			--Raise a generic error message, not sure what the problem is.
			raise_application_error(-20014, 'The code submitted does not look like a '||
				'valid SQL or PL/SQL statement.  Fix the syntax and try again.');
		--Wrap everything else in PL/SQL and handle the feedback message.
		else
			p_select_plsql_script := 'PLSQL';

			if not p_run_as_sys then
				p_transformed_code :=
					replace(replace(replace(
						q'[
							begin
								execute immediate q'##QUOTE_DELIMITER## ##CODE## ##QUOTE_DELIMITER##';
								sys.dbms_output.put_line('M5_FEEDBACK_MESSAGE:COMMAND_NAME=##COMMAND_NAME##;ROWCOUNT='||sql%rowcount);
								commit;
							end;
						]'
						, '##QUOTE_DELIMITER##', find_available_quote_delimiter(p_transformed_code))
						, '##CODE##', p_transformed_code)
						, '##COMMAND_NAME##', p_command_name);
			else
				p_encrypted_code := replace(
					q'[, '$$ENCRYPTED_RAW$$', method5.m5_pkg.get_encrypted_raw('##DATABASE_NAME##', q'##QUOTE_DELIMITER2## ##CODE## ##QUOTE_DELIMITER2##'))]'
					, '##CODE##', p_transformed_code);

				p_transformed_code :=
					replace(replace(replace(
						q'[
							begin
								sys.m5_runner.run_as_sys('$$ENCRYPTED_RAW$$');
								sys.dbms_output.put_line('M5_FEEDBACK_MESSAGE:COMMAND_NAME=##COMMAND_NAME##;ROWCOUNT='||sql%rowcount);
								commit;
							end;
						]'
						, '##QUOTE_DELIMITER##', find_available_quote_delimiter(p_transformed_code))
						, '##CODE##', p_transformed_code)
						, '##COMMAND_NAME##', p_command_name);
			end if;
		end if;

	end get_transformed_code_and_type;

	---------------------------------------------------------------------------
	procedure check_table_name_and_prep(p_table_owner varchar2, p_table_name varchar2, p_table_exists_action varchar2) is
		v_count number;
		v_drop_table_error_message varchar2(1000);
		v_drop_table_plsql varchar2(4000);
		v_delete_table_plsql varchar2(4000);
		v_return varchar2(1000);
		invalid_sql_name exception;
		pragma exception_init(invalid_sql_name, -44003);
		--This prevents weird errors in METHOD5_POLL_TABLE_OT, I'm not sure why.
		pragma autonomous_transaction;
	begin
		--Check length.
		if length(p_table_name) >= 26 then
			raise_application_error(-20015, '"'||p_table_name
				||'" must be 25 characters or less so that the '
				||'_META and _ERR tables can be created.');
		end if;

		--Check if table name is same as a default, public synonym.
		--It *is* possible to do this, but almost certainly a bad idea.
		select count(*)
		into v_count
		from sys.dba_synonyms
		where owner = 'PUBLIC'
			and table_owner in ('SYS', 'SYSMAN', 'SYSTEM', 'XDB')
			and table_name = p_table_name;

		if v_count >= 1 then
			raise_application_error(-20016, 'The table name you specified conflicts '||
			'with a default public synonym.  You almost certainly do not want to create '||
			'a table with this name, it would be very confusing.  Try appending "V_" to the name.');
		end if;

		--Check if exists.
		--
		--Create formatted string for error message, and a PL/SQL block to drop or delete the table.
		select
			case
				when count_of_tables = 0 then
					null
				else
					table_list||' already exist'||case when count_of_tables = 1 then 's' else null end||
					'.  You may want to set the parameter P_TABLE_EXISTS_ACTION to one of APPEND, DELETE, or DROP, '||
					'or manually drop '||case when count_of_tables = 1 then 'it' else 'them' end||
					' like this: '||chr(10)||drop_table_ddl_formatted
			end,
			drop_table_plsql,
			delete_table_plsql
		into v_drop_table_error_message, v_drop_table_plsql, v_delete_table_plsql
		from
		(
			--Aggregated list of tables.
			select
				listagg(owner||'.'||table_name, ', ') within group (order by table_name) table_list,
				listagg('drop table '||owner||'.'||table_name||';', chr(10)) within group (order by table_name) drop_table_ddl_formatted,
				'begin '||chr(10)||
					listagg('	execute immediate ''drop table "'||owner||'"."'||table_name||'" purge'';', chr(10)) within group (order by table_name)||chr(10)||
				'end;' drop_table_plsql,
				'begin '||chr(10)||
					listagg('	delete from "'||owner||'"."'||table_name||'";', chr(10)) within group (order by table_name)||chr(10)||
				'	commit;'||chr(10)||
				'end;' delete_table_plsql,
				count(*) count_of_tables
			from sys.dba_tables
			where owner = p_table_owner
				and table_name in
				(
					p_table_name,
					p_table_name||'_META',
					p_table_name||'_ERR'
				)
		);

		--If there are pre-existing tables, execute a table_exists_action.
		if v_drop_table_error_message is not null then
			if p_table_exists_action = 'ERROR' then
				raise_application_error(-20017, v_drop_table_error_message);
			elsif p_table_exists_action = 'DROP' then
				execute immediate v_drop_table_plsql;
			elsif p_table_exists_action = 'DELETE' then
				execute immediate v_delete_table_plsql;
			elsif p_table_exists_action = 'APPEND' then
				null;
			end if;
		end if;

		--For autonomous transaction.
		commit;

		--Check if valid name.
		v_return := sys.dbms_assert.simple_sql_name(p_table_name);
	exception when invalid_sql_name then
		raise_application_error(-20018, '"'||p_table_name||'" is not a valid table name');
	end check_table_name_and_prep;

	---------------------------------------------------------------------------
	procedure create_data_table
	(
		p_table_owner                     varchar2,
		p_table_name                      varchar2,
		p_code                            varchar2,
		p_run_as_sys                      boolean,
		p_has_version_star                boolean,
		p_has_column_gt_30         in out boolean,
		p_has_long                 in out boolean,
		p_explicit_column_list     in out varchar2,
		p_explicit_expression_list in out varchar2,
		p_select_plsql_script             varchar2,
		p_command_name                    varchar2,
		p_target_tab                      string_table,
		p_sequence                        number,
		p_is_first_column_sortable in out boolean
	) is
		v_data_type varchar2(100);
		v_name_already_used exception;
		pragma exception_init(v_name_already_used, -955);
	begin
		--For SELECTS create a result table to fit columns.
		if p_select_plsql_script = 'SELECT' then
			declare
				v_create_table_ddl varchar(32767);
				v_temp_table_name varchar2(128);
				v_successful_database_index number;
				v_failed_database_list varchar2(32767);
				v_last_error varchar2(32767);

				v_illegal_use_of_long exception;
				v_length_exceeds_maximum exception;
				pragma exception_init(v_illegal_use_of_long, -00997);
				pragma exception_init(v_length_exceeds_maximum, -01948);

				v_database_index number := 0;
				v_retry_counter number := 0;
			begin
				--Generate a temporary table name.
				v_temp_table_name := 'm5_temp_table_'||p_sequence;

				--Create a table to hold the required table structure.
				v_create_table_ddl := get_ctas_sql(
					p_code                     => p_code,
					p_owner                    => 'method5',
					p_table_name               => v_temp_table_name,
					p_has_version_star         => p_has_version_star,
					p_has_column_gt_30         => p_has_column_gt_30,
					p_has_long                 => p_has_long,
					p_column_list              => p_explicit_column_list,
					p_expression_list          => p_explicit_expression_list,
					p_add_database_name_column => true,
					p_copy_data                => false
				);

				--Try to create the temporary table on the first N databases.
				loop
					--Increment and test for limits.
					v_database_index := v_database_index + 1;
					exit when v_database_index > least(c_max_database_attempts, p_target_tab.count);

					--Try to create the table, handle errors.
					begin
						--Create the table.
						if p_run_as_sys then
							execute immediate replace(q'[
								begin
									sys.m5_runner.run_as_sys@m5_##DATABASE_NAME##(:encrypted_raw);
								end;
							]'
							, '##DATABASE_NAME##', p_target_tab(v_database_index)
							)
							using get_encrypted_raw(p_target_tab(v_database_index), v_create_table_ddl);
						else
							execute immediate replace(replace(replace(q'[
								begin
									sys.dbms_utility.exec_ddl_statement@m5_##DATABASE_NAME##(q'##QUOTE_DELIMITER1##
										##CTAS##
									##QUOTE_DELIMITER1##');
								end;
							]'
							, '##DATABASE_NAME##', p_target_tab(v_database_index))
							, '##CTAS##', v_create_table_ddl)
							, '##QUOTE_DELIMITER1##', find_available_quote_delimiter(v_create_table_ddl));
						end if;

						--Record the successful database index and exit the loop.
						v_successful_database_index := v_database_index;
						exit;

					--If it fails on one database we'll try again on another.
					exception
					when v_illegal_use_of_long or v_length_exceeds_maximum then
						--Try again with explicit column metadata to avoid LONG or identifiers over 30 bytes.
						--But only retry it once.
						if v_retry_counter = 0 then
							--Recreate the CTAS based on an explicit column listGet new list
							get_column_metadata(p_code, p_run_as_sys, p_target_tab(v_database_index), p_has_column_gt_30, p_has_long, p_explicit_column_list, p_explicit_expression_list);
							v_create_table_ddl := get_ctas_sql(
								p_code                     => p_code,
								p_owner                    => 'method5',
								p_table_name               => v_temp_table_name,
								p_has_version_star         => p_has_version_star,
								p_has_column_gt_30         => p_has_column_gt_30,
								p_has_long                 => p_has_long,
								p_column_list              => p_explicit_column_list,
								p_expression_list          => p_explicit_expression_list,
								p_add_database_name_column => true,
								p_copy_data                => false
							);

							--Only try this once.
							v_retry_counter := v_retry_counter + 1;

							--Lower the counter to ensure we'll try the database again.
							v_database_index := v_database_index - 1;
						--Else it's just another failure for some weird reason.
						else
							v_last_error := sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace;
							v_failed_database_list := v_failed_database_list || ',' || p_target_tab(v_database_index);
						end if;
					when others then
						v_last_error := sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace;
						v_failed_database_list := v_failed_database_list || ',' || p_target_tab(v_database_index);
					end;
				end loop;

				--Raise an error if none of the databases worked.
				if v_successful_database_index is null then
					raise_application_error(-20030, 'The SELECT statement was not valid, please check the syntax'||
						' and that the objects exist.  The statement was tested on '||substr(v_failed_database_list,2)||
						'.  If the objects only exist on a small number of'||
						' databases you may want to run Method5 first with P_TARGETS set to one database that has the'||
						' objects.  The SQL raised this error: '||chr(10)||v_last_error);
				end if;

				--Create a local table based on the remote table.
				begin
					execute immediate '
						create table '||p_table_owner||'.'||p_table_name||' nologging pctfree 0 as
						select * from method5.'||v_temp_table_name||'@m5_'||p_target_tab(v_successful_database_index);
				--Do nothing if the table already exists.
				--This can happen if they use "DELETE" or "APPEND".
				exception when v_name_already_used then
					null;
				end;
			end;

			--Find out if the second column is an unsortable type.
			select data_type
			into v_data_type
			from sys.dba_tab_columns
			where owner = p_table_owner
				and table_name = p_table_name
				and column_id = 2;

			if v_data_type in ('CLOB', 'NCLOB', 'BLOB') then
				p_is_first_column_sortable := false;
			end if;
		--For non-SELECTs create a generic result table.
		elsif p_select_plsql_script = 'PLSQL' then
			declare
				v_result_type varchar2(100);
			begin
				--Use CLOB for PLSQL_BLOCK (for large DBMS_OUTPUT), use VARCHAR2(4000) for others.
				if p_command_name = 'PL/SQL EXECUTE' then
					v_result_type := 'clob';
				else
					v_result_type := 'varchar2(4000)';
				end if;

				--Create the table.
				begin
					execute immediate '
						create table '||p_table_owner||'.'||p_table_name||'
						(
							database_name	varchar2(30),
							result			'||v_result_type||'
						) nologging pctfree 0';
				exception when v_name_already_used then
					null;
				end;
			end;
		--Shell scripts have a pre-determined table definition.
		elsif p_select_plsql_script = 'SCRIPT' then
			--Create the table.
			begin
				execute immediate '
					create table '||p_table_owner||'.'||p_table_name||'
					(
						host_name   varchar2(256),
						line_number number,
						output      varchar2(4000)
					) nologging pctfree 0';
			exception when v_name_already_used then
				null;
			end;


		end if;
	end create_data_table;

	---------------------------------------------------------------------------
	procedure create_meta_table(
		p_table_owner      varchar2,
		p_table_name       varchar2,
		p_sequence         number,
		p_code             varchar2,
		p_targets          varchar2,
		p_targets_expected number,
		p_audit_rowid      rowid
	) is
		v_name_already_used exception;
		pragma exception_init(v_name_already_used, -955);
		--This prevents weird errors in METHOD5_POLL_TABLE_OT, I'm not sure why.
		pragma autonomous_transaction;
	begin
		--Create _META table.
		begin
			execute immediate '
				create table '||p_table_owner||'.'||p_table_name||'_meta(
					date_started        date,
					date_updated        date,
					username            varchar2(128),
					is_complete         varchar2(3),
					targets_expected    number,
					targets_completed   number,
					targets_with_errors number,
					num_rows            number,
					code                clob,
					targets             clob
				)';
		exception when v_name_already_used then
			null;
		end;

		--I think this is necessary for autonomous transaction, to create table before the trigger.
		commit;

		--Create trigger to update audit record when inserts are done.
		execute immediate replace(replace(replace(replace(q'[
			create or replace trigger method5.m5_temp_#SEQUENCE#_trg
			after update or insert
			on #TABLE_OWNER#.#TABLE_NAME#
			for each row
			begin
				--Update the audit trail when all the jobs are done.
				if :new.is_complete = 'Yes' then
					update method5.m5_audit
					set m5_audit.targets_expected    = :new.targets_expected,
						m5_audit.targets_completed   = :new.targets_completed,
						m5_audit.targets_with_errors = :new.targets_with_errors,
						m5_audit.num_rows            = :new.num_rows
					where rowid = '#ROWID#';
				end if;
			end;
		]'
		, '#SEQUENCE#', p_sequence)
		, '#TABLE_OWNER#', p_table_owner)
		, '#TABLE_NAME#', p_table_name||'_meta')
		, '#ROWID#', p_audit_rowid);

		--Without a commit here the trigger doesn't become fully enabled when run
		--as a function.
		commit;

		--Initialize values.
		execute immediate
			'insert into '||p_table_owner||'.'||p_table_name||'_meta
			values(sysdate, null, :username, :is_complete, :expected, 0, 0, 0, :p_code, :p_targets)'
			using sys_context('userenv', 'session_user'), case when p_targets_expected = 0 then 'Yes' else 'No' end
				,p_targets_expected, p_code, p_targets;

		--Required for autonomous_transaction.
		commit;
	end create_meta_table;

	---------------------------------------------------------------------------
	procedure create_error_table(
			p_table_owner     varchar2,
			p_table_name      varchar2,
			p_is_shell_script boolean
	) is
		v_name_already_used exception;
		pragma exception_init(v_name_already_used, -955);
	begin
		if p_is_shell_script then
			execute immediate '
				create table '||p_table_owner||'.'||p_table_name||'_err(
					host_name                 varchar2(256),
					host_link_name            varchar2(128),
					date_error                date,
					error_stack_and_backtrace varchar2(4000)
				)';
		else
			execute immediate '
				create table '||p_table_owner||'.'||p_table_name||'_err(
					database_name             varchar2(30),
					db_link_name              varchar2(128),
					date_error                date,
					error_stack_and_backtrace varchar2(4000)
				)';
		end if;
	exception when v_name_already_used then
		null;
	end create_error_table;

	---------------------------------------------------------------------------
	--Some direct object grants are necessary if the table owner is in a schema
	--different than the current user.
	procedure grant_cross_schema_privileges(
		p_table_owner varchar2,
		p_table_name varchar2,
		p_username varchar2)
	is
	begin
		if p_table_owner <> p_username then
			method5.grants_for_diff_table_owner(p_table_owner, p_table_name, p_username);
			method5.grants_for_diff_table_owner(p_table_owner, p_table_name||'_META', p_username);
			method5.grants_for_diff_table_owner(p_table_owner, p_table_name||'_ERR', p_username);
		end if;
	end grant_cross_schema_privileges;

	---------------------------------------------------------------------------
	--Create views with a consistent name to make querying easier.
	--The view is always created in the user's schema, even if the table is
	--created in another schema.
	procedure create_views(p_table_owner varchar2, p_table_name varchar2) is
		procedure create_view(p_view_name varchar2, p_table_owner varchar2, p_table_name varchar2) is
			v_name_already_used exception;
			pragma exception_init(v_name_already_used, -955);
		begin
			execute immediate 'create or replace view '||sys_context('userenv', 'session_user')||'.'||p_view_name
				||' as select * from '||p_table_owner||'.'||p_table_name;
		exception when v_name_already_used then
			raise_application_error(-20021, 'Your schema already contains an object named '||
				p_view_name||'.  Please drop that object and try again.');
		end;
	begin
		create_view('M5_RESULTS', p_table_owner, p_table_name);
		create_view('M5_METADATA', p_table_owner, p_table_name||'_meta');
		create_view('M5_ERRORS', p_table_owner, p_table_name||'_err');
	end create_views;

	---------------------------------------------------------------------------
	procedure create_jobs(
		p_table_owner              varchar2,
		p_table_name               varchar2,
		p_run_as_sys               boolean,
		p_has_version_star         boolean,
		p_has_column_gt_30         boolean,
		p_has_long                 boolean,
		p_explicit_column_list     varchar2,
		p_explicit_expression_list varchar2,
		p_code                     varchar2,
		p_encrypted_code           varchar2,
		p_select_plsql_script      varchar2,
		p_allowed_privs            allowed_privs_nt,
		p_command_name             varchar2
	) is
		v_ctas_ddl            varchar2(32767);
		v_ctas_call           varchar2(32767);
		v_code                varchar2(32767);
		v_sequence            number;
		v_pipe_count          number;
		v_jobs                sys.job_definition_array := sys.job_definition_array();
	begin
		--Create a job to insert for each link.
		for i in 1 .. p_allowed_privs.count loop

			--Get sequence to ensure a unique name for the procedure and the job.
			v_sequence := get_sequence_nextval();

			--Build procedure string.
			begin
				--SELECT CTAS.
				if p_select_plsql_script = 'SELECT' then
					--Regular SELECT statement if there are no privileges.
					if p_allowed_privs(i).run_as_m5_or_temp_user = 'M5' then
						--Build the CTAS.
						v_ctas_ddl := get_ctas_sql(
							p_code                     => p_code,
							p_owner                    => 'method5',
							p_table_name               => 'm5_temp_table_'||to_char(v_sequence),
							p_has_version_star         => p_has_version_star,
							p_has_column_gt_30         => p_has_column_gt_30,
							p_has_long                 => p_has_long,
							p_column_list              => p_explicit_column_list,
							p_expression_list          => p_explicit_expression_list,
							p_add_database_name_column => false,
							p_copy_data                => true
						);

						--The CTAS requires encryption and a special procedure to run as SYS.
						if p_run_as_sys then
							v_ctas_call :=
							q'<
								sys.m5_runner.run_as_sys@##DB_LINK_NAME##
								(
									method5.m5_pkg.get_encrypted_raw('##DATABASE_NAME##',
										q'##QUOTE_DELIMITER1##
											##CTAS_DDL##
										##QUOTE_DELIMITER1##'
									)
								);
							>';
						--The CTAS can be called directly if run as DBA.
						else
							v_ctas_call :=
							q'<
								--Create remote temporary table with results.
								sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##
								(
									q'##QUOTE_DELIMITER1##
										##CTAS_DDL##
									##QUOTE_DELIMITER1##'
								);
							>';
						end if;

						v_code := replace(replace(replace(replace(replace(replace(replace(v_select_template
							,'##DBA_OR_SYS_RUN_CTAS##', v_ctas_call)
							,'##SEQUENCE##', to_char(v_sequence))
							,'##TABLE_OWNER##', p_table_owner)
							,'##TABLE_NAME##', p_table_name)
							,'##DATABASE_NAME##', p_allowed_privs(i).target)
							,'##DB_LINK_NAME##', p_allowed_privs(i).db_link_name)
							,'##CTAS_DDL##', v_ctas_ddl);
					--Create a temporary user if only specific privileges are allowed.
					else
						declare
							v_privs_string varchar2(32767);
						begin
							--Build the CTAS.
							v_ctas_ddl := get_ctas_sql(
								p_code                     => p_code,
								p_owner                    => 'm5_temp_user_'||to_char(v_sequence),
								p_table_name               => 'm5_temp_table_'||to_char(v_sequence),
								p_has_version_star         => p_has_version_star,
								p_has_column_gt_30         => p_has_column_gt_30,
								p_has_long                 => p_has_long,
								p_column_list              => p_explicit_column_list,
								p_expression_list          => p_explicit_expression_list,
								p_add_database_name_column => false,
								p_copy_data                => true
							);

							v_ctas_call :=
							q'<
								--Create remote procedure to create table with results.
								sys.dbms_utility.exec_ddl_statement@##DB_LINK_NAME##
								(
									q'##QUOTE_DELIMITER2##
										create procedure m5_temp_user_##SEQUENCE##.m5_temp_proc_##SEQUENCE## is
										begin
											execute immediate q'##QUOTE_DELIMITER1##
												##CTAS_DDL##
											##QUOTE_DELIMITER1##';
										end;
									##QUOTE_DELIMITER2##'
								);
							>';

							--Create string of privileges.
							for j in 1 .. p_allowed_privs(i).privileges.count loop
								v_privs_string := v_privs_string || ',''' || p_allowed_privs(i).privileges(j) || '''';
							end loop;

							v_code := replace(replace(replace(replace(replace(replace(replace(replace(v_select_limit_privs_template
								,'##ALLOWED_PRIVS##', v_privs_string)
								,'##CREATE_CTAS_PROC##', v_ctas_call)
								,'##SEQUENCE##', to_char(v_sequence))
								,'##TABLE_OWNER##', p_table_owner)
								,'##TABLE_NAME##', p_table_name)
								,'##DATABASE_NAME##', p_allowed_privs(i).target)
								,'##DB_LINK_NAME##', p_allowed_privs(i).db_link_name)
								,'##CTAS_DDL##', v_ctas_ddl);
						end;
					end if;

					v_code := replace(v_code, '##QUOTE_DELIMITER1##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER2##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER3##', find_available_quote_delimiter(v_code));

				--PL/SQL CTAS.
				elsif p_select_plsql_script = 'PLSQL' then
					v_code := replace(replace(replace(replace(replace(replace(replace(replace(v_plsql_template
						,'##SYS_REPLACE_WITH_ENCRYPTED_BEGIN##', case when p_run_as_sys then 'replace(' else null end)
						,'##SYS_REPLACE_WITH_ENCRYPTED_END##', case when p_run_as_sys then p_encrypted_code else null end)
						,'##SEQUENCE##', to_char(v_sequence))
						,'##TABLE_OWNER##', p_table_owner)
						,'##TABLE_NAME##', p_table_name)
						,'##DATABASE_NAME##', p_allowed_privs(i).target)
						,'##DB_LINK_NAME##', p_allowed_privs(i).db_link_name)
						,'##CODE##', p_code);

					if p_command_name = 'PL/SQL EXECUTE' then
						v_code := replace(v_code, '##CLOB_OR_VARCHAR2##', 'clob');
					else
						v_code := replace(v_code, '##CLOB_OR_VARCHAR2##', 'varchar2');
					end if;

					v_code := replace(v_code, '##QUOTE_DELIMITER1##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER2##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER3##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER4##', find_available_quote_delimiter(v_code));

				--Shell script.
				elsif p_select_plsql_script = 'SCRIPT' then
					v_code := replace(replace(replace(replace(replace(replace(v_shell_script_template
						,'##CODE##', p_code)
						,'##SEQUENCE##', to_char(v_sequence))
						,'##TABLE_OWNER##', p_table_owner)
						,'##TABLE_NAME##', p_table_name)
						,'##HOST_NAME##', p_allowed_privs(i).target)
						,'##HOST_LINK_NAME##', p_allowed_privs(i).db_link_name);
					v_code := replace(v_code, '##QUOTE_DELIMITER1##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER2##', find_available_quote_delimiter(v_code));
					v_code := replace(v_code, '##QUOTE_DELIMITER3##', find_available_quote_delimiter(v_code));
				end if;

			exception when value_error then
				raise_application_error(-20022, 'The code string is too long.  The limit is about 30,000 characters.  '||
					'This is due to the 32767 varchar2 limit, minus some overhead needed for Method5.');
			end;

			--Print the job code in debug mode, 4K bytes at a time because some tools don't handle large DBMS_OUTPUT well.
			if g_debug then
				for i in 0 .. ceil(length(v_code)/3980) - 1 loop
					sys.dbms_output.put_line('V_CODE '||to_char(i+1)||':'||chr(10)||substr(v_code, i*3980+1, 3980));
				end loop;
			end if;

			--Create procedures asynchronously, in parallel, to save time on compiling.
			--DBMS_PIPE is used because DBMS_SCHEDULER has 4K character limits.
			declare
				v_result integer;
				v_pipename varchar2(128);
			begin
				--Break into chunks of 1000 characters to avoid pipe 4K byte limit.
				v_pipe_count := ceil(length(v_code)/1000);

				for pipe_index in 1 .. v_pipe_count loop
					--Create private pipe.
					v_pipename := p_allowed_privs(i).db_link_name||'_'||v_sequence||'_'||pipe_index;
					v_result := sys.dbms_pipe.create_pipe(v_pipename);
					if v_result <> 0 then
						raise_application_error(-20023, 'Pipe error.  Result = '||v_result||'.');
					end if;

					--Pack the message with a chunk of DDL.
					sys.dbms_pipe.pack_message(substr(v_code, 1000 * (pipe_index-1) + 1, 1000));

					--Send the message.
					v_result := sys.dbms_pipe.send_message(v_pipename);
					if v_result <> 0 then
						raise_application_error(-20023, 'Pipe error.  Result = '||v_result||'.');
					end if;
				end loop;
			end;

			--Create scheduler job array to run and drop procedure.
			--Using an array and CREATE_JOBS is faster than multiple calls to CREATE_JOB.
			v_jobs.extend;
			v_jobs(v_jobs.count) := sys.job_definition
			(
				job_name   => p_allowed_privs(i).job_owner||'.'||p_allowed_privs(i).db_link_name||'_'||v_sequence,
				job_type   => 'PLSQL_BLOCK',
				job_action => replace(replace(replace(q'<
					declare
						v_result integer;
						v_code varchar2(32767);
						v_item varchar2(4000);
						v_pipename varchar2(128);
					begin
						--Get the code from the Method5 private pipe.
						v_code := m5_pkg.get_and_remove_pipe_data('##TARGET_NAME##', '##SEQUENCE##', '##PIPE_COUNT##');

						--Compile, execute, and drop.
						execute immediate v_code;
						begin
							execute immediate 'begin m5_temp_proc_##SEQUENCE##; end;';
						exception when others then
							execute immediate 'drop procedure m5_temp_proc_##SEQUENCE##';
							raise;
						end;
						execute immediate 'drop procedure m5_temp_proc_##SEQUENCE##';
					end;
				>','##SEQUENCE##', to_char(v_sequence)), '##PIPE_COUNT##', v_pipe_count), '##TARGET_NAME##', p_allowed_privs(i).target),
				start_date => systimestamp,
				enabled    => true,
				--Used to prevent the same user from writing to the same table with multiple processes.
				comments   => 'TABLE:'||p_table_name||'"CALLER:'||sys_context('userenv', 'session_user'),
				number_of_arguments => 0
			);
		end loop;

		--Create jobs from the job array.
		sys.dbms_scheduler.create_jobs(jobdef_array => v_jobs, commit_semantics => 'TRANSACTIONAL');
	end create_jobs;

	---------------------------------------------------------------------------
	--Wait for jobs to finish, for synchronous processing.
	procedure wait_for_jobs_to_finish(
		p_start_timestamp          timestamp with time zone,
		p_table_name               varchar2,
		p_max_seconds_to_wait      number default 999999999
	) is
		v_running_jobs number;
	begin
		--Wait for all jobs to be finished.
		loop
			--Look for jobs with the same username and table.
			--ASSUMPTION: Jobs are auto-dropped.
			select count(*)
			into v_running_jobs
			from sys.dba_scheduler_jobs
			where job_name like 'M5%'
				and regexp_replace(comments, 'TABLE:(.*)"CALLER:.*', '\1') = trim(upper(p_table_name))
				and regexp_replace(comments, 'TABLE:.*"CALLER:(.*)', '\1') = sys_context('userenv', 'session_user');

			exit when
				v_running_jobs = 0
				or
				(systimestamp - p_start_timestamp) > interval '1' second * p_max_seconds_to_wait;
		end loop;
	end wait_for_jobs_to_finish;

	---------------------------------------------------------------------------
	function get_low_parallel_dop_warning return varchar2 is
		v_low_prallel_dop_warning varchar2(4000);
	begin
		--Create a warning message if one of the common parallel settings are low.
		select
			case
				when message1 is not null or message2 is not null or message3 is not null then
					'--PARALLEL WARNING: Jobs may not use enough parallelism because of low settings:'||
					message1||message2||message3||chr(10)
				else
					null
			end low_parallel_settings_message
		into v_low_prallel_dop_warning
		from
		(
			--Create messages for low parallel settings.
			--OPEN_LINKS does not matter - there is only on link per session.
			select
				case when job_queue_processes < 100
					then chr(10)||'--JOB_QUEUE_PROCESSES parameter = '||job_queue_processes||'.' end message1,
				case when parallel_max_servers < cpu_count and parallel_max_servers < 100 then
					chr(10)||'--PARALLEL_MAX_SERVERS parameter = '||parallel_max_servers||'.' end message2,
				case when limit < 100 then
					chr(10)||'--SESSIONS_PER_USER for profile '||profile||' = '||limit||'.' end message3
			from
			(
				--Profile limits, convert "UNLIMITED" to a number for numeric comparison.
				select
					profile,
					case when limit = 'UNLIMITED' then 999999999 else to_number(limit) end limit
				from
				(
					--Profile limits.  Check DEFAULT profile if the limit is set to "DEFAULT".
					select
						case when dba_profiles.limit = 'DEFAULT' then 'DEFAULT' else dba_profiles.profile end profile,
						case when dba_profiles.limit = 'DEFAULT' then default_profiles.limit else dba_profiles.limit end limit
					from sys.dba_users
					join sys.dba_profiles
						on dba_users.profile = dba_profiles.profile
					cross join
					(
						select limit
						from sys.dba_profiles
						where profile = 'DEFAULT'
							and resource_name = 'SESSIONS_PER_USER'
					) default_profiles
					where dba_users.username = sys_context('userenv', 'session_user')
						and dba_profiles.resource_name = 'SESSIONS_PER_USER'
				) profile_limits
			) profile_limits_numeric
			cross join
			(
				--Parameter limits.
				select
					max(case when name = 'job_queue_processes' then value else null end) job_queue_processes,
					max(case when name = 'parallel_max_servers' then value else null end) parallel_max_servers,
					max(case when name = 'cpu_count' then value else null end) cpu_count
				from v$parameter
				where name in ('cpu_count', 'job_queue_processes', 'parallel_max_servers')
			)
		);

		return v_low_prallel_dop_warning;

	end get_low_parallel_dop_warning;

	---------------------------------------------------------------------------
	procedure print_useful_sql(
		p_code                     varchar2,
		p_targets                  varchar2,
		p_table_owner              varchar2,
		p_table_name               varchar2,
		p_asynchronous             boolean,
		p_table_exists_action      varchar2,
		p_run_as_sys               boolean,
		p_is_shell_script          boolean,
		v_is_first_column_sortable boolean
	) is
		v_code varchar2(32767);
		v_targets varchar2(32767);
		v_asynchronous varchar2(4000);
		v_run_as_sys varchar2(4000) := case when p_run_as_sys then 'TRUE' else 'FALSE' end;
		v_table_exists_action varchar2(4000);

		v_message varchar2(32767) :=
			q'[--------------------------------------------------------------------------------
			--Method5 #C_VERSION# run details:
			-- p_code                : #P_CODE#
			-- p_targets             : #P_TARGETS#
			-- p_table_name          : #P_TABLE_OWNER#.#P_TABLE_NAME#
			-- p_table_exists_action : #P_TABLE_EXISTS_ACTION#
			-- p_asynchronous        : #P_ASYNCHRONOUS#
			-- p_run_as_sys          : #P_RUN_AS_SYS#
			#PARALLEL_WARNING#
			--------------------------------------------------------------------------------
			--Query results, metadata, and errors:
			-- (Or use the views M5_RESULTS, M5_METADATA, and M5_ERRORS.)
			select * from #P_TABLE_OWNER#.#P_TABLE_NAME# order by #DATABASE_OR_HOST##SORT_FIRST_COLUMN#;
			select * from #P_TABLE_OWNER#.#P_TABLE_NAME#_meta order by date_started;
			select * from #P_TABLE_OWNER#.#P_TABLE_NAME#_err order by #DATABASE_OR_HOST#;
			#JOB_INFORMATION#]'
		;

		v_low_parallel_dop_warning varchar2(4000) := get_low_parallel_dop_warning();
		v_database_or_host varchar2(4000);
		v_sort_first_column varchar2(4000);
		v_job_information varchar2(4000);
	begin
		--Set V_CODE.  Add "..." if the length is too large to display.
		if lengthc(p_code) >= 50 then
			v_code := replace(replace(replace(substrc(p_code, 1, 50), chr(10), ' '), chr(13), null), chr(9), null) || '...';
		else
			v_code := replace(replace(replace(p_code, chr(10), ' '), chr(13), null), chr(9), null);
		end if;

		--Set V_TARGETS.  Add "..." if the length is too large to display.
		if lengthc(p_targets) >= 50 then
			v_targets := replace(replace(replace(substrc(p_targets, 1, 50), chr(10), ' '), chr(13), null), chr(9), null) || '...';
		else
			v_targets := replace(replace(replace(p_targets, chr(10), ' '), chr(13), null), chr(9), null);
		end if;

		--Set DATABASE_OR_HOST.
		if p_is_shell_script then
			v_database_or_host := 'host_name';
		else
			v_database_or_host := 'database_name';
		end if;

		--Set V_SORT_FIRST_COLUMN.
		if v_is_first_column_sortable then
			v_sort_first_column := ', 2';
		end if;

		--Set V_ASYNCHRONOUS message and V_JOB_INFORMATION.
		if p_asynchronous then
			v_asynchronous := 'TRUE - Some results may not be in yet';

			--Add job information
			v_job_information := q'[
				--------------------------------------------------------------------------------
				--Find jobs that have not finished yet:
				select *
				from sys.dba_scheduler_jobs
				where regexp_replace(dba_scheduler_jobs.comments, 'TABLE:(.*)"CALLER:.*', '\1') = '#P_TABLE_NAME#'
				  and regexp_replace(dba_scheduler_jobs.comments, 'TABLE:.*"CALLER:(.*)', '\1') = user;

				--------------------------------------------------------------------------------
				--Stop all jobs from this run (commented out so you don't run it by accident):
				-- begin
				--   method5.m5_pkg.stop_jobs(p_owner=> user, p_table_name=> '#P_TABLE_NAME#');
				-- end;
				-- #SLASH#]'
			;
		else
			--Get final metadata.
			execute immediate replace(replace(q'[
				select
					'FALSE - All results processed in '||nvl(round((date_updated - date_started) * 24 * 60 * 60), 0)||' seconds.  '||
					'Out of '||targets_expected||' jobs, '||targets_completed||' succeeded and '||targets_with_errors||' failed.' message
				from #P_TABLE_OWNER#.#P_TABLE_NAME#_meta
				where date_started = (select max(date_started) from #P_TABLE_OWNER#.#P_TABLE_NAME#_meta)
			]'
			, '#P_TABLE_OWNER#', p_table_owner)
			, '#P_TABLE_NAME#', p_table_name)
			into v_asynchronous;
		end if;

		--Set v_table_exists_action.  The option "ERROR" could use some explaining.
		if upper(p_table_exists_action) = 'ERROR' then
			v_table_exists_action := p_table_exists_action || ' (Raise error if table already exists.)';
		else
			v_table_exists_action := p_table_exists_action;
		end if;

		--Add parallel DOP warning if necessary.
		if v_low_parallel_dop_warning is not null then
			v_low_parallel_dop_warning := chr(10)||'--------------------------------------------------------------------------------'||
				chr(10)||v_low_parallel_dop_warning;
		end if;

		--Build message from template.
		v_message := replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
			v_message
			, '#JOB_INFORMATION#', v_job_information)
			, '#C_VERSION#', C_VERSION)
			, '#P_CODE#', v_code)
			, '#P_TARGETS#', v_targets)
			, '#P_TABLE_OWNER#', lower(p_table_owner))
			, '#P_TABLE_NAME#', lower(p_table_name))
			, '#P_ASYNCHRONOUS#', v_asynchronous)
			, '#P_RUN_AS_SYS#', v_run_as_sys)
			, '#P_TABLE_EXISTS_ACTION#', v_table_exists_action)
			, '#PARALLEL_WARNING#', v_low_parallel_dop_warning)
			, '#DATABASE_OR_HOST#', v_database_or_host)
			, '#SORT_FIRST_COLUMN#', v_sort_first_column)
			--Use #SLASH# instead of native slash to avoid SQL*Plus slash parsing.
			, '#SLASH#', '/')
			, chr(9), null);

		--Print the message.
		--Split it into individual lines to look better in SQL*Plus.
		--(SQL*Plus sucks for running Method5 but people will use it anyway.)
		declare
			v_line_index number := 0;
			v_lines string_table := string_table();
		begin
			for v_line_index in 1 .. regexp_count(v_message, chr(10))+1 loop
				v_lines.extend();
				v_lines(v_lines.count) := regexp_substr(v_message, '^.*$', 1, v_line_index, 'm');
			end loop;

			for i in 1 .. v_lines.count loop
				sys.dbms_output.put_line(v_lines(i));
			end loop;
		end;

	end print_useful_sql;

--Main procedure.
begin
	declare
		v_config_data                config_data_rec;
		v_allowed_privs              allowed_privs_nt;
		v_sequence                   number;
		v_start_timestamp            timestamp with time zone := systimestamp;
		v_transformed_code           clob;
		v_encrypted_code             clob;
		v_select_plsql_script        varchar2(6); --Will be either "SELECT", "PLSQL", or "SCRIPT".
		v_is_first_column_sortable   boolean;
		v_command_name               varchar2(100);
		v_table_name                 varchar2(128);
		v_table_owner                varchar2(128);
		v_original_targets           varchar2(32767) := p_targets;
		v_target_string_with_default varchar2(32767);
		v_table_exists_action        varchar2(100) := upper(trim(p_table_exists_action));
		v_audit_rowid                rowid;
		v_is_shell_script            boolean;
		v_target_tab                 string_table;
		--Variables used for creating CTAS:
		v_has_version_star           boolean := false;
		v_has_column_gt_30           boolean := false;
		v_has_long                   boolean := false;
		v_explicit_column_list       varchar2(32767);
		v_explicit_expression_list   varchar2(32767);
	begin
		if g_debug then
			sys.dbms_output.enable(null);
		end if;
		v_config_data := get_config_data;
		v_is_shell_script := is_shell_script(p_code);
		v_target_string_with_default := add_default_targets_if_null(v_original_targets, v_config_data);
		v_allowed_privs := get_allowed_privs(p_run_as_sys, v_is_shell_script, v_target_string_with_default);
		v_sequence := get_sequence_nextval;
		set_table_owner_and_name(p_table_name, v_sequence, v_table_owner, v_table_name);
		v_audit_rowid := audit(p_code, v_target_string_with_default, nvl(p_table_name, v_table_name), p_asynchronous, v_table_exists_action, p_run_as_sys);
		control_access(v_audit_rowid, v_config_data);
		validate_input(v_table_exists_action);
		create_link_refresh_job(v_allowed_privs);
		--TODO: Simplify
		create_db_links_in_m5_schema(get_links('METHOD5'), v_sequence);
		synchronize_links(v_allowed_privs);
		v_target_tab := get_target_tab(v_allowed_privs);
		raise_exception_if_no_targets(v_allowed_privs, v_original_targets, v_target_string_with_default, v_is_shell_script);
		check_if_already_running(v_table_name);
		get_transformed_code_and_type(p_code, p_run_as_sys, v_is_shell_script, v_target_tab, v_transformed_code, v_encrypted_code, v_select_plsql_script, v_is_first_column_sortable, v_command_name, v_has_version_star, v_has_column_gt_30, v_has_long, v_explicit_column_list, v_explicit_expression_list);
		check_table_name_and_prep(v_table_owner, v_table_name, v_table_exists_action);
		create_data_table(v_table_owner, v_table_name, v_transformed_code, p_run_as_sys, v_has_version_star, v_has_column_gt_30, v_has_long, v_explicit_column_list, v_explicit_expression_list, v_select_plsql_script, v_command_name, v_target_tab, v_sequence, v_is_first_column_sortable);
		create_meta_table(v_table_owner, v_table_name, v_sequence, p_code, v_target_string_with_default, v_allowed_privs.count, v_audit_rowid);
		create_error_table(v_table_owner, v_table_name, v_is_shell_script);
		grant_cross_schema_privileges(v_table_owner, v_table_name, sys_context('userenv', 'session_user'));
		create_views(v_table_owner, v_table_name);
		create_jobs(v_table_owner, v_table_name, p_run_as_sys, v_has_version_star, v_has_column_gt_30, v_has_long, v_explicit_column_list, v_explicit_expression_list, v_transformed_code, v_encrypted_code, v_select_plsql_script, v_allowed_privs, v_command_name);
		if not p_asynchronous then
			wait_for_jobs_to_finish(v_start_timestamp, v_table_name);
		end if;
		print_useful_sql(p_code, v_target_string_with_default, v_table_owner, v_table_name, p_asynchronous, v_table_exists_action, p_run_as_sys, v_is_shell_script, v_is_first_column_sortable);
	end;
end run;

end;
/
