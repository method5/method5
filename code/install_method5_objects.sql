prompt Creating Method5 objects...


---------------------------------------
--#0: Check the user.
@code/check_user must_not_run_as_sys_and_has_dba


---------------------------------------
--#1: Global sequence used by program.
create sequence method5.m5_generic_sequence;


---------------------------------------
--#2: Tables used by program.
--Audit all uses of the program.
create table method5.m5_audit
(
	username              varchar2(128) not null,
	create_date           date not null,
	table_name            varchar2(257) not null,
	code                  clob not null,
	targets               clob,
	asynchronous          varchar2(3),
	table_exists_action   varchar2(6),
	run_as_sys            varchar2(3),
	targets_expected      number,
	targets_completed     number,
	targets_with_errors   number,
	num_rows              number,
	access_control_error  varchar2(4000),
	constraint m5_audit_ck1 check (asynchronous in ('Yes', 'No')),
	constraint m5_audit_ck2 check (table_exists_action in ('ERROR', 'APPEND', 'DELETE', 'DROP')),
	constraint m5_audit_ck3 check (run_as_sys in ('Yes', 'No')),
	constraint m5_audit_pk primary key (username, create_date, table_name)
);

create table method5.m5_database
(
	host_name                  varchar2(256) not null,
	database_name              varchar2(9) not null,
	instance_name              varchar2(16),
	lifecycle_status           varchar2(256),
	line_of_business           varchar2(1024),
	target_version             varchar2(64),
	operating_system           varchar2(256),
	cluster_name               varchar2(1024),
	description                varchar2(4000),
	point_of_contact           varchar2(4000),
	app_connect_string         varchar2(4000),
	m5_default_connect_string  varchar2(4000),
	is_active                  varchar2(3) default 'Yes' not null,
	changed_by                 varchar2(128),
	changed_date               date,
	constraint m5_database_pk primary key (host_name, database_name),
	constraint m5_database_numbers_only_ck check (regexp_like(target_version, '^[0-9\.]*$')),
	constraint m5_database_is_active_ck check (is_active in ('Yes', 'No'))
);
comment on table method5.m5_database is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.';

comment on column method5.m5_database.host_name                  is 'The name of the machine the database instance runs on.';
comment on column method5.m5_database.database_name              is 'A short string to identify a database.  This name will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.';
comment on column method5.m5_database.instance_name              is 'A short string to uniquely identify a database instance.  For standalone databases this will probably be the same as the DATABASE_NAME.  For a Real Application Cluster (RAC) database this will probably be DATABASE_NAME plus a number at the end.';
comment on column method5.m5_database.lifecycle_status           is 'A value like "DEV" or "PROD".  (Your organization may refer to this as the "environment" or "tier".)';
comment on column method5.m5_database.line_of_business           is 'A value to identify a database by business unit, contract, company, etc.';
comment on column method5.m5_database.target_version             is 'A value like "11.2.0.4.0" or "12.1.0.2.0".  This value may be used to select the lowest or highest version so only use numbers.';
comment on column method5.m5_database.operating_system           is 'A value like "SunOS" or "Windows".';
comment on column method5.m5_database.cluster_name               is 'The Real Application Cluster (RAC) name for the cluster, if any.';
comment on column method5.m5_database.description                is 'Any additional description or comments about the database.';
comment on column method5.m5_database.point_of_contact           is 'The persons or teams that own or are responsible for these databases.  This may help with contacting people to get permission for an outage.';
comment on column method5.m5_database.app_connect_string         is 'The connection string an application would use to connect to this database.';
comment on column method5.m5_database.m5_default_connect_string  is 'The default connection string Method5 uses to connect to this database.  This value is only used once to create the database link, after that you must follow the steps in administer_method5.md to change database links.  This value is set by the trigger METHOD5.M5_DATABASE_TRG.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column (for each entry, use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.';
comment on column method5.m5_database.is_active                  is 'Is this target active and available for use in Method5?  Either Yes or No.';
comment on column method5.m5_database.changed_by                 is 'The last user who changed this row.';
comment on column method5.m5_database.changed_by                 is 'The last date someone changed this row.';

--Create new trigger to set some values.
create or replace trigger method5.m5_database_trg
before insert or update
on method5.m5_database
for each row
--Purpose: Automatically set M5_DEFAULT_CONNECT_STRING, CHANGED_BY, and CHANGED_DATE if they were not set.
--  You may want to customize the M5_DEFAULT_CONNECT_STRING to match your environment's connection policies.
begin
	if inserting then
		if :new.m5_default_connect_string is null then
			--
			-- BEGIN CUSTOMIZE HERE
			--
			--You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column
			--(for each entry, use the text after the first equal sign).
			--You may want to remove spaces and newlines, it is easier to compare the strings without them.
			--It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.
			:new.m5_default_connect_string :=
				lower(replace(replace(
						'(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SID=$instance_name))) ',
						--service_name may work better for some organizations:
						--'$instance_name=(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$host_name)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=$global_name))) ',
					'$instance_name', :new.instance_name)
					,'$host_name', :new.host_name)
				);
			--
			-- END CUSTOMIZE HERE
			--
		end if;

		if :new.changed_by is null then
			--Get the user from APEX if it was used.
			:new.changed_by := 	coalesce(
				sys_context('APEX$SESSION','app_user')
				,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
				,sys_context('userenv','session_user'));
		end if;

		if :new.changed_date is null then
			:new.changed_date := sysdate;
		end if;
	end if;

	if not updating('CHANGED_BY') then
		:new.changed_by := 	coalesce(
			--Get the user from APEX if it was used.
			sys_context('APEX$SESSION','app_user')
			,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
			,sys_context('userenv','session_user'));
	end if;
	if not updating('CHANGED_DATE') then
		:new.changed_date := sysdate;
	end if;
end;
/

create table method5.m5_database_hist as
select sysdate the_date, m5_database.*
from method5.m5_database;

--Create 4 sample rows.  Most data is fake but the connection information should work for most databases.
insert into method5.m5_database
(
	host_name, database_name, instance_name, lifecycle_status, line_of_business,
	target_version, operating_system, m5_default_connect_string
)
with database_info as
(
	select
		(select host_name version from v$instance) host_name,
		(select version from v$instance) version,
		(SELECT replace(replace(product, 'TNS for '), ':') FROM product_component_version where product like 'TNS%') operating_system,
		(
			select '(description=(address=(protocol=tcp)(host=localhost)(port=1521))(connect_data=(server=dedicated)(sid='||instance_name||')))'
			from v$instance
		) m5_default_connect_string
	from dual
)
select host_name, 'devdb1'  database_name, 'devdb1'  instance_name, 'dev'  lifecycle_status, 'ACME' line_of_business, version, operating_system, m5_default_connect_string from database_info union all
select host_name, 'testdb1' database_name, 'testdb1' instance_name, 'test' lifecycle_status, 'ACME' line_of_business, version, operating_system, m5_default_connect_string from database_info union all
select host_name, 'devdb2'  database_name, 'devdb2'  instance_name, 'dev'  lifecycle_status, 'Ajax' line_of_business, version, operating_system, m5_default_connect_string from database_info union all
select host_name, 'testdb2' database_name, 'testdb2' instance_name, 'test' lifecycle_status, 'Ajax' line_of_business, version, operating_system, m5_default_connect_string from database_info;

commit;

create table method5.m5_user
(
	oracle_username                varchar2(128)   not null,
	os_username                    varchar2(4000),
	email_address                  varchar2(4000),
	is_m5_admin                    varchar2(3)     not null,
	default_targets                varchar2(4000),
	can_use_sql_for_targets        varchar2(3)     not null,
	can_drop_tab_in_other_schema   varchar2(3)     not null,
	changed_by                     varchar2(128)   default user not null,
	changed_date                   date            default sysdate not null,
	constraint m5_user_pk primary key(oracle_username),
	constraint is_m5_admin_ck check(is_m5_admin in ('Yes', 'No')),
	constraint can_use_sql_for_targets_ck check (can_use_sql_for_targets in ('Yes', 'No')),
	constraint can_drop_tab_in_other_schem_ck check (can_drop_tab_in_other_schema in ('Yes', 'No'))
);
comment on table method5.m5_user                               is 'Method5 users.';
comment on column method5.m5_user.oracle_username              is 'Individual Oracle account used to access Method5.  Do not use a shared account.';
comment on column method5.m5_user.os_username                  is 'Individual operating system account used to access Method5.  Depending on your system and network configuration enforcing this username may also ensure two factor authentication.  Do not use a shared account.  If NULL then the OS_USERNAME will not be checked.';
comment on column method5.m5_user.email_address                is 'Only necessary for administrators so they can be notified when configuration tables are changed.';
comment on column method5.m5_user.is_m5_admin                  is 'Can this user change Method5 configuration tables.  This user will also receive emails about configuration problems and changes.  Either Yes or No.';
comment on column method5.m5_user.default_targets              is 'Use this target list if none is specified.  Leave NULL to use the global default set in M5_CONFIG.';
comment on column method5.m5_user.can_use_sql_for_targets      is 'Can use a SELECT SQL statement for choosing targets.  Target SELECT statements are run as Method5 so only grant this to trusted users.  Either Yes or No.';
comment on column method5.m5_user.can_drop_tab_in_other_schema is 'Can set P_TABLE_NAME to be in a different schema.  That may sound innocent but it also implies the user can drop or delete data from other schemas on the management database.  Only give this to users you trust on the management database.  Either Yes or No';
comment on column method5.m5_user.changed_by                   is 'User who last changed this row.';
comment on column method5.m5_user.changed_date                 is 'Date this row was last changed.';

--Default admin is the user who installs Method5.  They are given full privileges.
insert into method5.m5_user(oracle_username, os_username, email_address, is_m5_admin, default_targets, can_use_sql_for_targets, can_drop_tab_in_other_schema)
values (user, sys_context('userenv', 'os_user'), null, 'Yes', null, 'Yes', 'Yes');

create table method5.m5_role
(
	role_name               varchar2(128)  not null,
	target_string           varchar2(4000) not null,
	can_run_as_sys          varchar2(3)    not null,
	can_run_shell_script    varchar2(3)    not null,
	install_links_in_schema varchar2(3)    not null,
	run_as_m5_or_sandbox    varchar2(7)    not null,
	sandbox_default_ts      varchar2(30),
	sandbox_temporary_ts    varchar2(30),
	sandbox_quota           varchar2(100),
	sandbox_profile         varchar2(128),
	description             varchar2(4000),
	changed_by              varchar2(128)  default user not null,
	changed_date            date           default sysdate not null,
	constraint m5_role_pk primary key(role_name),
	constraint can_run_as_sys_ck check (can_run_as_sys in ('Yes', 'No')),
	constraint can_run_shell_script_ck check (can_run_shell_script in ('Yes', 'No')),
	constraint install_links_in_schema_ck check (install_links_in_schema in ('Yes', 'No')),
	constraint run_as_m5_or_sandbox_ck check (run_as_m5_or_sandbox in ('M5', 'SANDBOX')),
	constraint sandbox_props_not_set_for_m5 check
		(not (run_as_m5_or_sandbox = 'M5' and
			(
				sandbox_default_ts   is not null or
				sandbox_temporary_ts is not null or
				sandbox_quota        is not null or
				sandbox_profile      is not null)
			)),
	constraint ts_quota_size_clause check(
		upper(sandbox_quota) = 'UNLIMITED'
		or
		regexp_like(upper(sandbox_quota), '^[0-9]+[KMGTPE]?$')
	)
);
comment on table method5.m5_role is 'Method5 roles control the targets, features, and privileges available to Method5 users.';
comment on column method5.m5_role.role_name                  is 'Name of the role.';
comment on column method5.m5_role.target_string              is 'String that describes available targets.  Works the same way as the parameter P_TARGETS.  Use % to mean everything.';
comment on column method5.m5_role.can_run_as_sys             is 'Can run commands as SYS.  Either Yes or No.';
comment on column method5.m5_role.can_run_shell_script       is 'Can run shell scripts on the host.  Either Yes or No.';
comment on column method5.m5_role.install_links_in_schema    is 'Are private links installed in the user schemas.  Either Yes or NO.';
comment on column method5.m5_role.run_as_m5_or_sandbox       is 'Run as the user Method5 (with all privileges) or as a temporary sandbox users with precisely controlled privileges.  Either M5 or SANDBOX.';
comment on column method5.m5_role.sandbox_default_ts         is 'The permanent tablespace for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the tablespace is not found the default permanent tablespace is used.';
comment on column method5.m5_role.sandbox_temporary_ts       is 'The temporary tablespace for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the tablespace is not found the default temporary tablespace is used.';
comment on column method5.m5_role.sandbox_quota              is 'The quota on the permanent tablespace for the sanbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  This string can be a SIZE_CLAUSE.  For example, the values can be 10G, 9999999, 5M, etc.  If NULL then UNLIMITED will be used.';
comment on column method5.m5_role.sandbox_profile            is 'The profile used for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the profile is not found the DEFAULT profile is used.';
comment on column method5.m5_role.description                is 'Description of the role.';
comment on column method5.m5_role.changed_by                 is 'User who last changed this row.';
comment on column method5.m5_role.changed_date               is 'Date this row was last changed.';

--Default "all" role.  This role does not need to exist and can be dropped if necessary.
insert into method5.m5_role(role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema, run_as_m5_or_sandbox, description)
values ('ALL', '%', 'Yes', 'Yes', 'Yes', 'M5', 'This role grants everything.  It is created by default but you do not need to assign it to anyone and you may delete this role.');
commit;

create table method5.m5_role_priv
(
	role_name     varchar2(128)  not null,
	privilege     varchar2(4000) not null,
	changed_by    varchar2(128)  default user not null,
	changed_date  date           default sysdate not null,
	constraint m5_role_priv_pk primary key(role_name, privilege),
	constraint m5_role_user_fk1 foreign key(role_name) references method5.m5_role(role_name)
);
comment on table method5.m5_role_priv is 'Privileges granted to a role.';
comment on column method5.m5_role_priv.role_name     is 'Role name from METHOD5.ROLE.ROLE_NAME.';
comment on column method5.m5_role_priv.privilege     is 'An Oracle system privilege, object privilege, or role.  This string will be placed in the middle of:  grant <privilege> to m5_temp_sandbox_XYZ;  For example: select_catalog_role, select any table, delete any table.';
comment on column method5.m5_role_priv.changed_by    is 'User who last changed this row.';
comment on column method5.m5_role_priv.changed_date  is 'Date this row was last changed.';

create table method5.m5_user_role
(
	oracle_username  varchar2(128) not null,
	role_name        varchar2(128) not null,
	changed_by       varchar2(128) default user not null,
	changed_date     date          default sysdate not null,
	constraint m5_user_role_pk primary key(oracle_username, role_name),
	constraint m5_user_role_fk1 foreign key(oracle_username) references method5.m5_user(oracle_username),
	constraint m5_user_role_fk2 foreign key(role_name) references method5.m5_role(role_name)
);
comment on table method5.m5_user_role is 'Grants a Method5 role to a Method5 user.';
comment on column method5.m5_user_role.oracle_username is 'Oracle username from METHOD5.M5_USER.ORACLE_USERNAME.';
comment on column method5.m5_user_role.role_name       is 'Role name from METHOD5.ROLE.ROLE_NAME.';
comment on column method5.m5_user_role.changed_by      is 'User who last changed this row.';
comment on column method5.m5_user_role.changed_date    is 'Date this row was last changed.';

--Give default user the default role.
insert into method5.m5_user_role(oracle_username, role_name) values (user, 'ALL');

--Used for Method5 configuration.
create sequence method5.m5_config_seq;
create table method5.m5_config
(
	config_id    number not null,
	config_name  varchar2(100) not null,
	string_value varchar2(4000),
	number_value number,
	date_value   date,
	changed_by   varchar2(128) default user not null,
	changed_date date          default sysdate not null,
	constraint config_pk primary key (config_id)
);

--Add default configuration values.
insert into method5.m5_config(config_id, config_name, string_value, number_value)
select method5.m5_config_seq.nextval, name, string_value, number_value
from
(
	select 'Access Control - User is not locked'            name, 'ENABLED'  string_value, null number_value     from dual union all
	select 'Default Targets'                                name, '%'        string_value, null number_value     from dual union all
	select 'Job Timeout (seconds)'                          name, null       string_value, 23*60*60 number_value from dual
);
commit;

--Add triggers to set CHANGED_BY and CHANGED_DATE.
begin
	for tables in
	(
		select 'M5_CONFIG'      table_name from dual union all
		select 'M5_ROLE'        table_name from dual union all
		select 'M5_ROLE_PRIV'   table_name from dual union all
		select 'M5_USER'        table_name from dual union all
		select 'M5_USER_ROLE'   table_name from dual
		order by 1
	) loop
		execute immediate replace(q'[
			create or replace trigger method5.#TABLE_NAME#_trg
			before insert or update
			on method5.#TABLE_NAME#
			for each row
			begin
				if not updating('CHANGED_BY') then
					:new.changed_by := 	coalesce(
						--Get the user from APEX if it was used.
						sys_context('APEX$SESSION','app_user')
						,regexp_substr(sys_context('userenv','client_identifier'),'^[^:]*')
						,sys_context('userenv','session_user'));
				end if;
				if not updating('CHANGED_DATE') then
					:new.changed_date := sysdate;
				end if;
			end;

		]', '#TABLE_NAME#', tables.table_name);
	end loop;
end;
/

--Job timeouts.
create table method5.m5_job_timeout
(
	job_name      varchar2(128),
	owner         varchar2(128),
	database_name varchar2(9),
	table_name    varchar2(128),
	start_date    timestamp(6) with time zone,
	stop_date     timestamp(6) with time zone,
	constraint m5_job_timeout_pk primary key (job_name, owner)
);
comment on table method5.m5_job_timeout is 'Used for slow or broken jobs that timed out.  The column names and types are similar to those in DBA_SCHEDULER_*.';

create table method5.m5_global_data_dictionary
(
	owner      varchar2(128),
	table_name varchar2(128)
);
create unique index method5.m5_global_data_dictionary_uq on method5.m5_global_data_dictionary(upper(owner), upper(table_name));
comment on table method5.m5_global_data_dictionary is 'Tables used in the global data dictionary.  These tables are monitored by the daily email job.';

create table method5.m5_sys_key
(
	db_link varchar2(128),
	sys_key raw(32)
);
comment on table method5.m5_sys_key is 'Private keys used for encrypting and decrypting Method5 commands to run as SYS.';

create or replace procedure method5.m5_sleep(seconds in number) is
--Purpose: Sleep for the specified number of seconds.
--This procedure is necessary because DBMS_LOCK.SLEEP is not available by default.
begin
	sys.dbms_lock.sleep(seconds);
end;
/

create or replace procedure method5.m5_purge_sql_from_shared_pool(p_username varchar2) is
--Purpose: Method4 must force statements to hard-parse.  When type information is generated
-- dyanamically it's too hard to tell if "select * from some_table" has changed so it has to
-- be hard-parsed each time.
  type string_table is table of varchar2(32767);
  v_sql_ids string_table;
begin
	--Find SQL_IDs of the SQL statements used to call Method5.
	--Use dynamic SQL to enable roles to select from GV$SQL.
	execute immediate q'!
		select 'begin sys.dbms_shared_pool.purge('''||address||' '||hash_value||''', ''C''); end;' v_sql
		from sys.gv_$sql
		where
			parsing_schema_name = :parsing_schema_name
			and command_type = 3
			and lower(sql_text) like '%table%(%m5%(%'
			and lower(sql_text) not like '%quine%'
	!'
	bulk collect into v_sql_ids
	using p_username;

	--Purge each SQL_ID to force hard-parsing each time.
	--This cannot be done in the earlier Describe or Prepare phase or it will generate errors.
	for i in 1 .. v_sql_ids.count loop
		execute immediate v_sql_ids(i);
	end loop;
end;
/


---------------------------------------
--#3: Install packages used by Method5.
alter session set current_schema=method5;
@code/method4/install
@code/plsql_lexer/install


---------------------------------------
--#4: Install types and Method5 main objects.
create or replace type method5.string_table is table of varchar2(4000);
/

create or replace procedure method5.grants_for_diff_table_owner
--Purpose: Creating Method5 results, metadata, and error tables in another
--	schema requires additional direct grants.  Creating views requires the
--	WITH GRANT OPTION.
(
	p_table_owner varchar2,
	p_table_name  varchar2,
	p_username    varchar2
) authid definer is
begin
	execute immediate 'grant select, insert, update on '||p_table_owner||'.'||p_table_name
		||' to '||p_username||' with grant option';
end;
/

--Install packages and types.
alter session set current_schema=method5;
@code/m5_pkg.pck
@code/method4_m5_poll_table_ot.typ
@code/tests/method5_test.pck
@code/method5_admin.pck

--Create and assign an ACL so Method5 can send emails from definer's rights objects.
--
--This code is mostly from this site:
--	http://qdosmsq.dunbar-it.co.uk/blog/2013/02/cannot-send-emails-or-read-web-servers-from-oracle-11g/
declare
	v_smtp_out_server varchar2(4000);
	v_entity_exists exception;
	pragma exception_init(v_entity_exists, -46212);
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
exception when v_entity_exists then null;
end create_and_assign_m5_acl;
/

--Install function and procedure wrappers.
create or replace function method5.m5
--See the package Method5 for details about this program.
(
	p_code       varchar2,
	p_targets    varchar2 default null,
	p_run_as_sys varchar2 default 'NO'
)
return anydataset pipelined using method5.method4_m5_poll_table_ot;
/

create or replace procedure method5.m5_proc(
	p_code                varchar2,
	p_targets             varchar2 default null,
	p_table_name          varchar2 default null,
	p_table_exists_action varchar2 default 'ERROR',
	p_asynchronous        boolean default true,
	p_run_as_sys          boolean default false
) authid definer is
begin
	method5.m5_pkg.run(
		p_code                => p_code,
		p_targets             => p_targets,
		p_table_name          => p_table_name,
		p_table_exists_action => p_table_exists_action,
		p_asynchronous        => p_asynchronous,
		p_run_as_sys          => p_run_as_sys);
end m5_proc;
/


--Install user synchronize procedure that depends on above objects.
@code/m5_synch_user.prc


---------------------------------------
--#5: Create views.
create or replace view method5.m5_priv_vw as
select
--Allowed privileges.
--Aggregated and max privileges for each target.
--If there are conflicts, use the highest privilege.
--This allows roles to stack on top of each other.
	oracle_username,
	os_username,
	target,
	max(default_targets) default_targets,
	max(can_run_as_sys) can_run_as_sys,
	max(can_run_shell_script) can_run_shell_script,
	max(install_links_in_schema) install_links_in_schema,
	min(run_as_m5_or_sandbox) run_as_m5_or_sandbox,
	max(sandbox_default_ts) sandbox_default_ts,
	max(sandbox_temporary_ts) sandbox_temporary_ts,
	max(sandbox_quota) sandbox_quota,
	max(sandbox_profile) sandbox_profile,
	set(cast(collect(privilege) as method5.string_table)) privileges
from
(
	--Privileges for each role and target.
	select
		m5_user.oracle_username,
		m5_user.os_username,
		m5_user.default_targets,
		target_role.role_name,
		target_role.target_string,
		target_role.can_run_as_sys,
		target_role.can_run_shell_script,
		target_role.install_links_in_schema,
		target_role.run_as_m5_or_sandbox,
		target_role.sandbox_default_ts,
		target_role.sandbox_temporary_ts,
		--Convert a "size clause" into a number.
		--(The column has a constraint so this conversion should be safe.)
		case
			when lower(target_role.sandbox_quota) like '%k' then to_number(replace(lower(sandbox_quota), 'k')) * 1024
			when lower(target_role.sandbox_quota) like '%m' then to_number(replace(lower(sandbox_quota), 'm')) * 1024*1024
			when lower(target_role.sandbox_quota) like '%g' then to_number(replace(lower(sandbox_quota), 'g')) * 1024*1024*1024
			when lower(target_role.sandbox_quota) like '%t' then to_number(replace(lower(sandbox_quota), 't')) * 1024*1024*1024*1024
			when lower(target_role.sandbox_quota) like '%p' then to_number(replace(lower(sandbox_quota), 'p')) * 1024*1024*1024*1024*1024
			when lower(target_role.sandbox_quota) like '%e' then to_number(replace(lower(sandbox_quota), 'e')) * 1024*1024*1024*1024*1024*1024
			else to_number(sandbox_quota)
		end sandbox_quota,
		target_role.sandbox_profile,
		target_role.target,
		m5_role_priv.privilege
	from method5.m5_user
	join method5.m5_user_role
		on m5_user.oracle_username = m5_user_role.oracle_username
	join
	(
		--Expand the M5_ROLE target_string to a table of targets.
		select
			role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema,
			run_as_m5_or_sandbox, sandbox_default_ts, sandbox_temporary_ts, sandbox_quota, sandbox_profile,
			column_value target
		from method5.m5_role
		cross join table(method5.m5_pkg.get_target_tab_from_target_str(m5_role.target_string, p_database_or_host => 'database'))
		union all
		select
			role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema,
			run_as_m5_or_sandbox, sandbox_default_ts, sandbox_temporary_ts, sandbox_quota, sandbox_profile,
			column_value target
		from method5.m5_role
		cross join table(method5.m5_pkg.get_target_tab_from_target_str(m5_role.target_string, p_database_or_host => 'host'))
	) target_role
		on m5_user_role.role_name = target_role.role_name
	left join method5.m5_role_priv
		on target_role.role_name = m5_role_priv.role_name
) privileges
group by oracle_username, os_username, target
order by oracle_username;

create or replace view method5.m5_my_access_vw as
select *
from method5.m5_priv_vw
where upper(trim(oracle_username)) = sys_context('userenv', 'session_user');


---------------------------------------
--#6: Create public synonyms.
create public synonym m5_database   for method5.m5_database;
create public synonym m5            for method5.m5;
create public synonym m5_proc       for method5.m5_proc;
create public synonym m5_pkg        for method5.m5_pkg;
create public synonym m5_synch_user for method5.m5_synch_user;


---------------------------------------
--#7: Role, minimum privileges, and why they are needed, for database users to run Method5.
create role m5_run;

--These object privileges allow users to run Method5.
--But they can only use the packages as permitted by the M5_USER configuration.
grant select  on method5.m5_database         to m5_run;
grant execute on method5.m5                  to m5_run;
grant execute on method5.m5_proc             to m5_run;
grant execute on method5.m5_pkg              to m5_run;
grant execute on method5.m5_synch_user       to m5_run;
grant select  on method5.m5_generic_sequence to m5_run;
grant execute on method5.m5_sleep            to m5_run;
grant execute on method5.string_table        to m5_run;
grant select on method5.m5_my_access_vw      to m5_run;
--For Method4 dynamic SQL to return "anything" creating a type is necessary to describe the results.
grant create type      to m5_run;
--For Method4 dynamic SQL a function is needed to return the "anything".
grant create procedure to m5_run;
--The job allows Method4 dynamic SQL to purge each specific query from the
--shared pool, forcing hard parsing on every statement.  This is useful with
--Oracle Data Cartridge because the same query may be "described" differently
--after each run.
grant execute on method5.m5_purge_sql_from_shared_pool to m5_run;
grant create job                                       to m5_run;
--The user must be able to logon.
grant create session                                   to m5_run;
--Allow the person who installed Method5 to use it.
declare
	v_username varchar2(128) := sys_context('userenv', 'session_user');
begin
	execute immediate 'grant m5_run to '||v_username;
	execute immediate 'grant create database link to '||v_username;
end;
/


---------------------------------------
--#8: Audit Method5 objects. 
audit all on method5.m5_audit;
audit all on method5.m5_pkg;


---------------------------------------
--#9: Add triggers to protect important tables.
begin
	sys.m5_create_triggers;
end;
/


---------------------------------------
--#10: Quick check that Method5 schema is valid.
--If the top-level objects are valid then everything else should be OK.
prompt Validating Method5 installation...
set serveroutput on;
set feedback off;
declare
	v_count number := 0;
begin
	--Compile any invalid objects.
	--There are some self-referential objects that just need a recompile.
	dbms_utility.compile_schema('METHOD5', compile_all => false);

	--Print message if any errors.
	for objects in
	(
		select 'METHOD4_M5_POLL_TABLE_OT' object_name, 'TYPE BODY'    object_type from dual union all
		select 'METHOD5_ADMIN'            object_name, 'PACKAGE BODY' object_type from dual union all
		select 'METHOD5_TEST'             object_name, 'PACKAGE BODY' object_type from dual union all
		select 'STATEMENT_CLASSIFIER'     object_name, 'PACKAGE BODY' object_type from dual union all
		select 'M5'                       object_name, 'FUNCTION'     object_type from dual union all
		select 'M5_PKG'                   object_name, 'PACKAGE BODY' object_type from dual
		minus
		select object_name, object_type
		from dba_objects
		where owner = 'METHOD5'
			and status = 'VALID'
		order by 1,2
	) loop
		v_count := v_count + 1;
		dbms_output.new_line;
		dbms_output.put_line('ERROR - Installation failed, this object is invalid: '||objects.object_name);
		dbms_output.new_line;
	end loop;

	--Print message if success.
	if v_count = 0 then
		dbms_output.new_line;
		dbms_output.put_line('SUCCESS - All objects look OK.  Method5 installed correctly.');
		dbms_output.new_line;
	end if;
end;
/
set feedback on;
