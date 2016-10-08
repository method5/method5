create or replace package method5.method5_test authid current_user is
/*
== Purpose ==

Integration tests for Method5.


== Example ==

--If the package was recompiled it may be necessary to clear the session state first.
begin
	dbms_session.reset_package;
end;

begin
	method5.method5_test.run(
		p_database_name_1 =>   'devdb01',
		p_database_name_2 =>   'devdb02',
		p_other_schema_name => 'SOMEONE_ELSE');
end;

*/

--Run the unit tests and display the results in dbms output.
--	P_DATABASE_NAME_1 - The name of a database to use for testing.
--	P_DATABASE_NAME_2 - The name of a database to use for testing.
--	P_OTHER_SCHEMA_NAME - The name of a schema to put some temporary tables in to test
--		the feature where P_TABLE_NAME is set to another user's schema.
procedure run(
	p_database_name_1   in varchar2,
	p_database_name_2   in varchar2,
	p_other_schema_name in varchar2);

end;
/
create or replace package body method5.method5_test is

--Global counters and variables.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;
type string_table is table of varchar2(32767);
g_report string_table := string_table();

--------------------------------------------------------------------------------
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		g_report.extend; g_report(g_report.count) := 'Failure with: '||p_test;
		g_report.extend; g_report(g_report.count) := 'Expected: '||p_expected;
		g_report.extend; g_report(g_report.count) := 'Actual  : '||p_actual;
	end if;
end assert_equals;


--------------------------------------------------------------------------------
--Get a custom table name.
--
--By using the same M5_TEMP prefix as automatic tables there will be no need for
--a tear down.  Those tables are automatically dropped by a nightly job.
function get_custom_temp_table_name return varchar2 is
	v_table_name varchar2(128);
begin
	execute immediate q'[select 'M5_TEMP_'||round(dbms_random.value*10000000000) from dual]'
	into v_table_name;

	return v_table_name;
end get_custom_temp_table_name;


--------------------------------------------------------------------------------
procedure test_function(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'Function 1';
		v_expected_results := p_database_name_1||'-X';

		execute immediate replace(q'[
			select database_name||'-'||dummy
			from table(m5('select * from dual', '#DATABASE_1#'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_function;


--------------------------------------------------------------------------------
procedure test_procedure(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'Procedure 1';
		v_expected_results := p_database_name_1||'-Commit complete.';

		execute immediate replace(q'[
			begin
				m5_proc('commit', '#DATABASE_1#', p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1);

		execute immediate q'[select database_name||'-'||result from m5_results]'
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_procedure;


--------------------------------------------------------------------------------
procedure test_m5_views(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		--Results.
		v_test_name := 'Views - results (PL/SQL with no dbms_output returns NULL)';
		v_expected_results := p_database_name_1||'-';

		execute immediate replace(q'[
			begin
				m5_proc('begin null; end;', '#DATABASE_1#', p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1);

		execute immediate q'[select database_name||'-'||result from m5_results]'
		into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		--Metadata.
		v_test_name := 'Views - metdata';
		v_expected_results :=
			to_char(sysdate, 'YYYY-MM-DD')||'-'||
			to_char(sysdate, 'YYYY-MM-DD')||'-'||
			user||'-'||
			'Yes'||'-'||
			1||'-'||
			1||'-'||
			0||'-'||
			'begin null; end;'||'-'||
			p_database_name_1;

		execute immediate
		q'[
			select
				to_char(date_started, 'YYYY-MM-DD') ||'-'||
				to_char(date_updated, 'YYYY-MM-DD') ||'-'||
				username ||'-'||
				is_complete ||'-'||
				targets_expected ||'-'||
				targets_completed ||'-'||
				targets_with_errors ||'-'||
				to_char(code) ||'-'||
				to_char(targets)
			from m5_metadata		
		]' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		--Errors.
		v_test_name := 'Views - errors';
		v_expected_results := '0';
		execute immediate q'[select count(*) from m5_errors]'
		into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_m5_views;


--------------------------------------------------------------------------------
procedure test_p_code(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(32767);
	v_actual_results varchar2(32767);
	v_table_name varchar2(128);
begin
	--Note: Some other types of P_CODE were implicitly tested above.

	begin
		v_test_name := 'P_CODE 1 - DBMS_OUTPUT';
		v_expected_results := p_database_name_1||'-DBMS_OUTPUT test';

		execute immediate replace(q'[
			select database_name||'-'||result
			from table(m5(q'!begin dbms_output.put_line('DBMS_OUTPUT test'); end;!', '#DATABASE_1#'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'P_CODE 2 - DBMS_OUTPUT Over 4000';
		v_expected_results := p_database_name_1||'-'||lpad('A', 4001, 'A');

		execute immediate replace(q'[
			select database_name||'-'||result
			from table(m5(q'!begin dbms_output.put_line(lpad('A', 4001, 'A')); end;!', '#DATABASE_1#'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;


	begin
		--Create a table that only exists on your schema in another database.
		v_test_name := 'P_CODE 3 - Table that only exists in another database.';
		v_expected_results := p_database_name_1||'-2';

		v_table_name := get_custom_temp_table_name;
		execute immediate replace(replace(replace(q'[
			begin
				dbms_utility.exec_ddl_statement@m5_#DATABASE_1#
				('
					create table #OWNER#.#TABLE_NAME# as select * from (select 1+1 from dual)
				');
			end;
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#OWNER#', sys_context('userenv', 'current_user'))
		, '#TABLE_NAME#', v_table_name);

		execute immediate replace(replace(replace(q'[
			select database_name||'-'||"1+1"
			from table(m5(q'!select * from #OWNER#.#TABLE_NAME#!', '#DATABASE_1#'))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#OWNER#', sys_context('userenv', 'current_user'))
		, '#TABLE_NAME#', v_table_name)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_p_code;


--------------------------------------------------------------------------------
procedure test_p_targets(p_database_name_1 in varchar2, p_database_name_2 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	--No targets.
	begin
		v_test_name := 'P_TARGETS - No targets';
		v_expected_results := '0';

		execute immediate q'[
			begin
				m5_proc('insert into some_table values(1234);', 'Not a real database name', p_asynchronous => false);
			end;
		]';

		execute immediate q'[select count(*) from m5_results]'
		into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	--SELECT query.
	begin
		v_test_name := 'P_TARGETS - SELECT query';
		v_expected_results := '1';
		v_expected_results := p_database_name_1||'-Rollback complete.';

		execute immediate replace(q'[
			select database_name||'-'||result
			from table(m5('rollback', q'!select database_name from method5.m5_database where lower(database_name) = '#DATABASE_1#'!'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	--Comma-separated list.
	begin
		v_test_name := 'P_TARGETS - comma separated list';
		v_expected_results := '2';

		execute immediate replace(replace(q'[
			select count(*)
			from table(m5('rollback', '#DATABASE_1#,#DATABASE_2#'))
		]', '#DATABASE_1#', p_database_name_1), '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	--Pattern matching.
	begin
		v_test_name := 'P_TARGETS - pattern matching';
		v_expected_results := '1 or more';

		execute immediate replace(replace(q'[
			select count(*)
			from table(m5('rollback', substr('#DATABASE_1#', 1, length('#DATABASE_1#')-1)||'_'))
		]', '#DATABASE_1#', p_database_name_1), '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		--The pattern match should match at least one database, but there may be more.
		if to_number(v_actual_results) >= 1 then
			v_actual_results := '1 or more';
		end if;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_p_targets;


--------------------------------------------------------------------------------
procedure test_p_table_name(p_database_name_1 in varchar2, p_table_owner in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
	v_table_name varchar2(128);
begin
	begin
		v_table_name := get_custom_temp_table_name;
		v_test_name := 'P_TABLE_NAME - Results';
		v_expected_results := '1';

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate 'select count(*) from '||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		v_test_name := 'P_TABLE_NAME - Metadata';
		v_expected_results := '1';
		execute immediate 'select count(*) from '||v_table_name||'_meta' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		v_test_name := 'P_TABLE_NAME - Errors';
		v_expected_results := '0';
		execute immediate 'select count(*) from '||v_table_name||'_err' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_table_name := get_custom_temp_table_name;
		v_test_name := 'P_TABLE_NAME - Other Schema Results';
		v_expected_results := '1';

		execute immediate replace(replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_OWNER#.#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#TABLE_OWNER#', p_table_owner)
		, '#TABLE_NAME#', v_table_name);

		execute immediate 'select count(*) from '||p_table_owner||'.'||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		v_test_name := 'P_TABLE_NAME - Other Schema Metadata';
		v_expected_results := '1';
		execute immediate 'select count(*) from '||p_table_owner||'.'||v_table_name||'_meta' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		v_test_name := 'P_TABLE_NAME - Other Schema Errors';
		v_expected_results := '0';
		execute immediate 'select count(*) from '||p_table_owner||'.'||v_table_name||'_err' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_p_table_name;


--------------------------------------------------------------------------------
procedure test_p_asynchronous(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'P_ASYNCHRONOUS 1';
		v_expected_results := '0';

		execute immediate replace(q'[
			begin
				m5_proc(
					p_code => 'begin dbms_lock.sleep(5); end;',
					p_targets => '#DATABASE_1#',
					p_asynchronous => true);
			end;
		]', '#DATABASE_1#', p_database_name_1);

		--The view exists but there will be no data yet.
		execute immediate 'select count(*) from m5_results' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_p_asynchronous;


--------------------------------------------------------------------------------
procedure test_p_table_exists_action(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
	v_table_name varchar2(128);
	v_error_table_exists exception;
	pragma exception_init(v_error_table_exists, -20017);
begin
	begin
		v_table_name := get_custom_temp_table_name;

		--#1: Test drop by running it twice.
		v_test_name := 'P_TABLE_EXISTS_ACTION - DROP';
		v_expected_results := p_database_name_1||'-X';
		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_table_exists_action => 'DROP',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		--Must wait between runs with same table name, to avoid primary key violation.
		execute immediate 'begin dbms_lock.sleep(1); end;';

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_table_exists_action => 'DROP',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate q'[select database_name||'-'||dummy from ]'||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		--#2: Test DELETE with similar code.
		v_test_name := 'P_TABLE_EXISTS_ACTION - DELETE';
		v_expected_results := p_database_name_1||'-X';
		execute immediate 'begin dbms_lock.sleep(1); end;';

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_table_exists_action => 'DELETE',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate q'[select database_name||'-'||dummy from ]'||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		--#3: Error
		v_test_name := 'P_TABLE_EXISTS_ACTION - ERROR';
		v_expected_results := 'Exception caught';
		execute immediate 'begin dbms_lock.sleep(1); end;';

		begin
			execute immediate replace(replace(q'[
				begin
					m5_proc(
						p_code => 'select * from dual',
						p_targets => '#DATABASE_1#',
						p_asynchronous => false,
						p_table_name => '#TABLE_NAME#');
				end;
			]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

			assert_equals(v_test_name, v_expected_results, 'No exception caught.');
		exception when v_error_table_exists then
			assert_equals(v_test_name, v_expected_results, 'Exception caught');
		end;

		--#4: Append 1 - results
		v_test_name := 'P_TABLE_EXISTS_ACTION - APPEND 1';
		v_expected_results := p_database_name_1||'-X,'||p_database_name_1||'-X';
		execute immediate 'begin dbms_lock.sleep(1); end;';

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_table_exists_action => 'APPEND',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate q'[select listagg(database_name||'-'||dummy, ',') within group (order by 1) from ]'||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

		--#4: Append 2 - metadata
		execute immediate 'begin dbms_lock.sleep(1); end;';
		v_test_name := 'P_TABLE_EXISTS_ACTION - APPEND 2';
		v_expected_results := '2';
		execute immediate q'[select count(*) from ]'||v_table_name || '_meta' into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_p_table_exists_action;


--------------------------------------------------------------------------------
procedure test_audit(p_database_name_1 in varchar2, p_database_name_2 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
	v_table_name varchar2(128);
begin

	begin
		v_table_name := get_custom_temp_table_name;
		v_test_name := 'Audit 1 - From Procedure';
		v_expected_results := '2-2-0-2';

		execute immediate replace(replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from dual',
					p_targets => '#DATABASE_1#,#DATABASE_2#',
					p_table_name => '#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#DATABASE_2#', p_database_name_2), '#TABLE_NAME#', v_table_name);

		execute immediate q'[
			select targets_expected||'-'||targets_completed||'-'||targets_with_errors||'-'||num_rows
			from method5.m5_audit
			where table_name = :v_table_name
		]'
		into v_actual_results
		using v_table_name;

		assert_equals(v_test_name, v_expected_results, v_actual_results);

	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_table_name := get_custom_temp_table_name;
		v_test_name := 'Audit 1 - From Function';
		v_expected_results := '1-1-0-1';

		execute immediate replace(replace(q'[
			select database_name||'-'||dummy
			from table(m5('select * /*#TABLE_NAME#*/ from dual', '#DATABASE_1#'))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#TABLE_NAME#', v_table_name)
		into v_actual_results;

		execute immediate replace(q'[
			select targets_expected||'-'||targets_completed||'-'||targets_with_errors||'-'||num_rows
			from method5.m5_audit
			where create_date > sysdate - 1
				and to_char(substr(code, 1, 2000)) = 'select * /*#TABLE_NAME#*/ from dual'
		]'
		, '#TABLE_NAME#', v_table_name)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

end test_audit;


--------------------------------------------------------------------------------
procedure run(
	p_database_name_1   in varchar2,
	p_database_name_2   in varchar2,
	p_other_schema_name in varchar2
) is
	v_database_name_1 varchar2(100) := lower(trim(p_database_name_1));
	v_database_name_2 varchar2(100) := lower(trim(p_database_name_2));
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	g_report.extend; g_report(g_report.count) := null;
	g_report.extend; g_report(g_report.count) := '----------------------------------------';
	g_report.extend; g_report(g_report.count) := 'Method5 Test Summary';
	g_report.extend; g_report(g_report.count) := '----------------------------------------';

	--Run the tests.
	dbms_output.disable;
	test_function(v_database_name_1);
	test_procedure(v_database_name_1);
	test_m5_views(v_database_name_1);
	test_p_code(v_database_name_1);
	test_p_targets(v_database_name_1, v_database_name_2);
	test_p_table_name(v_database_name_1, p_other_schema_name);
	test_p_asynchronous(v_database_name_1);
	test_p_table_exists_action(v_database_name_1);
	test_audit(v_database_name_1, v_database_name_2);

	--Re-enable DBMS_OUTPUT.
	--It had to be suppressed because Method5 prints some information that
	--won't help us during testing.
	dbms_output.enable;

	for i in 1 .. g_report.count loop
		dbms_output.put_line(g_report(i));
	end loop;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line('
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/');
	else
		dbms_output.put_line('
  ______      _____ _
 |  ____/\   |_   _| |
 | |__ /  \    | | | |
 |  __/ /\ \   | | | |
 | | / ____ \ _| |_| |____
 |_|/_/    \_\_____|______|');
	end if;
end run;

end;
/
