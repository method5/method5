create or replace package statement_terminator_test authid current_user is
/*
== Purpose ==

Unit tests for statement_terminator.


== Example ==

begin
	statement_terminator_test.run;
	statement_terminator_test.run(statement_terminator_test.c_dynamic_tests);
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_semicolon          constant number := power(2, 1);
c_semicolon_errors   constant number := power(2, 2);
c_semicolon_commands constant number := power(2, 3);
c_sqlplus            constant number := power(2, 4);
c_sqlplus_and_semi   constant number := power(2, 5);

c_static_tests  constant number := c_semicolon+c_semicolon_errors+c_semicolon_commands+c_sqlplus+c_sqlplus_and_semi;

c_dynamic_tests constant number := power(2, 30);

c_all_tests constant number := c_static_tests+c_dynamic_tests;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body statement_terminator_test is
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


--------------------------------------------------------------------------------
function get_wo_semi(p_statement clob) return clob is
begin
	return plsql_lexer.concatenate(statement_terminator.remove_semicolon(p_tokens => plsql_lexer.lex(p_source => p_statement)));
end get_wo_semi;


--------------------------------------------------------------------------------
function get_wo_sqlplus(p_statement clob, p_delimiter in varchar2 default '/') return clob is
begin
	return plsql_lexer.concatenate(statement_terminator.remove_sqlplus_delimiter(
		p_tokens => plsql_lexer.lex(p_statement),
		p_sqlplus_delimiter => p_delimiter));
end get_wo_sqlplus;


--------------------------------------------------------------------------------
function get_wo_sqlplus_and_semi(p_statement clob, p_delimiter in varchar2 default '/') return clob is
begin
	return plsql_lexer.concatenate(statement_terminator.remove_sqlplus_del_and_semi(
		p_tokens => plsql_lexer.lex(p_source => p_statement),
		p_sqlplus_delimiter => p_delimiter));
end get_wo_sqlplus_and_semi;


-- =============================================================================
-- Test Suites
-- =============================================================================

--------------------------------------------------------------------------------
procedure test_semicolon is
	v_statement clob;
	v_tokens token_table;
begin
	--Simple example.
	v_statement := 'select * from dual;';
	assert_equals('Simple 1', 'select * from dual', get_wo_semi(v_statement));

	--Only remove one semicolon, not two.
	v_statement := 'select * from dual;;';
	assert_equals('Only remove one semi 1', 'select * from dual;', get_wo_semi(v_statement));

	--Smallest example.
	v_tokens := statement_terminator.remove_semicolon(plsql_lexer.lex('commit'));
	assert_equals('Small commit 1.', '2', v_tokens.count);
	v_tokens := statement_terminator.remove_semicolon(plsql_lexer.lex('commit;'));
	assert_equals('Small commit 1.', '2', v_tokens.count);

	--Null.
	v_tokens := statement_terminator.remove_semicolon(plsql_lexer.lex(null));
	assert_equals('NULL 1.', '1', v_tokens.count);
	assert_equals('NULL 2.', plsql_lexer.c_eof, v_tokens(1).type);

	--line_number, column_number, first_char_position, last_char_position.
	v_tokens := statement_terminator.remove_semicolon(plsql_lexer.lex('commit'||chr(10)||';'||chr(10)||'--asdf'));
	assert_equals('Whitespace is concatenated 1.', '4', v_tokens.count);
	assert_equals('Whitespace is concatenated 2.', plsql_lexer.c_comment, v_tokens(3).type);
	assert_equals('Whitespace is concatenated 3.', '2', lengthc(v_tokens(2).value));
	assert_equals('Line number stays the same 1.', 3, v_tokens(3).line_number);
	assert_equals('Column number 1.', 1, v_tokens(3).column_number);
	assert_equals('First char position 1.', 9, v_tokens(3).first_char_position);
	assert_equals('Last char position 1.', 14, v_tokens(3).last_char_position);

	v_tokens := statement_terminator.remove_semicolon(plsql_lexer.lex('commit;--asdf'));
	assert_equals('Column number shrinks on same line 1.', 7, v_tokens(2).column_number);
end test_semicolon;


--------------------------------------------------------------------------------
procedure test_semicolon_errors is
	v_statement clob;
begin
	v_statement := 'select * from dual;';
	assert_equals('No errors', 'select * from dual', get_wo_semi(v_statement));

	--The string should not change at all if there are significant parsing errors. 
	v_statement := '(select * from dual); /*';
	assert_equals('Comment error', v_statement, get_wo_semi(v_statement));

	v_statement := '(select * from dual); "';
	assert_equals('Missing double quote error 1', v_statement, get_wo_semi(v_statement));
	v_statement := '(select * from dual) ";';
	assert_equals('Missing double quote error 2', v_statement, get_wo_semi(v_statement));

	--These are *not* knowable lexical errors.
	--They could be valid for links so they cannot be checked at lex time.
	v_statement := '(select 1 "" from dual);';
	assert_equals('Zero-length identifier 1', '(select 1 "" from dual)', get_wo_semi(v_statement));
	v_statement := '(select 1 a123456789012345678901234567890 from dual);';
	assert_equals('Identifier too long error 1', '(select 1 a123456789012345678901234567890 from dual)', get_wo_semi(v_statement));
	v_statement := '(select 1 "a123456789012345678901234567890" from dual);';
	assert_equals('Identifier too long error 2', '(select 1 "a123456789012345678901234567890" from dual)', get_wo_semi(v_statement));

	v_statement := q'<select q'  ' from dual;>';
	assert_equals('Invalid character 1', v_statement, get_wo_semi(v_statement));

	v_statement := q'<select nq'  ' from dual;>';
	assert_equals('Invalid character 2', v_statement, get_wo_semi(v_statement));

	v_statement := '(select * from dual); '' ';
	assert_equals('String not terminated 1', v_statement, get_wo_semi(v_statement));

	v_statement := q'<(select * from dual); q'!' >';
	assert_equals('String not terminated 2', v_statement, get_wo_semi(v_statement));

	v_statement := q'<(select * from dual); q'!;' >';
	assert_equals('String not terminated 3', v_statement, get_wo_semi(v_statement));

	--Invalid
	v_statement := q'[asdf;]'; assert_equals('Invalid 1', v_statement, get_wo_semi(v_statement));
	v_statement := q'[create tableS test1(a number);]'; assert_equals('Invalid 2', v_statement, get_wo_semi(v_statement));
	v_statement := q'[seeelect * from dual;]'; assert_equals('Invalid 3', v_statement, get_wo_semi(v_statement));
	v_statement := q'[alter what_is_this set x = y;]'; assert_equals('Invalid 4', v_statement, get_wo_semi(v_statement));
	v_statement := q'[upsert my_table using other_table on (my_table.a = other_table.a) when matched then update set b = 1;]'; assert_equals('Invalid 5', v_statement, get_wo_semi(v_statement));

	--Nothing
	v_statement := q'[;]'; assert_equals('Nothing 1', v_statement, get_wo_semi(v_statement));
	v_statement := q'[ 	 ;]'; assert_equals('Nothing 2', v_statement, get_wo_semi(v_statement));
	v_statement := q'[ /* asdf */ ;]'; assert_equals('Nothing 3', v_statement, get_wo_semi(v_statement));
	v_statement := q'[; -- comment ]'; assert_equals('Nothing 4', v_statement, get_wo_semi(v_statement));
	v_statement := q'[; /* asdf ]'; assert_equals('Nothing 5', v_statement, get_wo_semi(v_statement));
end test_semicolon_errors;


--------------------------------------------------------------------------------
--NOTE: This test suite is similar in STATEMENT_CLASSIFIER_TEST, STATEMENT_FEEDBACK_TEST, and STATEMENT_TERMINATOR_TEST.
--If you add a test case here you should probably add one there as well.
procedure test_semicolon_commands is
	v_statement clob;
begin
	/*
	DDL
		ADMINISTER KEY MANAGEMENT, ALTER (except ALTER SESSION and ALTER SYSTEM),
		ANALYZE,ASSOCIATE STATISTICS,AUDIT,COMMENT,CREATE,DISASSOCIATE STATISTICS,
		DROP,FLASHBACK,GRANT,NOAUDIT,PURGE,RENAME,REVOKE,TRUNCATE
	DML
		CALL,DELETE,EXPLAIN PLAN,INSERT,LOCK TABLE,MERGE,SELECT,UPDATE
	Transaction Control
		COMMIT,ROLLBACK,SAVEPOINT,SET TRANSACTION,SET CONSTRAINT
	Session Control
		ALTER SESSION,SET ROLE
	System Control
		ALTER SYSTEM
	PL/SQL
		BLOCK
	*/

	--These tests are based on `select * from v$sqlcommand order by command_name;`,
	--and comparing syntx with the manual.
	v_statement := q'[/*comment*/ adMINister /*asdf*/ kEy manaGEment create keystore 'asdf' identified by qwer]'; assert_equals('ADMINISTER KEY MANAGEMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter assemBLY /*I don't think this is a real command but whatever*/;]'; assert_equals('ALTER ASSEMBLY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ ALTEr AUDIt POLICY myPOLICY drop roles myRole; --comment]'; assert_equals('ALTER AUDIT POLICY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[	alter	cluster	schema.my_cluster parallel 8; ]'; assert_equals('ALTER CLUSTER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter database cdb1 mount ;]'; assert_equals('ALTER DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter shared public database link my_link connect to me identified by "password";  ]'; assert_equals('ALTER DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter dimENSION my_dimension#12 compile;]'; assert_equals('ALTER DIMENSION', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Command name has extra space, real command is "DISKGROUP".ppp
	v_statement := q'[/*+useless comment*/ alter diskgroup +orcl13 resize disk '/emcpowersomething/' size 500m;]'; assert_equals('ALTER DISKGROUP', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Undocumented feature:
	v_statement := q'[ alter EDITION my_edition unusable;]'; assert_equals('ALTER EDITION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter  flashback  archive myarchive set default;]'; assert_equals('ALTER FLASHBACK ARCHIVE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER FUNCTION myschema.myfunction compile;]'; assert_equals('ALTER FUNCTION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter index asdf rebuild parallel 8;]'; assert_equals('ALTER INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER INDEXTYPE  my_schema.my_indextype compile;]'; assert_equals('ALTER INDEXTYPE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER java  source my_schema.some_object compile;]'; assert_equals('ALTER JAVA', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter library test_library editionable compile;]'; assert_equals('ALTER LIBRARY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER  MATERIALIZED  VIEW a_schema.mv_name cache consider fresh;]'; assert_equals('ALTER MATERIALIZED VIEW ', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER  SNAPSHOT a_schema.mv_name cache consider fresh;]'; assert_equals('ALTER MATERIALIZED VIEW ', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER /*a*/ MATERIALIZED /*b*/ VIEW /*c*/LOG force on my_table parallel 10;]'; assert_equals('ALTER MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER /*a*/ SNAPSHOT /*c*/LOG force on my_table parallel 10;]'; assert_equals('ALTER MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter  materialized	zonemap my_schema.my_zone enable pruning;]'; assert_equals('ALTER MATERIALIZED ZONEMAP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter operator my_operator add binding (number) return (number) using my_function;]'; assert_equals('ALTER OPERATOR', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter outline public my_outline disable;]'; assert_equals('ALTER OUTLINE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--ALTER PACKAGE gets complicated - may need to read up to 8 tokens.
	v_statement := q'[alter package test_package compile package;]'; assert_equals('ALTER PACKAGE 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile package;]'; assert_equals('ALTER PACKAGE 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package compile specification;]'; assert_equals('ALTER PACKAGE 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile specification;]'; assert_equals('ALTER PACKAGE 4', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package compile;]'; assert_equals('ALTER PACKAGE 5', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile;]'; assert_equals('ALTER PACKAGE 6', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package compile debug;]'; assert_equals('ALTER PACKAGE 7', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile debug;]'; assert_equals('ALTER PACKAGE 8', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package noneditionable;]'; assert_equals('ALTER PACKAGE 9', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package editionable;]'; assert_equals('ALTER PACKAGE 10', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package editionable;]'; assert_equals('ALTER PACKAGE 11', replace(v_statement, ';'), get_wo_semi(v_statement));

	--ALTER PACKAGE BODY is also complicated
	v_statement := q'[alter package test_package compile body;]'; assert_equals('ALTER PACKAGE BODY 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile body;]'; assert_equals('ALTER PACKAGE BODY 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package test_package compile debug body;]'; assert_equals('ALTER PACKAGE BODY 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter package jheller.test_package compile debug body;]'; assert_equals('ALTER PACKAGE BODY 4', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER PLUGGABLE DATABASE my_pdb default tablespace some_tbs;]'; assert_equals('ALTER PLUGGABLE DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER PROCEDURE my_proc compile;]'; assert_equals('ALTER PROCEDURE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ alter profile default limit password_lock_time unlimited;]'; assert_equals('ALTER PROFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER RESOURCE COST privat_sga 1000;]'; assert_equals('ALTER RESOURCE COST', replace(v_statement, ';'), get_wo_semi(v_statement));

	--I don't think this is a real command.
	--v_statement := q'[ALTER REWRITE EQUIVALENCE]'; assert_equals('ALTER REWRITE EQUIVALENCE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter role some_role# identified externally;]'; assert_equals('ALTER ROLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER ROLLBACK SEGMENT my_rbs offline;]'; assert_equals('ALTER ROLLBACK SEGMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter sequence my_seq cache 100;]'; assert_equals('ALTER SEQUENCE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter session set OPTIMIZER_DYNAMIC_SAMPLING=5;]'; assert_equals('ALTER SESSION', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ALTER SESSION set current_schema=my_schema;]'; assert_equals('ALTER SESSION', replace(v_statement, ';'), get_wo_semi(v_statement));

	--An old version of "ALTER SNAPSHOT"?  This is not supported in 11gR2+.
	--v_statement := q'[ALTER SUMMARY a_schema.mv_name cache;]'; assert_equals('ALTER SUMMARY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER /**/public/**/ SYNONYM my_synonym compile;]'; assert_equals('ALTER SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ALTER SYNONYM  my_synonym compile;]'; assert_equals('ALTER SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter system set memory_target=5m;]'; assert_equals('ALTER SYSTEM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter system reset "_stupid_hidden_parameter";]'; assert_equals('ALTER SYSTEM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ ALTER  TABLE my_schema.my_table rename to new_name;]'; assert_equals('ALTER TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER TABLESPACE some_tbs coalesce;]'; assert_equals('ALTER TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Undocumented by still runs in 12.1.0.2.
	v_statement := q'[ALTER TRACING enable;]'; assert_equals('ALTER TRACING', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[alter trigger my_schema.my_trigger enable;]'; assert_equals('ALTER TRIGGER', replace(v_statement, ';'), get_wo_semi(v_statement));

	--ALTER TYPE gets complicated - may need to read up to 8 tokens.
	v_statement := q'[alter type test_type compile type;]'; assert_equals('ALTER TYPE 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile type;]'; assert_equals('ALTER TYPE 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type compile specification;]'; assert_equals('ALTER TYPE 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile specification;]'; assert_equals('ALTER TYPE 4', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type compile;]'; assert_equals('ALTER TYPE 5', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile;]'; assert_equals('ALTER TYPE 6', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type compile debug;]'; assert_equals('ALTER TYPE 7', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile debug;]'; assert_equals('ALTER TYPE 8', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type noneditionable;]'; assert_equals('ALTER TYPE 9', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type editionable;]'; assert_equals('ALTER TYPE 10', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type editionable;]'; assert_equals('ALTER TYPE 11', replace(v_statement, ';'), get_wo_semi(v_statement));

	--ALTER TYPE BODY is also complicated
	v_statement := q'[alter type test_type compile body;]'; assert_equals('ALTER TYPE BODY 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile body;]'; assert_equals('ALTER TYPE BODY 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type test_type compile debug body;]'; assert_equals('ALTER TYPE BODY 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[alter type jheller.test_type compile debug body;]'; assert_equals('ALTER TYPE BODY 4', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER USER my_user profile default;]'; assert_equals('ALTER USER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ALTER VIEW my_schema.my_view read only;]'; assert_equals('ALTER VIEW', replace(v_statement, ';'), get_wo_semi(v_statement));

	--The syntax diagram in manual is wrong, it's "ANALYZE CLUSTER", not "CLUSTER ...".
	v_statement := q'[ ANALYZE CLUSTER my_cluster validate structure;]'; assert_equals('ANALYZE CLUSTER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ ANALYZE INDEX my_index validate structure;]'; assert_equals('ANALYZE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ ANALYZE TABLE my_table validate structure;]'; assert_equals('ANALYZE TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[associate statistics with columns my_schema.my_table using null;]'; assert_equals('ASSOCIATE STATISTICS', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[audit all on my_schema.my_table whenever not successful;]'; assert_equals('AUDIT OBJECT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[audit policy some_policy;]'; assert_equals('AUDIT OBJECT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CALL my_procedure(1,2)]'; assert_equals('CALL METHOD', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ call my_procedure(3,4);]'; assert_equals('CALL METHOD', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ call my_schema.my_type.my_method('asdf', 'qwer') into :variable;]'; assert_equals('CALL METHOD', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ call my_type(3,4).my_method() into :x;]'; assert_equals('CALL METHOD', replace(v_statement, ';'), get_wo_semi(v_statement));

	--I don't think this is a real command.
	--v_statement := q'[CHANGE PASSWORD]'; assert_equals('CHANGE PASSWORD', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[comment on audit policy my_policy is 'asdf';]'; assert_equals('COMMENT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[comment on column my_schema.my_mv is q'!as'!';]'; assert_equals('COMMENT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[comment on table some_table is 'asdfasdf';]'; assert_equals('COMMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ commit work comment 'some comment' write wait batch;]'; assert_equals('COMMIT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[COMMIT force corrupt_xid_all;]'; assert_equals('COMMIT', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Is this a real command?  http://dba.stackexchange.com/questions/96002/what-is-an-oracle-assembly/
	--Oddly this seems to work in dynamic SQL either with or without a semicolon.
	--I kept the semicolon since it seemed to be more consistent with similar commands.
	v_statement := q'[create or replace assembly some_assembly is 'some string';]'; assert_equals('CREATE ASSEMBLY', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE AUDIT POLICY my_policy actions update on oe.orders;]'; assert_equals('CREATE AUDIT POLICY', replace(v_statement, ';'), get_wo_semi(v_statement));

	--This is not a real command as far as I can tell.
	--v_statement := q'[CREATE BITMAPFILE]'; assert_equals('CREATE BITMAPFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE CLUSTER my_schema.my_cluster(a number sort);]'; assert_equals('CREATE CLUSTER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE CONTEXT my_context using my_package;]'; assert_equals('CREATE CONTEXT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or  REplace  CONTEXT my_context using my_package;]'; assert_equals('CREATE CONTEXT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE CONTROLFILE database my_db resetlogs;]'; assert_equals('CREATE CONTROL FILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE DATABASE my_database controlfile reuse;]'; assert_equals('CREATE DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]'; assert_equals('CREATE DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE shared DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]'; assert_equals('CREATE DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]'; assert_equals('CREATE DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE shared public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]'; assert_equals('CREATE DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE DIMENSION my_schema.my_dimension level l1 is t1.a;]'; assert_equals('CREATE DIMENSION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE DIRECTORY my_directory#$1 as '/load/blah/';]'; assert_equals('CREATE DIRECTORY', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace DIRECTORY my_directory#$1 as '/load/blah/';]'; assert_equals('CREATE DIRECTORY', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Command name has extra space, real command is "DISKGROUP".
	v_statement := q'[CREATE DISKGROUP my_diskgroup disk '/emc/powersomething/' size 555m;]'; assert_equals('CREATE DISK GROUP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE EDITION my_edition as child of my_parent;]'; assert_equals('CREATE EDITION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE FLASHBACK ARCHIVE default my_fba tablespace my_ts quota 5g;]'; assert_equals('CREATE FLASHBACK ARCHIVE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE FUNCTION my_schema.my_function() return number is begin return 1; end;  ]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace FUNCTION my_schema.my_function() return number is begin return 1; end; ]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable FUNCTION my_schema.my_function() return number is begin return 1; end; ]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; --comment]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable FUNCTION my_schema.my_function() return number is begin return 1; end; ]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; ]'; assert_equals('CREATE FUNCTION', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE INDEX on table1(a);]'; assert_equals('CREATE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE unique INDEX on table1(a);]'; assert_equals('CREATE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE bitmap INDEX on table1(a);]'; assert_equals('CREATE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]'; assert_equals('CREATE INDEXTYPE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]'; assert_equals('CREATE INDEXTYPE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--12 combinations of initial keywords.  COMPILE is optional here, but not elsewhere so it requires special handling.
	v_statement := q'[CREATE and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE and resolve JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE and compile JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace and resolve  JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace and compile  JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace JAVA CLASS USING BFILE (java_dir, 'Agent.class'); --]'; assert_equals('CREATE JAVA', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/'; assert_equals('CREATE LIBRARY', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE MATERIALIZED VIEW my_mv as select 1 a from dual;]'; assert_equals('CREATE MATERIALIZED VIEW ', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE SNAPSHOT my_mv as select 1 a from dual;]'; assert_equals('CREATE MATERIALIZED VIEW ', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE MATERIALIZED VIEW LOG on my_table with (a);]'; assert_equals('CREATE MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE SNAPSHOT LOG on my_table with (a);]'; assert_equals('CREATE MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE MATERIALIZED ZONEMAP sales_zmap ON sales(cust_id, prod_id);]'; assert_equals('CREATE MATERIALIZED ZONEMAP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]'; assert_equals('CREATE OPERATOR', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE OR REPLACE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]'; assert_equals('CREATE OPERATOR', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE or replace OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	--Although CREATE OUTLINE with a PLSQL_DECLARATION must end with a "/" on SQL*Plus,
	--the last semicolon must be removed when it is run as dynamic SQL. 
	v_statement := q'[create or replace outline salaries for category special on with function test_function return number is begin return 1; end; select test_function() from dual;]';
		assert_equals('CREATE OUTLINE 2', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));
	v_statement := q'[CREATE public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]'; assert_equals('CREATE OUTLINE 4', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable PACKAGE my_package is v_number number; end;]'; assert_equals('CREATE PACKAGE', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable PACKAGE BODY my_package is begin null; end;]'; assert_equals('CREATE PACKAGE BODY', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE PFILE from memory;]'; assert_equals('CREATE PFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE PLUGGABLE DATABASE my_pdb from another_pdb]'; assert_equals('CREATE PLUGGABLE DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable PROCEDURE my proc is begin null; end;]'; assert_equals('CREATE PROCEDURE', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE PROFILE my_profile limit sessions_per_user 50;]'; assert_equals('CREATE PROFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE RESTORE POINT before_change gaurantee flashback database;]'; assert_equals('CREATE RESTORE POINT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE ROLE my_role;]'; assert_equals('CREATE ROLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE ROLLBACK SEGMENT my_rbs;]'; assert_equals('CREATE ROLLBACK SEGMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE public ROLLBACK SEGMENT my_rbs;]'; assert_equals('CREATE ROLLBACK SEGMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE SCHEMA authorization my_schema grant select on table1 to user2 grant select on table2 to user3;]'; assert_equals('CREATE SCHEMA', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[create schema authorization jheller create view test_view1 as select 1 a from dual;]'; assert_equals('CREATE SCHEMA', replace(v_statement, ';'), get_wo_semi(v_statement));
	--CREATE SCHEMA and PLSQL_DECLARATION always causes ORA-600 on 12.1.0.2.
	--But I'm pretty sure the last semicolon should be removed.
	--For example, the statement in the above test only works in dynamic SQL if the semicolon is removed.
	v_statement := q'[create schema authorization jheller create view test_view1 as with function f return number is begin return 1; end; select f from dual;]'; assert_equals('CREATE SCHEMA', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	--Undocumented feature.
	v_statement := q'[CREATE SCHEMA SYNONYM demo2 for demo1;]'; assert_equals('CREATE SCHEMA SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE SEQUENCE my_schema.my_sequence cache 20;]'; assert_equals('CREATE SEQUENCE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE SPFILE = 'my_spfile' from pfile;]'; assert_equals('CREATE SPFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--An old version of "CREATE SNAPSHOT"?  This is not supported in 11gR2+.
	--v_statement := q'[CREATE SUMMARY]'; assert_equals('CREATE SUMMARY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]'; assert_equals('CREATE SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE TABLE my_table(a number);]'; assert_equals('CREATE TABLE 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	--Must remove last semicolon even with PLSQL_DECLARATION or else it will throw ORA-600.
	v_statement := q'[create table test1 as with function f return number is begin return 1; end; select f from dual;]'; assert_equals('CREATE TABLE 2', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	v_statement := q'[CREATE global temporary TABLE my_table(a number);]'; assert_equals('CREATE TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE temporary TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE temporary bigfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE temporary smallfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE undo TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE undo bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE undo smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]'; assert_equals('CREATE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Simple triggers, keep semicolon.
	v_statement := q'[CREATE TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable TRIGGER my_trigger before insert on my_table begin null; end;]'; assert_equals('CREATE TRIGGER', v_statement, get_wo_semi(v_statement));
	--Compound triggers, keep semicolon.
	v_statement := q'[
		create or replace trigger test1_trigger2
		for update of a on test1
		compound trigger
			test_variable number;
			procedure nested_procedure is begin null; end nested_procedure;
			before statement is begin null; end before statement;
			before each row is begin null; end before each row;
			after statement is begin null; end after statement;
			after each row is begin null; end after each row;
		end test1_trigger2;]';
	 assert_equals('CREATE TRIGGER - COMPOUND', v_statement, get_wo_semi(v_statement));
	--CALL trigger, remove semicolon.
	v_statement := q'[create or replace trigger test1_trigger1 before delete on test1 for each row call test_procedure;]'; assert_equals('CREATE TRIGGER - CALL', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable TYPE my_type as object(a number);]'; assert_equals('CREATE TYPE', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]'; assert_equals('CREATE TYPE BODY', v_statement, get_wo_semi(v_statement));

	v_statement := q'[CREATE USER my_user identified by "asdf";]'; assert_equals('CREATE USER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[CREATE VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 4', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 5', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE force VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 6', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE force editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 7', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE force editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 8', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE force editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 9', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE force noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 10', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE no force VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 11', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE no force editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 12', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE no force editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 13', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE no force editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 14', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE no force noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 15', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 16', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 17', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 18', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 19', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 20', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace force VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 21', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace force editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 22', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace force editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 23', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace force editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 24', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace force noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 25', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace no force VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 26', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace no force editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 27', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace no force editionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 28', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace no force editionable editioning VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 29', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[CREATE or replace no force noneditionable VIEW my_view as select 1 a from dual;]'; assert_equals('CREATE VIEW 30', replace(v_statement, ';'), get_wo_semi(v_statement));
	--Must remove last semicolon on PLSQL_DECLARATION or an ORA-600 error is generated.
	v_statement := q'[create or replace view test_view as with function f return number is begin return 1; end; select f from dual;]'; assert_equals('CREATE VIEW 30', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	--Not a real command.
	--v_statement := q'[DECLARE REWRITE EQUIVALENCE]'; assert_equals('DECLARE REWRITE EQUIVALENCE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DELETE my_schema.my_table@my_link;]'; assert_equals('DELETE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[DELETE FROM my_schema.my_table@my_link;]'; assert_equals('DELETE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[delete from test1 where a in (with function f return number is begin return 1; end; select f from dual);]'; assert_equals('DELETE', replace(v_statement, 'dual);', 'dual)'), get_wo_semi(v_statement));

	v_statement := q'[DISASSOCIATE STATISTICS from columns mytable.a force;]'; assert_equals('DISASSOCIATE STATISTICS', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP ASSEMBLY my_assembly;]'; assert_equals('DROP ASSEMBLY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP AUDIT POLICY my_policy;]'; assert_equals('DROP AUDIT POLICY', replace(v_statement, ';'), get_wo_semi(v_statement));

	--This isn't a real command as far as I can tell.
	--v_statement := q'[DROP BITMAPFILE]'; assert_equals('DROP BITMAPFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP CLUSTER my_cluster;]'; assert_equals('DROP CLUSTER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP CONTEXT my_context;]'; assert_equals('DROP CONTEXT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP DATABASE;]'; assert_equals('DROP DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP DATABASE LINK my_link;]'; assert_equals('DROP DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[DROP public DATABASE LINK my_link;]'; assert_equals('DROP DATABASE LINK', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP DIMENSION my_dimenson;]'; assert_equals('DROP DIMENSION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP DIRECTORY my_directory;]'; assert_equals('DROP DIRECTORY', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Command name has extra space, real command is "DISKGROUP".
	v_statement := q'[DROP DISKGROUP fradg force including contents;]'; assert_equals('DROP DISK GROUP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP EDITION my_edition cascade;]'; assert_equals('DROP EDITION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP FLASHBACK ARCHIVE my_fba;]'; assert_equals('DROP FLASHBACK ARCHIVE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP FUNCTION my_schema.my_function;]'; assert_equals('DROP FUNCTION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP INDEX my_schema.my_index online force;]'; assert_equals('DROP INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP INDEXTYPE my_indextype force;]'; assert_equals('DROP INDEXTYPE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP JAVA resourse some_resource;]'; assert_equals('DROP JAVA', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP LIBRARY my_library;]'; assert_equals('DROP LIBRARY', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Commands have an extra space in them.
	v_statement := q'[DROP MATERIALIZED VIEW my_mv preserve table;]'; assert_equals('DROP MATERIALIZED VIEW', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[DROP SNAPSHOT my_mv preserve table;]'; assert_equals('DROP MATERIALIZED VIEW', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP MATERIALIZED VIEW LOG on some_table;]'; assert_equals('DROP MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[DROP snapshot LOG on some_table;]'; assert_equals('DROP MATERIALIZED VIEW LOG', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP MATERIALIZED ZONEMAP my_schema.my_zonemap;]'; assert_equals('DROP MATERIALIZED ZONEMAP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP OPERATOR my_operator force;]'; assert_equals('DROP OPERATOR', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP OUTLINE my_outline;]'; assert_equals('DROP OUTLINE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP PACKAGE my_package;]'; assert_equals('DROP PACKAGE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP PACKAGE BODY my_package;]'; assert_equals('DROP PACKAGE BODY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP PLUGGABLE DATABASE my_pdb;]'; assert_equals('DROP PLUGGABLE DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP PROCEDURE my_proc;]'; assert_equals('DROP PROCEDURE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP PROFILE my_profile cascade;]'; assert_equals('DROP PROFILE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP RESTORE POINT my_restore_point;]'; assert_equals('DROP RESTORE POINT', replace(v_statement, ';'), get_wo_semi(v_statement));

	--This is not a real command.
	--v_statement := q'[DROP REWRITE EQUIVALENCE]'; assert_equals('DROP REWRITE EQUIVALENCE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP ROLE my_role;]'; assert_equals('DROP ROLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP ROLLBACK SEGMENT my_rbs;]'; assert_equals('DROP ROLLBACK SEGMENT', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Undocumented feature.
	v_statement := q'[DROP SCHEMA SYNONYM a_schema_synonym;]'; assert_equals('DROP SCHEMA SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP SEQUENCE my_sequence;]'; assert_equals('DROP SEQUENCE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--An old version of "DROP SNAPSHOT"?  This is not supported in 11gR2+.
	--v_statement := q'[DROP SUMMARY]'; assert_equals('DROP SUMMARY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP SYNONYM my_synonym;]'; assert_equals('DROP SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[DROP public SYNONYM my_synonym;]'; assert_equals('DROP SYNONYM', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP TABLE my_schema.my_table cascade constraints purge;]'; assert_equals('DROP TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP TABLESPACE my_tbs including contents and datafiles cascade constraints;]'; assert_equals('DROP TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP TRIGGER my_trigger;]'; assert_equals('DROP TRIGGER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP TYPE my_type validate;]'; assert_equals('DROP TYPE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP TYPE BODY my_type;]'; assert_equals('DROP TYPE BODY', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP USER my_user cascde;]'; assert_equals('DROP USER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[DROP VIEW my_schema.my_view cascade constraints;]'; assert_equals('DROP VIEW', replace(v_statement, ';'), get_wo_semi(v_statement));

	--v_statement := q'[Do not use 184]'; assert_equals('Do not use 184', replace(v_statement, ';'), get_wo_semi(v_statement));
	--v_statement := q'[Do not use 185]'; assert_equals('Do not use 185', replace(v_statement, ';'), get_wo_semi(v_statement));
	--v_statement := q'[Do not use 186]'; assert_equals('Do not use 186', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[EXPLAIN plan set statement_id='asdf' for select * from dual]'; assert_equals('EXPLAIN 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[explain plan for with function f return number is begin return 1; end; select f from dual;]'; assert_equals('EXPLAIN 2', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	v_statement := q'[FLASHBACK DATABASE to restore point my_restore_point]'; assert_equals('FLASHBACK DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[FLASHBACK standby DATABASE to restore point my_restore_point;]'; assert_equals('FLASHBACK DATABASE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[FLASHBACK TABLE my_schema.my_table to timestamp timestamp '2015-01-01 12:00:00';]'; assert_equals('FLASHBACK TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[GRANT dba my_user;]'; assert_equals('GRANT OBJECT 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[GRANT select on my_table to some_other_user with grant option;]'; assert_equals('GRANT OBJECT 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[GRANT dba to my_package;]'; assert_equals('GRANT OBJECT 3', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[INSERT /*+ append */ into my_table select * from other_table;]'; assert_equals('INSERT 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[INSERT all into table1(a) values(b) into table2(a) values(b) select b from another_table;]'; assert_equals('INSERT 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[insert into test1 with function f return number is begin return 1; end; select f from dual;]'; assert_equals('INSERT 3', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	v_statement := q'[LOCK TABLE my_schema.my_table in exclsive mode;]'; assert_equals('LOCK TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--See "UPSERT" for "MERGE".
	--v_statement := q'[NO-OP]'; assert_equals('NO-OP', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[NOAUDIT insert any table;]'; assert_equals('NOAUDIT OBJECT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[NOAUDIT policy my_policy by some_user;]'; assert_equals('NOAUDIT OBJECT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ <<my_label>>begin null; end;]'; assert_equals('PL/SQL EXECUTE 1', v_statement, get_wo_semi(v_statement));
	v_statement := q'[/*asdf*/declare v_test number; begin null; end;]'; assert_equals('PL/SQL EXECUTE 2', v_statement, get_wo_semi(v_statement));
	v_statement := q'[  begin null; end;]'; assert_equals('PL/SQL EXECUTE 3', v_statement, get_wo_semi(v_statement));

	--Command name has space instead of underscore.
 	v_statement := q'[PURGE DBA_RECYCLEBIN;]'; assert_equals('PURGE DBA RECYCLEBIN', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[PURGE INDEX my_index;]'; assert_equals('PURGE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[PURGE TABLE my_table;]'; assert_equals('PURGE TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[PURGE TABLESPACE my_tbs user my_user;]'; assert_equals('PURGE TABLESPACE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Command name has extra "USER".
	v_statement := q'[PURGE RECYCLEBIN;]'; assert_equals('PURGE USER RECYCLEBIN', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[RENAME old_table to new_table;]'; assert_equals('RENAME', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[REVOKE select any table from my_user;]'; assert_equals('REVOKE OBJECT 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[REVOKE select on my_tables from user2;]'; assert_equals('REVOKE OBJECT 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[REVOKE dba from my_package;]'; assert_equals('REVOKE OBJECT 3', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[ROLLBACK;]'; assert_equals('ROLLBACK 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ROLLBACK work;]'; assert_equals('ROLLBACK 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[ROLLBACK to savepoint savepoint1;]'; assert_equals('ROLLBACK 3', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[SAVEPOINT my_savepoint;]'; assert_equals('SAVEPOINT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[select * from dual;]'; assert_equals('SELECT 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[/*asdf*/select * from dual;]'; assert_equals('SELECT 2', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[((((select * from dual))));]'; assert_equals('SELECT 3', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[with test1 as (select 1 a from dual) select * from test1;]'; assert_equals('SELECT 4', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[with function test_function return number is begin return 1; end; select test_function from dual;]'; assert_equals('SELECT 4', replace(v_statement, 'dual;', 'dual'), get_wo_semi(v_statement));

	--There are two versions of CONSTRAINT[S].
	v_statement := q'[SET CONSTRAINTS all deferred;]'; assert_equals('SET CONSTRAINT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[SET CONSTRAINT all immediate;]'; assert_equals('SET CONSTRAINT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[SET ROLE none;]'; assert_equals('SET ROLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[SET TRANSACTION read only;]'; assert_equals('SET TRANSACTION', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[TRUNCATE CLUSTER my_schema.my_cluster drop storage;]'; assert_equals('TRUNCATE CLUSTER', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[TRUNCATE TABLE my_schema.my_table purge materialized view log;]'; assert_equals('TRUNCATE TABLE', replace(v_statement, ';'), get_wo_semi(v_statement));

	--Not a real command.
	--v_statement := q'[UNDROP OBJECT]'; assert_equals('UNDROP OBJECT', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[UPDATE my_tables set a = 1;]'; assert_equals('UPDATE 1', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[UPDATE my_tables set a = (with function f return number is begin return 1; end; select f from dual);]'; assert_equals('UPDATE 2', replace(v_statement, 'dual);', 'dual)'), get_wo_semi(v_statement));

	--These are not real commands (they are part of alter table) and they could be ambiguous with an UPDATE statement
	--if there was a table named "INDEXES" or "JOIN".
	--v_statement := q'[UPDATE INDEXES]'; assert_equals('UPDATE INDEXES', replace(v_statement, ';'), get_wo_semi(v_statement));
	--v_statement := q'[UPDATE JOIN INDEX]'; assert_equals('UPDATE JOIN INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

	v_statement := q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = 1;]'; assert_equals('UPSERT', replace(v_statement, ';'), get_wo_semi(v_statement));
	v_statement := q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = (with function test_function return number is begin return 1; end; select test_function from dual);]'; assert_equals('UPSERT', replace(v_statement, 'dual);', 'dual)'), get_wo_semi(v_statement));

	--Not a real command, this is part of ANALYZE.
	--v_statement := q'[VALIDATE INDEX]'; assert_equals('VALIDATE INDEX', replace(v_statement, ';'), get_wo_semi(v_statement));

end test_semicolon_commands;


--------------------------------------------------------------------------------
procedure test_sqlplus is
	v_statement clob;
begin
	--Simple.
	v_statement := 'select * from dual'||chr(10)||'/';
	assert_equals('Simple 1', 'select * from dual'||chr(10), get_wo_sqlplus(v_statement));

	--Ignore whitespace around slash.
	v_statement := 'select * from dual'||chr(10)||' / ';
	assert_equals('Ignore whitespace around slash 1', 'select * from dual'||chr(10)||'  ', get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||chr(10)||chr(10)||' / ';
	assert_equals('Ignore whitespace around slash 2', 'select * from dual'||chr(10)||chr(10)||chr(10)||'  ', get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||'		 / 		';
	assert_equals('Ignore whitespace around slash 3', 'select * from dual'||chr(10)||'		  		', get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||chr(13)||' / ';
	assert_equals('Ignore whitespace around slash 4', 'select * from dual'||chr(10)||chr(13)||'  ', get_wo_sqlplus(v_statement));

	--Ignore slash if there's non-whitespace.
	v_statement := 'select * from dual'||chr(10)||' / --asdf';
	assert_equals('Ignore if non-whitespace on line 1', v_statement, get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||'a /';
	assert_equals('Ignore if non-whitespace on line 2', v_statement, get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||' / /*comment*/';
	assert_equals('Ignore if non-whitespace on line 3', v_statement, get_wo_sqlplus(v_statement));
	v_statement := 'select * from dual'||chr(10)||'/*comment*/ / ';
	assert_equals('Ignore if non-whitespace on line 4', v_statement, get_wo_sqlplus(v_statement));

	--Remove slash if there's a comment on the *next* line.
	v_statement := 'select * from dual'||chr(10)||' /'||chr(10)||'/*asdf*/';
	assert_equals('Remove slash if comment on next line', 'select * from dual'||chr(10)||' '||chr(10)||'/*asdf*/', get_wo_sqlplus(v_statement));

	--Double slashes are not removed.
	v_statement := 'select * from dual'||chr(10)||'//';
	assert_equals('Double slashes are not removed', v_statement, get_wo_sqlplus(v_statement));

	--Always remove the slash, regardless of the command type, even for garbage.
	v_statement := 'asdf'||chr(10)||'/';
	assert_equals('Remove slash regardless of command 1', 'asdf'||chr(10), get_wo_sqlplus(v_statement));
	v_statement := ' / ';
	assert_equals('Remove slash regardless of command 2', '  ', get_wo_sqlplus(v_statement));
	v_statement := '/';
	assert_equals('Remove slash regardless of command 3', '', get_wo_sqlplus(v_statement));

	--Nothing should return nothing.
	v_statement := '';
	assert_equals('Nothing 1', '', get_wo_sqlplus(v_statement));

	--Test multi-character delimiter.
	v_statement := 'select * from dual'||chr(10)||'//';
	assert_equals('Simple 1', 'select * from dual'||chr(10), get_wo_sqlplus(v_statement, '//'));
	v_statement := 'select * from dual'||chr(10)||'reallyLongDelimiterWhyWouldAnyoneDoThis?';
	assert_equals('Simple 1', 'select * from dual'||chr(10), get_wo_sqlplus(v_statement, 'reallyLongDelimiterWhyWouldAnyoneDoThis?'));

	--Test UTF8 characters delimiter.
	v_statement := 'select * from dual'||chr(10)||unistr('\d841\df79');
	assert_equals('Simple 1', 'select * from dual'||chr(10), get_wo_sqlplus(v_statement, unistr('\d841\df79')));

	--TODO: Test line_number, column_number, first_char_position, and last_char_position.
end test_sqlplus;


--------------------------------------------------------------------------------
procedure test_sqlplus_and_semi is
	v_statement clob;
begin
	--Simple.
	v_statement := 'select * from dual;'||chr(10)||'/';
	assert_equals('Simple 1', 'select * from dual'||chr(10), get_wo_sqlplus_and_semi(v_statement));

	--TODO: Add more here.

	--TODO: Test line_number, column_number, first_char_position, and last_char_position.
end test_sqlplus_and_semi;


--------------------------------------------------------------------------------
procedure dynamic_tests is
	type clob_table is table of clob;
	type string_table is table of varchar2(100);
	v_sql_ids string_table;
	v_sql_fulltexts clob_table;
	sql_cursor sys_refcursor;
begin
	--Test everything in GV$SQL.
	open sql_cursor for
	q'<
		--Only need to select one value per SQL_ID.
		select sql_id, sql_fulltext
		from
		(
			select sql_id, sql_fulltext, row_number() over (partition by sql_id order by 1) rownumber
			from gv$sql
		)
		where rownumber = 1
		order by sql_id
	>';

	loop
		fetch sql_cursor bulk collect into v_sql_ids, v_sql_fulltexts limit 100;
		exit when v_sql_fulltexts.count = 0;

		--Debug if there is an infinite loop.
		--dbms_output.put_line('SQL_ID: '||statements.sql_id);

		--Nothing in GV$SQL should have an extra semicolon.
		for i in 1 .. v_sql_fulltexts.count loop

			g_test_count := g_test_count + 1;

			if v_sql_fulltexts(i) = plsql_lexer.concatenate(statement_terminator.remove_semicolon(plsql_lexer.lex(v_sql_fulltexts(i)))) then
				g_passed_count := g_passed_count + 1;
			else
				g_failed_count := g_failed_count + 1;
				dbms_output.put_line('Failed: '||v_sql_ids(i));
			end if;
		end loop;
	end loop;
end dynamic_tests;



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
	dbms_output.put_line('PL/SQL Statement Terminator Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_semicolon)          > 0 then test_semicolon; end if;
	if bitand(p_tests, c_semicolon_errors)   > 0 then test_semicolon_errors; end if;
	if bitand(p_tests, c_semicolon_commands) > 0 then test_semicolon_commands; end if;
	if bitand(p_tests, c_sqlplus)            > 0 then test_sqlplus; end if;
	if bitand(p_tests, c_sqlplus_and_semi)   > 0 then test_sqlplus_and_semi; end if;
	if bitand(p_tests, c_dynamic_tests)      > 0 then dynamic_tests; end if;

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
