create or replace package method5.method5_test authid current_user is

/*******************************************************************************
GET_RUN_SCRIPT

Purpose:
	Get a SQL*Plus-like script to run the tests.  The script is necessary because
	full testing requires creating and loggiong on as different users.  This is
	probably the only public function you need to directly worry about for testing.

Inputs:
	p_database_name_1 - A database name.
	p_database_name_2 - Another database name.
	p_other_schema_name - A schema to test writing and reading from a different schema.
	p_test_run_as_sys - Should RUN_AS_SYS be tested?  "Yes" or "No".
	p_test_shell_script - Should shell scripts be tested?  "Yes" or "No".
	p_tns_alias - TNS alias of your management database, to print as part of the script.

Outputs:
	Some commands to setup the test, and command-line SQL*Plus scripts to run tests.
	If it works you'll see multiple "PASS" messages.  You should not see any "FAIL"s.

Side-Effects:
	Testing created and then drops Method5 users.  This may lead to emails going out
	to administrators, warning them that configuration tables were changed.

Example:

	--Example for running with default M5_DATABASE databases, with a simple Windows
	--install (where shell scripts should not be used since they don't run on Windows).
	select method5.method5_admin.get_run_script(
		p_database_name_1 => 'devdb1',
		p_database_name_2 => 'devdb2',
		p_other_schema_name => '????????',
		p_test_run_as_sys => "Yes",
		p_test_shell_script => "No",
		p_tns_alias => 'orcl')
	from dual;

*******************************************************************************/
function get_run_script(
	p_database_name_1   varchar2,
	p_database_name_2   varchar2,
	p_other_schema_name varchar2,
	p_test_run_as_sys   varchar2,
	p_test_shell_script varchar2,
	p_tns_alias         varchar2
) return varchar2;




--Although public, you probably don't need to worry about anything below.








--Procedures to help with GET_RUN_SCRIPT.
procedure create_test_users(p_database_name_1 varchar2, p_database_name_2 varchar2);
procedure drop_test_users_if_exist;

--Globals to select which test suites to run.
c_test_function                constant number := power(2, 1);
c_test_procedure               constant number := power(2, 2);
c_test_m5_views                constant number := power(2, 3);
c_test_p_code                  constant number := power(2, 4);
c_test_p_targets               constant number := power(2, 5);
c_test_p_table_name            constant number := power(2, 6);
c_test_p_asynchronous          constant number := power(2, 7);
c_test_p_table_exists_action   constant number := power(2, 8);
c_test_audit                   constant number := power(2, 9);
c_test_long                    constant number := power(2, 10);
c_test_version_star            constant number := power(2, 11);
c_test_get_target_tab_from_tar constant number := power(2, 12);

--These tests should always work.
c_base_tests                   constant number :=
	c_test_function+c_test_procedure+c_test_m5_views+c_test_p_code+c_test_p_targets+
	c_test_p_table_name+c_test_p_asynchronous+c_test_p_table_exists_action+c_test_audit+
	c_test_long+c_test_version_star+c_test_get_target_tab_from_tar;

--These tests may not work in some environments if SYS or shell script feature is disable.
c_test_run_as_sys              constant number := power(2, 13);
c_test_shell_script            constant number := power(2, 14);

c_all_tests                    constant number := c_base_tests+c_test_run_as_sys+c_test_shell_script;

--Test sandbox privileges, allowed and default targets, and config table protection.
c_sandbox_and_targets       constant number := power(2,15);
c_test_cannot_change_config constant number := power(2,16);



/*******************************************************************************
Purpose:
	Detailed integration tests for Method5.

Parameters:
	P_DATABASE_NAME_1 - The name of a database to use for testing.
	P_DATABASE_NAME_2 - The name of a database to use for testing.
		To test the version star feature, the two databases should be on different versions of Oracle
	P_OTHER_SCHEMA_NAME - The name of a schema to put some temporary tables in to test
		the feature where P_TABLE_NAME is set to another user's schema.
	P_TEST_RUN_AS_SYS - Should the RUN_AS_SYS feature be tested.  Defaults to
		TRUE, set it to FALSE if you did not install the RUN_AS_SYS feature.
	P_TEST_SHELLS_CRIPT - Should shell scripts be tested.  Defaults to true, set
		it to FALSE if you did not install the RUN_AS_SYS feature of if you are
		not testing on Linux or Unix.

Example:

	--If the package was recompiled it may be necessary to clear the session state first.
	begin
		dbms_session.reset_package;
	end;

	begin
		method5.method5_test.run(
			p_database_name_1 =>   'devdb1',
			p_database_name_2 =>   'devdb2',
			p_other_schema_name => 'SOMEONE_ELSE');
	end;
*******************************************************************************/
procedure run(
	p_database_name_1   in varchar2,
	p_database_name_2   in varchar2,
	p_other_schema_name in varchar2,
	p_tests             in number default c_all_tests);
end;
/
create or replace package body method5.method5_test is

--Global counters and variables.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;
type string_table is table of varchar2(32767);
g_report string_table;


--------------------------------------------------------------------------------
function get_version_warning(p_database_name_1 varchar2, p_database_name_2 varchar2) return varchar2 is
	v_version_1 varchar2(4000);
	v_version_2 varchar2(4000);
begin
	--Get the two versions.
	select
		max(case when lower(database_name) = lower(p_database_name_1) then nvl(target_version, 'Not available.') end) version_1,
		max(case when lower(database_name) = lower(p_database_name_2) then nvl(target_version, 'Not available.') end) version_2
	into v_version_1, v_version_2
	from m5_database where lower(database_name) in (lower(p_database_name_1), lower(p_database_name_2));

	--Return results of the comparison.
	if v_version_1 = 'Not available' then
		return 'WARNING: Could not find version information for '||p_database_name_1||
			' in M5_DATABASE.  Using different versions will produce more robust tests.'||chr(10); 
	elsif v_version_2 = 'Not available' then
		return 'WARNING: Could not find version information for '||p_database_name_2||
			' in M5_DATABASE.  Using different versions will produce more robust tests.'||chr(10); 
	elsif v_version_1 = v_version_2 then
		return 'WARNING: '||p_database_name_1||' and '||p_database_name_2||' have the same '||
			'version.  Using different versions will produce more robust tests.'||chr(10);
	else
		return null;
	end if;
end get_version_warning;


--------------------------------------------------------------------------------
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or (p_expected is null and p_actual is null) then
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
		v_test_name := 'P_CODE 3 - Table that only exists in another database.';
		v_expected_results := p_database_name_1||'-2';

		--Create a table that only exists on your schema in another database.
		v_table_name := get_custom_temp_table_name;
		execute immediate replace(replace(replace(q'[
			select 1
			from table(m5('create table #OWNER#.#TABLE_NAME# as select * from (select 1+1 from dual) ', '#DATABASE_1#'))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#OWNER#', sys_context('userenv', 'current_user'))
		, '#TABLE_NAME#', v_table_name)
		into v_actual_results;

		--Query that table.
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

	begin
		v_test_name := 'P_CODE 4 - SQL*Plus commands generate a special error message.';
		v_expected_results := 'Exception caught: ORA-20004: The code is not a valid SQL or PL/SQL statement.  '||
			'It looks like a SQL*Plus command and Method5 does not yet run SQL*Plus.  '||
			'Try wrapping the script in a PL/SQL block, like this: begin <statements> end;';

		execute immediate replace(q'[
			begin
				m5_proc('execute some_procedure();', '#DATABASE_1#', p_asynchronous => false);
			end;
		]'
		, '#DATABASE_1#', p_database_name_1);

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

	begin
		v_test_name := 'P_CODE 5 - DBMS_OUTPUT from CALL';
		v_expected_results := p_database_name_1||'-CALL DBMS_OUTPUT test';

		--Create a temporary procedure that only exists on your schema in another database.
		execute immediate replace(replace(q'[
			select 1
			from table(m5(q'!
				create or replace procedure #OWNER#.temp_proc_for_m5_testing is
				begin
					dbms_output.put_line('CALL DBMS_OUTPUT test');
				end;!',
				'#DATABASE_1#'
			))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#OWNER#', sys_context('userenv', 'current_user'))
		into v_actual_results;

		execute immediate replace(replace(q'[
			select database_name||'-'||result
			from table(m5(q'!call #OWNER#.temp_proc_for_m5_testing()!', '#DATABASE_1#'))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#OWNER#', sys_context('userenv', 'current_user'))
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		--TODO: Perhaps change this to work with 128 characters for 12.2?
		v_test_name := 'P_CODE 6 - Column name larger than 30 characters';
		v_expected_results := '66';
		v_table_name := get_custom_temp_table_name;

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select 1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1 from dual',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate 'select "1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+" from '||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		--TODO: Perhaps change this to work with 128 characters for 12.2?
		v_test_name := 'P_CODE 7 - Column name larger than 30 characters and a LONG.';
		v_expected_results := '66-0 ';
		v_table_name := get_custom_temp_table_name;

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => q'!
						select
							1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1
							,data_default
						from dba_tab_columns
						where owner = 'SYS'
							and table_name = 'JOB$'
							and column_name = 'FLAG'
					!',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

		execute immediate q'[select "1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+"||'-'||data_default from ]'||v_table_name into v_actual_results;
		assert_equals(v_test_name, v_expected_results, v_actual_results);

	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'Error when selecting from table that does not exist.';
		v_expected_results :=
			'Exception caught: ORA-20030: The SELECT statement did not run.'||chr(10)||
			'Please ensure the syntax is valid, all the objects exist, and you have access to all the objects.'||chr(10)||
			'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
			'The SELECT statement raised this error:'||chr(10)||
			'ORA-00942: table or view does not exist';

		execute immediate replace(q'[
			select count(*)
			from table(m5('select count(*) from "This Does Not Exist..."', '#DATABASE_1#'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		--Use substr because we only want to test the text part of the error.
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||substr(sqlerrm, 1, 320));
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
		v_expected_results := 'Exception caught: -20404';

		execute immediate q'[
			begin
				m5_proc('insert into some_table values(1234);', 'Not a real database name', p_asynchronous => false);
			end;
		]';

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlcode);
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
		execute immediate 'begin method5.m5_sleep(1); end;';

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
		execute immediate 'begin method5.m5_sleep(1); end;';

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
		execute immediate 'begin method5.m5_sleep(1); end;';

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
		execute immediate 'begin method5.m5_sleep(1); end;';

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
		execute immediate 'begin method5.m5_sleep(1); end;';
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
		v_test_name := 'Audit 1 - From Procedure';
		v_table_name := get_custom_temp_table_name;
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
		v_test_name := 'Audit 1 - From Function';
		v_table_name := get_custom_temp_table_name;
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
procedure test_long(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'LONG - Convert LONG to CLOB';
		--Big assumption!  This column default is not documented.
		--I'm just guessing it's the same between versions.
		--If it fails on some versions, any other default will work.
		v_expected_results := '0 ';

		execute immediate replace(q'[
			select data_default
			from table(m5(
				q'!
					select data_default
					from dba_tab_columns
					where owner = 'SYS'
						and table_name = 'JOB$'
						and column_name = 'FLAG'
				!',
				'#DATABASE_1#'))
		]'
		, '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_long;


--------------------------------------------------------------------------------
procedure test_version_star(p_database_name_1 in varchar2, p_database_name_2 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
	v_table_name varchar2(128);
begin
	begin
		v_test_name := 'Version star 1 - only one version.';
		v_table_name := get_custom_temp_table_name;
		v_expected_results := '1-1-0-1';

		execute immediate replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select ** from v$session where rownum = 1',
					p_targets => '#DATABASE_1#',
					p_table_name => '#TABLE_NAME#',
					p_asynchronous => false);
			end;
		]', '#DATABASE_1#', p_database_name_1), '#TABLE_NAME#', v_table_name);

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
		v_test_name := 'Version star 2 - two different versions.';
		v_table_name := get_custom_temp_table_name;
		v_expected_results := '2-2-0-2';

		execute immediate replace(replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select ** from v$session where rownum = 1',
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
		v_test_name := 'Version star 3 - two different versions with weird column names and nested **.';
		v_table_name := get_custom_temp_table_name;
		v_expected_results := '2-2-0-2';

		execute immediate replace(replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select * from (select ** from (select v$session.*, 1+1 from v$session where rownum = 1)) ',
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
		v_test_name := 'Version star 4 - LONG.';
		v_table_name := get_custom_temp_table_name;
		v_expected_results := '2-2-0-2';

		execute immediate replace(replace(replace(q'[
			begin
				m5_proc(
					p_code => 'select ** from dba_tab_columns where rownum <= 1',
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
end test_version_star;


--------------------------------------------------------------------------------
procedure test_get_target_tab_from_targe(v_database_name_1 in varchar2, v_database_name_2 varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'Get Target Table from Target String 1';
		v_expected_results :=
			least(v_database_name_1, v_database_name_2) || '-' ||
			greatest(v_database_name_1, v_database_name_2);

		select listagg(column_value, '-') within group (order by column_value)
		into v_actual_results
		from table(method5.m5_pkg.get_target_tab_from_target_str(v_database_name_1||','||v_database_name_2));

		assert_equals(v_test_name, v_expected_results, v_actual_results);

	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'Target SELECT string only returns valid targets.';
		v_expected_results := null;

		select max(column_value)
		into v_actual_results
		from table(method5.m5_pkg.get_target_tab_from_target_str(q'[select 'this_is_a_fake_target_does_not_exist' from dual]'));

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

end test_get_target_tab_from_targe;


--------------------------------------------------------------------------------
procedure test_run_as_sys(p_database_name_1 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'SYS select - table that only SYS can read';
		v_expected_results := '1';

		execute immediate replace(q'[
			select a
			from table(m5('select max(1) a from sys.link$', '#DATABASE_1#', ' YeS '))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	declare
		v_database_name varchar2(128);
	begin
		v_test_name := 'SYS select with name over 128 bytes, to test GET_COLUMN_METADATA over link';
		v_expected_results := '65';

		execute immediate replace(q'[
			select *
			from table(m5(
				'select 1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1+1 from dual'
				,'#DATABASE_1#'
				,'yes'
			))
		]', '#DATABASE_1#', p_database_name_1)
		into v_database_name, v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'SYS CALL';
		v_expected_results := 'CALL test';

		execute immediate replace(q'[
			select result
			from table(m5('call dbms_output.put_line(''CALL test'') ', '#DATABASE_1#', 'YES'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'SYS DML/DDL';
		v_expected_results := '0 rows deleted.';

		execute immediate replace(q'[
			select result
			from table(m5('delete from sys.user_history$ where 1 = 0;', '#DATABASE_1#', 'YES'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'SYS PL/SQL';
		v_expected_results := 'PL/SQL test';

		execute immediate replace(q'[
			select result
			from table(m5('begin dbms_output.put_line(''PL/SQL test''); end;', '#DATABASE_1#', 'YES'))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_run_as_sys;


--------------------------------------------------------------------------------
procedure test_shell_script(p_database_name_1 in varchar2, p_database_name_2 in varchar2) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'Shell script 1 - test stdout and stderr write in order';
		v_expected_results := '1,2,3-stdout1,/test/stderr/: No such file or directory,stdout2';

		execute immediate replace(
		q'[
			select
				listagg(line_number, ',') within group (order by line_number)
				||'-'||
				listagg(output, ',') within group (order by line_number) line_numbers_and_output
			from table(m5(
				'#!/bin/sh
				echo stdout1
				ls /test/stderr/
				echo stdout2
				'			
				,'#DATABASE_1#'
			))
		]', '#DATABASE_1#', p_database_name_1)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'Shell script 2 - no-op shell script works but returns nothing';
		v_expected_results := '';

		execute immediate replace(replace(
		q'[
			select max(output)
			from table(m5(
				'#!/bin/sh'
				,'#DATABASE_1#,#DATABASE_2#'
			))
		]'
		, '#DATABASE_1#', p_database_name_1)
		, '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;
end test_shell_script;


--------------------------------------------------------------------------------
procedure test_sandbox_and_targets(
	p_database_name_2 varchar2,
	p_other_schema_name	varchar2
) is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
	v_actual_results varchar2(4000);
begin
	begin
		v_test_name := 'Defaults and allowed targets do not match and generate an error.';
		v_expected_results :=
			'Exception caught: ORA-20035: You do not have access to any of targets requested.'||chr(10)||
			'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
			'Contact your Method5 administrator to change your access.';

		execute immediate q'[
			begin
				m5_proc('select * from dual', p_asynchronous => false);
			end;
		]';

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

	begin
		v_test_name := 'User can select from the allowed target, if explicitly referenced.';
		v_expected_results := '1';

		execute immediate replace(q'[
			select count(*)
			from table(m5('select count(*) from dual', '#DATABASE_2#'))
		]', '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'User cannot create a view.';
		v_expected_results := '1';

		execute immediate replace(q'[
			select count(*)
			from table(m5('create or replace view test_vw as select * from dual', '#DATABASE_2#'))
		]', '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		execute immediate q'[
			select count(*)
			from m5_test_sandbox_and_targets.m5_errors
			where error_stack_and_backtrace like '%ORA-01031: insufficient privileges%'
		]'
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'User cannot select from a DBA table.';
		v_expected_results :=
			'Exception caught: ORA-20030: The SELECT statement did not run.'||chr(10)||
			'Please ensure the syntax is valid, all the objects exist, and you have access to all the objects.'||chr(10)||
			'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
			'The SELECT statement raised this error:'||chr(10)||
			'ORA-00942: table or view does not exist';
		execute immediate replace(q'[
			select count(*)
			from table(m5('select count(*) from dba_users', '#DATABASE_2#'))
		]', '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		--Use substr because we only want to test the text part of the error.
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||substr(sqlerrm, 1, 320));
	end;

	begin
		v_test_name := 'Users can select from METHOD5.M5_MY_ACCESS_VW.';
		v_expected_results := '1';

		execute immediate 'select count(*) from method5.m5_my_access_vw where rownum = 1'
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'Simple PL/SQL works.';
		v_expected_results := 'TEST OUTPUT';

		execute immediate replace(q'[
			select to_char(result)
			from table(m5('begin dbms_output.put_line(''TEST OUTPUT''); end;', '#DATABASE_2#'))
		]', '#DATABASE_2#', p_database_name_2)
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'PL/SQL that requires privileges does not work.';
		v_expected_results := '1';

		execute immediate replace(q'[
			begin
				m5_proc(
					p_code => 'declare v_count number; begin select count(*) into v_count from dba_users; end;',
					p_targets => '#DATABASE_2#',
					p_table_name => 'test_no_privs',
					p_table_exists_action => 'drop',
					p_asynchronous => false,
					p_run_as_sys => false
				);
			end;
		]'
		, '#DATABASE_2#', p_database_name_2);

		execute immediate q'[
			select count(*)
			from m5_test_sandbox_and_targets.test_no_privs_err
			where error_stack_and_backtrace like '%PL/SQL: ORA-00942: table or view does not exist%'
		]'
		into v_actual_results;

		assert_equals(v_test_name, v_expected_results, v_actual_results);
	exception when others then
		assert_equals(v_test_name, v_expected_results,
			sys.dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
	end;

	begin
		v_test_name := 'No privileges to run as SYS.';
		v_expected_results :=
			'Exception caught: ORA-20035: You do not have access to any of targets requested.'||chr(10)||
			'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
			'Contact your Method5 administrator to change your access.';

		execute immediate replace(q'[
			begin
				m5_proc('select * from dual', '#DATABASE_2#', p_run_as_sys => true);
			end;
		]'
		, '#DATABASE_2#', p_database_name_2);

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

	begin
		v_test_name := 'No privileges to run as SYS.';
		v_expected_results :=
			'Exception caught: ORA-20035: You do not have access to any of targets requested.'||chr(10)||
			'Run this query to check your Method5 roles and privileges: select * from method5.m5_my_access_vw;'||chr(10)||
			'Contact your Method5 administrator to change your access.';

		execute immediate replace(q'[
			begin
				m5_proc('#!/bin/sh
					echo test',
					'#DATABASE_2#');
			end;
		]'
		, '#DATABASE_2#', p_database_name_2);

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

	begin
		v_test_name := 'No privileges to run SELECT in P_TARGETS.';
		v_expected_results :=
			'Exception caught: ORA-20036: You are not authorized to run SQL statements in P_TARGETS.'||chr(10)||
			'Contact your Method5 administrator to change your access.';

		execute immediate q'[
			begin
				m5_proc('select * from dual', 'select ''devdb2'' from dual');
			end;
		]';

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

	begin
		v_test_name := 'No privileges to create tables in other schemas.';
		v_expected_results :=
			'Exception caught: ORA-20037: You are not authorized to create tables in other schemas.'||chr(10)||
			'Contact your Method5 administrator to change your access.';

		execute immediate replace(q'[
			begin
				m5_proc('select * from dual', p_table_name => '#OTHER_SCHEMA_NAME#.table_that_should_not_exist');
			end;
		]', '#OTHER_SCHEMA_NAME#', p_other_schema_name);

		assert_equals(v_test_name, v_expected_results, 'No exception caught.');
	exception when others then
		assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
	end;

end test_sandbox_and_targets;


--------------------------------------------------------------------------------
procedure test_cannot_change_config is
	v_test_name varchar2(100);
	v_expected_results varchar2(4000);
begin
	for tables in
	(
		select 'M5_CONFIG'    table_name from dual union all
		select 'M5_DATABASE'  table_name from dual union all
		select 'M5_ROLE'      table_name from dual union all
		select 'M5_ROLE_PRIV' table_name from dual union all
		select 'M5_USER'      table_name from dual union all
		select 'M5_USER_ROLE' table_name from dual
		order by 1
	) loop
		begin
			v_expected_results := 'Exception caught: ORA-20000: You do not have permission to modify the table '||tables.table_name||'.'||chr(10)||
				'Only Method5 administrators can modify that table.'||chr(10)||
				'Contact your current administrator if you need access.';

			v_test_name := 'Modify '||tables.table_name;
			execute immediate 'update method5.'||tables.table_name||' set changed_by = changed_by where rownum = 1';
			assert_equals(v_test_name, v_expected_results, 'No exception caught.');
		exception when others then
			assert_equals(v_test_name, v_expected_results, 'Exception caught: '||sqlerrm);
		end;
	end loop;

	rollback;
end test_cannot_change_config;


--------------------------------------------------------------------------------
procedure run(
	p_database_name_1   in varchar2,
	p_database_name_2   in varchar2,
	p_other_schema_name in varchar2,
	p_tests             in number default c_all_tests
) is
	v_database_name_1 varchar2(100) := lower(trim(p_database_name_1));
	v_database_name_2 varchar2(100) := lower(trim(p_database_name_2));
	v_version_warning varchar2(32767);
begin
	--Reset globals.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;
	g_report := string_table();

	--Print header.
	g_report.extend; g_report(g_report.count) := null;
	g_report.extend; g_report(g_report.count) := '----------------------------------------';
	g_report.extend; g_report(g_report.count) := 'Method5 Test Summary';
	g_report.extend; g_report(g_report.count) := '----------------------------------------';

	--Raise error if the same database is used for both parameters.
	if lower(trim(p_database_name_1)) = lower(trim(p_database_name_2)) then
		raise_application_error(-20000, 'You must use two different database names for testing.');
	end if;

	--Get warning message if the two databases use the same version.
	v_version_warning := get_version_warning(p_database_name_1, p_database_name_2);
	if v_version_warning is not null then
		g_report.extend; g_report(g_report.count) := null;
		g_report.extend; g_report(g_report.count) := v_version_warning;
	end if;

	dbms_output.disable;

	--Run the chosen tests.
	if bitand(p_tests, c_test_function               ) > 0 then test_function(v_database_name_1);                                     end if;
	if bitand(p_tests, c_test_procedure              ) > 0 then test_procedure(v_database_name_1);                                    end if;
	if bitand(p_tests, c_test_m5_views               ) > 0 then test_m5_views(v_database_name_1);                                     end if;
	if bitand(p_tests, c_test_p_code                 ) > 0 then test_p_code(v_database_name_1);                                       end if;
	if bitand(p_tests, c_test_p_targets              ) > 0 then test_p_targets(v_database_name_1, v_database_name_2);                 end if;
	if bitand(p_tests, c_test_p_table_name           ) > 0 then test_p_table_name(v_database_name_1, p_other_schema_name);            end if;
	if bitand(p_tests, c_test_p_asynchronous         ) > 0 then test_p_asynchronous(v_database_name_1);                               end if;
	if bitand(p_tests, c_test_p_table_exists_action  ) > 0 then test_p_table_exists_action(v_database_name_1);                        end if;
	if bitand(p_tests, c_test_audit                  ) > 0 then test_audit(v_database_name_1, v_database_name_2);                     end if;
	if bitand(p_tests, c_test_long                   ) > 0 then test_long(v_database_name_1);                                         end if;
	if bitand(p_tests, c_test_version_star           ) > 0 then test_version_star(v_database_name_1, v_database_name_2);              end if;
	if bitand(p_tests, c_test_get_target_tab_from_tar) > 0 then test_get_target_tab_from_targe(v_database_name_1, v_database_name_2); end if;
	if bitand(p_tests, c_test_run_as_sys             ) > 0 then test_run_as_sys(v_database_name_1);                                   end if;
	if bitand(p_tests, c_test_shell_script           ) > 0 then test_shell_script(v_database_name_1, v_database_name_2);              end if;
	if bitand(p_tests, c_sandbox_and_targets         ) > 0 then test_sandbox_and_targets(v_database_name_2, p_other_schema_name);     end if;
	if bitand(p_tests, c_test_cannot_change_config   ) > 0 then test_cannot_change_config;                                            end if;

	--TODO: Test dropping and recreating a database link.

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



--------------------------------------------------------------------------------
procedure create_test_users(p_database_name_1 varchar2, p_database_name_2 varchar2) is
begin
	--Create user 1: Direct access - run as Method5 and use database links.
	execute immediate 'create user M5_TEST_DIRECT identified by "justATempPassword#4321" quota unlimited on users';
	execute immediate 'grant dba to M5_TEST_DIRECT';
	execute immediate 'grant m5_run to M5_TEST_DIRECT';
	execute immediate 'grant create database link to M5_TEST_DIRECT';

	--Create user 2: Access through sandbox user, no database links.
	execute immediate 'create user M5_TEST_SANDBOX_FULL_NO_LINKS identified by "justATempPassword#4321" quota unlimited on users';
	execute immediate 'grant create session to M5_TEST_SANDBOX_FULL_NO_LINKS';
	execute immediate 'grant m5_run to M5_TEST_SANDBOX_FULL_NO_LINKS';
	execute immediate 'grant create database link to M5_TEST_SANDBOX_FULL_NO_LINKS';
	--Need some extra privileges to run the tests.
	execute immediate 'grant execute on method5.method5_test to M5_TEST_SANDBOX_FULL_NO_LINKS';
	execute immediate 'grant select on method5.m5_audit to M5_TEST_SANDBOX_FULL_NO_LINKS';

	--Create user 3: Access through sandbox user, no database links, virtually no privileges, only defaults to ONE of the 2 databases.
	execute immediate 'create user M5_TEST_SANDBOX_AND_TARGETS identified by "justATempPassword#4321" quota unlimited on users';
	execute immediate 'grant create session to M5_TEST_SANDBOX_AND_TARGETS';
	execute immediate 'grant m5_run to M5_TEST_SANDBOX_AND_TARGETS';
	execute immediate 'grant create database link to M5_TEST_SANDBOX_AND_TARGETS';
	--Need some extra privileges to run the tests.
	execute immediate 'grant execute on method5.method5_test to M5_TEST_SANDBOX_AND_TARGETS';


	--Create M5 user, role, and user-role connection.
	insert into method5.m5_user(oracle_username, os_username, email_address, is_m5_admin, default_targets, can_use_sql_for_targets, can_drop_tab_in_other_schema)
		values('M5_TEST_DIRECT', sys_context('userenv', 'os_user'), null, 'No', null, 'Yes', 'Yes');
	insert into method5.m5_role(role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema, run_as_m5_or_sandbox)
		values('M5_TEST_DIRECT', p_database_name_1||','||p_database_name_2, 'Yes', 'Yes', 'Yes', 'M5');
	insert into method5.m5_user_role(oracle_username, role_name)
		values('M5_TEST_DIRECT', 'M5_TEST_DIRECT');

	insert into method5.m5_user(oracle_username, os_username, email_address, is_m5_admin, default_targets, can_use_sql_for_targets, can_drop_tab_in_other_schema)
		values('M5_TEST_SANDBOX_FULL_NO_LINKS', sys_context('userenv', 'os_user'), null, 'No', null, 'Yes', 'Yes');
	insert into method5.m5_role(role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema, run_as_m5_or_sandbox)
		values('M5_TEST_SANDBOX_FULL_NO_LINKS', p_database_name_1||','||p_database_name_2, 'No', 'No', 'No', 'SANDBOX');
	insert into method5.m5_user_role(oracle_username, role_name)
		values('M5_TEST_SANDBOX_FULL_NO_LINKS', 'M5_TEST_SANDBOX_FULL_NO_LINKS');
	insert into method5.m5_role_priv(role_name, privilege)
		values('M5_TEST_SANDBOX_FULL_NO_LINKS', 'DBA');

	insert into method5.m5_user(oracle_username, os_username, email_address, is_m5_admin, default_targets, can_use_sql_for_targets, can_drop_tab_in_other_schema)
		values('M5_TEST_SANDBOX_AND_TARGETS', sys_context('userenv', 'os_user'), null, 'No', p_database_name_1, 'No', 'No'); --Note this user defaults only to only DB1.
	insert into method5.m5_role(role_name, target_string, can_run_as_sys, can_run_shell_script, install_links_in_schema, run_as_m5_or_sandbox)
		values('M5_TEST_SANDBOX_AND_TARGETS', p_database_name_2, 'No', 'No', 'No', 'SANDBOX'); --But it can only access DB2.
	insert into method5.m5_user_role(oracle_username, role_name)
		values('M5_TEST_SANDBOX_AND_TARGETS', 'M5_TEST_SANDBOX_AND_TARGETS');
	--Nothing inserted into M5_ROLE_PRIV

	commit;
end create_test_users;

--------------------------------------------------------------------------------
procedure drop_test_users_if_exist is
	v_count number;

	procedure drop_user(p_username varchar2) is
	begin
		execute immediate 'select count(*) from dba_users where username = :p_username'
		into v_count
		using p_username;

		if v_count = 1 then
			execute immediate 'drop user '||p_username||' cascade';
			delete from method5.m5_user_role where oracle_username = p_username;
			delete from method5.m5_role_priv where role_name = p_username;
			delete from method5.m5_role where role_name = p_username;
			delete from method5.m5_user where oracle_username = p_username;
			commit;
		end if;
	end;
begin
	drop_user('M5_TEST_DIRECT');
	drop_user('M5_TEST_SANDBOX_FULL_NO_LINKS');
	drop_user('M5_TEST_SANDBOX_AND_TARGETS');
end drop_test_users_if_exist;


--------------------------------------------------------------------------------
function get_run_script(
	p_database_name_1   varchar2,
	p_database_name_2   varchar2,
	p_other_schema_name varchar2,
	p_test_run_as_sys   varchar2,
	p_test_shell_script varchar2,
	p_tns_alias         varchar2
) return varchar2 is
begin
	return(replace(replace(replace(replace(replace(replace(replace(replace(q'[
			--#1: Run from a Method5 administrator account, to drop and recreate test users.
			--These tests will create users, which may generate emails to administrators
			--since it modifies important tables.
			begin
				method5.method5_test.drop_test_users_if_exist;
				method5.method5_test.create_test_users('##DATABASE_NAME_1##', '##DATABASE_NAME_2##');
			end;
			##SLASH##

			--#2: Create and test a user with all privileges.
			sqlplus M5_TEST_DIRECT/"justATempPassword#4321"@##TNS_ALIAS##
			set serveroutput on timing on;
			begin
				method5.method5_test.run(
					p_database_name_1   => '##DATABASE_NAME_1##',
					p_database_name_2   => '##DATABASE_NAME_2##',
					p_other_schema_name => '##OTHER_SCHEMA_NAME##',
					p_tests => method5.method5_test.c_base_tests  + method5.method5_test.c_test_cannot_change_config ##RUN_AS_SYS## ##SHELL_SCRIPT##);
			end;
			##SLASH##
			quit;

			--#3: Create and test a user with no links, and full DBA privs granted through a link.
			sqlplus M5_TEST_SANDBOX_FULL_NO_LINKS/"justATempPassword#4321"@##TNS_ALIAS##
			set serveroutput on timing on;
			begin
				method5.method5_test.run(
					p_database_name_1   => '##DATABASE_NAME_1##',
					p_database_name_2   => '##DATABASE_NAME_2##',
					p_other_schema_name => '##OTHER_SCHEMA_NAME##',
					--Never test SYS and shell script for SANDBOX users.
					p_tests => method5.method5_test.c_base_tests);
			end;
			##SLASH##
			quit;

			--#4: Create and test a user with limited privileges.
			sqlplus M5_TEST_SANDBOX_AND_TARGETS/"justATempPassword#4321"@##TNS_ALIAS##
			set serveroutput on timing on;
			begin
				method5.method5_test.run(
					p_database_name_1   => '##DATABASE_NAME_1##',
					p_database_name_2   => '##DATABASE_NAME_2##',
					p_other_schema_name => '##OTHER_SCHEMA_NAME##',
					--Never test SYS and shell script for SANDBOX users.
					p_tests => method5.method5_test.c_sandbox_and_targets);
			end;
			##SLASH##
			quit;

			--#5: Run from a Method5 administrator account, to drop the test users.
			begin
				method5.method5_test.drop_test_users_if_exist;
			end;
			##SLASH##

			]'
		, '			')
		,'##SLASH##', '/')
		,'##TNS_ALIAS##', p_tns_alias)
		,'##DATABASE_NAME_1##', p_database_name_1)
		,'##DATABASE_NAME_2##', p_database_name_2)
		,'##OTHER_SCHEMA_NAME##', p_other_schema_name)
		,'##RUN_AS_SYS##', case when trim(upper(p_test_run_as_sys)) = 'YES' then '+ method5.method5_test.c_test_run_as_sys' else '' end)
		,'##SHELL_SCRIPT##', case when trim(upper(p_test_shell_script)) = 'YES' then '+ method5.method5_test.c_test_shell_script' else '' end)
	);
end get_run_script;


end;
/
