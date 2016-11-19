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
	targets_expected      number,
	targets_completed     number,
	targets_with_errors   number,
	num_rows              number,
	access_control_error  varchar2(4000),
	constraint m5_audit_ck1 check (asynchronous in ('Yes', 'No')),
	constraint m5_audit_ck2 check (table_exists_action in ('ERROR', 'APPEND', 'DELETE', 'DROP')),
	constraint m5_audit_pk primary key (username, create_date, table_name)
);

--This table is very similar to sysman.mgmt$db_dbninstanceinfo and sysman.em_global_target_properties properties.
create table method5.m5_database
(
	target_guid      raw(16),
	host_name        varchar2(256),
	database_name    varchar2(9),
	instance_name    varchar2(16),
	lifecycle_status varchar2(256),
	line_of_business varchar2(1024),
	target_version   varchar2(64),
	operating_system varchar2(256),
	user_comment     varchar2(1024),
	cluster_name     varchar2(1024),
	refresh_date     date
);

create table method5.m5_database_hist as select * from method5.m5_database;

create table method5.m5_database_not_queried
(
	database_name	varchar2(30),
	reason			varchar2(4000),
	constraint m5_database_not_queried_pk primary key (database_name)
);

create table method5.m5_2step_authentication
(
	oracle_username varchar2(128) not null,
	os_username     varchar2(4000) not null,
	constraint m5_2step_authentication_uq unique(oracle_username, os_username)
);

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
	select 'Access Control - Username has _DBA suffix'      name, 'ENABLED' value from dual union all
	select 'Access Control - User has DBA role'             name, 'ENABLED' value from dual union all
	select 'Access Control - User has DBA_PROFILE'          name, 'ENABLED' value from dual union all
	select 'Access Control - User is not locked'            name, 'ENABLED' value from dual union all
	select 'Access Control - User has expected OS username' name, 'ENABLED' value from dual union all
	select 'Default Targets'                                name, '%'       value from dual
);
commit;

--Create trigger to alert admin whenever the configuration changes.
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
end send_email_and_raise_error;
/

create table method5.m5_global_data_dictionary
(
	owner      varchar2(128),
	table_name varchar2(128)
);
create unique index method5.m5_global_data_dictionary_uq on method5.m5_global_data_dictionary(upper(owner), upper(table_name));
comment on table method5.m5_global_data_dictionary is 'Tables used in the global data dictionary.  These tables are monitored by the daily email job.';


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

--Install package and type.
alter session set current_schema=method5;
@code/m5_pkg.pck
@code/method4_m5_poll_table_ot.typ
@code/tests/method5_test.pck
@code/method5_admin.pck


--Install function and procedure wrappers.
create or replace function method5.m5
--See the package Method5 for details about this program.
(
	p_code    varchar2,
	p_targets varchar2 default null
)
return anydataset pipelined using method5.method4_m5_poll_table_ot;
/

create or replace procedure method5.m5_proc(
	p_code                varchar2,
	p_targets             varchar2 default null,
	p_table_name          varchar2 default null,
	p_table_exists_action varchar2 default 'ERROR',
	p_asynchronous        boolean default true
) authid current_user is
begin
	method5.m5_pkg.run(
		p_code                => p_code,
		p_targets             => p_targets,
		p_table_name          => p_table_name,
		p_table_exists_action => p_table_exists_action,
		p_asynchronous        => p_asynchronous);
end m5_proc;
/


---------------------------------------
--#5: Create public synonyms.
create public synonym m5_database for method5.m5_database;
create public synonym m5 for method5.m5;
create public synonym m5_proc for method5.m5_proc;
create public synonym m5_pkg for method5.m5_pkg;


---------------------------------------
--#6: Audit Method5 objects. 
audit all on method5.m5_audit;
audit all on method5.m5_pkg;


prompt Done.
