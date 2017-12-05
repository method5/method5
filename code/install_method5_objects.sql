prompt Creating Method5 objects...


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
	target_guid      raw(16),
	host_name        varchar2(256),
	database_name    varchar2(9) not null,
	instance_name    varchar2(16),
	lifecycle_status varchar2(256),
	line_of_business varchar2(1024),
	target_version   varchar2(64),
	operating_system varchar2(256),
	user_comment     varchar2(1024),
	cluster_name     varchar2(1024),
	connect_string   varchar2(4000) not null,
	refresh_date     date,
	constraint m5_database_ck_numbers_only check (regexp_like(target_version, '^[0-9\.]*$'))
);

comment on table method5.m5_database                   is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.';
comment on column method5.m5_database.target_guid      is 'This GUID may be useful for matching to the Oracle Enterprise Manager GUID.';
comment on column method5.m5_database.host_name        is 'The name of the machine the database instance runs on.';
comment on column method5.m5_database.database_name    is 'A short string to identify a database.  This name will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.';
comment on column method5.m5_database.instance_name    is 'A short string to uniquely identify a database instance.  For standalone databases this will probably be the same as the DATABASE_NAME.  For a Real Application Cluster (RAC) database this will probably be DATABASE_NAME plus a number at the end.';
comment on column method5.m5_database.lifecycle_status is 'A value like "DEV" or "PROD".  (Your organization may refer to this as the "environment" or "tier".)';
comment on column method5.m5_database.line_of_business is 'A value to identify a database by business unit, contract, company, etc.';
comment on column method5.m5_database.target_version   is 'A value like "11.2.0.4.0" or "12.1.0.2.0".  This value may be used to select the lowest or highest version so only use numbers.';
comment on column method5.m5_database.operating_system is 'A value like "SunOS" or "Windows".';
comment on column method5.m5_database.user_comment     is 'Any additional comments.';
comment on column method5.m5_database.cluster_name     is 'The Real Application Cluster (RAC) name for the cluster.';
comment on column method5.m5_database.connect_string   is 'Used to create the database link.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column (for each entry, use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.';
comment on column method5.m5_database.refresh_date     is 'The date this row was last refreshed.';

create table method5.m5_database_hist as select * from method5.m5_database;

--Create 4 sample rows.  Most data is fake but the connection information should work for most databases.
insert into method5.m5_database
(
	target_guid, host_name, database_name, instance_name, lifecycle_status, line_of_business,
	target_version, operating_system, user_comment, cluster_name, connect_string, refresh_date
)
with database_info as
(
	select
		null target_guid,
		(select host_name version from v$instance) host_name,
		(select version from v$instance) version,
		(SELECT replace(replace(product, 'TNS for '), ':') FROM product_component_version where product like 'TNS%') operating_system,
		null user_comment,
		null cluster_name,
		(
			select '(description=(address=(protocol=tcp)(host=localhost)(port=1521))(connect_data=(server=dedicated)(sid='||instance_name||')))'
			from v$instance
		) connect_string,
		sysdate refresh_date
	from dual
)
select target_guid, host_name, 'devdb1'  database_name, 'devdb1'  instance_name, 'dev'  lifecycle_status, 'ACME' line_of_business,	version, operating_system, user_comment, cluster_name, connect_string, refresh_date from database_info union all
select target_guid, host_name, 'testdb1' database_name, 'testdb1' instance_name, 'test' lifecycle_status, 'ACME' line_of_business,	version, operating_system, user_comment, cluster_name, connect_string, refresh_date from database_info union all
select target_guid, host_name, 'devdb2'  database_name, 'devdb2'  instance_name, 'dev'  lifecycle_status, 'Ajax' line_of_business,	version, operating_system, user_comment, cluster_name, connect_string, refresh_date from database_info union all
select target_guid, host_name, 'testdb2' database_name, 'testdb2' instance_name, 'test' lifecycle_status, 'Ajax' line_of_business,	version, operating_system, user_comment, cluster_name, connect_string, refresh_date from database_info;

commit;

create table method5.m5_user
(
	oracle_username      varchar2(128) not null,
	os_username          varchar2(4000),
	email_address        varchar2(4000),
	is_m5_admin          varchar2(3) not null,
	can_run_as_sys       varchar2(3) not null,
	can_run_shell_script varchar2(3) not null,
	allowed_targets      varchar2(4000),
	default_targets      varchar2(4000),
	constraint m5_user_uq unique(oracle_username, os_username),
	constraint can_is_m5_admin_ck check(is_m5_admin in ('Yes', 'No')),
	constraint can_run_as_sys_ck check(can_run_as_sys in ('Yes', 'No')),
	constraint can_run_shell_script_ck check (can_run_shell_script in ('Yes', 'No'))
);
comment on table method5.m5_user is 'Method5 users and what they are allowed to run.';
comment on column method5.m5_user.oracle_username is 'Individual Oracle account used to access Method5.  Do not use a shared account.';
comment on column method5.m5_user.os_username is 'Individual operating system account used to access Method5.  Depending on your system and network configuration enforcing this username may also ensure two factor authentication.  Do not use a shared account.';
comment on column method5.m5_user.email_address is 'Only necessary for administrators so they can be notified when configuration tables are changed.';
comment on column method5.m5_user.is_m5_admin is 'Can this user change Method5 configuration tables.  Either Yes or No.';
comment on column method5.m5_user.can_run_as_sys is 'Can the user run commands as the SYS user.  Either Yes or No.';
comment on column method5.m5_user.can_run_shell_script is 'Can the user run shell scripts.  Either Yes or No.';
comment on column method5.m5_user.allowed_targets is 'Restrict a user to this target list of databases.  It works the same as P_TARGETS, and can be a comma-separated list of databases, hosts, lifecycles, wildcards, target groups, etc.  Leave NULL to allow access to everything.';
comment on column method5.m5_user.default_targets is 'Use this target list if none is specified.  Leave NULL to use the global default set in M5_CONFIG.';

--Used for Method5 configuration.
create sequence method5.m5_config_seq;
create table method5.m5_config
(
	config_id    number not null,
	config_name  varchar2(100) not null,
	string_value varchar2(4000),
	number_value number,
	date_value   date,
	constraint config_pk primary key (config_id)
);

--Add default configuration values.
insert into method5.m5_config(config_id, config_name, string_value)
select method5.m5_config_seq.nextval, name, value
from
(
	select 'Access Control - User is not locked'            name, 'ENABLED' value from dual union all
	select 'Access Control - User has expected OS username' name, 'ENABLED' value from dual union all
	select 'Default Targets'                                name, '%'       value from dual
);

insert into method5.m5_config(config_id, config_name, number_value)
select method5.m5_config_seq.nextval, name, value
from
(
	select 'Job Timeout (seconds)' name, 23*60*60 value from dual
);

commit;

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

--Create triggers to alert admin whenever the configuration changes.
create or replace trigger method5.detect_changes_to_m5_config
after insert or update or delete on method5.m5_config
--Purpose: Email the administrator if anyone changes the M5_CONFIG table.
declare
	v_sender_address varchar2(4000);
	v_recipients varchar2(4000);
begin
	--Get email configuration information.
	select min(string_value) sender_address
		,listagg(string_value, ',') within group (order by string_value) recipients
	into v_sender_address, v_recipients
	from method5.m5_config
	where config_name = 'Administrator Email Address';

	--Only try to send an email if there is an address configured.
	if v_sender_address is not null then
		sys.utl_mail.send(
			sender => v_sender_address,
			recipients => v_recipients,
			subject => 'M5_CONFIG table was changed.',
			message => 'The database user '||sys_context('userenv', 'session_user')||
				' (OS user '||sys_context('userenv', 'os_user')||') made a change to the'||
				' table M5_CONFIG.'
		);
	end if;
end;
/

create or replace trigger method5.detect_changes_to_m5_user_conf
after insert or update or delete on method5.m5_user
--Purpose: Email the administrator if anyone changes the M5_USER table.
declare
	v_sender_address varchar2(4000);
	v_recipients varchar2(4000);
begin
	--Get email configuration information.
	select min(string_value) sender_address
		,listagg(string_value, ',') within group (order by string_value) recipients
	into v_sender_address, v_recipients
	from method5.m5_config
	where config_name = 'Administrator Email Address';

	--Only try to send an email if there is an address configured.
	if v_sender_address is not null then
		sys.utl_mail.send(
			sender => v_sender_address,
			recipients => v_recipients,
			subject => 'M5_USER table was changed.',
			message => 'The database user '||sys_context('userenv', 'session_user')||
				' (OS user '||sys_context('userenv', 'os_user')||') made a change to the'||
				' table M5_USER.'
		);
	end if;
end;
/

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

--Create Method5 ACL to enable sending emails.
begin
	method5.method5_admin.create_and_assign_m5_acl;
end;
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
) authid current_user is
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
--#5: Create public synonyms.
create public synonym m5_database for method5.m5_database;
create public synonym m5 for method5.m5;
create public synonym m5_proc for method5.m5_proc;
create public synonym m5_pkg for method5.m5_pkg;
create public synonym m5_synch_user for method5.m5_synch_user;


---------------------------------------
--#6: Audit Method5 objects. 
audit all on method5.m5_audit;
audit all on method5.m5_pkg;


prompt Done.
