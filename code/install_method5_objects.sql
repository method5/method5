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
comment on column method5.m5_database.operating_system is 'A value like "Linux", "Windows", "SunOS", etc.';
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
	oracle_username         varchar2(128)   not null,
	os_username             varchar2(4000),
	email_address           varchar2(4000),
	is_m5_admin             varchar2(3)     not null,
	default_targets         varchar2(4000),
	changed_by              varchar2(128)   default user not null,
	changed_date            date            default sysdate not null,
	constraint m5_user_pk primary key(oracle_username),
	constraint is_m5_admin_ck check(is_m5_admin in ('Yes', 'No'))
);
comment on table method5.m5_user is 'Method5 users.';
comment on column method5.m5_user.oracle_username is 'Individual Oracle account used to access Method5.  Do not use a shared account.';
comment on column method5.m5_user.os_username is 'Individual operating system account used to access Method5.  Depending on your system and network configuration enforcing this username may also ensure two factor authentication.  Do not use a shared account.';
comment on column method5.m5_user.email_address is 'Only necessary for administrators so they can be notified when configuration tables are changed.';
comment on column method5.m5_user.is_m5_admin is 'Can this user change Method5 configuration tables.  Either Yes or No.';
comment on column method5.m5_user.default_targets is 'Use this target list if none is specified.  Leave NULL to use the global default set in M5_CONFIG.';
comment on column method5.m5_user.changed_by is 'User who last changed this row.';
comment on column method5.m5_user.changed_date is 'Date this row was last changed.';

create table method5.m5_role
(
	role_name                varchar2(128)  not null,
	target_string            varchar2(4000) not null,
	run_as_m5_or_temp_user   varchar2(9)    not null,
	can_run_as_sys           varchar2(3)    not null,
	can_run_shell_script     varchar2(3)    not null,
	install_links_in_schema  varchar2(3)    not null,
	description              varchar2(4000),
	changed_by               varchar2(128)  default user not null,
	changed_date             date           default sysdate not null,
	constraint m5_role_pk primary key(role_name),
	constraint run_as_m5_or_temp_user_ck check (run_as_m5_or_temp_user in ('M5', 'TEMP_USER')),
	constraint can_run_as_sys_ck check (can_run_as_sys in ('Yes', 'No')),
	constraint can_run_shell_script_ck check (can_run_shell_script in ('Yes', 'No')),
	constraint install_links_in_schema_ck check (install_links_in_schema in ('Yes', 'No')),
	constraint temp_usr_cant_run_sys_or_shell check (not (run_as_m5_or_temp_user = 'TEMP_USER' and (can_run_as_sys = 'Yes' or can_run_shell_script = 'Yes')))
);
--TODO: Comments

--Default "all" role.  This role does not need to exist and can be dropped if necessary.
insert into method5.m5_role(role_name, target_string, run_as_m5_or_temp_user, can_run_as_sys, can_run_shell_script, install_links_in_schema, description)
values ('ALL', '%', 'M5', 'Yes', 'Yes', 'Yes', 'This role grants everything.  It is created by default but you do not need to assign it to anyone and you may delete this role.');
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
--TODO: Comments

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
--TODO: Comments

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

create or replace procedure method5.m5_sleep(seconds in number) is
--Purpose: Sleep for the specified number of seconds.
--This procedure is necessary because DBMS_LOCK.SLEEP is not available by default.
begin
	sys.dbms_lock.sleep(seconds);
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
	min(run_as_m5_or_temp_user) run_as_m5_or_temp_user,
	max(can_run_as_sys) can_run_as_sys,
	max(can_run_shell_script) can_run_shell_script,
	max(install_links_in_schema) install_links_in_schema,
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
		target_role.run_as_m5_or_temp_user,
		target_role.can_run_as_sys,
		target_role.can_run_shell_script,
		target_role.install_links_in_schema,
		target_role.target,
		m5_role_priv.privilege
	from method5.m5_user
	join method5.m5_user_role
		on m5_user.oracle_username = m5_user_role.oracle_username
	join
	(
		--Expand the M5_ROLE target_string to a table of targets.
		select
			role_name, target_string, run_as_m5_or_temp_user, can_run_as_sys, can_run_shell_script, install_links_in_schema,
			column_value target
		from method5.m5_role
		cross join method5.m5_pkg.get_target_tab_from_target_str(m5_role.target_string, p_database_or_host => 'database')
		union all
		select
			role_name, target_string, run_as_m5_or_temp_user, can_run_as_sys, can_run_shell_script, install_links_in_schema,
			column_value target
		from method5.m5_role
		cross join method5.m5_pkg.get_target_tab_from_target_str(m5_role.target_string, p_database_or_host => 'host')
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
--#7: Role, minimum privileges, and why they are needed, for the Method5 users.
create role m5_user_role;

--These object privileges allow users to run Method5.
--But they can only use the packages as permitted by the M5_USER configuration.
grant select  on method5.m5_database         to m5_user_role;
grant execute on method5.m5                  to m5_user_role;
grant execute on method5.m5_proc             to m5_user_role;
grant execute on method5.m5_pkg              to m5_user_role;
grant execute on method5.m5_synch_user       to m5_user_role;
grant select  on method5.m5_generic_sequence to m5_user_role;
grant execute on method5.m5_sleep            to m5_user_role;
grant select on method5.m5_my_access_vw      to m5_user_role;

--For Method4 dynamic SQL to return "anything" creating a type is necessary to describe the results.
grant create type      to m5_user_role;
--For Method4 dynamic SQL a function is needed to return the "anything".
grant create procedure to m5_user_role;
--The job allows Method4 dynamic SQL to purge each specific query from the
--shared pool, forcing hard parsing on every statement.  This is useful with
--Oracle Data Cartridge because the same query may be "described" differently
--after each run.
grant create job       to m5_user_role;


---------------------------------------
--#8: Audit Method5 objects. 
audit all on method5.m5_audit;
audit all on method5.m5_pkg;


prompt Done.
