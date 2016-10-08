create or replace package statement_splitter_test authid current_user is
/*
= Purpose ==

Unit tests for statement_splitter.


== Example ==

begin
	statement_splitter_test.run;
	statement_splitter_test.run(statement_splitter_test.c_dynamic_tests);
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_errors                 constant number := power(2, 1);
c_simple                 constant number := power(2, 2);
c_plsql_declaration      constant number := power(2, 3);
c_plsql_block            constant number := power(2, 4);
c_package                constant number := power(2, 5);
c_type_body              constant number := power(2, 6);
c_trigger                constant number := power(2, 7);
c_proc_and_func          constant number := power(2, 8);
c_package_body           constant number := power(2, 9);
c_metadata               constant number := power(2, 10);

c_sqlplus_delim          constant number := power(2, 30);
c_sqlplus_delim_and_semi constant number := power(2, 31);


c_static_tests  constant number := c_errors+c_simple+c_plsql_declaration
	+c_plsql_block+c_package+c_type_body+c_trigger+c_proc_and_func+c_package_body
	+c_metadata+c_sqlplus_delim+c_sqlplus_delim_and_semi;

c_dynamic_sql constant number := power(2, 51);
c_dynamic_plsql constant number := power(2, 52);
c_dynamic_tests constant number := c_dynamic_sql + c_dynamic_plsql;

c_all_tests constant number := c_static_tests+c_dynamic_tests;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body statement_splitter_test is
pragma serially_reusable;

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;


-- =============================================================================
-- Helper procedures.
-- =============================================================================

--------------------------------------------------------------------------------
procedure assert_equals(p_test varchar2, p_expected varchar2, p_actual varchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


-- =============================================================================
-- Test Suites
-- =============================================================================

--------------------------------------------------------------------------------
procedure test_errors is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	v_statements:='begin null;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Incompleted PLSQL Block 1a', 1, v_split_statements.count);
	assert_equals('Incompleted PLSQL Block 1b', v_statements, plsql_lexer.concatenate(v_split_statements(1)));

	v_statements:='create function f1 return asdf is begin null; ';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Incompleted PLSQL Block 2a', 1, v_split_statements.count);
	assert_equals('Incompleted PLSQL Block 2b', v_statements, plsql_lexer.concatenate(v_split_statements(1)));

	--TODO
	--v_statements:='begin loop null; end NOT_LOOP;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	--assert_equals('Incompleted PLSQL Block 3a', 1, v_split_statements.count);
	--assert_equals('Incompleted PLSQL Block 3b', v_statements, plsql_lexer.concatenate(v_split_statements(1)));
end test_errors;


--------------------------------------------------------------------------------
procedure test_simple is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	v_statements:='select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('No split 1', v_statements, plsql_lexer.concatenate(v_split_statements(1)));
	v_statements:='select * from dual';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('No split 2', v_statements, plsql_lexer.concatenate(v_split_statements(1)));

	v_statements:='select * from dual a;select * from dual b;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Simple split 1a', 'select * from dual a;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Simple split 1b', 'select * from dual b;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='select * from dual a; select * from dual b; ';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Simple split 2a', 'select * from dual a;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Simple split 2b', ' select * from dual b; ', plsql_lexer.concatenate(v_split_statements(2)));
	assert_equals('Simple split 2c', 2, v_split_statements.count);

	--Small or empty strings should not crash.
	v_statements:='';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Simple split 3a', 1, v_split_statements.count);
	assert_equals('Simple split 3b', null, plsql_lexer.concatenate(v_split_statements(1)));

	v_statements:='a'||chr(10);v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Simple split 4a', 1, v_split_statements.count);
	assert_equals('Simple split 4b', 'a'||chr(10), plsql_lexer.concatenate(v_split_statements(1)));
end test_simple;


--------------------------------------------------------------------------------
procedure test_plsql_declaration is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 1a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 1b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 1c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; h as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 2a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 2b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; h as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 2c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; h(a) as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 3a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 3b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; h(a) as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 3c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; h as (select 1 a from dual), i as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 4a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 4b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; h as (select 1 a from dual), i as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 4c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; procedure g is begin null; end; h as (select 1 a from dual), i as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 5a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 5b', 'with function f return number is begin return 1; end; procedure g is begin null; end; h as (select 1 a from dual), i as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 5c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; function as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 6a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 6b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; function as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 6c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='with function f return number is begin return 1; end; function g return number is begin return 2; end; function(a) as (select 1 a from dual) select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 7a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 7b', 'with function f return number is begin return 1; end; function g return number is begin return 2; end; function(a) as (select 1 a from dual) select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 7c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--"select 1 as begin" should not count as a "BEGIN".
	v_statements:='with function f return number is v_test number; begin select 1 as begin into v_test from dual; return 1; end; select f from dual;select 1 from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 8a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 8b', 'with function f return number is v_test number; begin select 1 as begin into v_test from dual; return 1; end; select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 8c', 'select 1 from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--TODO: Test commas, FROM, into, bulk collect.

	--CLUSTER_ID "as begin" exception
	v_statements:='with function f return number is v_number number; begin select cluster_id(some_model using asdf as begin) into v_number from dual; return v_number; end; select f from dual;select * from dual b;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 9a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 9b', 'with function f return number is v_number number; begin select cluster_id(some_model using asdf as begin) into v_number from dual; return v_number; end; select f from dual;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_declaration 9c', 'select * from dual b;', plsql_lexer.concatenate(v_split_statements(2)));

	--PIVOT_IN_CLAUSE "as begin" exception.
	v_statements:=q'!
with function f return number is
	v_number number;
begin
	select 1
	into v_number
	from (select 1 deptno, 'A' job, 100 sal from dual)
	pivot
	(
		sum(sal)
		for deptno
		in  (1,2 as begin)
	);
	return v_number;
end;select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 10a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 10b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLATTRIBUTES "as begin" exception.
	v_statements:=q'!
with function f return xmltype is
	v_test xmltype;
begin
	select xmlelement("a", xmlattributes(1 as begin)) into v_test from dual;
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 11a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 11b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLCOLATTVAL "as begin" exception.
	v_statements:=q'!
with function f return xmltype is
	v_test xmltype;
begin
	select xmlelement("a", xmlcolattval(1 as begin))
	into v_test
	from dual;
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 12a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 12b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLELEMENTS "as begin" exception.
	v_statements:=q'!
with function f return xmltype is
	v_test xmltype;
begin
	select xmlelement("a", sys.odcivarchar2list('b') as begin) into v_test from dual;
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 13a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 13b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLFOREST "as begin" exception.
	v_statements:=q'!
with function f return xmltype is
	v_test xmltype;
begin
	select xmlforest(1 as begin) into v_test from dual;
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 14a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 14b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLTABLE_options "as begin" exception.
	v_statements:=q'!
with function f return varchar2 is
	v_test varchar2(1);
begin
	select name
	into v_test
	from (select xmltype('<emp><name>A</name></emp>') the_xml from dual) emp
	cross join xmltable('/emp' passing emp.the_xml, emp.the_xml as begin columns name varchar2(100) path '/emp/name');
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 15a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 15b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--XMLnamespaces_clause "as begin" exception.
	v_statements:=q'!
with function f return varchar2 is
	v_test varchar2(1);
begin
	select name
	into v_test
	from (select xmltype('<emp><name>A</name></emp>') the_xml from dual) emp
	cross join xmltable(xmlnamespaces('N' as begin, default ''), '/emp' passing the_xml columns name varchar2(1) path '/emp/name');
	return v_test;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 16a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 16b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--PIVOT "as begin" exception.
	v_statements:=q'!
with function f return number is
	v_number number;
begin
	select 1
	into v_number
	from (select 1 deptno, 'A' job, 100 sal from dual)
	pivot
	(
		sum(sal) as begin
		for deptno
		in  (1,2)
	);
	return v_number;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 17a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 17b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--PIVOT XML "as begin" exception.
	v_statements:=q'!
with function f return number is
	v_number number;
begin
	select 1
	into v_number
	from (select 1 deptno, 'A' job, 100 sal from dual)
	pivot xml
	(
		sum(sal) as begin1, sum(sal) as begin
		for deptno
		in  (any)
	);
	return v_number;
end; select f from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 18a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 18b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--nested_table_col_properties "as begin" exception.
	v_statements:=q'!
create table test1 nested table a store as begin as
with function f return varchar2 is v_string varchar2(1); begin return 'A'; end;
select sys.dbms_debug_vc2coll('A') a from dual;select * from dual b!';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_declaration 19a', 2, v_split_statements.count);
	assert_equals('plsql_declaration 19b', 'select * from dual b', plsql_lexer.concatenate(v_split_statements(2)));

	--TODO: SQL with PL/SQL with a SQL with PL/SQL.
end test_plsql_declaration;


--------------------------------------------------------------------------------
procedure test_plsql_block is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	v_statements:='declare v_test number; begin select begin begin into v_test from (select 1 begin from dual); end; select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_block: begin begin does not start a block 1a', 2, v_split_statements.count);
	assert_equals('plsql_block: begin begin does not start a block 1b', 'declare v_test number; begin select begin begin into v_test from (select 1 begin from dual); end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_block: begin begin does not start a block 1c', ' select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='select begin begin into v_test from (select 1 begin from dual); select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_block: begin begin does not start a block 2a', 2, v_split_statements.count);
	assert_equals('plsql_block: begin begin does not start a block 2b', 'select begin begin into v_test from (select 1 begin from dual);', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_block: begin begin does not start a block 2c', ' select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='declare v_test number; begin begin begin select begin begin into v_test from (select 1 begin from dual); end; end; end; select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_block: begin begin does not start a block 3a', 2, v_split_statements.count);
	assert_equals('plsql_block: begin begin does not start a block 3b', 'declare v_test number; begin begin begin select begin begin into v_test from (select 1 begin from dual); end; end; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_block: begin begin does not start a block 3c', ' select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='declare v_test number; begin select 1 as end into v_test from dual; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_block: "as end" does not count 1a', 2, v_split_statements.count);
	assert_equals('plsql_block: "as end" does not count 1b', 'declare v_test number; begin select 1 as end into v_test from dual; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_block: "as end" does not count 1c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='declare v_test number; begin with end as (select 1 a from dual) select a into v_test from end; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('plsql_block: "as end" does not count 2a', 2, v_split_statements.count);
	assert_equals('plsql_block: "as end" does not count 2b', 'declare v_test number; begin with end as (select 1 a from dual) select a into v_test from end; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('plsql_block: "as end" does not count 2c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Don't count "end if".
	v_statements:='begin if 1=1 then null; end if; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 1a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 1b', 'begin if 1=1 then null; end if; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 1c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Don't count "end loop".
	v_statements:='begin loop null; end loop; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 2a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 2b', 'begin loop null; end loop; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 2c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Don't count "end case".
	v_statements:='begin case when 1=1 then null; end case; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 3a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 3b', 'begin case when 1=1 then null; end case; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 3c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Count "begin begin".
	v_statements:='begin begin null; end; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 4a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 4b', 'begin begin null; end; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 4c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--(Cannot test "as begin" and "is begin", those are tested in test_proc_and_func.)

	--Count "; begin".
	v_statements:='declare a number; begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 5a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 5b', 'declare a number; begin null; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 5c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Count ">> begin".
	v_statements:='declare a number; begin <<label1>> null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 6a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 6b', 'declare a number; begin <<label1>> null; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 6c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Count "then begin".
	v_statements:='begin if 1=1 then begin null; end; end if; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 7a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 7b', 'begin if 1=1 then begin null; end; end if; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 7c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Count "else begin".
	v_statements:='begin if 1=1 then null; else begin null; end; end if; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 8a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 8b', 'begin if 1=1 then null; else begin null; end; end if; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 8c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Count "loop begin".
	v_statements:='begin for i in 1 .. 2 loop begin null; end; end loop; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 9a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 9b', 'begin for i in 1 .. 2 loop begin null; end; end loop; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 9c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--DECLARE with PROCEDURE.
	v_statements:='declare procedure p1 is begin null; end; begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('PLSQL Block 10a', 2, v_split_statements.count);
	assert_equals('PLSQL Block 10b', 'declare procedure p1 is begin null; end; begin null; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('PLSQL Block 10c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
end test_plsql_block;


--------------------------------------------------------------------------------
procedure test_package is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	--Empty package.
	v_statements:='create or replace package test_package is end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package 1a', 2, v_split_statements.count);
	assert_equals('Package 1b', 'create or replace package test_package is end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Package 1c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Package with procedures and functions and items.
	v_statements:='
		create or replace package test_package is
			procedure procedure1;
			function function1 return number;
		end;select * from dual;';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package 2a', 2, v_split_statements.count);
	assert_equals('Package 2b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Package with PLSQL_DECLARATION cursor - Not valid in 12.1.0.2.0.
	/*
	--Using a PLSQL_DECLARATION in a cursor is invalid but it does compile.
	v_statements:='
		create or replace package test_package is
			cursor c1 is select 1 end from dual;
			cursor c2 is with function f return number is begin begin return 1; end; end; select f end from dual;
			procedure procedure1;
			function function1 return number;
		end;select * from dual;';
	v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package 3a', 2, v_split_statements.count);
	assert_equals('Package 3b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
	*/
end test_package;


--------------------------------------------------------------------------------
procedure test_type_body is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	--TODO:
	--All type body member types.
	/* This is the type spec to make the next type body work.
	create or replace type type1 is object
	(
		a number,
		member procedure procedure1,
		member function function1 return number,
		order member function return_order(a type1) return number,
		final instantiable constructor function type1 return self as result
	);
	*/

	v_statements:='
		create or replace type body type1 is
			member procedure procedure1 is begin null; end;
			member function function1 return number is begin return 1; end;
			order member function return_order(a type1) return number is begin return 1; end;
			final instantiable constructor function type1 return self as result is begin null; end;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Type Body 1a', 2, v_split_statements.count);
	assert_equals('Type body 1b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
end test_type_body;


--------------------------------------------------------------------------------
procedure test_trigger is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	--Regular triggers have a matched begin/end.
	v_statements:='
		create or replace trigger test2_trigger1
		instead of insert on test2_vw
		begin null; end test2_trigger1;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 1a', 2, v_split_statements.count);
	assert_equals('Trigger 1b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Compound triggers require an extra END.
	v_statements:='
		create or replace trigger test1_trigger2
		for update of a on test1
		compound trigger
			test_variable number;
			procedure nested_procedure is begin null; end nested_procedure;
			before statement is begin null; end before statement;
			before each row is begin null; end before each row;
			after statement is begin null; end after statement;
			after each row is begin null; end after each row;
			--This is invalid even though the manual implies it is allowed.
			--instead of each row is begin null; end instead of each row;
		end test1_trigger2;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 2a', 2, v_split_statements.count);
	assert_equals('Trigger 2b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--A CALL trigger needs a regular terminator.
	--(This behavior is slightly different than SQL*Plus and the manual.
	--Officially, the CALL version of a trigger cannot end with a semicolon.)
	v_statements:='
		create or replace trigger test1_trigger1
		before delete on test1
		for each row
		call test_procedure;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 3a', 2, v_split_statements.count);
	assert_equals('Trigger 3b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));


	---------------------------------------
	--Regular triggers with "CALL" in different position.
	---------------------------------------

	--Name of trigger.
	v_statements:='create trigger call before update on table1 for each row begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 4a', 2, v_split_statements.count);
	assert_equals('Trigger 4b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Name of schema and trigger.
	v_statements:='create trigger call.call before update on table1 for each row begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 5a', 2, v_split_statements.count);
	assert_equals('Trigger 5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Name of schema and trigger.
	v_statements:='create trigger call.call before update on table1 for each row begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 6a', 2, v_split_statements.count);
	assert_equals('Trigger 6b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--dml_event_clause - first column, schema name and table name
	v_statements:='create trigger call.call before update of call on call.call for each row begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 7a', 2, v_split_statements.count);
	assert_equals('Trigger 7b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--dml_event_clause - additional column, schema name, and tble name.
	v_statements:='create trigger call.call before update of a, call on call.call for each row begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 8a', 2, v_split_statements.count);
	assert_equals('Trigger 8b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 1 - old
	v_statements:='create or replace trigger trigger1 after update on table1 referencing old as call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 9a', 2, v_split_statements.count);
	assert_equals('Trigger 9b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 2 - new
	v_statements:='create or replace trigger trigger1 after update on table1 referencing new as call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 10a', 2, v_split_statements.count);
	assert_equals('Trigger 10b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 3 - parent
	v_statements:='create or replace trigger trigger1 instead of update on nested table v_type1_nt of view1 referencing parent as call old as asdf new as qwer begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 11a', 2, v_split_statements.count);
	assert_equals('Trigger 11b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 4 - combined 1
	v_statements:='create or replace trigger trigger1 instead of update on nested table v_type1_nt of view1 referencing parent as call old as asdf new as qwer begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 12a', 2, v_split_statements.count);
	assert_equals('Trigger 12b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 5 - combined 2
	v_statements:='create or replace trigger trigger1 instead of update on nested table v_type1_nt of view1 referencing old as asdf parent as call new as qwer begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 13a', 2, v_split_statements.count);
	assert_equals('Trigger 13b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 6 - "as begin" does not count as a real BEGIN.
	v_statements:='create or replace trigger trigger1 after update on table1 referencing old as begin begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 13.5a', 2, v_split_statements.count);
	assert_equals('Trigger 13.5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--referencing_clause 7 - "as end" does not count as a real END.
	v_statements:='create or replace trigger trigger1 after update on table1 referencing old as end begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 13.7a', 2, v_split_statements.count);
	assert_equals('Trigger 13.7b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--trigger_ordering_clause 1 - follows 1
	v_statements:='create or replace trigger trigger2 before update on table1 for each row follows call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 14a', 2, v_split_statements.count);
	assert_equals('Trigger 14b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--trigger_ordering_clause 1 - follows 2
	v_statements:='create or replace trigger trigger2 before update on table1 for each row follows call.call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 15a', 2, v_split_statements.count);
	assert_equals('Trigger 15b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--trigger_ordering_clause 1 - follows 3
	v_statements:='create or replace trigger trigger2 before update on table1 for each row follows call.call, call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 16a', 2, v_split_statements.count);
	assert_equals('Trigger 16b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--trigger_ordering_clause 1 - follows 4.  Yes, this is valid syntax!  (Except that the semicolon after the first statement would not work in SQL*Plus.)
	v_statements:='create or replace trigger trigger2 before update on table1 for each row follows call.call, call, call, call call test_procedure;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 17a', 2, v_split_statements.count);
	assert_equals('Trigger 17b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--trigger_ordering_clause 2 - precedes
	v_statements:='create or replace trigger trigger2 before update on table1 for each row precedes call begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 18a', 2, v_split_statements.count);
	assert_equals('Trigger 18b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--WHEN (condition)
	v_statements:='create or replace trigger trigger2 before update on table1 for each row when (((old.call > new.call)) or (old.call > 1)) begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 19a', 2, v_split_statements.count);
	assert_equals('Trigger 19b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--system_trigger [on schema.schema]
	v_statements:='create or replace trigger trigger_schema before comment or create on call.schema begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 20a', 2, v_split_statements.count);
	assert_equals('Trigger 20b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--system_trigger - syntax the manual leaves out
	v_statements:='create or replace trigger trigger_schema before comment or create on jheller.schema enable when (1=1) begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Trigger 21a', 2, v_split_statements.count);
	assert_equals('Trigger 21b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
end test_trigger;


--------------------------------------------------------------------------------
procedure test_proc_and_func is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	--Regular procedure.
	v_statements:='create procedure test_procedure is begin null; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 1a', 2, v_split_statements.count);
	assert_equals('Procedure and Function 1b', 'create procedure test_procedure is begin null; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Procedure and Function 1c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--External procedure.
	v_statements:='create procedure test_procedure as external language c name "c_test" library test_lib;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 2a', 2, v_split_statements.count);
	assert_equals('Procedure and Function 2b', 'create procedure test_procedure as external language c name "c_test" library test_lib;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Procedure and Function 2c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--Regular function.
	v_statements:='create function test_function return number is begin return 1; end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 3a', 2, v_split_statements.count);
	assert_equals('Procedure and Function 3b', 'create function test_function return number is begin return 1; end;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Procedure and Function 3c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--External function.
	v_statements:='create function test_function return number as external language c name "c_test" library test_lib;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 4a', 2, v_split_statements.count);
	assert_equals('Procedure and Function 4b', 'create function test_function return number as external language c name "c_test" library test_lib;', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Procedure and Function 4c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--External function with CALL syntax.
	--This would be a valid example with this Java:
	--  create or replace and compile java source named "RandomUUID" as
	--  public class RandomUUID { public static String create() { return java.util.UUID.randomUUID().toString(); } }
	--External function.
	v_statements:=q'<create or replace function randomuuid return varchar2 as language java name 'RandomUUID.create() return java.lang.String';select * from dual;>';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 5a', 2, v_split_statements.count);
	assert_equals('Procedure and Function 5b', q'<create or replace function randomuuid return varchar2 as language java name 'RandomUUID.create() return java.lang.String';>', plsql_lexer.concatenate(v_split_statements(1)));
	assert_equals('Procedure and Function 5c', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--TODO: How to handle errors?
/*
	--Procedure that doesn't properly end.  EOF should always end.
	v_statements:='create procedure test_procedure is ';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Procedure and Function 6a', 1, v_split_statements.count);
	assert_equals('Procedure and Function 6b', 'create procedure test_procedure is ', plsql_lexer.concatenate(v_split_statements(1)));
*/
end test_proc_and_func;


--------------------------------------------------------------------------------
procedure test_package_body is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();
begin
	--#1: Extra END in an emtpy package body.
	v_statements:='
		create or replace package body test_package is
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 1a', 2, v_split_statements.count);
	assert_equals('Package Body 1b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	v_statements:='
		create or replace package body test_package is
		end test_package;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 1.5a', 2, v_split_statements.count);
	assert_equals('Package Body 1.5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#2: One matched BEGIN and END when there is only an initialization block.
	v_statements:='
		create or replace package body test_package is
		begin
			null;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 2a', 2, v_split_statements.count);
	assert_equals('Package Body 2b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#3: Matched BEGIN and END and extra END.
	v_statements:='
		create or replace package body test_package is
			procedure test1 is begin null; end;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 3a', 2, v_split_statements.count);
	assert_equals('Package Body 3b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#4: Two sets of matched BEGINs and ENDs - from methods.
	v_statements:='
		create or replace package body test_package is
			procedure test1 is begin null; end;
		begin
			null;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 4a', 2, v_split_statements.count);
	assert_equals('Package Body 4b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#4.5: Two sets of matched BEGINs and ENDs - from methods.
	v_statements:='
		create or replace package body test_package is
			procedure test1 is begin null; end;
			procedure test2 is begin null; end;
		begin
			null;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 4.5a', 2, v_split_statements.count);
	assert_equals('Package Body 4.5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#5: Two sets of matched BEGINs and ENDs - from CURSORS and methods.
	/*
	--This is not valid in 12.1.0.2.
	v_statements:='
		create or replace package body test_package is
			cursor my_cursor is with function test_function return number is begin return 1; end; select test_function from dual;
			procedure test1 is begin null; end;
		begin
			null;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 5a', 2, v_split_statements.count);
	assert_equals('Package Body 5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
	*/

	--#5.5: Sets of matched BEGINs and ENDs - from CURSORS with multiple plsql_declarations
	-- and a SQL WITH named "function".  The SQL statements are valid, although it's an
	-- invalid (but parsable) package body.
	/*
	--This is not valid in 12.1.0.2.
	v_statements:='
		create or replace package body test_package is
			cursor my_cursor is with function test_function1 return number is begin return 1; end; function test_function2 return number is begin return 2; end; select test_function1() from dual;
			cursor my_cursor is with function test_function1 return number is begin return 1; end; function as (select 1 a from dual) select a from function;
		begin
			null;
		end;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 5.5a', 2, v_split_statements.count);
	assert_equals('Package Body 5.5b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));
	*/

	--#6: Items only.
	v_statements:=q'<
		create or replace package body test_package is
			variable1 number;
			variable2 number := 5;
			type type1 is table of varchar2(4000);
			string_nt type1 := type1('asdf', 'qwer');
		end;select * from dual;>';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 6a', 2, v_split_statements.count);
	assert_equals('Package Body 6b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

	--#7: External functions.
	v_statements:=q'<
		create or replace package body test_package is
			function randomuuid1 return varchar2 as language java name 'RandomUUID.create() return java.lang.String';
			function randomuuid2 return varchar2 as language java name 'RandomUUID.create() return java.lang.String';
		end;select * from dual;>';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Package Body 7a', 2, v_split_statements.count);
	assert_equals('Package Body 7b', 'select * from dual;', plsql_lexer.concatenate(v_split_statements(2)));

end test_package_body;



--------------------------------------------------------------------------------
procedure test_sqlplus_delim is
	v_statements clob;
	v_split_statements clob_table := clob_table();
	custom_exception_20000 exception;
	pragma exception_init(custom_exception_20000, -20000);
	custom_exception_20001 exception;
	pragma exception_init(custom_exception_20001, -20001);
begin
	--NULL delimiter raises exception.
	begin
		v_statements:='select * from dual a';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, null);
		assert_equals('SQL*Plus Delimiter 1', 'Exception', 'No exception');
	exception when custom_exception_20000 then
		assert_equals('SQL*Plus Delimiter 1', 'ORA-20000: The SQL*Plus delimiter cannot be NULL.', sqlerrm);
	end;

	--Whitespace delimiter raises exception.
	begin
		v_statements:='select * from dual a';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, ' ');
		assert_equals('SQL*Plus Delimiter 2', 'Exception', 'No exception');
	exception when custom_exception_20001 then
		assert_equals('SQL*Plus Delimiter 2', 'ORA-20001: The SQL*Plus delimiter cannot contain whitespace.', sqlerrm);
	end;

	--NULL input returns NULL output.
	v_statements:='';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 3a', '1', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 3b', v_statements, v_split_statements(1));

	--Semicolons do not split.
	v_statements:='select * from dual a;select * from dual b;';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 4a', '1', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 4b', v_statements, v_split_statements(1));

	--Slash on line with code does not split.
	v_statements:='select * from dual a / select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 5a', '1', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 5b', v_statements, v_split_statements(1));

	--Slash on line with comments does not split.
	v_statements:='select * from dual a '||chr(10)||'/ --comment'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 6a', '1', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 6b', v_statements, v_split_statements(1));

	--Simple slash split - slash and whitespace on line
	v_statements:='select * from dual a '||chr(10)||'/'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 7a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 7b', 'select * from dual a '||chr(10)||'/'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 7b', 'select * from dual b', v_split_statements(2));

	--Default delimiter is slash.
	v_statements:='select * from dual a '||chr(10)||'/'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements);
	assert_equals('SQL*Plus Delimiter 8a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 8b', 'select * from dual a '||chr(10)||'/'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 8b', 'select * from dual b', v_split_statements(2));

	--Different delimiter.
	v_statements:='select * from dual a '||chr(10)||'%'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '%');
	assert_equals('SQL*Plus Delimiter 9a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 9b', 'select * from dual a '||chr(10)||'%'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 9b', 'select * from dual b', v_split_statements(2));

	--Multi-character delimiter 1.
	v_statements:='select * from dual a '||chr(10)||'**'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '**');
	assert_equals('SQL*Plus Delimiter 10a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 10b', 'select * from dual a '||chr(10)||'**'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 10b', 'select * from dual b', v_split_statements(2));

	--Multi-character delimiter 2.
	v_statements:='select * from dual a '||chr(10)||'asd'||chr(10)||'select * from dual b';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, 'asd');
	assert_equals('SQL*Plus Delimiter 11a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 11b', 'select * from dual a '||chr(10)||'asd'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 11b', 'select * from dual b', v_split_statements(2));

	--Multiple split lines 1.
	v_statements:='select * from dual a '||chr(10)||' / '||chr(10)||'select * from dual b '||chr(10)||'	/	'||chr(10)||'select * from dual c';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 12a', '3', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 12b', 'select * from dual a '||chr(10)||' / '||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 12c', 'select * from dual b '||chr(10)||'	/	'||chr(10), v_split_statements(2));
	assert_equals('SQL*Plus Delimiter 12d', 'select * from dual c', v_split_statements(3));

	--Multiple split lines 2.
	v_statements:='select * from dual a '||chr(10)||' / '||chr(10)||'select * from dual b '||chr(10)||'	/	'||chr(10)||'select * from dual c '||chr(10)||'/'||chr(10)||'asdf';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 13a', '4', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 13b', 'select * from dual a '||chr(10)||' / '||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 13c', 'select * from dual b '||chr(10)||'	/	'||chr(10), v_split_statements(2));
	assert_equals('SQL*Plus Delimiter 13d', 'select * from dual c '||chr(10)||'/'||chr(10), v_split_statements(3));
	assert_equals('SQL*Plus Delimiter 13e', 'asdf', v_split_statements(4));

	--Slash inside a string splits.
	v_statements:='select '''||chr(10)||'/'||chr(10)||''' from dual;';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 14a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 14b', 'select '''||chr(10)||'/'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 14b', ''' from dual;', v_split_statements(2));

	--Slash inside a comment splits.
	v_statements:='select /*'||chr(10)||'/'||chr(10)||'*/ 1 from dual;';v_split_statements:=statement_splitter.split_by_sqlplus_delimiter(v_statements, '/');
	assert_equals('SQL*Plus Delimiter 15a', '2', v_split_statements.count);
	assert_equals('SQL*Plus Delimiter 15b', 'select /*'||chr(10)||'/'||chr(10), v_split_statements(1));
	assert_equals('SQL*Plus Delimiter 15b', '*/ 1 from dual;', v_split_statements(2));
end test_sqlplus_delim;


--------------------------------------------------------------------------------
procedure test_sqlplus_delim_and_semi is
begin
	--TODO:
	null;
end test_sqlplus_delim_and_semi;


--------------------------------------------------------------------------------
procedure test_metadata is
	v_statements clob;
	v_split_statements token_table_table := token_table_table();

	function concat_metadata(p_token in token) return varchar2 is
	begin
		return
			p_token.line_number||','||
			p_token.column_number||','||
			p_token.first_char_position||','||
			p_token.last_char_position;
	end;
begin
	v_statements:='select * from dual;select * from dual;';v_split_statements:=statement_splitter.split_by_semicolon(plsql_lexer.lex(v_statements));
	assert_equals('Metadata 1', '1,1,1,6|1,1,1,6', concat_metadata(v_split_statements(1)(1)) || '|' || concat_metadata(v_split_statements(2)(1)));

	--TODO: More unit tests.
	null;
end test_metadata;


--------------------------------------------------------------------------------
procedure test_dynamic_sql is
	type clob_table is table of clob;
	type string_table is table of varchar2(100);
	v_sql_ids string_table;
	v_sql_fulltexts clob_table;
	sql_cursor sys_refcursor;
	v_split_statements token_table_table := token_table_table();
begin
	--TODO: Also test source code.

	--Test statements in GV$SQL.
	--Takes 171 seconds on my PC.
	open sql_cursor for
	q'<
		--Only need to select one value per SQL_ID.
		select sql_id, sql_fulltext
		from
		(
			select sql_id, sql_fulltext, row_number() over (partition by sql_id order by 1) rownumber
			from gv$sql
			--TEST - takes 2 seconds
			--where sql_id = 'dfffkcnqfystw'
			--TEST
			--where rownum <= 100
		)
		where rownumber = 1
		order by sql_id
	>';

	loop
		fetch sql_cursor bulk collect into v_sql_ids, v_sql_fulltexts limit 100;
		exit when v_sql_fulltexts.count = 0;

		--Debug if there is an infinite loop.
		--dbms_output.put_line('SQL_ID: '||statements.sql_id);

		for i in 1 .. v_sql_fulltexts.count loop
			g_test_count := g_test_count + 1;

			--Test that each statement is only split into one
			v_split_statements := statement_splitter.split_by_semicolon(plsql_lexer.lex(v_sql_fulltexts(i)));

			if v_split_statements.count = 1 then
				g_passed_count := g_passed_count + 1;
			else
				g_failed_count := g_failed_count + 1;
				dbms_output.put_line('Failed: '||v_sql_ids(i));
				dbms_output.put_line('Expected Statement Count: 1');
				dbms_output.put_line('Actual Statemrnt Count:   '||v_split_statements.count);
			end if;
		end loop;
	end loop;
end test_dynamic_sql;


--------------------------------------------------------------------------------
procedure test_dynamic_plsql is
	v_source clob;
	v_statements token_table_table;
begin
	--Test all source code.
	--Takes 2.5 hours on my PC.
	--
	--Loop through all source code.
	for source_code in
	(
		select owner, name, type, line, text
			,row_number() over (partition by owner, name, type order by line desc) last_when_1
		from all_source
		--Test small subset:
		--where owner = 'APEX_040200' and name like 'APEX%'
		where owner = 'APEX_040200' --and name like 'WWV_FLOW_AUTHORIZED_URLS_T1'
		order by owner, name, type, line
	) loop
		--Append source.
		v_source := v_source ||source_code.text;

		--Process previous source.
		if source_code.last_when_1 = 1 then
			g_test_count := g_test_count + 1;

			--Process source after adding "CREATE" to each statement.
			v_statements := statement_splitter.split_by_semicolon(plsql_lexer.lex('create '||v_source));

			--Count as success or failure depending on count.
			if v_statements.count = 1 then
				g_passed_count := g_passed_count + 1;
			else
				g_failed_count := g_failed_count + 1;
				dbms_output.put_line('OWNER: '||source_code.owner);
				dbms_output.put_line('NAME:  '||source_code.name);
				dbms_output.put_line('TYPE:  '||source_code.type);
				dbms_output.put_line('Count: '||v_statements.count);
			end if;

			--Start new source code.
			v_source := null;
		end if;

	end loop;
end test_dynamic_plsql;


-- =============================================================================
-- Main Procedure
-- =============================================================================

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
	dbms_output.put_line('PL/SQL Statement Splitter Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_errors)                 > 0 then test_errors;                 end if;
	if bitand(p_tests, c_simple)                 > 0 then test_simple;                 end if;
	if bitand(p_tests, c_plsql_declaration)      > 0 then test_plsql_declaration;      end if;
	if bitand(p_tests, c_plsql_block)            > 0 then test_plsql_block;            end if;
	if bitand(p_tests, c_package)                > 0 then test_package;                end if;
	if bitand(p_tests, c_type_body)              > 0 then test_type_body;              end if;
	if bitand(p_tests, c_trigger)                > 0 then test_trigger;                end if;
	if bitand(p_tests, c_proc_and_func)          > 0 then test_proc_and_func;          end if;
	if bitand(p_tests, c_package_body)           > 0 then test_package_body;           end if;
	if bitand(p_tests, c_sqlplus_delim)          > 0 then test_sqlplus_delim;          end if;
	if bitand(p_tests, c_sqlplus_delim_and_semi) > 0 then test_sqlplus_delim_and_semi; end if;
	if bitand(p_tests, c_metadata)               > 0 then test_metadata;               end if;

	if bitand(p_tests, c_dynamic_sql)            > 0 then test_dynamic_sql;            end if;
	if bitand(p_tests, c_dynamic_plsql)          > 0 then test_dynamic_plsql;          end if;

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
