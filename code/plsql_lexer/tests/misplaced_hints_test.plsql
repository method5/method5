create or replace package misplaced_hints_test authid current_user is
/*
== Purpose ==

Unit tests for MISPLACED_HINTS.


== Example ==

begin
	misplaced_hints_test.run;
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_test_code  constant number := power(2, 1);
c_test_schema  constant number := power(2, 2);

--Default option is to run all static test suites.
c_static_tests constant number := c_test_code+c_test_schema;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body misplaced_hints_test is
pragma serially_reusable;

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--Helper procedures.
--------------------------------------------------------------------------------
procedure assert_equals(p_test varchar2, p_expected varchar2, p_actual varchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--Test Suites
--------------------------------------------------------------------------------
procedure test_code is
	v_bad_hints misplaced_hints_code_table;
begin
	--Empty.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code(null);
	assert_equals('Empty 1', 0, v_bad_hints.count);

	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('select * from dual');
	assert_equals('Empty 2', 0, v_bad_hints.count);

	--SELECT, one line.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('select * /*+ parallel*/ from dual');
	assert_equals('SQL hint 1, count', 1, v_bad_hints.count);
	assert_equals('SQL hint 1, line number', 1, v_bad_hints(1).line_number);
	assert_equals('SQL hint 1, column number', 10, v_bad_hints(1).column_number);
	assert_equals('SQL hint 1, lin etext', 'select * /*+ parallel*/ from dual', v_bad_hints(1).line_text);

	--INSERT, multiple lines.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('insert into '||chr(10)||'/*+ parallel*/'||chr(10)||'some_table ...');
	assert_equals('SQL hint 2, count', 1, v_bad_hints.count);
	assert_equals('SQL hint 2, line number', 2, v_bad_hints(1).line_number);
	assert_equals('SQL hint 2, column number', 1, v_bad_hints(1).column_number);
	assert_equals('SQL hint 2, lin etext', '/*+ parallel*/', v_bad_hints(1).line_text);

	--MERGE, "--+" syntax.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('merge into --+parallel'||chr(10)||'some_table...');
	assert_equals('SQL hint 3, count', 1, v_bad_hints.count);
	assert_equals('SQL hint 3, line number', 1, v_bad_hints(1).line_number);
	assert_equals('SQL hint 3, column number', 12, v_bad_hints(1).column_number);
	assert_equals('SQL hint 3, lin etext', 'merge into --+parallel', v_bad_hints(1).line_text);

	--Multiple hints, works in PL/SQL.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('begin '||chr(10)||'delete from /*+a*/ test1; delete from '||chr(10)||'/*+b*/'||chr(10)||'test2; end;');
	assert_equals('SQL hint 4, count', 2, v_bad_hints.count);
	assert_equals('SQL hint 4, line number 1', 2, v_bad_hints(1).line_number);
	assert_equals('SQL hint 4, column number 1', 13, v_bad_hints(1).column_number);
	assert_equals('SQL hint 4, lin etext 1', 'delete from /*+a*/ test1; delete from ', v_bad_hints(1).line_text);

	assert_equals('SQL hint 4, line number 2', 3, v_bad_hints(2).line_number);
	assert_equals('SQL hint 4, column number 2', 1, v_bad_hints(2).column_number);
	assert_equals('SQL hint 4, lin etext 2', '/*+b*/', v_bad_hints(2).line_text);

	--Ignore SELECT with correct hint.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('select /*+ parallel */ * from dual');
	assert_equals('SQL hint 5, count', 0, v_bad_hints.count);

	--Ignore INSERT with correct hint.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('insert --+ parallel ...');
	assert_equals('SQL hint 6, count', 0, v_bad_hints.count);

	--Ignore UPDATE with correct hint.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('update /*+ full(t) */ ...');
	assert_equals('SQL hint 7, count', 0, v_bad_hints.count);

	--Ignore DELETE with correct hint.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('delete /*+ parallel */ table1');
	assert_equals('SQL hint 8, count', 0, v_bad_hints.count);

	--Ignore MERGE with correct hint.
	v_bad_hints := misplaced_hints.get_misplaced_hints_in_code('merge /*+ asdf */ into ...');
	assert_equals('SQL hint 9, count', 0, v_bad_hints.count);
end test_code;


--------------------------------------------------------------------------------
procedure test_schema is
begin
	--TODO - how do I test for an entire schema without a huge setup and teardown?
	null;
end test_schema;


--------------------------------------------------------------------------------
procedure run(p_tests number default c_static_tests) is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('Misplaced Hints Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_test_code)   > 0 then test_code; end if;
	if bitand(p_tests, c_test_schema) > 0 then test_schema; end if;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line(unit_tests.C_PASS_MESSAGE);
	else
		dbms_output.put_line(unit_tests.C_FAIL_MESSAGE);
	end if;
end run;

end;
/
