create or replace package statement_classifier_test authid current_user is
/*
== Purpose ==

Unit tests for statement_classifier.


== Example ==

begin
	statement_classifier_test.run;
	statement_classifier_test.run(statement_classifier_test.c_dynamic_tests);
end;

*/
pragma serially_reusable;

--Globals to select which test suites to run.
c_errors                  constant number := power(2, 1);
c_commands                constant number := power(2, 2);
c_start_index             constant number := power(2, 3);
c_has_plsql_declaration   constant number := power(2, 4);
c_trigger_type_body_index constant number := power(2, 5);
c_simplified_functions    constant number := power(2, 6);

c_static_tests  constant number := c_errors+c_commands+c_start_index+c_has_plsql_declaration+c_trigger_type_body_index+c_simplified_functions;

c_dynamic_tests constant number := power(2, 30);

c_all_tests constant number := c_static_tests+c_dynamic_tests;

--Run the unit tests and display the results in dbms output.
procedure run(p_tests number default c_static_tests);

end;
/
create or replace package body statement_classifier_test is
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
function get_sqlerrm(p_statement clob) return varchar2 is
	v_category varchar2(100);
	v_statement_type varchar2(100);
	v_command_name varchar2(64);
	v_command_type number;
	v_lex_sqlcode number;
	v_lex_sqlerrm varchar2(4000);
begin
	statement_classifier.classify(plsql_lexer.lex(p_statement),
		v_category,v_statement_type,v_command_name,v_command_type,v_lex_sqlcode,v_lex_sqlerrm);
	return null;
exception when others then
	return sqlerrm;
end get_sqlerrm;


-- =============================================================================
-- Test Suites
-- =============================================================================

--------------------------------------------------------------------------------
procedure test_errors is
	v_output output_rec;

	--Helper function that concatenates results for easy string comparison.
	function concat(p_output output_rec) return varchar2 is
	begin
		return nvl(p_output.fatal_error,
			p_output.category||'|'||p_output.statement_type||'|'||p_output.command_name||'|'||p_output.command_type);
	end;
begin
	classify('(select * from dual)', v_output);
	assert_equals('No errors 1', null, v_output.lex_sqlcode);
	assert_equals('No errors 1', null, v_output.lex_sqlerrm);

	classify('(select * from dual) /*', v_output);
	assert_equals('Comment error 1', -1742, v_output.lex_sqlcode);
	assert_equals('Comment error 2', 'comment not terminated properly', v_output.lex_sqlerrm);

	classify('(select * from dual) "', v_output);
	assert_equals('Missing double quote error 1', -1740, v_output.lex_sqlcode);
	assert_equals('Missing double quote error 2', 'missing double quote in identifier', v_output.lex_sqlerrm);

	--"Zero-length identifier" error, but must be caught by the parser.
	classify('(select 1 "" from dual)', v_output);
	assert_equals('Zero-length identifier 1', null, v_output.lex_sqlcode);
	assert_equals('Zero-length identifier 2', null, v_output.lex_sqlerrm);

	--"identifier is too long" error, but must be caught by the parser.
	classify('(select 1 a123456789012345678901234567890 from dual)', v_output);
	assert_equals('Identifier too long error 1', null, v_output.lex_sqlcode);
	assert_equals('Identifier too long error 2', null, v_output.lex_sqlerrm);

	--"identifier is too long" error, but must be caught by the parser.
	classify('(select 1 "a123456789012345678901234567890" from dual)', v_output);
	assert_equals('Identifier too long error 3', null, v_output.lex_sqlcode);
	assert_equals('Identifier too long error 4', null, v_output.lex_sqlerrm);

	classify(q'<declare v_test varchar2(100) := q'  '; begin null; end;>', v_output);
	assert_equals('Invalid character 1', -911, v_output.lex_sqlcode);
	assert_equals('Invalid character 2', 'invalid character', v_output.lex_sqlerrm);
	classify(q'<declare v_test varchar2(100) := nq'  '; begin null; end;>', v_output);
	assert_equals('Invalid character 3', -911, v_output.lex_sqlcode);
	assert_equals('Invalid character 4', 'invalid character', v_output.lex_sqlerrm);

	classify('(select * from dual) '' ', v_output);
	assert_equals('String not terminated 1', -1756, v_output.lex_sqlcode);
	assert_equals('String not terminated 2', 'quoted string not properly terminated', v_output.lex_sqlerrm);
	classify(q'<(select * from dual) q'!' >', v_output);
	assert_equals('String not terminated 3', -1756, v_output.lex_sqlcode);
	assert_equals('String not terminated 4', 'quoted string not properly terminated', v_output.lex_sqlerrm);

	--Invalid.
	classify(q'[asdf]', v_output); assert_equals('Cannot classify 1', 'Invalid|Invalid|Invalid|-1', concat(v_output));
	classify(q'[create tableS test1(a number);]', v_output); assert_equals('Cannot classify 2', 'Invalid|Invalid|Invalid|-1', concat(v_output));
	classify(q'[seeelect * from dual]', v_output); assert_equals('Cannot classify 3', 'Invalid|Invalid|Invalid|-1', concat(v_output));
	classify(q'[alter what_is_this set x = y;]', v_output); assert_equals('Cannot classify 4', 'Invalid|Invalid|Invalid|-1', concat(v_output));
	classify(q'[upsert my_table using other_table on (my_table.a = other_table.a) when matched then update set b = 1]', v_output); assert_equals('Cannot classify 5', 'Invalid|Invalid|Invalid|-1', concat(v_output));

	--Nothing.
	classify(q'[]', v_output); assert_equals('Nothing to classify 1', 'Nothing|Nothing|Nothing|-2', concat(v_output));
	classify(q'[ 	 ]', v_output); assert_equals('Nothing to classify 2', 'Nothing|Nothing|Nothing|-2', concat(v_output));
	classify(q'[ /* asdf */ ]', v_output); assert_equals('Nothing to classify 3', 'Nothing|Nothing|Nothing|-2', concat(v_output));
	classify(q'[ -- comment ]', v_output); assert_equals('Nothing to classify 4', 'Nothing|Nothing|Nothing|-2', concat(v_output));
	classify(q'[ /* asdf ]', v_output); assert_equals('Nothing to classify 5', 'Nothing|Nothing|Nothing|-2', concat(v_output));
end test_errors;


--------------------------------------------------------------------------------
--NOTE: This test suite is similar in STATEMENT_CLASSIFIER_TEST, STATEMENT_FEEDBACK_TEST, and STATEMENT_TERMINATOR_TEST.
--If you add a test case here you should probably add one there as well.
procedure test_commands is
	v_output output_rec;

	--Helper function that concatenates results for easy string comparison.
	function concat(p_output output_rec) return varchar2 is
	begin
		return nvl(p_output.fatal_error,
			p_output.category||'|'||p_output.statement_type||'|'||p_output.command_name||'|'||p_output.command_type);
	end;
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
	classify(q'[/*comment*/ adMINister /*asdf*/ kEy manaGEment create keystore 'asdf' identified by qwer]', v_output); assert_equals('ADMINISTER KEY MANAGEMENT', 'DDL|ADMINISTER KEY MANAGEMENT|ADMINISTER KEY MANAGEMENT|238', concat(v_output));

	classify(q'[ alter  analytic view some_name compile;]', v_output); assert_equals('ALTER ANALYTIC VIEW', 'DDL|ALTER|ALTER ANALYTIC VIEW|250', concat(v_output));

	classify(q'[ alter assemBLY /*I don't think this is a real command but whatever*/]', v_output); assert_equals('ALTER ASSEMBLY', 'DDL|ALTER|ALTER ASSEMBLY|217', concat(v_output));

	classify(q'[ Alter Attribute Dimension asdf.qwer compile;]', v_output); assert_equals('ALTER ASSEMBLY', 'DDL|ALTER|ALTER ATTRIBUTE DIMENSION|244', concat(v_output));

	classify(q'[ ALTEr AUDIt POLICY myPOLICY drop roles myRole; --comment]', v_output); assert_equals('ALTER AUDIT POLICY', 'DDL|ALTER|ALTER AUDIT POLICY|230', concat(v_output));

	classify(q'[	alter	cluster	schema.my_cluster parallel 8]', v_output); assert_equals('ALTER CLUSTER', 'DDL|ALTER|ALTER CLUSTER|5', concat(v_output));

	classify(q'[alter database cdb1 mount]', v_output); assert_equals('ALTER DATABASE', 'DDL|ALTER|ALTER DATABASE|35', concat(v_output));

	classify(q'[alter shared public database link my_link connect to me identified by "password";]', v_output); assert_equals('ALTER DATABASE LINK', 'DDL|ALTER|ALTER DATABASE LINK|225', concat(v_output));

	classify(q'[ alter dimENSION my_dimension#12 compile;]', v_output); assert_equals('ALTER DIMENSION', 'DDL|ALTER|ALTER DIMENSION|175', concat(v_output));

	--Command name has extra space, real command is "DISKGROUP".
	classify(q'[/*+useless comment*/ alter diskgroup +orcl13 resize disk '/emcpowersomething/' size 500m;]', v_output); assert_equals('ALTER DISKGROUP', 'DDL|ALTER|ALTER DISK GROUP|193', concat(v_output));

	--Undocumented feature:
	classify(q'[ alter EDITION my_edition unusable]', v_output); assert_equals('ALTER EDITION', 'DDL|ALTER|ALTER EDITION|213', concat(v_output));

	classify(q'[ alter  flashback  archive myarchive set default;]', v_output); assert_equals('ALTER FLASHBACK ARCHIVE', 'DDL|ALTER|ALTER FLASHBACK ARCHIVE|219', concat(v_output));

	classify(q'[ALTER FUNCTION myschema.myfunction compile;]', v_output); assert_equals('ALTER FUNCTION', 'DDL|ALTER|ALTER FUNCTION|92', concat(v_output));

	classify(q'[ALTER HIERARCHY myschema.myhierarchy compile;]', v_output); assert_equals('ALTER HIERARCHY', 'DDL|ALTER|ALTER HIERARCHY|247', concat(v_output));

	classify(q'[ alter index asdf rebuild parallel 8]', v_output); assert_equals('ALTER INDEX', 'DDL|ALTER|ALTER INDEX|11', concat(v_output));

	classify(q'[ALTER INDEXTYPE  my_schema.my_indextype compile;]', v_output); assert_equals('ALTER INDEXTYPE', 'DDL|ALTER|ALTER INDEXTYPE|166', concat(v_output));

	classify(q'[ALTER inmemory  join group my_group add (mytable(mycolumn));]', v_output); assert_equals('ALTER INDEXTYPE', 'DDL|ALTER|ALTER INMEMORY JOIN GROUP|-101', concat(v_output));

	classify(q'[ALTER java  source my_schema.some_object compile;]', v_output); assert_equals('ALTER JAVA', 'DDL|ALTER|ALTER JAVA|161', concat(v_output));

	classify(q'[alter library test_library editionable compile;]', v_output); assert_equals('ALTER LIBRARY', 'DDL|ALTER|ALTER LIBRARY|196', concat(v_output));

	classify(q'[alter lockdown profile my_profile disable feature all]', v_output); assert_equals('ALTER LOCKDOWN PROFILE', 'DDL|ALTER|ALTER LOCKDOWN PROFILE|236', concat(v_output));

	classify(q'[ALTER  MATERIALIZED  VIEW a_schema.mv_name cache consider fresh;]', v_output); assert_equals('ALTER MATERIALIZED VIEW ', 'DDL|ALTER|ALTER MATERIALIZED VIEW |75', concat(v_output));
	classify(q'[ALTER  SNAPSHOT a_schema.mv_name cache consider fresh;]', v_output); assert_equals('ALTER MATERIALIZED VIEW ', 'DDL|ALTER|ALTER MATERIALIZED VIEW |75', concat(v_output));

	classify(q'[ALTER /*a*/ MATERIALIZED /*b*/ VIEW /*c*/LOG force on my_table parallel 10]', v_output); assert_equals('ALTER MATERIALIZED VIEW LOG', 'DDL|ALTER|ALTER MATERIALIZED VIEW LOG|72', concat(v_output));
	classify(q'[ALTER /*a*/ SNAPSHOT /*c*/LOG force on my_table parallel 10]', v_output); assert_equals('ALTER MATERIALIZED VIEW LOG', 'DDL|ALTER|ALTER MATERIALIZED VIEW LOG|72', concat(v_output));

	classify(q'[ alter  materialized	zonemap my_schema.my_zone enable pruning]', v_output); assert_equals('ALTER MATERIALIZED ZONEMAP', 'DDL|ALTER|ALTER MATERIALIZED ZONEMAP|240', concat(v_output));

	classify(q'[alter operator my_operator add binding (number) return (number) using my_function]', v_output); assert_equals('ALTER OPERATOR', 'DDL|ALTER|ALTER OPERATOR|183', concat(v_output));

	classify(q'[alter outline public my_outline disable;]', v_output); assert_equals('ALTER OUTLINE', 'DDL|ALTER|ALTER OUTLINE|179', concat(v_output));

	--ALTER PACKAGE gets complicated - may need to read up to 8 tokens.
	classify(q'[alter package test_package compile package]', v_output); assert_equals('ALTER PACKAGE 1', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package jheller.test_package compile package]', v_output); assert_equals('ALTER PACKAGE 2', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package test_package compile specification]', v_output); assert_equals('ALTER PACKAGE 3', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package jheller.test_package compile specification]', v_output); assert_equals('ALTER PACKAGE 4', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package test_package compile]', v_output); assert_equals('ALTER PACKAGE 5', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package jheller.test_package compile]', v_output); assert_equals('ALTER PACKAGE 6', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package test_package compile debug]', v_output); assert_equals('ALTER PACKAGE 7', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package jheller.test_package compile debug]', v_output); assert_equals('ALTER PACKAGE 8', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package test_package noneditionable]', v_output); assert_equals('ALTER PACKAGE 9', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package test_package editionable]', v_output); assert_equals('ALTER PACKAGE 10', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));
	classify(q'[alter package jheller.test_package editionable]', v_output); assert_equals('ALTER PACKAGE 11', 'DDL|ALTER|ALTER PACKAGE|95', concat(v_output));

	--ALTER PACKAGE BODY is also complicated
	classify(q'[alter package test_package compile body]', v_output); assert_equals('ALTER PACKAGE BODY 1', 'DDL|ALTER|ALTER PACKAGE BODY|98', concat(v_output));
	classify(q'[alter package jheller.test_package compile body]', v_output); assert_equals('ALTER PACKAGE BODY 2', 'DDL|ALTER|ALTER PACKAGE BODY|98', concat(v_output));
	classify(q'[alter package test_package compile debug body]', v_output); assert_equals('ALTER PACKAGE BODY 3', 'DDL|ALTER|ALTER PACKAGE BODY|98', concat(v_output));
	classify(q'[alter package jheller.test_package compile debug body]', v_output); assert_equals('ALTER PACKAGE BODY 4', 'DDL|ALTER|ALTER PACKAGE BODY|98', concat(v_output));

	classify(q'[ALTER PLUGGABLE DATABASE my_pdb default tablespace some_tbs]', v_output); assert_equals('ALTER PLUGGABLE DATABASE', 'DDL|ALTER|ALTER PLUGGABLE DATABASE|227', concat(v_output));

	classify(q'[ALTER PROCEDURE my_proc compile]', v_output); assert_equals('ALTER PROCEDURE', 'DDL|ALTER|ALTER PROCEDURE|25', concat(v_output));

	classify(q'[ alter profile default limit password_lock_time unlimited;]', v_output); assert_equals('ALTER PROFILE', 'DDL|ALTER|ALTER PROFILE|67', concat(v_output));

	classify(q'[ALTER RESOURCE COST privat_sga 1000;]', v_output); assert_equals('ALTER RESOURCE COST', 'DDL|ALTER|ALTER RESOURCE COST|70', concat(v_output));

	--I don't think this is a real command.
	--classify(q'[ALTER REWRITE EQUIVALENCE]', v_output); assert_equals('ALTER REWRITE EQUIVALENCE', 'DDL|ALTER|ALTER REWRITE EQUIVALENCE|210', concat(v_output));

	classify(q'[alter role some_role# identified externally]', v_output); assert_equals('ALTER ROLE', 'DDL|ALTER|ALTER ROLE|79', concat(v_output));

	classify(q'[ALTER ROLLBACK SEGMENT my_rbs offline]', v_output); assert_equals('ALTER ROLLBACK SEGMENT', 'DDL|ALTER|ALTER ROLLBACK SEGMENT|37', concat(v_output));

	classify(q'[alter sequence my_seq cache 100]', v_output); assert_equals('ALTER SEQUENCE', 'DDL|ALTER|ALTER SEQUENCE|14', concat(v_output));

	classify(q'[alter session set OPTIMIZER_DYNAMIC_SAMPLING=5;]', v_output); assert_equals('ALTER SESSION', 'Session Control|ALTER SESSION|ALTER SESSION|42', concat(v_output));
	classify(q'[ALTER SESSION set current_schema=my_schema]', v_output); assert_equals('ALTER SESSION', 'Session Control|ALTER SESSION|ALTER SESSION|42', concat(v_output));

	--An old version of "ALTER SNAPSHOT"?  This is not supported in 11gR2+.
	--classify(q'[ALTER SUMMARY a_schema.mv_name cache;]', v_output); assert_equals('ALTER SUMMARY', 'DDL|ALTER|ALTER SUMMARY|172', concat(v_output));

	classify(q'[ALTER /**/public/**/ SYNONYM my_synonym compile]', v_output); assert_equals('ALTER SYNONYM', 'DDL|ALTER|ALTER SYNONYM|192', concat(v_output));
	classify(q'[ALTER SYNONYM  my_synonym compile]', v_output); assert_equals('ALTER SYNONYM', 'DDL|ALTER|ALTER SYNONYM|192', concat(v_output));

	classify(q'[alter system set memory_target=5m]', v_output); assert_equals('ALTER SYSTEM', 'System Control|ALTER SYSTEM|ALTER SYSTEM|49', concat(v_output));
	classify(q'[alter system reset "_stupid_hidden_parameter"]', v_output); assert_equals('ALTER SYSTEM', 'System Control|ALTER SYSTEM|ALTER SYSTEM|49', concat(v_output));

	classify(q'[ ALTER  TABLE my_schema.my_table rename to new_name;]', v_output); assert_equals('ALTER TABLE', 'DDL|ALTER|ALTER TABLE|15', concat(v_output));

	classify(q'[ALTER TABLESPACE SET some_set coalesce]', v_output); assert_equals('ALTER TABLESPACE SET', 'DDL|ALTER|ALTER TABLESPACE SET|-201', concat(v_output));

	classify(q'[ALTER TABLESPACE some_tbs coalesce]', v_output); assert_equals('ALTER TABLESPACE', 'DDL|ALTER|ALTER TABLESPACE|40', concat(v_output));

	--Undocumented by still runs in 12.1.0.2.
	classify(q'[ALTER TRACING enable;]', v_output); assert_equals('ALTER TRACING', 'DDL|ALTER|ALTER TRACING|58', concat(v_output));

	classify(q'[alter trigger my_schema.my_trigger enable;]', v_output); assert_equals('ALTER TRIGGER', 'DDL|ALTER|ALTER TRIGGER|60', concat(v_output));

	--ALTER TYPE gets complicated - may need to read up to 8 tokens.
	classify(q'[alter type test_type compile type]', v_output); assert_equals('ALTER TYPE 1', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type jheller.test_type compile type]', v_output); assert_equals('ALTER TYPE 2', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type test_type compile specification]', v_output); assert_equals('ALTER TYPE 3', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type jheller.test_type compile specification]', v_output); assert_equals('ALTER TYPE 4', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type test_type compile]', v_output); assert_equals('ALTER TYPE 5', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type jheller.test_type compile]', v_output); assert_equals('ALTER TYPE 6', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type test_type compile debug]', v_output); assert_equals('ALTER TYPE 7', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type jheller.test_type compile debug]', v_output); assert_equals('ALTER TYPE 8', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type test_type noneditionable]', v_output); assert_equals('ALTER TYPE 9', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type test_type editionable]', v_output); assert_equals('ALTER TYPE 10', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));
	classify(q'[alter type jheller.test_type editionable]', v_output); assert_equals('ALTER TYPE 11', 'DDL|ALTER|ALTER TYPE|80', concat(v_output));

	--ALTER TYPE BODY is also complicated
	classify(q'[alter type test_type compile body]', v_output); assert_equals('ALTER TYPE BODY 1', 'DDL|ALTER|ALTER TYPE BODY|82', concat(v_output));
	classify(q'[alter type jheller.test_type compile body]', v_output); assert_equals('ALTER TYPE BODY 2', 'DDL|ALTER|ALTER TYPE BODY|82', concat(v_output));
	classify(q'[alter type test_type compile debug body]', v_output); assert_equals('ALTER TYPE BODY 3', 'DDL|ALTER|ALTER TYPE BODY|82', concat(v_output));
	classify(q'[alter type jheller.test_type compile debug body]', v_output); assert_equals('ALTER TYPE BODY 4', 'DDL|ALTER|ALTER TYPE BODY|82', concat(v_output));

	classify(q'[ALTER USER my_user profile default]', v_output); assert_equals('ALTER USER', 'DDL|ALTER|ALTER USER|43', concat(v_output));

	classify(q'[ALTER VIEW my_schema.my_view read only;]', v_output); assert_equals('ALTER VIEW', 'DDL|ALTER|ALTER VIEW|88', concat(v_output));

	--The syntax diagram in manual is wrong, it's "ANALYZE CLUSTER", not "CLUSTER ...".
	classify(q'[ ANALYZE CLUSTER my_cluster validate structure]', v_output); assert_equals('ANALYZE CLUSTER', 'DDL|ANALYZE|ANALYZE CLUSTER|64', concat(v_output));

	classify(q'[ ANALYZE INDEX my_index validate structure]', v_output); assert_equals('ANALYZE INDEX', 'DDL|ANALYZE|ANALYZE INDEX|63', concat(v_output));

	classify(q'[ ANALYZE TABLE my_table validate structure;]', v_output); assert_equals('ANALYZE TABLE', 'DDL|ANALYZE|ANALYZE TABLE|62', concat(v_output));

	classify(q'[associate statistics with columns my_schema.my_table using null;]', v_output); assert_equals('ASSOCIATE STATISTICS', 'DDL|ASSOCIATE STATISTICS|ASSOCIATE STATISTICS|168', concat(v_output));

	classify(q'[audit all on my_schema.my_table whenever not successful]', v_output); assert_equals('AUDIT OBJECT', 'DDL|AUDIT|AUDIT OBJECT|30', concat(v_output));
	classify(q'[audit policy some_policy;]', v_output); assert_equals('AUDIT OBJECT', 'DDL|AUDIT|AUDIT OBJECT|30', concat(v_output));

	classify(q'[CALL my_procedure(1,2)]', v_output); assert_equals('CALL METHOD', 'DML|CALL|CALL METHOD|170', concat(v_output));
	classify(q'[ call my_procedure(3,4);]', v_output); assert_equals('CALL METHOD', 'DML|CALL|CALL METHOD|170', concat(v_output));
	classify(q'[ call my_schema.my_type.my_method('asdf', 'qwer') into :variable;]', v_output); assert_equals('CALL METHOD', 'DML|CALL|CALL METHOD|170', concat(v_output));
	classify(q'[ call my_type(3,4).my_method() into :x;]', v_output); assert_equals('CALL METHOD', 'DML|CALL|CALL METHOD|170', concat(v_output));

	--I don't think this is a real command.
	--classify(q'[CHANGE PASSWORD]', v_output); assert_equals('CHANGE PASSWORD', 'DDL|ALTER|CHANGE PASSWORD|190', concat(v_output));

	classify(q'[comment on audit policy my_policy is 'asdf']', v_output); assert_equals('COMMENT', 'DDL|COMMENT|COMMENT|29', concat(v_output));
	classify(q'[comment on column my_schema.my_mv is q'!as'!';]', v_output); assert_equals('COMMENT', 'DDL|COMMENT|COMMENT|29', concat(v_output));
	classify(q'[comment on table some_table is 'asdfasdf']', v_output); assert_equals('COMMENT', 'DDL|COMMENT|COMMENT|29', concat(v_output));

	classify(q'[ commit work comment 'some comment' write wait batch]', v_output); assert_equals('COMMIT', 'Transaction Control|COMMIT|COMMIT|44', concat(v_output));
	classify(q'[COMMIT force corrupt_xid_all]', v_output); assert_equals('COMMIT', 'Transaction Control|COMMIT|COMMIT|44', concat(v_output));

	classify(q'[CREATE or replace analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 1', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));
	classify(q'[CREATE or replace force analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 2', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));
	classify(q'[CREATE or replace noforce analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 3', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));
	classify(q'[CREATE force analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 4', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));
	classify(q'[CREATE noforce analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 5', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));
	classify(q'[CREATE analytic view some_view using my_fact ...]', v_output); assert_equals('CREATE ANALYTIC VIEW 6', 'DDL|CREATE|CREATE ANALYTIC VIEW|249', concat(v_output));

	--Is this a real command?  http://dba.stackexchange.com/questions/96002/what-is-an-oracle-assembly/
	classify(q'[create or replace assembly some_assembly is 'some string';
	/]', v_output); assert_equals('CREATE ASSEMBLY', 'DDL|CREATE|CREATE ASSEMBLY|216', concat(v_output));

	classify(q'[ CREATE or replace ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 1', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));
	classify(q'[ CREATE or replace force ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 2', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));
	classify(q'[ CREATE or replace noforce ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 3', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));
	classify(q'[ CREATE force ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 4', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));
	classify(q'[ CREATE noforce ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 5', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));
	classify(q'[ CREATE ATTRIBUTE DIMENSION some_attribute_dimension dimension type time ... ]', v_output); assert_equals('CREATE ATTRIBUTE DIMENSION 6', 'DDL|CREATE|CREATE ATTRIBUTE DIMENSION|243', concat(v_output));

	classify(q'[CREATE AUDIT POLICY my_policy actions update on oe.orders]', v_output); assert_equals('CREATE AUDIT POLICY', 'DDL|CREATE|CREATE AUDIT POLICY|229', concat(v_output));

	--This is not a real command as far as I can tell.
	--classify(q'[CREATE BITMAPFILE]', v_output); assert_equals('CREATE BITMAPFILE', 'DDL|CREATE|CREATE BITMAPFILE|87', concat(v_output));

	classify(q'[CREATE CLUSTER my_schema.my_cluster(a number sort);]', v_output); assert_equals('CREATE CLUSTER', 'DDL|CREATE|CREATE CLUSTER|4', concat(v_output));

	classify(q'[CREATE CONTEXT my_context using my_package;]', v_output); assert_equals('CREATE CONTEXT', 'DDL|CREATE|CREATE CONTEXT|177', concat(v_output));
	classify(q'[CREATE or  REplace  CONTEXT my_context using my_package;]', v_output); assert_equals('CREATE CONTEXT', 'DDL|CREATE|CREATE CONTEXT|177', concat(v_output));

	classify(q'[CREATE CONTROLFILE database my_db resetlogs]', v_output); assert_equals('CREATE CONTROL FILE', 'DDL|CREATE|CREATE CONTROL FILE|57', concat(v_output));

	classify(q'[CREATE DATABASE my_database controlfile reuse;]', v_output); assert_equals('CREATE DATABASE', 'DDL|CREATE|CREATE DATABASE|34', concat(v_output));

	classify(q'[CREATE DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_output); assert_equals('CREATE DATABASE LINK', 'DDL|CREATE|CREATE DATABASE LINK|32', concat(v_output));
	classify(q'[CREATE shared DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_output); assert_equals('CREATE DATABASE LINK', 'DDL|CREATE|CREATE DATABASE LINK|32', concat(v_output));
	classify(q'[CREATE public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_output); assert_equals('CREATE DATABASE LINK', 'DDL|CREATE|CREATE DATABASE LINK|32', concat(v_output));
	classify(q'[CREATE shared public DATABASE LINK my_link connect to my_user identified by "some_password*#&$@" using 'orcl1234';]', v_output); assert_equals('CREATE DATABASE LINK', 'DDL|CREATE|CREATE DATABASE LINK|32', concat(v_output));

	classify(q'[CREATE DIMENSION my_schema.my_dimension level l1 is t1.a;]', v_output); assert_equals('CREATE DIMENSION', 'DDL|CREATE|CREATE DIMENSION|174', concat(v_output));

	classify(q'[CREATE DIRECTORY my_directory#$1 as '/load/blah/']', v_output); assert_equals('CREATE DIRECTORY', 'DDL|CREATE|CREATE DIRECTORY|157', concat(v_output));
	classify(q'[CREATE or replace DIRECTORY my_directory#$1 as '/load/blah/']', v_output); assert_equals('CREATE DIRECTORY', 'DDL|CREATE|CREATE DIRECTORY|157', concat(v_output));

	--Command name has extra space, real command is "DISKGROUP".
	classify(q'[CREATE DISKGROUP my_diskgroup disk '/emc/powersomething/' size 555m;]', v_output); assert_equals('CREATE DISK GROUP', 'DDL|CREATE|CREATE DISK GROUP|194', concat(v_output));

	classify(q'[CREATE EDITION my_edition as child of my_parent;]', v_output); assert_equals('CREATE EDITION', 'DDL|CREATE|CREATE EDITION|212', concat(v_output));

	classify(q'[CREATE FLASHBACK ARCHIVE default my_fba tablespace my_ts quota 5g;]', v_output); assert_equals('CREATE FLASHBACK ARCHIVE', 'DDL|CREATE|CREATE FLASHBACK ARCHIVE|218', concat(v_output));

	classify(q'[CREATE FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));
	classify(q'[CREATE or replace FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));
	classify(q'[CREATE or replace editionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));
	classify(q'[CREATE or replace noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));
	classify(q'[CREATE editionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));
	classify(q'[CREATE noneditionable FUNCTION my_schema.my_function() return number is begin return 1; end; /]', v_output); assert_equals('CREATE FUNCTION', 'DDL|CREATE|CREATE FUNCTION|91', concat(v_output));

	classify(q'[CREATE hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 1', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));
	classify(q'[CREATE or replace hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 2', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));
	classify(q'[CREATE or replace force hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 3', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));
	classify(q'[CREATE or replace noforce hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 4', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));
	classify(q'[CREATE force hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 5', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));
	classify(q'[CREATE noforce hierarchy some_hierarchy using some_attr ...]', v_output); assert_equals('CREATE HIERARCHY 6', 'DDL|CREATE|CREATE HIERARCHY|246', concat(v_output));

	classify(q'[CREATE INDEX on table1(a);]', v_output); assert_equals('CREATE INDEX', 'DDL|CREATE|CREATE INDEX|9', concat(v_output));
	classify(q'[CREATE unique INDEX on table1(a);]', v_output); assert_equals('CREATE INDEX', 'DDL|CREATE|CREATE INDEX|9', concat(v_output));
	classify(q'[CREATE bitmap INDEX on table1(a);]', v_output); assert_equals('CREATE INDEX', 'DDL|CREATE|CREATE INDEX|9', concat(v_output));

	classify(q'[CREATE INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]', v_output); assert_equals('CREATE INDEXTYPE', 'DDL|CREATE|CREATE INDEXTYPE|164', concat(v_output));
	classify(q'[CREATE or replace INDEXTYPE my_schema.my_indextype for indtype(a number) using my_type;]', v_output); assert_equals('CREATE INDEXTYPE', 'DDL|CREATE|CREATE INDEXTYPE|164', concat(v_output));

	classify(q'[CREATE inmemory join group my_group (my_table(my_column));]', v_output); assert_equals('CREATE INMEMORY JOIN GROUP', 'DDL|CREATE|CREATE INMEMORY JOIN GROUP|-102', concat(v_output));

	--12 combinations of initial keywords.  COMPILE is optional here, but not elsewhere so it requires special handling.
	classify(q'[CREATE and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE and resolve JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE and compile JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace and resolve noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace and resolve  JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace and compile noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace and compile  JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace noforce JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));
	classify(q'[CREATE or replace JAVA CLASS USING BFILE (java_dir, 'Agent.class') --]'||chr(10)||'/', v_output); assert_equals('CREATE JAVA', 'DDL|CREATE|CREATE JAVA|160', concat(v_output));

	classify(q'[CREATE LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));
	classify(q'[CREATE or replace LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));
	classify(q'[CREATE or replace editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));
	classify(q'[CREATE or replace noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));
	classify(q'[CREATE editionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));
	classify(q'[CREATE noneditionable LIBRARY ext_lib AS 'ddl_1' IN ddl_dir;]'||chr(10)||'/', v_output); assert_equals('CREATE LIBRARY', 'DDL|CREATE|CREATE LIBRARY|159', concat(v_output));

	classify(q'[create lockdown profile my_profile;]', v_output); assert_equals('CREATE LOCKDOWN PROFILE', 'DDL|CREATE|CREATE LOCKDOWN PROFILE|234', concat(v_output));

	classify(q'[CREATE MATERIALIZED VIEW my_mv as select 1 a from dual;]', v_output); assert_equals('CREATE MATERIALIZED VIEW ', 'DDL|CREATE|CREATE MATERIALIZED VIEW |74', concat(v_output));
	classify(q'[CREATE SNAPSHOT my_mv as select 1 a from dual;]', v_output); assert_equals('CREATE MATERIALIZED VIEW ', 'DDL|CREATE|CREATE MATERIALIZED VIEW |74', concat(v_output));

	classify(q'[CREATE MATERIALIZED VIEW LOG on my_table with (a)]', v_output); assert_equals('CREATE MATERIALIZED VIEW LOG', 'DDL|CREATE|CREATE MATERIALIZED VIEW LOG|71', concat(v_output));
	classify(q'[CREATE SNAPSHOT LOG on my_table with (a)]', v_output); assert_equals('CREATE MATERIALIZED VIEW LOG', 'DDL|CREATE|CREATE MATERIALIZED VIEW LOG|71', concat(v_output));

	classify(q'[CREATE MATERIALIZED ZONEMAP sales_zmap ON sales(cust_id, prod_id);]', v_output); assert_equals('CREATE MATERIALIZED ZONEMAP', 'DDL|CREATE|CREATE MATERIALIZED ZONEMAP|239', concat(v_output));

	classify(q'[CREATE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]', v_output); assert_equals('CREATE OPERATOR', 'DDL|CREATE|CREATE OPERATOR|163', concat(v_output));
	classify(q'[CREATE OR REPLACE OPERATOR eq_op BINDING (VARCHAR2, VARCHAR2) RETURN NUMBER USING eq_f; ]', v_output); assert_equals('CREATE OPERATOR', 'DDL|CREATE|CREATE OPERATOR|163', concat(v_output));

	classify(q'[CREATE or replace OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE or replace public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE or replace private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE public OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));
	classify(q'[CREATE private OUTLINE salaries FOR CATEGORY special ON SELECT last_name, salary FROM employees;]', v_output); assert_equals('CREATE OUTLINE', 'DDL|CREATE|CREATE OUTLINE|180', concat(v_output));

	classify(q'[CREATE PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));
	classify(q'[CREATE editionable PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));
	classify(q'[CREATE noneditionable PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));
	classify(q'[CREATE or replace PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));
	classify(q'[CREATE or replace editionable PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));
	classify(q'[CREATE or replace noneditionable PACKAGE my_package is v_number number; end; /]', v_output); assert_equals('CREATE PACKAGE', 'DDL|CREATE|CREATE PACKAGE|94', concat(v_output));

	classify(q'[CREATE PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));
	classify(q'[CREATE editionable PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));
	classify(q'[CREATE noneditionable PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));
	classify(q'[CREATE or replace PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));
	classify(q'[CREATE or replace editionable PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));
	classify(q'[CREATE or replace noneditionable PACKAGE BODY my_package is begin null; end;]', v_output); assert_equals('CREATE PACKAGE BODY', 'DDL|CREATE|CREATE PACKAGE BODY|97', concat(v_output));

	classify(q'[CREATE PFILE from memory;]', v_output); assert_equals('CREATE PFILE', 'DDL|CREATE|CREATE PFILE|188', concat(v_output));

	classify(q'[CREATE PLUGGABLE DATABASE my_pdb from another_pdb]', v_output); assert_equals('CREATE PLUGGABLE DATABASE', 'DDL|CREATE|CREATE PLUGGABLE DATABASE|226', concat(v_output));

	classify(q'[CREATE PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));
	classify(q'[CREATE editionable PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));
	classify(q'[CREATE noneditionable PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));
	classify(q'[CREATE or replace PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));
	classify(q'[CREATE or replace editionable PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));
	classify(q'[CREATE or replace noneditionable PROCEDURE my proc is begin null; end; /]', v_output); assert_equals('CREATE PROCEDURE', 'DDL|CREATE|CREATE PROCEDURE|24', concat(v_output));

	classify(q'[CREATE PROFILE my_profile limit sessions_per_user 50;]', v_output); assert_equals('CREATE PROFILE', 'DDL|CREATE|CREATE PROFILE|65', concat(v_output));

	classify(q'[CREATE RESTORE POINT before_change gaurantee flashback database;]', v_output); assert_equals('CREATE RESTORE POINT', 'DDL|CREATE|CREATE RESTORE POINT|206', concat(v_output));

	classify(q'[CREATE ROLE my_role;]', v_output); assert_equals('CREATE ROLE', 'DDL|CREATE|CREATE ROLE|52', concat(v_output));

	classify(q'[CREATE ROLLBACK SEGMENT my_rbs]', v_output); assert_equals('CREATE ROLLBACK SEGMENT', 'DDL|CREATE|CREATE ROLLBACK SEGMENT|36', concat(v_output));
	classify(q'[CREATE public ROLLBACK SEGMENT my_rbs]', v_output); assert_equals('CREATE ROLLBACK SEGMENT', 'DDL|CREATE|CREATE ROLLBACK SEGMENT|36', concat(v_output));

	classify(q'[CREATE SCHEMA authorization my_schema grant select on table1 to user2 grant select on table2 to user3]', v_output); assert_equals('CREATE SCHEMA', 'DDL|CREATE|CREATE SCHEMA|56', concat(v_output));

	--Undocumented feature.
	classify(q'[CREATE SCHEMA SYNONYM demo2 for demo1]', v_output); assert_equals('CREATE SCHEMA SYNONYM', 'DDL|CREATE|CREATE SCHEMA SYNONYM|222', concat(v_output));

	classify(q'[CREATE SEQUENCE my_schema.my_sequence cache 20;]', v_output); assert_equals('CREATE SEQUENCE', 'DDL|CREATE|CREATE SEQUENCE|13', concat(v_output));

	classify(q'[CREATE SPFILE = 'my_spfile' from pfile;]', v_output); assert_equals('CREATE SPFILE', 'DDL|CREATE|CREATE SPFILE|187', concat(v_output));

	--An old version of "CREATE SNAPSHOT"?  This is not supported in 11gR2+.
	--classify(q'[CREATE SUMMARY]', v_output); assert_equals('CREATE SUMMARY', 'DDL|CREATE|CREATE SUMMARY|171', concat(v_output));

	classify(q'[CREATE SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE editionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace editionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace editionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace noneditionable SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));
	classify(q'[CREATE or replace noneditionable public SYNONYM my_synonym for other_schema.some_object@some_link;]', v_output); assert_equals('CREATE SYNONYM', 'DDL|CREATE|CREATE SYNONYM|19', concat(v_output));

	classify(q'[CREATE TABLE my_table(a number);]', v_output); assert_equals('CREATE TABLE 1', 'DDL|CREATE|CREATE TABLE|1', concat(v_output));
	classify(q'[CREATE global temporary TABLE my_table(a number);]', v_output); assert_equals('CREATE TABLE 2', 'DDL|CREATE|CREATE TABLE|1', concat(v_output));
	classify(q'[CREATE sharded TABLE my_table(a number);]', v_output); assert_equals('CREATE TABLE 3', 'DDL|CREATE|CREATE TABLE|1', concat(v_output));
	classify(q'[CREATE duplicated TABLE my_table(a number);]', v_output); assert_equals('CREATE TABLE 4', 'DDL|CREATE|CREATE TABLE|1', concat(v_output));

	classify(q'[create tablespace set my_set;]', v_output); assert_equals('CREATE TABLESPACE SET', 'DDL|CREATE|CREATE TABLESPACE SET|-202', concat(v_output));

	classify(q'[CREATE TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE temporary TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE temporary bigfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE temporary smallfile TABLESPACE my_tbs tempfile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE undo TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE undo bigfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));
	classify(q'[CREATE undo smallfile TABLESPACE my_tbs datafile '+mydg' size 100m autoextend on;]', v_output); assert_equals('CREATE TABLESPACE', 'DDL|CREATE|CREATE TABLESPACE|39', concat(v_output));

	classify(q'[CREATE TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));
	classify(q'[CREATE editionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));
	classify(q'[CREATE noneditionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));
	classify(q'[CREATE or replace TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));
	classify(q'[CREATE or replace editionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));
	classify(q'[CREATE or replace noneditionable TRIGGER my_trigger before insert on my_table begin null; end; /]', v_output); assert_equals('CREATE TRIGGER', 'DDL|CREATE|CREATE TRIGGER|59', concat(v_output));

	classify(q'[CREATE TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));
	classify(q'[CREATE editionable TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));
	classify(q'[CREATE noneditionable TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));
	classify(q'[CREATE or replace TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));
	classify(q'[CREATE or replace editionable TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));
	classify(q'[CREATE or replace noneditionable TYPE my_type as object(a number); /]', v_output); assert_equals('CREATE TYPE', 'DDL|CREATE|CREATE TYPE|77', concat(v_output));

	classify(q'[CREATE TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));
	classify(q'[CREATE editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));
	classify(q'[CREATE noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));
	classify(q'[CREATE or replace TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));
	classify(q'[CREATE or replace editionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));
	classify(q'[CREATE or replace noneditionable TYPE BODY my_type is member function my_function return number is begin return 1; end; end; ]', v_output); assert_equals('CREATE TYPE BODY', 'DDL|CREATE|CREATE TYPE BODY|81', concat(v_output));

	classify(q'[CREATE USER my_user identified by "asdf";]', v_output); assert_equals('CREATE USER', 'DDL|CREATE|CREATE USER|51', concat(v_output));

	classify(q'[CREATE VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 1', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 2', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 3', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 4', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 5', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE force VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 6', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE force editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 7', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE force editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 8', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE force editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 9', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE force noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 10', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE no force VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 11', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE no force editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 12', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE no force editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 13', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE no force editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 14', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE no force noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 15', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 16', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 17', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 18', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 19', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 20', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace force VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 21', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace force editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 22', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace force editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 23', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace force editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 24', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace force noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 25', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace no force VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 26', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace no force editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 27', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace no force editionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 28', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace no force editionable editioning VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 29', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));
	classify(q'[CREATE or replace no force noneditionable VIEW my_view as select 1 a from dual;]', v_output); assert_equals('CREATE VIEW 30', 'DDL|CREATE|CREATE VIEW|21', concat(v_output));

	--Not a real command.
	--classify(q'[DECLARE REWRITE EQUIVALENCE]', v_output); assert_equals('DECLARE REWRITE EQUIVALENCE', 'DDL|ALTER|DECLARE REWRITE EQUIVALENCE|209', concat(v_output));

	classify(q'[DELETE my_schema.my_table@my_link]', v_output); assert_equals('DELETE', 'DML|DELETE|DELETE|7', concat(v_output));
	classify(q'[DELETE FROM my_schema.my_table@my_link]', v_output); assert_equals('DELETE', 'DML|DELETE|DELETE|7', concat(v_output));

	classify(q'[DISASSOCIATE STATISTICS from columns mytable.a force;]', v_output); assert_equals('DISASSOCIATE STATISTICS', 'DDL|DISASSOCIATE STATISTICS|DISASSOCIATE STATISTICS|169', concat(v_output));

	classify(q'[drop analytic view some_view;]', v_output); assert_equals('DROP ANALYTIC VIEW', 'DDL|DROP|DROP ANALYTIC VIEW|251', concat(v_output));

	classify(q'[DROP ASSEMBLY my_assembly]', v_output); assert_equals('DROP ASSEMBLY', 'DDL|DROP|DROP ASSEMBLY|215', concat(v_output));

	classify(q'[DROP attribute dimension asdf;]', v_output); assert_equals('DROP ATTRIBUTE DIMENSION', 'DDL|DROP|DROP ATTRIBUTE DIMENSION|245', concat(v_output));

	classify(q'[DROP AUDIT POLICY my_policy;]', v_output); assert_equals('DROP AUDIT POLICY', 'DDL|DROP|DROP AUDIT POLICY|231', concat(v_output));

	--This isn't a real command as far as I can tell.
	--classify(q'[DROP BITMAPFILE]', v_output); assert_equals('DROP BITMAPFILE', 'DDL|DROP|DROP BITMAPFILE|89', concat(v_output));

	classify(q'[DROP CLUSTER my_cluster]', v_output); assert_equals('DROP CLUSTER', 'DDL|DROP|DROP CLUSTER|8', concat(v_output));

	classify(q'[DROP CONTEXT my_context;]', v_output); assert_equals('DROP CONTEXT', 'DDL|DROP|DROP CONTEXT|178', concat(v_output));

	classify(q'[DROP DATABASE;]', v_output); assert_equals('DROP DATABASE', 'DDL|DROP|DROP DATABASE|203', concat(v_output));

	classify(q'[DROP DATABASE LINK my_link;]', v_output); assert_equals('DROP DATABASE LINK', 'DDL|DROP|DROP DATABASE LINK|33', concat(v_output));
	classify(q'[DROP public DATABASE LINK my_link;]', v_output); assert_equals('DROP DATABASE LINK', 'DDL|DROP|DROP DATABASE LINK|33', concat(v_output));

	classify(q'[DROP DIMENSION my_dimenson;]', v_output); assert_equals('DROP DIMENSION', 'DDL|DROP|DROP DIMENSION|176', concat(v_output));

	classify(q'[DROP DIRECTORY my_directory;]', v_output); assert_equals('DROP DIRECTORY', 'DDL|DROP|DROP DIRECTORY|158', concat(v_output));

	--Command name has extra space, real command is "DISKGROUP".
	classify(q'[DROP DISKGROUP fradg force including contents;]', v_output); assert_equals('DROP DISK GROUP', 'DDL|DROP|DROP DISK GROUP|195', concat(v_output));

	classify(q'[DROP EDITION my_edition cascade;]', v_output); assert_equals('DROP EDITION', 'DDL|DROP|DROP EDITION|214', concat(v_output));

	classify(q'[DROP FLASHBACK ARCHIVE my_fba;]', v_output); assert_equals('DROP FLASHBACK ARCHIVE', 'DDL|DROP|DROP FLASHBACK ARCHIVE|220', concat(v_output));

	classify(q'[DROP FUNCTION my_schema.my_function;]', v_output); assert_equals('DROP FUNCTION', 'DDL|DROP|DROP FUNCTION|93', concat(v_output));

	classify(q'[DROP hierarchy my_hierarchy; ]', v_output); assert_equals('DROP HIERARCHY', 'DDL|DROP|DROP HIERARCHY|248', concat(v_output));

	classify(q'[DROP INDEX my_schema.my_index online force;]', v_output); assert_equals('DROP INDEX', 'DDL|DROP|DROP INDEX|10', concat(v_output));

	classify(q'[DROP INDEXTYPE my_indextype force;]', v_output); assert_equals('DROP INDEXTYPE', 'DDL|DROP|DROP INDEXTYPE|165', concat(v_output));

	classify(q'[DROP inmemory  join  group my_group;]', v_output); assert_equals('DROP INMEMORY JOIN GROUP', 'DDL|DROP|DROP INMEMORY JOIN GROUP|-103', concat(v_output));

	classify(q'[DROP JAVA resourse some_resource;]', v_output); assert_equals('DROP JAVA', 'DDL|DROP|DROP JAVA|162', concat(v_output));

	classify(q'[DROP LIBRARY my_library]', v_output); assert_equals('DROP LIBRARY', 'DDL|DROP|DROP LIBRARY|84', concat(v_output));

	classify(q'[DROP lockdown profile some_profile;]', v_output); assert_equals('DROP LOCKDOWN PROFILE', 'DDL|DROP|DROP LOCKDOWN PROFILE|235', concat(v_output));

	--Commands have an extra space in them.
	classify(q'[DROP MATERIALIZED VIEW my_mv preserve table]', v_output); assert_equals('DROP MATERIALIZED VIEW', 'DDL|DROP|DROP MATERIALIZED VIEW |76', concat(v_output));
	classify(q'[DROP SNAPSHOT my_mv preserve table]', v_output); assert_equals('DROP MATERIALIZED VIEW', 'DDL|DROP|DROP MATERIALIZED VIEW |76', concat(v_output));

	classify(q'[DROP MATERIALIZED VIEW LOG on some_table;]', v_output); assert_equals('DROP MATERIALIZED VIEW LOG', 'DDL|DROP|DROP MATERIALIZED VIEW  LOG|73', concat(v_output));
	classify(q'[DROP snapshot LOG on some_table;]', v_output); assert_equals('DROP MATERIALIZED VIEW LOG', 'DDL|DROP|DROP MATERIALIZED VIEW  LOG|73', concat(v_output));

	classify(q'[DROP MATERIALIZED ZONEMAP my_schema.my_zonemap]', v_output); assert_equals('DROP MATERIALIZED ZONEMAP', 'DDL|DROP|DROP MATERIALIZED ZONEMAP|241', concat(v_output));

	classify(q'[DROP OPERATOR my_operator force;]', v_output); assert_equals('DROP OPERATOR', 'DDL|DROP|DROP OPERATOR|167', concat(v_output));

	classify(q'[DROP OUTLINE my_outline;]', v_output); assert_equals('DROP OUTLINE', 'DDL|DROP|DROP OUTLINE|181', concat(v_output));

	classify(q'[DROP PACKAGE my_package]', v_output); assert_equals('DROP PACKAGE', 'DDL|DROP|DROP PACKAGE|96', concat(v_output));

	classify(q'[DROP PACKAGE BODY my_package;]', v_output); assert_equals('DROP PACKAGE BODY', 'DDL|DROP|DROP PACKAGE BODY|99', concat(v_output));

	classify(q'[DROP PLUGGABLE DATABASE my_pdb]', v_output); assert_equals('DROP PLUGGABLE DATABASE', 'DDL|DROP|DROP PLUGGABLE DATABASE|228', concat(v_output));

	classify(q'[DROP PROCEDURE my_proc]', v_output); assert_equals('DROP PROCEDURE', 'DDL|DROP|DROP PROCEDURE|68', concat(v_output));

	classify(q'[DROP PROFILE my_profile cascade;]', v_output); assert_equals('DROP PROFILE', 'DDL|DROP|DROP PROFILE|66', concat(v_output));

	classify(q'[DROP RESTORE POINT my_restore_point]', v_output); assert_equals('DROP RESTORE POINT', 'DDL|DROP|DROP RESTORE POINT|207', concat(v_output));

	--This is not a real command.
	--classify(q'[DROP REWRITE EQUIVALENCE]', v_output); assert_equals('DROP REWRITE EQUIVALENCE', 'DDL|DROP|DROP REWRITE EQUIVALENCE|211', concat(v_output));

	classify(q'[DROP ROLE my_role]', v_output); assert_equals('DROP ROLE', 'DDL|DROP|DROP ROLE|54', concat(v_output));

	classify(q'[DROP ROLLBACK SEGMENT my_rbs]', v_output); assert_equals('DROP ROLLBACK SEGMENT', 'DDL|DROP|DROP ROLLBACK SEGMENT|38', concat(v_output));

	--Undocumented feature.
	classify(q'[DROP SCHEMA SYNONYM a_schema_synonym]', v_output); assert_equals('DROP SCHEMA SYNONYM', 'DDL|DROP|DROP SCHEMA SYNONYM|224', concat(v_output));

	classify(q'[DROP SEQUENCE my_sequence;]', v_output); assert_equals('DROP SEQUENCE', 'DDL|DROP|DROP SEQUENCE|16', concat(v_output));

	--An old version of "DROP SNAPSHOT"?  This is not supported in 11gR2+.
	--classify(q'[DROP SUMMARY]', v_output); assert_equals('DROP SUMMARY', 'DDL|DROP|DROP SUMMARY|173', concat(v_output));

	classify(q'[DROP SYNONYM my_synonym]', v_output); assert_equals('DROP SYNONYM', 'DDL|DROP|DROP SYNONYM|20', concat(v_output));
	classify(q'[DROP public SYNONYM my_synonym]', v_output); assert_equals('DROP SYNONYM', 'DDL|DROP|DROP SYNONYM|20', concat(v_output));

	classify(q'[DROP TABLE my_schema.my_table cascade constraints purge]', v_output); assert_equals('DROP TABLE', 'DDL|DROP|DROP TABLE|12', concat(v_output));

	classify(q'[DROP TABLESPACE set asdf;;]', v_output); assert_equals('DROP TABLESPACE SET', 'DDL|DROP|DROP TABLESPACE SET|-203', concat(v_output));

	classify(q'[DROP TABLESPACE my_tbs including contents and datafiles cascade constraints;]', v_output); assert_equals('DROP TABLESPACE', 'DDL|DROP|DROP TABLESPACE|41', concat(v_output));

	classify(q'[DROP TRIGGER my_trigger]', v_output); assert_equals('DROP TRIGGER', 'DDL|DROP|DROP TRIGGER|61', concat(v_output));

	classify(q'[DROP TYPE my_type validate]', v_output); assert_equals('DROP TYPE', 'DDL|DROP|DROP TYPE|78', concat(v_output));

	classify(q'[DROP TYPE BODY my_type]', v_output); assert_equals('DROP TYPE BODY', 'DDL|DROP|DROP TYPE BODY|83', concat(v_output));

	classify(q'[DROP USER my_user cascde;]', v_output); assert_equals('DROP USER', 'DDL|DROP|DROP USER|53', concat(v_output));

	classify(q'[DROP VIEW my_schema.my_view cascade constraints;]', v_output); assert_equals('DROP VIEW', 'DDL|DROP|DROP VIEW|22', concat(v_output));

	--classify(q'[Do not use 184]', v_output); assert_equals('Do not use 184', 'DDL|ALTER|Do not use 184|184', concat(v_output));
	--classify(q'[Do not use 185]', v_output); assert_equals('Do not use 185', 'DDL|ALTER|Do not use 185|185', concat(v_output));
	--classify(q'[Do not use 186]', v_output); assert_equals('Do not use 186', 'DDL|ALTER|Do not use 186|186', concat(v_output));

	classify(q'[EXPLAIN plan set statement_id='asdf' for select * from dual]', v_output); assert_equals('EXPLAIN 1', 'DML|EXPLAIN PLAN|EXPLAIN|50', concat(v_output));
	classify(q'[explain plan for with function f return number is begin return 1; end; select f from dual;]', v_output); assert_equals('EXPLAIN 2', 'DML|EXPLAIN PLAN|EXPLAIN|50', concat(v_output));

	classify(q'[FLASHBACK DATABASE to restore point my_restore_point]', v_output); assert_equals('FLASHBACK DATABASE', 'DDL|FLASHBACK|FLASHBACK DATABASE|204', concat(v_output));
	classify(q'[FLASHBACK standby DATABASE to restore point my_restore_point]', v_output); assert_equals('FLASHBACK DATABASE', 'DDL|FLASHBACK|FLASHBACK DATABASE|204', concat(v_output));

	classify(q'[FLASHBACK TABLE my_schema.my_table to timestamp timestamp '2015-01-01 12:00:00']', v_output); assert_equals('FLASHBACK TABLE', 'DDL|FLASHBACK|FLASHBACK TABLE|205', concat(v_output));

	classify(q'[GRANT dba my_user]', v_output); assert_equals('GRANT OBJECT 1', 'DDL|GRANT|GRANT OBJECT|17', concat(v_output));
	classify(q'[GRANT select on my_table to some_other_user with grant option]', v_output); assert_equals('GRANT OBJECT 2', 'DDL|GRANT|GRANT OBJECT|17', concat(v_output));
	classify(q'[GRANT dba to my_package]', v_output); assert_equals('GRANT OBJECT 3', 'DDL|GRANT|GRANT OBJECT|17', concat(v_output));

	classify(q'[INSERT /*+ append */ into my_table select * from other_table]', v_output); assert_equals('INSERT 1', 'DML|INSERT|INSERT|2', concat(v_output));
	classify(q'[INSERT all into table1(a) values(b) into table2(a) values(b) select b from another_table;]', v_output); assert_equals('INSERT 2', 'DML|INSERT|INSERT|2', concat(v_output));
	classify(q'[insert into test1 with function f return number is begin return 1; end; select f from dual;]', v_output); assert_equals('INSERT 3', 'DML|INSERT|INSERT|2', concat(v_output));

	classify(q'[LOCK TABLE my_schema.my_table in exclsive mode]', v_output); assert_equals('LOCK TABLE', 'DML|LOCK TABLE|LOCK TABLE|26', concat(v_output));

	--See "UPSERT" for "MERGE".
	--classify(q'[NO-OP]', v_output); assert_equals('NO-OP', 'DDL|ALTER|NO-OP|27', concat(v_output));

	classify(q'[NOAUDIT insert any table]', v_output); assert_equals('NOAUDIT OBJECT', 'DDL|NOAUDIT|NOAUDIT OBJECT|31', concat(v_output));
	classify(q'[NOAUDIT policy my_policy by some_user]', v_output); assert_equals('NOAUDIT OBJECT', 'DDL|NOAUDIT|NOAUDIT OBJECT|31', concat(v_output));

	classify(q'[ <<my_label>>begin null; end;]', v_output); assert_equals('PL/SQL EXECUTE 1', 'PL/SQL|BLOCK|PL/SQL EXECUTE|47', concat(v_output));
	classify(q'[/*asdf*/declare v_test number; begin null; end; /]', v_output); assert_equals('PL/SQL EXECUTE 2', 'PL/SQL|BLOCK|PL/SQL EXECUTE|47', concat(v_output));
	classify(q'[  begin null; end; /]', v_output); assert_equals('PL/SQL EXECUTE 3', 'PL/SQL|BLOCK|PL/SQL EXECUTE|47', concat(v_output));

	--Command name has space instead of underscore.
 	classify(q'[PURGE DBA_RECYCLEBIN;]', v_output); assert_equals('PURGE DBA RECYCLEBIN', 'DDL|PURGE|PURGE DBA RECYCLEBIN|198', concat(v_output));

	classify(q'[PURGE INDEX my_index]', v_output); assert_equals('PURGE INDEX', 'DDL|PURGE|PURGE INDEX|201', concat(v_output));

	classify(q'[PURGE TABLE my_table]', v_output); assert_equals('PURGE TABLE', 'DDL|PURGE|PURGE TABLE|200', concat(v_output));

	classify(q'[PURGE TABLESPACE SET some_set]', v_output); assert_equals('PURGE TABLESPACE SET', 'DDL|PURGE|PURGE TABLESPACE SET|-204', concat(v_output));

	classify(q'[PURGE TABLESPACE my_tbs user my_user]', v_output); assert_equals('PURGE TABLESPACE', 'DDL|PURGE|PURGE TABLESPACE|199', concat(v_output));

	--Command name has extra "USER".
	classify(q'[PURGE RECYCLEBIN;]', v_output); assert_equals('PURGE USER RECYCLEBIN', 'DDL|PURGE|PURGE USER RECYCLEBIN|197', concat(v_output));

	classify(q'[RENAME old_table to new_table]', v_output); assert_equals('RENAME', 'DDL|RENAME|RENAME|28', concat(v_output));

	classify(q'[REVOKE select any table from my_user]', v_output); assert_equals('REVOKE OBJECT 1', 'DDL|REVOKE|REVOKE OBJECT|18', concat(v_output));
	classify(q'[REVOKE select on my_tables from user2]', v_output); assert_equals('REVOKE OBJECT 2', 'DDL|REVOKE|REVOKE OBJECT|18', concat(v_output));
	classify(q'[REVOKE dba from my_package]', v_output); assert_equals('REVOKE OBJECT 3', 'DDL|REVOKE|REVOKE OBJECT|18', concat(v_output));

	classify(q'[ROLLBACK;]', v_output); assert_equals('ROLLBACK 1', 'Transaction Control|ROLLBACK|ROLLBACK|45', concat(v_output));
	classify(q'[ROLLBACK work;]', v_output); assert_equals('ROLLBACK 2', 'Transaction Control|ROLLBACK|ROLLBACK|45', concat(v_output));
	classify(q'[ROLLBACK to savepoint savepoint1]', v_output); assert_equals('ROLLBACK 3', 'Transaction Control|ROLLBACK|ROLLBACK|45', concat(v_output));

	classify(q'[SAVEPOINT my_savepoint;]', v_output); assert_equals('SAVEPOINT', 'Transaction Control|SAVEPOINT|SAVEPOINT|46', concat(v_output));

	classify(q'[select * from dual;]', v_output); assert_equals('SELECT 1', 'DML|SELECT|SELECT|3', concat(v_output));
	classify(q'[/*asdf*/select * from dual;]', v_output); assert_equals('SELECT 2', 'DML|SELECT|SELECT|3', concat(v_output));
	classify(q'[((((select * from dual))));]', v_output); assert_equals('SELECT 3', 'DML|SELECT|SELECT|3', concat(v_output));
	classify(q'[with test1 as (select 1 a from dual) select * from test1;]', v_output); assert_equals('SELECT 4', 'DML|SELECT|SELECT|3', concat(v_output));
	classify(q'[with function test_function return number is begin return 1; end; select test_function from dual;
	/]', v_output); assert_equals('SELECT 4', 'DML|SELECT|SELECT|3', concat(v_output));

	--There are two versions of CONSTRAINT[S].
	classify(q'[SET CONSTRAINTS all deferred]', v_output); assert_equals('SET CONSTRAINT', 'Transaction Control|SET CONSTRAINT|SET CONSTRAINTS|90', concat(v_output));
	classify(q'[SET CONSTRAINT all immediate]', v_output); assert_equals('SET CONSTRAINT', 'Transaction Control|SET CONSTRAINT|SET CONSTRAINTS|90', concat(v_output));

	classify(q'[SET ROLE none]', v_output); assert_equals('SET ROLE', 'Session Control|SET ROLE|SET ROLE|55', concat(v_output));

	classify(q'[SET TRANSACTION read only]', v_output); assert_equals('SET TRANSACTION', 'Transaction Control|SET TRANSACTION|SET TRANSACTION|48', concat(v_output));

	classify(q'[TRUNCATE CLUSTER my_schema.my_cluster drop storage;]', v_output); assert_equals('TRUNCATE CLUSTER', 'DDL|TRUNCATE|TRUNCATE CLUSTER|86', concat(v_output));

	classify(q'[TRUNCATE TABLE my_schema.my_table purge materialized view log]', v_output); assert_equals('TRUNCATE TABLE', 'DDL|TRUNCATE|TRUNCATE TABLE|85', concat(v_output));

	--Not a real command.
	--classify(q'[UNDROP OBJECT]', v_output); assert_equals('UNDROP OBJECT', 'DDL|ALTER|UNDROP OBJECT|202', concat(v_output));

	classify(q'[UPDATE my_tables set a = 1]', v_output); assert_equals('UPDATE 1', 'DML|UPDATE|UPDATE|6', concat(v_output));
	classify(q'[UPDATE my_tables set a = (with function f return number is begin return 1; end; select f from dual);]', v_output); assert_equals('UPDATE 2', 'DML|UPDATE|UPDATE|6', concat(v_output));

	--These are not real commands (they are part of alter table) and they could be ambiguous with an UPDATE statement
	--if there was a table named "INDEXES" or "JOIN".
	--classify(q'[UPDATE INDEXES]', v_output); assert_equals('UPDATE INDEXES', '?|?|UPDATE INDEXES|182', concat(v_output));
	--classify(q'[UPDATE JOIN INDEX]', v_output); assert_equals('UPDATE JOIN INDEX', '?|?|UPDATE JOIN INDEX|191', concat(v_output));

	classify(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = 1;]', v_output); assert_equals('UPSERT 1', 'DML|MERGE|UPSERT|189', concat(v_output));
	classify(q'[merge into table1 using table2 on (table1.a = table2.a) when matched then update set table1.b = (with function test_function return number is begin return 1; end; select test_function from dual);]', v_output); assert_equals('UPSERT 2', 'DML|MERGE|UPSERT|189', concat(v_output));

	--Not a real command, this is part of ANALYZE.
	--classify(q'[VALIDATE INDEX]', v_output); assert_equals('VALIDATE INDEX', '?|?|VALIDATE INDEX|23', concat(v_output));
end test_commands;


--------------------------------------------------------------------------------
procedure test_start_index is
	v_output output_rec;

	--Helper function that concatenates results for easy string comparison.
	function concat(p_output output_rec) return varchar2 is
	begin
		return nvl(p_output.fatal_error,
			p_output.category||'|'||p_output.statement_type||'|'||p_output.command_name||'|'||p_output.command_type);
	end;
begin
	classify(q'[begin null; end;select * from dual;]', v_output, 8); assert_equals('Start index 1', 'DML|SELECT|SELECT|3', concat(v_output));
	classify(q'[select * from dual a; <<my_label>>begin null; end;]', v_output, 11); assert_equals('Start index 2', 'PL/SQL|BLOCK|PL/SQL EXECUTE|47', concat(v_output));
	classify(q'[select * from dual;select * from dual;select * from dual;]', v_output, 17); assert_equals('Start index 1', 'DML|SELECT|SELECT|3', concat(v_output));
end test_start_index;


--------------------------------------------------------------------------------
procedure test_has_plsql_declaration is

	function has_declaration(p_statement clob, p_token_start_index number default 1) return varchar2 is
	begin
		if statement_classifier.has_plsql_declaration(plsql_lexer.lex(p_statement), p_token_start_index) then

			return 'TRUE';
		else
			return 'FALSE';
		end if;
	end;
begin
	assert_equals('PLSQL Declaration, null tokens.', has_declaration('', 1), 'FALSE');
	assert_equals('PLSQL Declaration, simple 1.', has_declaration('commit;', 1), 'FALSE');
	assert_equals('PLSQL Declaration, function 1.', has_declaration('with function f return number is begin return 1; end; select f from dual;', 1), 'TRUE');
	assert_equals('PLSQL Declaration, procedure 1.', has_declaration('with procedure p is begin null; end; function f return number is begin return 1; end; select f from dual;', 1), 'TRUE');
	assert_equals('PLSQL Declaration, hierarchical look-a-like.', has_declaration('
		select *
		from
		(
			select 1 function from dual
		)
		connect by function = 1
		start with function = 1;')
		,'FALSE');
	assert_equals('PLSQL Declaration, function look-a-like 1.', has_declaration('
		with function as (select 1 a from dual) select * from function;'),
		'FALSE');
	assert_equals('PLSQL Declaration, function look-a-like 2.', has_declaration('
		with function(a) as (select 1 a from dual) select * from function;'),
		'FALSE');
	assert_equals('PLSQL Declaration, unsupported by may work some day.', has_declaration('
		/* asdf */ insert into test1 with function f return number is begin return 1; end; select f from dual'),
		'TRUE');
end test_has_plsql_declaration;


--------------------------------------------------------------------------------
procedure test_trigger_type_body_index is
begin
	--TODO (maybe).
	--This functionality is tested well in STATEMENT_SPLIITER_TEST.TEST_TRIGGER.
	null;
end test_trigger_type_body_index;


--------------------------------------------------------------------------------
procedure test_simplified_functions is
begin
	assert_equals('Simplified Functions 1', 'DDL',         statement_classifier.get_category('alter table asdf move'));
	assert_equals('Simplified Functions 2', 'ALTER',       statement_classifier.get_statement_type('alter table asdf move'));
	assert_equals('Simplified Functions 3', 'ALTER TABLE', statement_classifier.get_command_name('alter table asdf move'));
	assert_equals('Simplified Functions 4', '15',          statement_classifier.get_command_type('alter table asdf move'));
end test_simplified_functions;


--------------------------------------------------------------------------------
procedure dynamic_tests is
	type clob_table is table of clob;
	type string_table is table of varchar2(100);
	type number_table is table of number;
	v_sql_ids string_table;
	v_sql_fulltexts clob_table;
	v_command_types number_table;
	v_command_names string_table;
	sql_cursor sys_refcursor;

	v_category varchar2(30);
	v_statement_type varchar2(30);
	v_command_name varchar2(4000);
	v_command_type varchar2(4000);
	v_lex_sqlcode number;
	v_lex_sqlerrm varchar2(4000);
begin
	--Test everything in GV$SQL.
	open sql_cursor for
	q'<
		--Only need to select one value per SQL_ID.
		select sql_id, sql_fulltext, command_type, command_name
		from
		(
			select sql_id, sql_fulltext, command_type, command_name, row_number() over (partition by sql_id order by 1) rownumber
			from gv$sql
			join gv$sqlcommand using (command_type)
			--TEST - takes 2 seconds
			--where sql_id = 'dfffkcnqfystw'
		)
		where rownumber = 1
		order by sql_id
	>';

	loop
		fetch sql_cursor bulk collect into v_sql_ids, v_sql_fulltexts, v_command_types, v_command_names limit 100;
		exit when v_sql_fulltexts.count = 0;

		--Debug if there is an infinite loop.
		--dbms_output.put_line('SQL_ID: '||statements.sql_id);

		for i in 1 .. v_sql_fulltexts.count loop

			g_test_count := g_test_count + 1;

			statement_classifier.classify(plsql_lexer.lex(v_sql_fulltexts(i))
				,v_category, v_statement_type, v_command_name, v_command_type, v_lex_sqlcode, v_lex_sqlerrm);
			if v_command_type = v_command_types(i) and v_command_name = v_command_names(i) then
				g_passed_count := g_passed_count + 1;
			else
				g_failed_count := g_failed_count + 1;
				dbms_output.put_line('Failed: '||v_sql_ids(i));
				dbms_output.put_line('Expected Command Type: '||v_command_types(i));
				dbms_output.put_line('Expected Command Name: '||v_command_names(i));
				dbms_output.put_line('Actual Command Type:   '||v_command_type);
				dbms_output.put_line('Actual Command Name:   '||v_command_name);
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
	dbms_output.put_line('PL/SQL Statement Classifier Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the chosen tests.
	if bitand(p_tests, c_errors)                  > 0 then test_errors; end if;
	if bitand(p_tests, c_commands)                > 0 then test_commands; end if;
	if bitand(p_tests, c_start_index)             > 0 then test_start_index; end if;
	if bitand(p_tests, c_has_plsql_declaration)   > 0 then test_has_plsql_declaration; end if;
	if bitand(p_tests, c_trigger_type_body_index) > 0 then test_trigger_type_body_index; end if;
	if bitand(p_tests, c_simplified_functions)    > 0 then test_simplified_functions; end if;

	if bitand(p_tests, c_dynamic_tests)           > 0 then dynamic_tests; end if;

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
