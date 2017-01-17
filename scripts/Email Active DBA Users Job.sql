--Purpose: Email a list of active DBA users on all databases.
--How to use:
--  Run step #1 to check job status.  
--  Customize and run step #2 to configure the job.
--  Run step #3 and #4 to create and schedule the job.
--Prerequisites:
--	1. The user running this script must be able to use Method5.
--	2. The M5_DBA_USERS and M5_DBA_ROLE_PRIVS jobs must be installed and running.
--Version: 2.0.1



--------------------------------------------------------------------------------
--#1: Check job status (check periodically)
--------------------------------------------------------------------------------
--Check job status - there should be a "SUCCEEDED".
select *
from dba_scheduler_job_run_details
where job_name = 'EMAIL_ACTIVE_DBA_USERS_JOB'
order by log_date desc;

--Check global data dictionary results.  It should work about 99% of the time.
select * from m5_dba_users;
select * from m5_dba_users_meta;
select * from m5_dba_users_err;



--------------------------------------------------------------------------------
--#2: Create tables to hold configuration data.
--------------------------------------------------------------------------------

--Mapping between users and organization names to display on the email.
create table dba_user_org
(
  username VARCHAR2(128) not null,
  org      VARCHAR2(100) not null,
  constraint dba_user_org_pk primary key (username)
);

--Insert new users:
insert into dba_user_org(username, org) values('', '');

--Job configuration data.
create table email_active_dba_users_config
(
	config_name varchar2(4000),
	config_value varchar2(4000),
	constraint email_active_dba_users_conf_pk primary key (config_name)
);

--Add configuration data.
--Customize this.
insert into email_active_dba_users_config
--Required:
          select 'sender_email', '?????' from dual
union all select 'recipients_email_list', '????;????;????' from dual
--Optional, comment these lines out if you don't want them:
union all select 'profile_predicate', q'[ and profile not in ('????', '????') ]' from dual
union all select 'database_exceptions_predicate', q'[ and database_name not in ('????', '?????') ]' from dual
;



--------------------------------------------------------------------------------
--#3: Create procedure (one-time step)
--------------------------------------------------------------------------------
create or replace procedure email_active_dba_users authid current_user is
/*
	Purpose: Send an email of all active DBA users.

	WARNING: Do not directly modify this procedure.  The official copy is version controlled.

*/
	v_sql varchar2(32767);
	v_sender_email varchar2(32767);
	v_recipients_email_list varchar2(32767);
	v_profile_predicate varchar2(32767);
	v_database_exceptions_pred varchar2(32767);

	type v_active_dbas_rec is record
	(
		username  varchar2(128),
		org       varchar2(100),
		databases varchar2(4000)
	);
	type v_active_dbas_nt is table of v_active_dbas_rec;
	v_active_dbas v_active_dbas_nt := v_active_dbas_nt();

	v_email_body varchar2(32767);
begin
	--Get configuration data.
	select
		max(case when config_name = 'sender_email'                  then config_value else null end),
		max(case when config_name = 'recipients_email_list'         then config_value else null end),
		max(case when config_name = 'profile_predicate'             then config_value else null end),
		max(case when config_name = 'database_exceptions_predicate' then config_value else null end)
	into
		v_sender_email,
		v_recipients_email_list,
		v_profile_predicate,
		v_database_exceptions_pred
	from email_active_dba_users_config;

	--Create SQL statement.
	v_sql :=
	replace(replace(q'[
		--List of users and fist 10 databases.
		select username, org,
			listagg(database_name, ',') within group (order by database_name)
			||
			case when count_per_user > 10 then '... ('||(count_per_user-10)||' databases not displayed) ' end
			databases
		from
		(
			--DBA users with counts.
			select
				active_dbas.username,
				nvl(org, '????') org,
				database_name
				,row_number() over (partition by active_dbas.username order by database_name) rownumber
				,count(*) over (partition by active_dbas.username) count_per_user
			from
			(
				--Active DBAs.
				select database_name, username
				from m5_dba_users
				where
					(database_name, username) in
					(
						select database_name, grantee
						from m5_dba_role_privs
						where granted_role = 'DBA'
					)
					and account_status not like '%LOCK%'
					and username not in ('SYS', 'SYSTEM')
					##PROFILE_PREDICATE##
					##DATABASE_EXCEPTIONS_PREDICATE##
			) active_dbas
			left join dba_user_org
				on active_dbas.username = dba_user_org.username
		) dba_users_with_counts
		where rownumber <= 10
		group by username, org, count_per_user
		order by username
	]'
	, '##PROFILE_PREDICATE##', v_profile_predicate)
	, '##DATABASE_EXCEPTIONS_PREDICATE##', v_database_exceptions_pred);


	--Get data.
	execute immediate v_sql
	bulk collect into v_active_dbas;

	--Add header.
	v_email_body := v_email_body||'
	<html>
	<head>
		<STYLE TYPE="text/css">
		<!--
		TD{font-family: Courier New; font-size: 10pt;}
		TH{font-family: Courier New; font-size: 10pt;}
		--->
		</STYLE>
	</head>

	<body>
	<table border="1">
	<tr>
		<th>Username</th>
		<th>Org</th>
		<th>Database(s)</th>
	</tr>
	';

	--Add DBA rows to table.
	for i in 1 .. v_active_dbas.count loop
		v_email_body := v_email_body||'<tr><td>'||v_active_dbas(i).username||'</td><td>'
			||v_active_dbas(i).org||'</td><td>'||v_active_dbas(i).databases||'</td></tr>';
	end loop;

	--Add footer.
	v_email_body := v_email_body||q'[</table></body></html>]';

	--Send an email.
	utl_mail.send(
		sender     => v_sender_email,
		recipients => v_recipients_email_list,
		subject    => 'Active Users with DBA Role',
		message    => v_email_body,
		mime_type  => 'text/html'
	);
end;
/



--------------------------------------------------------------------------------
--#4: Create, test, and verify job (one-time step)
--------------------------------------------------------------------------------
begin
	dbms_scheduler.create_job
	(
		job_name        => 'EMAIL_ACTIVE_DBA_USERS_JOB',
		job_type        => 'PLSQL_BLOCK',
		start_date      => trunc(systimestamp) + interval '5' minute,
		enabled         => true,
		repeat_interval => 'FREQ=WEEKLY',
		job_action      => 'begin email_active_dba_users; end;'
	);
end;
/

/*
--Force the job to run, for testing.
begin
	dbms_scheduler.run_job('EMAIL_ACTIVE_DBA_USERS_JOB');
end;
/
*/

--Check job status.
select * from dba_scheduler_job_run_details where job_name = 'EMAIL_ACTIVE_DBA_USERS_JOB' and log_date > sysdate - 10 order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'EMAIL_ACTIVE_DBA_USERS_JOB';

