--Add some final SYS objects.
--The sys scripts cannot be combined because triggers cannot be created on tables that don't exist.
prompt Installing final SYS components for Method5...

create or replace procedure sys.m5_protect_config_tables
/*
	Purpose: Protect impotant Method5 configuration tables from changes.
		Send an email when the table changes.
		Raise an exception if the user is not a Method5 administrator.
*/
(
	p_table_name    varchar2
) is
	v_sender_address varchar2(4000);
	v_recipients varchar2(4000);
	v_count number;
begin
	--Get email configuration information.
	select
		min(email_address) sender_address
		,listagg(email_address, ',') within group (order by email_address) recipients
	into v_sender_address, v_recipients
	from method5.m5_user
	where is_m5_admin = 'Yes'
		and email_address is not null;

	--Try to send an email if there is a configuration change.
	begin
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
	--I hate to swallow exceptions but in this case it's more important to raise an exception
	--about invalid privileges than about the email.
	exception when others then null;
	end;

	--Check if the user is an admin.
	select count(*) valid_user_count
	into v_count
	from method5.m5_user
	where is_m5_admin = 'Yes'
		and trim(lower(oracle_username)) = lower(sys_context('userenv', 'session_user'))
		and
		(
			lower(os_username) = lower(sys_context('userenv', 'os_user'))
			or
			os_username is null
		);

	--Raise error if the user is not allowed.
	if v_count = 0 then
		raise_application_error(-20000, 'You do not have permission to modify the table '||p_table_name||'.'||chr(10)||
			'Only Method5 administrators can modify that table.'||chr(10)||
			'Contact your current administrator if you need access.');
	end if;
end m5_protect_config_tables;
/

--Create triggers to protect Method5 tables.
begin
	for tables in
	(
		select 'M5_CONFIG'      table_name from dual union all
		select 'M5_DATABASE'    table_name from dual union all
		select 'M5_ROLE'        table_name from dual union all
		select 'M5_ROLE_PRIV'   table_name from dual union all
		select 'M5_USER'        table_name from dual union all
		select 'M5_USER_ROLE'   table_name from dual
		order by 1
	) loop
		execute immediate replace(q'[
			create or replace trigger sys.#TABLE_NAME#_user_trg
			before update or delete or insert on method5.#TABLE_NAME#
			begin
				sys.m5_protect_config_tables
				(
					p_table_name    => '#TABLE_NAME#'
				);
			end;
		]',
		'#TABLE_NAME#', tables.table_name);
	end loop;
end;
/

--Quick check that Method5 schema is valid.
--If the top-level objects are valid then everything else should be OK.
set serveroutput on;
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
		dbms_output.put_line('ERROR - Installation failed, this object is invalid: '||objects.object_name);
	end loop;

	--Print message if success.
	if v_count = 0 then
		dbms_output.put_line('SUCCESS - All objects look OK.  Method5 installed correctly.');
	end if;
end;
/
