prompt Creating Snare objects...


--------------------------------------------------------------------------------
--#0: Check the user.
--------------------------------------------------------------------------------

@code/check_user must_not_run_as_sys_and_has_dba


--------------------------------------------------------------------------------
--#1: Create snare tables.
--------------------------------------------------------------------------------

create table method5.snapshots(
	snapshot_name  varchar2(128) not null,
	the_date       date not null,
	target_string  varchar2(4000) not null,
	constraint snapshots_pk primary key(snapshot_name),
	constraint snapshots_ck1 check (snapshot_name = upper(snapshot_name))
);
comment on table method5.snapshots is 'One row for every Snare run.';

create table method5.configs
(
	config_type             varchar2(100) not null,
	gather_code             clob not null,
	table_name              varchar2(26) not null,
	config_name_column      varchar2(30) not null,
	config_value_column     varchar2(30) not null,
	config_value_data_type  varchar2(30) not null,
	static_targets          varchar2(4000),
	constraint configs_pk primary key (config_type),
	constraint configs_ck check (config_value_data_type in ('STRING', 'NUMBER', 'DATE'))
);
comment on table method5.configs is 'One row per configuration item to collect.';

create table method5.snapshot_results
(
	snapshot_name varchar2(128) not null,
	config_type   varchar2(100) not null,
	target        varchar2(128) not null,
	config_name   varchar2(100) not null,
	string_value  varchar2(4000),
	number_value  number,
	date_value    date,
	primary key (snapshot_name, config_type, target, config_name),
	constraint snapshot_results_fk foreign key (config_type) references method5.configs(config_type)
)
--Compressed IOT saves a lot of space compared to a regular table and index.
organization index compress 3 overflow tablespace users;
comment on table method5.snapshot_results is 'Snaphot result values, for a given snapshot and configuration type.';

create table method5.snapshot_metadata
(
	snapshot_name varchar2(128) not null,
	config_type varchar2(100) not null,
	date_started date,
	date_updated date,
	username varchar2(128),
	is_complete varchar2(3),
	targets_expected number,
	targets_completed number,
	targets_with_errors number,
	num_rows number,
	constraint snapshot_metadata_pk primary key (snapshot_name, config_type, date_started, username),
	constraint snapshot_metadata_fk1 foreign key (snapshot_name) references method5.snapshots(snapshot_name),
	constraint snapshot_metadata_fk2 foreign key (config_type) references method5.configs(config_type)
);
comment on table method5.snapshot_metadata is 'Metadata for each snapshot-configuration.';

create table method5.snapshot_errors
(
	snapshot_name varchar2(128) not null,
	config_type varchar2(100) not null,
	target varchar2(30),
	link_name varchar2(128),
	date_error date,
	error_stack_and_backtrace varchar2(4000),
	constraint snapshot_errors_pk primary key (snapshot_name, config_type, target, date_error),
	constraint snapshot_errors_fk1 foreign key (snapshot_name) references method5.snapshots(snapshot_name),
	constraint snapshot_errors_fk2 foreign key (config_type) references method5.configs(config_type)
);
comment on table method5.snapshot_errors is 'Metadata for each snapshot-configuration.';


--------------------------------------------------------------------------------
--#2: Add default configurations
--------------------------------------------------------------------------------

--Default configurations
insert into method5.configs(config_type, gather_code, table_name, config_name_column, config_value_column, config_value_data_type, static_targets)
select 'Components', q'[select comp_id, status from dba_registry]', 'snare_components', 'comp_id', 'status', 'STRING', null from dual union all
select 'Crontab', '#!/bin/ksh'||chr(10)||'crontab -l', 'snare_crontab', 'lpad(line_number, 4, ''0'')', 'output', 'STRING', null from dual union all
select 'Invalid objects',
	q'[
		select distinct '"'||owner||'"."'||object_name||'": '||object_type object
		from dba_objects
		where status <> 'VALID'
			and object_name not like 'M__TEMP%'
	]',
	'snare_invalid_objects', 'object', 'null', 'STRING', null
from dual union all
select 'Last patch',
	q'[
		--Get latest patch status for either 11g or 12c database.
		--Due to bug 25269268 the table DBA_REGISTRY_HISTORY is not populated in 12c.
		--To workaround this we must query the 12c-only table DBA_REGISTRY_SQLPATCH.
		--That requires using DBMS_XMLGEN.GETXML which can handle non-existing objects.
		select 'LAST_PATCH' name, 
		nvl
		(
			(
				--Latest 12c patch, if any.
				select extractvalue(xmltype(dbms_xmlgen.getxml(q'!
					--Last patch status for 12c databases.
					select last_patch
					from
					(
						select
							description || ' - '
								|| status || ' - '
								|| to_char(action_time, 'YYYY-MM-DD') last_patch,
							row_number() over (order by action_time desc) last_when_1
						from dba_registry_sqlpatch
					)
					where last_when_1 = 1
				!')),'/ROWSET/ROW/LAST_PATCH') last_patch
				from dba_views
				where owner = 'SYS' and view_name = 'DBA_REGISTRY_SQLPATCH'
			),
			(
				--Latest 11g patch.
				select last_patch
				from
				(
					--Registry History with version number ordering.
					select
						comments || ' - ' || to_char(action_time, 'YYYY-MM-DD') last_patch,
						row_number() over (order by version desc, id desc) last_when_1
					from dba_registry_history
					where comments like 'PSU%'
				)
				where last_when_1 = 1
			)
		) last_patch
		from dual
	]',
	'snare_last_patch', 'name', 'last_patch', 'STRING', null
from dual union all
select 'Misc database settings',
	q'[
		select 'LOG_MODE' name, log_mode value from v$database union all
		select 'VERSION' name, version value from v$instance
	]',
	'snare_misc_db_settings', 'name', 'value', 'STRING', null
from dual union all
select 'M5_DATABASE', q'[select instance_name, host_name||','||database_name||','||lifecycle_status||','||line_of_business||','||target_version||','||is_active host_db_env_lob_ver_act from m5_database]', 'snare_m5_database', 'instance_name', 'host_db_env_lob_ver_act', 'STRING', sys_context('userenv', 'db_name') from dual union all
select 'Ping database', 'select dummy from dual', 'snare_ping_database', 'dummy', 'dummy', 'STRING', null from dual union all
select 'Ping host', '#!/bin/sh'||chr(10)||'echo x', 'snare_ping_host', 'line_number', 'output', 'STRING', null from dual union all
select 'V$PARAMETER', 'select name,value from v$parameter', 'snare_v$parameter', 'name', 'value', 'STRING', null from dual;

commit;


--------------------------------------------------------------------------------
--#3: Create types.
--------------------------------------------------------------------------------

--Types for return data.
create or replace type method5.config_rec is object
(
	before_or_after varchar2(7),
	config_type     varchar2(100),
	target          varchar2(100),
	config_name     varchar2(100),
	string_value    varchar2(4000),
	number_value    number,
	date_value      date
);
/
create or replace type method5.config_nt is table of method5.config_rec;
/

--------------------------------------------------------------------------------
--#4: Create package.
--------------------------------------------------------------------------------

@code/addons/snare.pck


--------------------------------------------------------------------------------
--#5: Create public synonyms.
--------------------------------------------------------------------------------

create public synonym snare             for method5.snare;
create public synonym snapshot_results  for method5.snapshot_results;
create public synonym snapshot_metadata for method5.snapshot_metadata;
create public synonym snapshot_errors   for method5.snapshot_errors;
create public synonym snapshots         for method5.snapshots;
create public synonym configs           for method5.configs;


--------------------------------------------------------------------------------
--#6: Schedule job (but leave it disabled so it doesn't run unless people want it.)
--------------------------------------------------------------------------------

begin
	dbms_scheduler.create_job
	(
		job_name        => 'SNARE_DAILY_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => systimestamp at time zone 'US/Eastern',
		enabled         => false,
		repeat_interval => 'FREQ=DAILY; BYHOUR=3; BYMINUTE=0;',
		job_action      =>
		q'[
			begin
				method5.snare.create_snapshot(
					p_snapshot_name => 'EVERYTHING_'||to_char(sysdate, 'YYYYMMDD'),
					p_targets => '%'
				);
			end;
		]'
	);
end;
/


prompt Finished creating snare objects.
