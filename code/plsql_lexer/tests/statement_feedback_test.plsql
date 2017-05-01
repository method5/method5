create or replace package statement_feedback_test authid current_user is
/*
== Purpose ==

Unit tests for statement_feedback.


== Example ==

begin
	statement_feedback_test.run;
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_errors                  constant number := power(2, 1);
c_commands                constant number := power(2, 2);
c_command_name_api        constant number := power(2, 3);

c_static_tests  constant number := c_errors+c_commands+c_command_name_api;

c_all_tests constant number := c_static_tests;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body statement_feedback_test is
pragma serially_reusable;

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--Global types
type output_rec is record
(
	category varchar2(100),
	statement_type varchar2(100),
	command_name varchar2(64),
	command_type number,
	lex_sqlcode number,
	lex_sqlerrm varchar2(4000),
	fatal_error varchar2(4000)
);


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
procedure classify(p_statement clob, p_output out output_rec, p_start_index in number default 1) is
	v_category varchar2(100);
	v_statement_type varchar2(100);
	v_command_name varchar2(64);
	v_command_type number;
	v_lex_sqlcode number;
	v_lex_sqlerrm varchar2(4000);
begin
	statement_classifier.classify(plsql_lexer.lex(p_statement),
		v_category,v_statement_type,v_command_name,v_command_type,v_lex_sqlcode,v_lex_sqlerrm,p_start_index);

	p_output.category := v_category;
	p_output.statement_type := v_statement_type;
	p_output.command_name := v_command_name;
	p_output.command_type := v_command_type;
	p_output.lex_sqlcode := v_lex_sqlcode;
	p_output.lex_sqlerrm := v_lex_sqlerrm;
	p_output.fatal_error := null;
exception when others then
	p_output.fatal_error := dbms_utility.format_error_stack||dbms_utility.format_error_backtrace;
end classify;


--------------------------------------------------------------------------------
procedure feedback(p_statement clob, p_success out varchar2, p_warning out varchar2, p_rowcount in number default null) is
begin
	statement_feedback.get_feedback_message(
		p_tokens => plsql_lexer.lex(p_statement),
		p_rowcount => p_rowcount,
		p_success_message => p_success,
		p_compile_warning_message => p_warning
	);
end feedback;


--------------------------------------------------------------------------------
procedure feedback_command_name(p_command_name varchar2, p_success out varchar2, p_warning out varchar2, p_rowcount in number default null) is
begin
	statement_feedback.get_feedback_message(
		p_command_name => p_command_name,
		p_rowcount => p_rowcount,
		p_success_message => p_success,
		p_compile_warning_message => p_warning
	);
end feedback_command_name;


-- =============================================================================
-- Test Suites
-- =============================================================================

--------------------------------------------------------------------------------
procedure test_errors is
	v_success varchar2(32767);
	v_warning varchar2(32767);
begin
	--Huge syntax errors but it's still obvious what the statement is.
	feedback(q'[(select * from dual) /*]', v_success, v_warning, 10); assert_equals('Bad SELECT 1', '10 rows selected.|', v_success||'|'||v_warning);
	feedback(q'[(select * from dual) " ]', v_success, v_warning, 20); assert_equals('Bad SELECT 2', '20 rows selected.|', v_success||'|'||v_warning);
	feedback(q'[(select * from dual) ' ]', v_success, v_warning, 30); assert_equals('Bad SELECT 2', '30 rows selected.|', v_success||'|'||v_warning);

	--Completely invalid syntax, no way to even guess at the intent.
	feedback(q'[asdf]', v_success, v_warning); assert_equals('Invalid 1', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[asdf]', v_success, v_warning, 10); assert_equals('Invalid 2', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[asdf]', v_success, v_warning); assert_equals('Invalid 3', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[create tableS test1(a number);]', v_success, v_warning); assert_equals('Invalid 4', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[seeelect * from dual]', v_success, v_warning); assert_equals('Invalid 5', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[alter what_is_this set x = y;]', v_success, v_warning); assert_equals('Invalid 6', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[upsert my_table using other_table on (my_table.a = other_table.a) when matched then update set b = 1]', v_success, v_warning); assert_equals('Invalid 7', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);

	--Nothing.
	feedback(q'[]', v_success, v_warning); assert_equals('Nothing 1', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[ /* asdf */-- ]', v_success, v_warning); assert_equals('Nothing 2', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[ -- comment ]', v_success, v_warning); assert_equals('Nothing 3', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
	feedback(q'[ /* asdf ]', v_success, v_warning); assert_equals('Nothing 4', 'ERROR: Cannot determine statement type.|', v_success||'|'||v_warning);
end test_errors;


--------------------------------------------------------------------------------
--NOTE: This test suite is similar in STATEMENT_CLASSIFIER_TEST, STATEMENT_FEEDBACK_TEST, and STATEMENT_TERMINATOR_TEST.
--If you add a test case here you should probably add one there as well.
procedure test_commands is
	v_success varchar2(32767);
	v_warning varchar2(32767);
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
	--The results come from running commands in SQL*Plus.
	feedback(q'[/*comment*/ adMINister /*asdf*/ kEy manaGEment create keystore 'asdf' identified by qwer]', v_success, v_warning); assert_equals('ADMINISTER KEY MANAGEMENT', 'keystore altered.|', v_success||'|'||v_warning);

	feedback(q'[ alter analytic view emp_sales_av compile;]', v_success, v_warning); assert_equals('ALTER ANALYTIC VIEW', 'Analytic view altered.|Warning: Analytic view altered with compilation errors.', v_success||'|'||v_warning);

	--I can't find a single real "alter assembly" command on Google so I'm guessing at the success message.
	--It's possible to create the warning with "alter assembly some_assembly compile;".
	feedback(q'[ alter assemBLY /*I don't think this is a real command but whatever*/]', v_success, v_warning); assert_equals('ALTER ASSEMBLY', 'Assembly altered.|Warning: Assembly altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ alter attribute dimension mydim compile;]', v_success, v_warning); assert_equals('ALTER ATTRIBUTE DIMENSION', 'Attribute dimension altered.|Warning: Attribute dimension altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ ALTEr AUDIt POLICY myPOLICY drop roles myRole; --comment]', v_success, v_warning); assert_equals('ALTER AUDIT POLICY', 'Audit policy altered.|', v_success||'|'||v_warning);

	feedback(q'[	alter	cluster	schema.my_cluster parallel 8]', v_success, v_warning); assert_equals('ALTER CLUSTER', 'Cluster altered.|', v_success||'|'||v_warning);

	feedback(q'[alter database cdb1 mount]', v_success, v_warning); assert_equals('ALTER DATABASE', 'Database altered.|', v_success||'|'||v_warning);

	feedback(q'[alter shared public database link my_link connect to me identified by "password";]', v_success, v_warning); assert_equals('ALTER DATABASE LINK', 'Database link altered.|', v_success||'|'||v_warning);

	feedback(q'[ alter dimENSION my_dimension#12 compile;]', v_success, v_warning); assert_equals('ALTER DIMENSION', 'Dimension altered.|Warning: Dimension altered with compilation errors.', v_success||'|'||v_warning);

	--Command name has extra space, real command is "DISKGROUP".
	feedback(q'[/*+useless comment*/ alter diskgroup +orcl13 resize disk '/emcpowersomething/' size 500m;]', v_success, v_warning); assert_equals('ALTER DISKGROUP', 'Diskgroup altered.|', v_success||'|'||v_warning);

	--Undocumented feature, the feedback message is a guess.
	feedback(q'[ alter EDITION my_edition unusable]', v_success, v_warning); assert_equals('ALTER EDITION', 'Edition altered.|', v_success||'|'||v_warning);

	feedback(q'[ alter  flashback  archive myarchive set default;]', v_success, v_warning); assert_equals('ALTER FLASHBACK ARCHIVE', 'Flashback archive altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER FUNCTION myschema.myfunction compile;]', v_success, v_warning); assert_equals('ALTER FUNCTION', 'Function altered.|Warning: Function altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[alter hierarchy myhieararchy compile;]', v_success, v_warning); assert_equals('ALTER HIERARCHY', 'Hierarchy altered.|Warning: Hierarchy altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ alter index asdf rebuild parallel 8]', v_success, v_warning); assert_equals('ALTER INDEX', 'Index altered.|', v_success||'|'||v_warning);

	feedback(q'[ ALTER INMEMORY JOIN GROUP imjg add (test1(b));]', v_success, v_warning); assert_equals('ALTER INMEMORY JOIN GROUP', 'Join group altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER INDEXTYPE  my_schema.my_indextype compile;]', v_success, v_warning); assert_equals('ALTER INDEXTYPE', 'Indextype altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER java  source my_schema.some_object compile;]', v_success, v_warning); assert_equals('ALTER JAVA', 'Java altered.|Warning: Java altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[alter library test_library editionable compile;]', v_success, v_warning); assert_equals('ALTER LIBRARY', 'Library altered.|Warning: Library altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ALTER LOCKDOWN PROFILE compile;]', v_success, v_warning); assert_equals('ALTER LOCKDOWN PROFILE', 'Lockdown Profile altered.|', v_success||'|'||v_warning);

	--Unlike most ALTERS with a COMPILE option, MATERIALIZED VIEWS will not display a warning if it is invalid.
	feedback(q'[ALTER  MATERIALIZED  VIEW a_schema.mv_name cache consider fresh;]', v_success, v_warning); assert_equals('ALTER MATERIALIZED VIEW ', 'Materialized view altered.|', v_success||'|'||v_warning);
	feedback(q'[ALTER  SNAPSHOT a_schema.mv_name cache consider fresh;]', v_success, v_warning); assert_equals('ALTER MATERIALIZED VIEW ', 'Materialized view altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER /*a*/ MATERIALIZED /*b*/ VIEW /*c*/LOG force on my_table parallel 10]', v_success, v_warning); assert_equals('ALTER MATERIALIZED VIEW LOG', 'Materialized view log altered.|', v_success||'|'||v_warning);
	feedback(q'[ALTER /*a*/ SNAPSHOT /*c*/LOG force on my_table parallel 10]', v_success, v_warning); assert_equals('ALTER MATERIALIZED VIEW LOG', 'Materialized view log altered.|', v_success||'|'||v_warning);

	feedback(q'[ alter  materialized	zonemap my_schema.my_zone enable pruning]', v_success, v_warning); assert_equals('ALTER MATERIALIZED ZONEMAP', 'Materialized zonemap altered.|', v_success||'|'||v_warning);

	feedback(q'[alter operator my_operator add binding (number) return (number) using my_function]', v_success, v_warning); assert_equals('ALTER OPERATOR', 'Operator altered.|', v_success||'|'||v_warning);

	feedback(q'[alter outline public my_outline disable;]', v_success, v_warning); assert_equals('ALTER OUTLINE', 'Outline altered.|', v_success||'|'||v_warning);

	--ALTER PACKAGE gets complicated - may need to read up to 8 tokens.
	feedback(q'[alter package test_package compile package]', v_success, v_warning); assert_equals('ALTER PACKAGE 1', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile package]', v_success, v_warning); assert_equals('ALTER PACKAGE 2', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package compile specification]', v_success, v_warning); assert_equals('ALTER PACKAGE 3', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile specification]', v_success, v_warning); assert_equals('ALTER PACKAGE 4', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package compile]', v_success, v_warning); assert_equals('ALTER PACKAGE 5', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile]', v_success, v_warning); assert_equals('ALTER PACKAGE 6', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package compile debug]', v_success, v_warning); assert_equals('ALTER PACKAGE 7', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile debug]', v_success, v_warning); assert_equals('ALTER PACKAGE 8', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package noneditionable]', v_success, v_warning); assert_equals('ALTER PACKAGE 9', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package editionable]', v_success, v_warning); assert_equals('ALTER PACKAGE 10', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package editionable]', v_success, v_warning); assert_equals('ALTER PACKAGE 11', 'Package altered.|Warning: Package altered with compilation errors.', v_success||'|'||v_warning);

	--ALTER PACKAGE BODY is also complicated
	feedback(q'[alter package test_package compile body]', v_success, v_warning); assert_equals('ALTER PACKAGE BODY 1', 'Package body altered.|Warning: Package Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile body]', v_success, v_warning); assert_equals('ALTER PACKAGE BODY 2', 'Package body altered.|Warning: Package Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package test_package compile debug body]', v_success, v_warning); assert_equals('ALTER PACKAGE BODY 3', 'Package body altered.|Warning: Package Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter package jheller.test_package compile debug body]', v_success, v_warning); assert_equals('ALTER PACKAGE BODY 4', 'Package body altered.|Warning: Package Body altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ALTER PLUGGABLE DATABASE my_pdb default tablespace some_tbs]', v_success, v_warning); assert_equals('ALTER PLUGGABLE DATABASE', 'Pluggable database altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER PROCEDURE my_proc compile]', v_success, v_warning); assert_equals('ALTER PROCEDURE', 'Procedure altered.|Warning: Procedure altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ alter profile default limit password_lock_time unlimited;]', v_success, v_warning); assert_equals('ALTER PROFILE', 'Profile altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER RESOURCE COST private_sga 1000;]', v_success, v_warning); assert_equals('ALTER RESOURCE COST', 'Resource cost altered.|', v_success||'|'||v_warning);

	--I don't think this is a real command.
	--feedback(q'[ALTER REWRITE EQUIVALENCE]', v_success, v_warning); assert_equals('ALTER REWRITE EQUIVALENCE', '|', v_success||'|'||v_warning);

	feedback(q'[alter role some_role# identified externally]', v_success, v_warning); assert_equals('ALTER ROLE', 'Role altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER ROLLBACK SEGMENT my_rbs offline]', v_success, v_warning); assert_equals('ALTER ROLLBACK SEGMENT', 'Rollback segment altered.|', v_success||'|'||v_warning);

	feedback(q'[alter sequence my_seq cache 100]', v_success, v_warning); assert_equals('ALTER SEQUENCE', 'Sequence altered.|', v_success||'|'||v_warning);

	feedback(q'[alter session set OPTIMIZER_DYNAMIC_SAMPLING=5;]', v_success, v_warning); assert_equals('ALTER SESSION', 'Session altered.|', v_success||'|'||v_warning);
	feedback(q'[ALTER SESSION set current_schema=my_schema]', v_success, v_warning); assert_equals('ALTER SESSION', 'Session altered.|', v_success||'|'||v_warning);

	--An old version of "ALTER SNAPSHOT"?  This is not supported in 11gR2+.
	--feedback(q'[ALTER SUMMARY a_schema.mv_name cache;]', v_success, v_warning); assert_equals('ALTER SUMMARY', '|', v_success||'|'||v_warning);

	feedback(q'[ALTER /**/public/**/ SYNONYM my_synonym compile]', v_success, v_warning); assert_equals('ALTER SYNONYM', 'Synonym altered.|', v_success||'|'||v_warning);
	feedback(q'[ALTER SYNONYM  my_synonym compile]', v_success, v_warning); assert_equals('ALTER SYNONYM', 'Synonym altered.|', v_success||'|'||v_warning);

	feedback(q'[alter system set memory_target=5m]', v_success, v_warning); assert_equals('ALTER SYSTEM', 'System altered.|', v_success||'|'||v_warning);
	feedback(q'[alter system reset "_stupid_hidden_parameter"]', v_success, v_warning); assert_equals('ALTER SYSTEM', 'System altered.|', v_success||'|'||v_warning);

	feedback(q'[ ALTER  TABLE my_schema.my_table rename to new_name;]', v_success, v_warning); assert_equals('ALTER TABLE', 'Table altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER TABLESPACE some_tbs coalesce]', v_success, v_warning); assert_equals('ALTER TABLESPACE', 'Tablespace altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER TABLESPACE SET my_set begin backup]', v_success, v_warning); assert_equals('ALTER TABLESPACE SET', 'Tablespace altered.|', v_success||'|'||v_warning);

	--Undocumented by still runs in 12.1.0.2.
	feedback(q'[ALTER TRACING enable;]', v_success, v_warning); assert_equals('ALTER TRACING', 'Tracing altered.|', v_success||'|'||v_warning);

	feedback(q'[alter trigger my_schema.my_trigger enable;]', v_success, v_warning); assert_equals('ALTER TRIGGER', 'Trigger altered.|Warning: Trigger altered with compilation errors.', v_success||'|'||v_warning);

	--ALTER TYPE gets complicated - may need to read up to 8 tokens.
	feedback(q'[alter type test_type compile type]', v_success, v_warning); assert_equals('ALTER TYPE 1', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile type]', v_success, v_warning); assert_equals('ALTER TYPE 2', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type compile specification]', v_success, v_warning); assert_equals('ALTER TYPE 3', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile specification]', v_success, v_warning); assert_equals('ALTER TYPE 4', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type compile]', v_success, v_warning); assert_equals('ALTER TYPE 5', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile]', v_success, v_warning); assert_equals('ALTER TYPE 6', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type compile debug]', v_success, v_warning); assert_equals('ALTER TYPE 7', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile debug]', v_success, v_warning); assert_equals('ALTER TYPE 8', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type noneditionable]', v_success, v_warning); assert_equals('ALTER TYPE 9', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type editionable]', v_success, v_warning); assert_equals('ALTER TYPE 10', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type editionable]', v_success, v_warning); assert_equals('ALTER TYPE 11', 'Type altered.|Warning: Type altered with compilation errors.', v_success||'|'||v_warning);

	--ALTER TYPE BODY is also complicated
	feedback(q'[alter type test_type compile body]', v_success, v_warning); assert_equals('ALTER TYPE BODY 1', 'Type body altered.|Warning: Type Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile body]', v_success, v_warning); assert_equals('ALTER TYPE BODY 2', 'Type body altered.|Warning: Type Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type test_type compile debug body]', v_success, v_warning); assert_equals('ALTER TYPE BODY 3', 'Type body altered.|Warning: Type Body altered with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[alter type jheller.test_type compile debug body]', v_success, v_warning); assert_equals('ALTER TYPE BODY 4', 'Type body altered.|Warning: Type Body altered with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[ALTER USER my_user profile default]', v_success, v_warning); assert_equals('ALTER USER', 'User altered.|', v_success||'|'||v_warning);

	feedback(q'[ALTER VIEW my_schema.my_view read only;]', v_success, v_warning); assert_equals('ALTER VIEW', 'View altered.|Warning: View altered with compilation errors.', v_success||'|'||v_warning);

	--The syntax diagram in manual is wrong, it's "ANALYZE CLUSTER", not "CLUSTER ...".
	feedback(q'[ ANALYZE CLUSTER my_cluster validate structure]', v_success, v_warning); assert_equals('ANALYZE CLUSTER', 'Cluster analyzed.|', v_success||'|'||v_warning);

	feedback(q'[ ANALYZE INDEX my_index validate structure]', v_success, v_warning); assert_equals('ANALYZE INDEX', 'Index analyzed.|', v_success||'|'||v_warning);

	feedback(q'[ ANALYZE TABLE my_table validate structure;]', v_success, v_warning); assert_equals('ANALYZE TABLE', 'Table analyzed.|', v_success||'|'||v_warning);

	feedback(q'[associate statistics with columns my_schema.my_table using null;]', v_success, v_warning); assert_equals('ASSOCIATE STATISTICS', 'Statistics associated.|', v_success||'|'||v_warning);

	feedback(q'[audit all on my_schema.my_table whenever not successful]', v_success, v_warning); assert_equals('AUDIT OBJECT', 'Audit succeeded.|', v_success||'|'||v_warning);
	feedback(q'[audit policy some_policy;]', v_success, v_warning); assert_equals('AUDIT OBJECT', 'Audit succeeded.|', v_success||'|'||v_warning);

	feedback(q'[CALL my_procedure(1,2)]', v_success, v_warning); assert_equals('CALL METHOD', 'Call completed.|', v_success||'|'||v_warning);
	feedback(q'[ call my_procedure(3,4);]', v_success, v_warning); assert_equals('CALL METHOD', 'Call completed.|', v_success||'|'||v_warning);
	feedback(q'[ call my_schema.my_type.my_method('asdf', 'qwer') into :variable;]', v_success, v_warning); assert_equals('CALL METHOD', 'Call completed.|', v_success||'|'||v_warning);
	feedback(q'[ call my_type(3,4).my_method() into :x;]', v_success, v_warning); assert_equals('CALL METHOD', 'Call completed.|', v_success||'|'||v_warning);

	--I don't think this is a real command.
	--feedback(q'[CHANGE PASSWORD]', v_success, v_warning); assert_equals('CHANGE PASSWORD', '|', v_success||'|'||v_warning);

	feedback(q'[comment on audit policy my_policy is 'asdf']', v_success, v_warning); assert_equals('COMMENT', 'Comment created.|', v_success||'|'||v_warning);
	feedback(q'[comment on column my_schema.my_mv is q'!as'!';]', v_success, v_warning); assert_equals('COMMENT', 'Comment created.|', v_success||'|'||v_warning);
	feedback(q'[comment on table some_table is 'asdfasdf']', v_success, v_warning); assert_equals('COMMENT', 'Comment created.|', v_success||'|'||v_warning);

	feedback(q'[ commit work comment 'some comment' write wait batch]', v_success, v_warning); assert_equals('COMMIT', 'Commit complete.|', v_success||'|'||v_warning);
	feedback(q'[COMMIT force corrupt_xid_all]', v_success, v_warning); assert_equals('COMMIT', 'Commit complete.|', v_success||'|'||v_warning);

	feedback(q'[Create or Replace force Analytic View emp_sales_av2 Using emp_sales2 Dimension By ...]', v_success, v_warning); assert_equals('COMMIT', 'Analytic view created.|Warning: Analytic view created with compilation errors.', v_success||'|'||v_warning);

	--Is this a real command?  http://dba.stackexchange.com/questions/96002/what-is-an-oracle-assembly/
	feedback(q'[create or replace assembly some_assembly is 'some string';
	/]', v_success, v_warning); assert_equals('CREATE ASSEMBLY', 'Assembly created.|Warning: Assembly created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[create or replace force attribute dimension date_dim using ...]', v_success, v_warning); assert_equals('CREATE ATTRIBUTE DIMENSION', 'Attribute dimension created.|Warning: Attribute dimension created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE AUDIT POLICY my_policy actions update on oe.orders]', v_success, v_warning); assert_equals('CREATE AUDIT POLICY', 'Audit policy created.|', v_success||'|'||v_warning);

	--This is not a real command as far as I can tell.
	--feedback(q'[CREATE BITMAPFILE]', v_success, v_warning); assert_equals('CREATE BITMAPFILE', '|', v_success||'|'||v_warning);

	feedback(q'[CREATE CLUSTER my_schema.my_cluster(a number sort);]', v_success, v_warning); assert_equals('CREATE CLUSTER', 'Cluster created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE CONTEXT my_context using my_package;]', v_success, v_warning); assert_equals('CREATE CONTEXT', 'Context created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or  REplace  CONTEXT my_context using my_package;]', v_success, v_warning); assert_equals('CREATE CONTEXT', 'Context created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE CONTROLFILE database my_db resetlogs]', v_success, v_warning); assert_equals('CREATE CONTROL FILE', 'Control file created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE DATABASE my_database controlfile reuse;]', v_success, v_warning); assert_equals('CREATE DATABASE', 'Database created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_success, v_warning); assert_equals('CREATE DATABASE LINK', 'Database link created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE shared DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_success, v_warning); assert_equals('CREATE DATABASE LINK', 'Database link created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_success, v_warning); assert_equals('CREATE DATABASE LINK', 'Database link created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE shared public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_success, v_warning); assert_equals('CREATE DATABASE LINK', 'Database link created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE DIMENSION my_schema.my_dimension level l1 is t1.a;]', v_success, v_warning); assert_equals('CREATE DIMENSION', 'Dimension created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE DIRECTORY my_directory#$1 as '/load/blah/']', v_success, v_warning); assert_equals('CREATE DIRECTORY', 'Directory created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace DIRECTORY my_directory#$1 as '/load/blah/']', v_success, v_warning); assert_equals('CREATE DIRECTORY', 'Directory created.|', v_success||'|'||v_warning);

	--Command name has extra space, real command is "DISKGROUP".
	feedback(q'[CREATE DISKGROUP my_diskgroup disk '/emc/powersomething/' size 555m;]', v_success, v_warning); assert_equals('CREATE DISK GROUP', 'Diskgroup created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE EDITION my_edition as child of my_parent;]', v_success, v_warning); assert_equals('CREATE EDITION', 'Edition created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE FLASHBACK ARCHIVE default my_fba tablespace my_ts quota 5g;]', v_success, v_warning); assert_equals('CREATE FLASHBACK ARCHIVE', 'Flashback archive created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 1', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 2', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 3', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 4', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 5', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_success, v_warning); assert_equals('CREATE FUNCTION 6', 'Function created.|Warning: Function created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[Create or replace force Hierarchy calendar_hier Using date_dim (cal_year);]', v_success, v_warning); assert_equals('CREATE HIERARCHY', 'Hierarchy created.|Warning: Hierarchy created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE INDEX on table1(a);]', v_success, v_warning); assert_equals('CREATE INDEX', 'Index created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE unique INDEX on table1(a);]', v_success, v_warning); assert_equals('CREATE INDEX', 'Index created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE bitmap INDEX on table1(a);]', v_success, v_warning); assert_equals('CREATE INDEX', 'Index created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]', v_success, v_warning); assert_equals('CREATE INDEXTYPE', 'Indextype created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]', v_success, v_warning); assert_equals('CREATE INDEXTYPE', 'Indextype created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE INMEMORY JOIN GROUP imjg (test1(a), test1(a));]', v_success, v_warning); assert_equals('CREATE INMEMORY JOIN GROUP', 'Join group created.|', v_success||'|'||v_warning);

	--12 combinations of initial keywords.  COMPILE is optional here, but not elsewhere so it requires special handling.
	feedback(q'[CREATE and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE and resolve JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE and compile JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace and resolve  JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace and compile  JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE JAVA', 'Java created.|Warning: Java created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LIBRARY', 'Library created.|Warning: Library created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[create lockdown profile some_profile]'||chr(10)||'/', v_success, v_warning); assert_equals('CREATE LOCKDOWN PROFILE', 'Lockdown Profile created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE MATERIALIZED VIEW my_mv as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE MATERIALIZED VIEW ', 'Materialized view created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE SNAPSHOT my_mv as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE MATERIALIZED VIEW ', 'Materialized view created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE MATERIALIZED VIEW LOG on my_table with (a)]', v_success, v_warning); assert_equals('CREATE MATERIALIZED VIEW LOG', 'Materialized view log created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE SNAPSHOT LOG on my_table with (a)]', v_success, v_warning); assert_equals('CREATE MATERIALIZED VIEW LOG', 'Materialized view log created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE MATERIALIZED ZONEMAP sales_zmap ON sales(cust_id, prod_id);]', v_success, v_warning); assert_equals('CREATE MATERIALIZED ZONEMAP', 'Materialized zonemap created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]', v_success, v_warning); assert_equals('CREATE OPERATOR', 'Operator created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE OR REPLACE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]', v_success, v_warning); assert_equals('CREATE OPERATOR', 'Operator created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE or replace OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_success, v_warning); assert_equals('CREATE OUTLINE', 'Outline created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable PACKAGE my_package is v_number number; end; /]', v_success, v_warning); assert_equals('CREATE PACKAGE', 'Package created.|Warning: Package created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable PACKAGE BODY my_package is begin null; end;]', v_success, v_warning); assert_equals('CREATE PACKAGE BODY', 'Package body created.|Warning: Package Body created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE PFILE from memory;]', v_success, v_warning); assert_equals('CREATE PFILE', 'File created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE PLUGGABLE DATABASE my_pdb from another_pdb]', v_success, v_warning); assert_equals('CREATE PLUGGABLE DATABASE', 'Pluggable database created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable PROCEDURE my proc is begin null; end; /]', v_success, v_warning); assert_equals('CREATE PROCEDURE', 'Procedure created.|Warning: Procedure created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE PROFILE my_profile limit sessions_per_user 50;]', v_success, v_warning); assert_equals('CREATE PROFILE', 'Profile created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE RESTORE POINT before_change gaurantee flashback database;]', v_success, v_warning); assert_equals('CREATE RESTORE POINT', 'Restore point created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE ROLE my_role;]', v_success, v_warning); assert_equals('CREATE ROLE', 'Role created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE ROLLBACK SEGMENT my_rbs]', v_success, v_warning); assert_equals('CREATE ROLLBACK SEGMENT', 'Rollback segment created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE public ROLLBACK SEGMENT my_rbs]', v_success, v_warning); assert_equals('CREATE ROLLBACK SEGMENT', 'Rollback segment created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE SCHEMA authorization my_schema grant select on table1 to user2 grant select on table2 to user3]', v_success, v_warning); assert_equals('CREATE SCHEMA', 'Schema created.|', v_success||'|'||v_warning);

	--Undocumented feature.
	feedback(q'[CREATE SCHEMA SYNONYM demo2 for demo1]', v_success, v_warning); assert_equals('CREATE SCHEMA SYNONYM', 'Schema synonym created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE SEQUENCE my_schema.my_sequence cache 20;]', v_success, v_warning); assert_equals('CREATE SEQUENCE', 'Sequence created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE SPFILE = 'my_spfile' from pfile;]', v_success, v_warning); assert_equals('CREATE SPFILE', 'File created.|', v_success||'|'||v_warning);

	--An old version of "CREATE SNAPSHOT"?  This is not supported in 11gR2+.
	--feedback(q'[CREATE SUMMARY]', v_success, v_warning); assert_equals('CREATE SUMMARY', '|', v_success||'|'||v_warning);

	feedback(q'[CREATE SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_success, v_warning); assert_equals('CREATE SYNONYM', 'Synonym created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE TABLE my_table(a number);]', v_success, v_warning); assert_equals('CREATE TABLE 1', 'Table created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE global temporary TABLE my_table(a number);]', v_success, v_warning); assert_equals('CREATE TABLE 2', 'Table created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE sharded TABLE my_table(a number);]', v_success, v_warning); assert_equals('CREATE TABLE 3', 'Table created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE duplicated TABLE my_table(a number);]', v_success, v_warning); assert_equals('CREATE TABLE 4', 'Table created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE TABLESPACE SET myset in shardspace ss1 using template(datafile size 1g)]', v_success, v_warning); assert_equals('CREATE TABLESPACE SET', 'Tablespace created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE temporary TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE temporary bigfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE temporary smallfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE undo TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE undo bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);
	feedback(q'[CREATE undo smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_success, v_warning); assert_equals('CREATE TABLESPACE', 'Tablespace created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_success, v_warning); assert_equals('CREATE TRIGGER', 'Trigger created.|Warning: Trigger created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable TYPE my_type as object(a number); /]', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_success, v_warning); assert_equals('CREATE TYPE BODY', 'Type body created.|Warning: Type Body created with compilation errors.', v_success||'|'||v_warning);

	feedback(q'[CREATE USER my_user identified by "asdf";]', v_success, v_warning); assert_equals('CREATE USER', 'User created.|', v_success||'|'||v_warning);

	feedback(q'[CREATE VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 1', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 2', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 3', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 4', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 5', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE force VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 6', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE force editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 7', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE force editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 8', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE force editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 9', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE force noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 10', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE no force VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 11', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE no force editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 12', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE no force editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 13', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE no force editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 14', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE no force noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 15', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 16', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 17', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 18', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 19', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 20', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace force VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 21', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace force editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 22', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace force editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 23', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace force editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 24', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace force noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 25', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace no force VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 26', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace no force editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 27', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace no force editionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 28', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace no force editionable editioning VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 29', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);
	feedback(q'[CREATE or replace no force noneditionable VIEW my_view as select 1 a from dual;]', v_success, v_warning); assert_equals('CREATE VIEW 30', 'View created.|Warning: View created with compilation errors.', v_success||'|'||v_warning);

	--Not a real command.
	--feedback(q'[DECLARE REWRITE EQUIVALENCE]', v_success, v_warning); assert_equals('DECLARE REWRITE EQUIVALENCE', '|', v_success||'|'||v_warning);

	feedback(q'[DELETE my_schema.my_table@my_link]', v_success, v_warning); assert_equals('DELETE 1', 'ERROR: Unknown number of rows deleted.|', v_success||'|'||v_warning);
	feedback(q'[DELETE FROM my_schema.my_table@my_link]', v_success, v_warning, 0); assert_equals('DELETE 2', '0 rows deleted.|', v_success||'|'||v_warning);
	feedback(q'[DELETE FROM my_schema.my_table@my_link]', v_success, v_warning, 1); assert_equals('DELETE 3', '1 row deleted.|', v_success||'|'||v_warning);
	feedback(q'[DELETE FROM my_schema.my_table@my_link]', v_success, v_warning, 999999); assert_equals('DELETE 4', '999999 rows deleted.|', v_success||'|'||v_warning);

	feedback(q'[DISASSOCIATE STATISTICS from columns mytable.a force;]', v_success, v_warning); assert_equals('DISASSOCIATE STATISTICS', 'Statistics disassociated.|', v_success||'|'||v_warning);

	feedback(q'[drop analytic view myview;]', v_success, v_warning); assert_equals('DROP ANALYTIC VIEW', 'Analytic view dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP ASSEMBLY my_assembly]', v_success, v_warning); assert_equals('DROP ASSEMBLY', 'Assembly dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP ATTRIBUTE DIMENSION my_attribute_dimension]', v_success, v_warning); assert_equals('DROP ATTRIBUTE DIMENSION', 'Attribute dimension dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP AUDIT POLICY my_policy;]', v_success, v_warning); assert_equals('DROP AUDIT POLICY', 'Audit Policy dropped.|', v_success||'|'||v_warning);

	--This isn't a real command as far as I can tell.
	--feedback(q'[DROP BITMAPFILE]', v_success, v_warning); assert_equals('DROP BITMAPFILE', '|', v_success||'|'||v_warning);

	feedback(q'[DROP CLUSTER my_cluster]', v_success, v_warning); assert_equals('DROP CLUSTER', 'Cluster dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP CONTEXT my_context;]', v_success, v_warning); assert_equals('DROP CONTEXT', 'Context dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP DATABASE;]', v_success, v_warning); assert_equals('DROP DATABASE', 'Database dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP DATABASE LINK my_link;]', v_success, v_warning); assert_equals('DROP DATABASE LINK', 'Database link dropped.|', v_success||'|'||v_warning);
	feedback(q'[DROP public DATABASE LINK my_link;]', v_success, v_warning); assert_equals('DROP DATABASE LINK', 'Database link dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP DIMENSION my_dimenson;]', v_success, v_warning); assert_equals('DROP DIMENSION', 'Dimension dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP DIRECTORY my_directory;]', v_success, v_warning); assert_equals('DROP DIRECTORY', 'Directory dropped.|', v_success||'|'||v_warning);

	--Command name has extra space, real command is "DISKGROUP".
	feedback(q'[DROP DISKGROUP fradg force including contents;]', v_success, v_warning); assert_equals('DROP DISK GROUP', 'Diskgroup dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP EDITION my_edition cascade;]', v_success, v_warning); assert_equals('DROP EDITION', 'Edition dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP FLASHBACK ARCHIVE my_fba;]', v_success, v_warning); assert_equals('DROP FLASHBACK ARCHIVE', 'Flashback archive dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP FUNCTION my_schema.my_function;]', v_success, v_warning); assert_equals('DROP FUNCTION', 'Function dropped.|', v_success||'|'||v_warning);

	feedback(q'[drop hierarchy my_hierarchy]', v_success, v_warning); assert_equals('DROP HIERARCHY', 'Hierarchy dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP INDEX my_schema.my_index online force;]', v_success, v_warning); assert_equals('DROP INDEX', 'Index dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP INDEXTYPE my_indextype force;]', v_success, v_warning); assert_equals('DROP INDEXTYPE', 'Indextype dropped.|', v_success||'|'||v_warning);

	feedback(q'[drop inmemory join group my injg]', v_success, v_warning); assert_equals('DROP INMEMORY JOIN GROUP', 'Join group deleted.|', v_success||'|'||v_warning);

	feedback(q'[DROP JAVA resourse some_resource;]', v_success, v_warning); assert_equals('DROP JAVA', 'Java dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP LIBRARY my_library]', v_success, v_warning); assert_equals('DROP LIBRARY', 'Library dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP LOCKDOWN PROFILE some_profile]', v_success, v_warning); assert_equals('DROP LOCKDOWN PROFILE', 'Lockdown Profile dropped.|', v_success||'|'||v_warning);

	--Commands have an extra space in them.
	feedback(q'[DROP MATERIALIZED VIEW my_mv preserve table]', v_success, v_warning); assert_equals('DROP MATERIALIZED VIEW', 'Materialized view dropped.|', v_success||'|'||v_warning);
	feedback(q'[DROP SNAPSHOT my_mv preserve table]', v_success, v_warning); assert_equals('DROP MATERIALIZED VIEW', 'Materialized view dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP MATERIALIZED VIEW LOG on some_table;]', v_success, v_warning); assert_equals('DROP MATERIALIZED VIEW LOG', 'Materialized view log dropped.|', v_success||'|'||v_warning);
	feedback(q'[DROP snapshot LOG on some_table;]', v_success, v_warning); assert_equals('DROP MATERIALIZED VIEW LOG', 'Materialized view log dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP MATERIALIZED ZONEMAP my_schema.my_zonemap]', v_success, v_warning); assert_equals('DROP MATERIALIZED ZONEMAP', 'Materialized zonemap dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP OPERATOR my_operator force;]', v_success, v_warning); assert_equals('DROP OPERATOR', 'Operator dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP OUTLINE my_outline;]', v_success, v_warning); assert_equals('DROP OUTLINE', 'Outline dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP PACKAGE my_package]', v_success, v_warning); assert_equals('DROP PACKAGE', 'Package dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP PACKAGE BODY my_package;]', v_success, v_warning); assert_equals('DROP PACKAGE BODY', 'Package body dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP PLUGGABLE DATABASE my_pdb]', v_success, v_warning); assert_equals('DROP PLUGGABLE DATABASE', 'Pluggable database dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP PROCEDURE my_proc]', v_success, v_warning); assert_equals('DROP PROCEDURE', 'Procedure dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP PROFILE my_profile cascade;]', v_success, v_warning); assert_equals('DROP PROFILE', 'Profile dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP RESTORE POINT my_restore_point]', v_success, v_warning); assert_equals('DROP RESTORE POINT', 'Restore point dropped.|', v_success||'|'||v_warning);

	--This is not a real command.
	--feedback(q'[DROP REWRITE EQUIVALENCE]', v_success, v_warning); assert_equals('DROP REWRITE EQUIVALENCE', '|', v_success||'|'||v_warning);

	feedback(q'[DROP ROLE my_role]', v_success, v_warning); assert_equals('DROP ROLE', 'Role dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP ROLLBACK SEGMENT my_rbs]', v_success, v_warning); assert_equals('DROP ROLLBACK SEGMENT', 'Rollback segment dropped.|', v_success||'|'||v_warning);

	--Undocumented feature.
	feedback(q'[DROP SCHEMA SYNONYM a_schema_synonym]', v_success, v_warning); assert_equals('DROP SCHEMA SYNONYM', 'Schema synonym dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP SEQUENCE my_sequence;]', v_success, v_warning); assert_equals('DROP SEQUENCE', 'Sequence dropped.|', v_success||'|'||v_warning);

	--An old version of "DROP SNAPSHOT"?  This is not supported in 11gR2+.
	--feedback(q'[DROP SUMMARY]', v_success, v_warning); assert_equals('DROP SUMMARY', '|', v_success||'|'||v_warning);

	feedback(q'[DROP SYNONYM my_synonym]', v_success, v_warning); assert_equals('DROP SYNONYM', 'Synonym dropped.|', v_success||'|'||v_warning);
	feedback(q'[DROP public SYNONYM my_synonym]', v_success, v_warning); assert_equals('DROP SYNONYM', 'Synonym dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TABLE my_schema.my_table cascade constraints purge]', v_success, v_warning); assert_equals('DROP TABLE', 'Table dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TABLESPACE SET my_set]', v_success, v_warning); assert_equals('DROP TABLESPACE SET', 'Tablespace dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TABLESPACE my_tbs including contents and datafiles cascade constraints;]', v_success, v_warning); assert_equals('DROP TABLESPACE', 'Tablespace dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TRIGGER my_trigger]', v_success, v_warning); assert_equals('DROP TRIGGER', 'Trigger dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TYPE my_type validate]', v_success, v_warning); assert_equals('DROP TYPE', 'Type dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP TYPE BODY my_type]', v_success, v_warning); assert_equals('DROP TYPE BODY', 'Type body dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP USER my_user cascde;]', v_success, v_warning); assert_equals('DROP USER', 'User dropped.|', v_success||'|'||v_warning);

	feedback(q'[DROP VIEW my_schema.my_view cascade constraints;]', v_success, v_warning); assert_equals('DROP VIEW', 'View dropped.|', v_success||'|'||v_warning);

	--feedback(q'[Do not use 184]', v_success, v_warning); assert_equals('Do not use 184', '|', v_success||'|'||v_warning);
	--feedback(q'[Do not use 185]', v_success, v_warning); assert_equals('Do not use 185', '|', v_success||'|'||v_warning);
	--feedback(q'[Do not use 186]', v_success, v_warning); assert_equals('Do not use 186', '|', v_success||'|'||v_warning);

	feedback(q'[EXPLAIN plan set statement_id='asdf' for select * from dual]', v_success, v_warning); assert_equals('EXPLAIN 1', 'Explained.|', v_success||'|'||v_warning);
	feedback(q'[explain plan for with function f return number is begin return 1; end; select f from dual;]', v_success, v_warning); assert_equals('EXPLAIN 2', 'Explained.|', v_success||'|'||v_warning);

	feedback(q'[FLASHBACK DATABASE to restore point my_restore_point]', v_success, v_warning); assert_equals('FLASHBACK DATABASE', 'Flashback complete.|', v_success||'|'||v_warning);
	feedback(q'[FLASHBACK standby DATABASE to restore point my_restore_point]', v_success, v_warning); assert_equals('FLASHBACK DATABASE', 'Flashback complete.|', v_success||'|'||v_warning);

	feedback(q'[FLASHBACK TABLE my_schema.my_table to timestamp timestamp '2015-01-01 12:00:00']', v_success, v_warning); assert_equals('FLASHBACK TABLE', 'Flashback complete.|', v_success||'|'||v_warning);

	feedback(q'[GRANT dba my_user]', v_success, v_warning); assert_equals('GRANT OBJECT 1', 'Grant succeeded.|', v_success||'|'||v_warning);
	feedback(q'[GRANT select on my_table to some_other_user with grant option]', v_success, v_warning); assert_equals('GRANT OBJECT 2', 'Grant succeeded.|', v_success||'|'||v_warning);
	feedback(q'[GRANT dba to my_package]', v_success, v_warning); assert_equals('GRANT OBJECT 3', 'Grant succeeded.|', v_success||'|'||v_warning);

	feedback(q'[INSERT /*+ append */ into my_table select * from other_table]', v_success, v_warning); assert_equals('INSERT 1', 'ERROR: Unknown number of rows created.|', v_success||'|'||v_warning);
	feedback(q'[INSERT all into table1(a) values(b) into table2(a) values(b) select b from another_table;]', v_success, v_warning, 0); assert_equals('INSERT 2', '0 rows created.|', v_success||'|'||v_warning);
	feedback(q'[insert into test1 with function f return number is begin return 1; end; select f from dual;]', v_success, v_warning, 1); assert_equals('INSERT 3', '1 row created.|', v_success||'|'||v_warning);
	feedback(q'[insert into test1 with function f return number is begin return 1; end; select f from dual;]', v_success, v_warning, 99999); assert_equals('INSERT 4', '99999 rows created.|', v_success||'|'||v_warning);

	feedback(q'[LOCK TABLE my_schema.my_table in exclsive mode]', v_success, v_warning); assert_equals('LOCK TABLE', 'Table(s) Locked.|', v_success||'|'||v_warning);

	--See "UPSERT" for "MERGE".
	--feedback(q'[NO-OP]', v_success, v_warning); assert_equals('NO-OP', '|', v_success||'|'||v_warning);

	feedback(q'[NOAUDIT insert any table]', v_success, v_warning); assert_equals('NOAUDIT OBJECT', 'Noaudit succeeded.|', v_success||'|'||v_warning);
	feedback(q'[NOAUDIT policy my_policy by some_user]', v_success, v_warning); assert_equals('NOAUDIT OBJECT', 'Noaudit succeeded.|', v_success||'|'||v_warning);

	feedback(q'[ <<my_label>>begin null; end;]', v_success, v_warning); assert_equals('PL/SQL EXECUTE 1', 'PL/SQL procedure successfully completed.|', v_success||'|'||v_warning);
	feedback(q'[/*asdf*/declare v_test number; begin null; end; /]', v_success, v_warning); assert_equals('PL/SQL EXECUTE 2', 'PL/SQL procedure successfully completed.|', v_success||'|'||v_warning);
	feedback(q'[  begin null; end; /]', v_success, v_warning); assert_equals('PL/SQL EXECUTE 3', 'PL/SQL procedure successfully completed.|', v_success||'|'||v_warning);

	--Command name has space instead of underscore.
 	feedback(q'[PURGE DBA_RECYCLEBIN;]', v_success, v_warning); assert_equals('PURGE DBA RECYCLEBIN', 'DBA Recyclebin purged.|', v_success||'|'||v_warning);

	feedback(q'[PURGE INDEX my_index]', v_success, v_warning); assert_equals('PURGE INDEX', 'Index purged.|', v_success||'|'||v_warning);

	feedback(q'[PURGE TABLE my_table]', v_success, v_warning); assert_equals('PURGE TABLE', 'Table purged.|', v_success||'|'||v_warning);

	feedback(q'[PURGE TABLESPACE SET my_set]', v_success, v_warning); assert_equals('PURGE TABLESPACE SET', 'Tablespace purged.|', v_success||'|'||v_warning);

	feedback(q'[PURGE TABLESPACE my_tbs user my_user]', v_success, v_warning); assert_equals('PURGE TABLESPACE', 'Tablespace purged.|', v_success||'|'||v_warning);

	--Command name has extra "USER".
	feedback(q'[PURGE RECYCLEBIN;]', v_success, v_warning); assert_equals('PURGE USER RECYCLEBIN', 'Recyclebin purged.|', v_success||'|'||v_warning);

	--It's always "Table renamed", even if it's a view or other objects.
	feedback(q'[RENAME old_table to new_table]', v_success, v_warning); assert_equals('RENAME', 'Table renamed.|', v_success||'|'||v_warning);

	feedback(q'[REVOKE select any table from my_user]', v_success, v_warning); assert_equals('REVOKE OBJECT 1', 'Revoke succeeded.|', v_success||'|'||v_warning);
	feedback(q'[REVOKE select on my_tables from user2]', v_success, v_warning); assert_equals('REVOKE OBJECT 2', 'Revoke succeeded.|', v_success||'|'||v_warning);
	feedback(q'[REVOKE dba from my_package]', v_success, v_warning); assert_equals('REVOKE OBJECT 3', 'Revoke succeeded.|', v_success||'|'||v_warning);

	feedback(q'[ROLLBACK;]', v_success, v_warning); assert_equals('ROLLBACK 1', 'Rollback complete.|', v_success||'|'||v_warning);
	feedback(q'[ROLLBACK work;]', v_success, v_warning); assert_equals('ROLLBACK 2', 'Rollback complete.|', v_success||'|'||v_warning);
	feedback(q'[ROLLBACK to savepoint savepoint1]', v_success, v_warning); assert_equals('ROLLBACK 3', 'Rollback complete.|', v_success||'|'||v_warning);

	feedback(q'[SAVEPOINT my_savepoint;]', v_success, v_warning); assert_equals('SAVEPOINT', 'Savepoint created.|', v_success||'|'||v_warning);

	--Slight deviation from SQL*Plus behavior:
	--SQL*Plus does not display any feedback message if the number of rows is between 1 to 5.
	--This program always displays the number of rows.
	feedback(q'[select * from dual;]', v_success, v_warning); assert_equals('SELECT 1', 'ERROR: Unknown number of rows selected.|', v_success||'|'||v_warning);
	feedback(q'[/*asdf*/select * from dual;]', v_success, v_warning, 0); assert_equals('SELECT 2', 'no rows selected|', v_success||'|'||v_warning);
	feedback(q'[((((select * from dual))));]', v_success, v_warning, 1); assert_equals('SELECT 3', '1 row selected.|', v_success||'|'||v_warning);
	feedback(q'[with test1 as (select 1 a from dual) select * from test1;]', v_success, v_warning, 5); assert_equals('SELECT 4', '5 rows selected.|', v_success||'|'||v_warning);
	feedback(q'[with function test_function return number is begin return 1; end; select test_function from dual;
	/]', v_success, v_warning, 6); assert_equals('SELECT 5', '6 rows selected.|', v_success||'|'||v_warning);

	--There are two versions of CONSTRAINT[S].
	feedback(q'[SET CONSTRAINTS all deferred]', v_success, v_warning); assert_equals('SET CONSTRAINT', 'Constraint set.|', v_success||'|'||v_warning);
	feedback(q'[SET CONSTRAINT all immediate]', v_success, v_warning); assert_equals('SET CONSTRAINT', 'Constraint set.|', v_success||'|'||v_warning);

	feedback(q'[SET ROLE none]', v_success, v_warning); assert_equals('SET ROLE', 'Role set.|', v_success||'|'||v_warning);

	feedback(q'[SET TRANSACTION read only]', v_success, v_warning); assert_equals('SET TRANSACTION', 'Transaction set.|', v_success||'|'||v_warning);

	feedback(q'[TRUNCATE CLUSTER my_schema.my_cluster drop storage;]', v_success, v_warning); assert_equals('TRUNCATE CLUSTER', 'Cluster truncated.|', v_success||'|'||v_warning);

	feedback(q'[TRUNCATE TABLE my_schema.my_table purge materialized view log]', v_success, v_warning); assert_equals('TRUNCATE TABLE', 'Table truncated.|', v_success||'|'||v_warning);

	--Not a real command.
	--feedback(q'[UNDROP OBJECT]', v_success, v_warning); assert_equals('UNDROP OBJECT', '|', v_success||'|'||v_warning);

	feedback(q'[UPDATE my_tables set a = 1]', v_success, v_warning); assert_equals('UPDATE 1', 'ERROR: Unknown number of rows updated.|', v_success||'|'||v_warning);
	feedback(q'[UPDATE my_tables set a = (with function f return number is begin return 1; end; select f from dual);]', v_success, v_warning, 0); assert_equals('UPDATE 2', '0 rows updated.|', v_success||'|'||v_warning);
	feedback(q'[UPDATE my_tables set a = 1]', v_success, v_warning, 1); assert_equals('UPDATE 3', '1 row updated.|', v_success||'|'||v_warning);
	feedback(q'[UPDATE my_tables set a = 1]', v_success, v_warning, 555); assert_equals('UPDATE 4', '555 rows updated.|', v_success||'|'||v_warning);

	--These are not real commands (they are part of alter table) and they could be ambiguous with an UPDATE statement
	--if there was a table named "INDEXES" or "JOIN".
	--feedback(q'[UPDATE INDEXES]', v_success, v_warning); assert_equals('UPDATE INDEXES', '|', v_success||'|'||v_warning);
	--feedback(q'[UPDATE JOIN INDEX]', v_success, v_warning); assert_equals('UPDATE JOIN INDEX', '|', v_success||'|'||v_warning);

	feedback(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = 1;]', v_success, v_warning); assert_equals('UPSERT 1', 'ERROR: Unknown number of rows merged.|', v_success||'|'||v_warning);
	feedback(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = (with function test_function return number is begin return 1; end; select test_function from dual);]', v_success, v_warning, 0); assert_equals('UPSERT 2', '0 rows merged.|', v_success||'|'||v_warning);
	feedback(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = 1;]', v_success, v_warning, 1); assert_equals('UPSERT 3', '1 row merged.|', v_success||'|'||v_warning);
	feedback(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = 1;]', v_success, v_warning, 100); assert_equals('UPSERT 4', '100 rows merged.|', v_success||'|'||v_warning);

	--Not a real command, this is part of ANALYZE.
	--feedback(q'[VALIDATE INDEX]', v_success, v_warning); assert_equals('VALIDATE INDEX', '|', v_success||'|'||v_warning);
end test_commands;


--------------------------------------------------------------------------------
--Purpose: Test the API that uses P_COMMAND_NAME.  The other tests test the
--P_TOKENS interface.
procedure test_command_name_api is
	v_success varchar2(32767);
	v_warning varchar2(32767);
begin
	feedback_command_name('ALTER TABLE', v_success, v_warning); assert_equals('ALTER TABLE', 'Table altered.|', v_success||'|'||v_warning);
	feedback_command_name('CREATE TYPE', v_success, v_warning); assert_equals('CREATE TYPE', 'Type created.|Warning: Type created with compilation errors.', v_success||'|'||v_warning);
	feedback_command_name('SELECT', v_success, v_warning); assert_equals('SELECT 1', 'ERROR: Unknown number of rows selected.|', v_success||'|'||v_warning);
	feedback_command_name('SELECT', v_success, v_warning, 5); assert_equals('SELECT 4', '5 rows selected.|', v_success||'|'||v_warning);
	feedback_command_name('INSERT', v_success, v_warning); assert_equals('INSERT 1', 'ERROR: Unknown number of rows created.|', v_success||'|'||v_warning);
end test_command_name_api;


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
	dbms_output.put_line('--------------------------------------');
	dbms_output.put_line('PL/SQL Statement Feedback Test Summary');
	dbms_output.put_line('--------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_errors)                  > 0 then test_errors; end if;
	if bitand(p_tests, c_commands)                > 0 then test_commands; end if;
	if bitand(p_tests, c_command_name_api)        > 0 then test_command_name_api; end if;

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
