--Purpose: Install unit tests for PLSQL_LEXER.
--How to run:
--	alter session set current_schema=&schema_name;
--	@install_unit_tests

--#1: Stop the script at first error, make the installation less noisy.
whenever sqlerror exit failure
whenever oserror exit failure
set feedback off

--#2: Installation banner
prompt
prompt ======================================
prompt = PLSQL_LEXER Unit Test Installation =
prompt ======================================
prompt


--#3: Install packages.
prompt Installing packages...
start tests/unit_tests.spc
start tests/statement_classifier_test.plsql
start tests/statement_feedback_test.plsql
start tests/statement_splitter_test.plsql
start tests/statement_terminator_test.plsql
start tests/plsql_lexer_test.plsql
start tests/misplaced_hints_test.plsql
--Separate spec and body because of circular dependency.
start tests/unit_tests.bdy


--#4: Verify installation.
prompt Verifying installation...

--Display all invalid objects.
column owner format a30;
column object_name format a30;
column object_type format a13;

select owner, object_name, object_type
from all_objects
where object_name in ('PLSQL_LEXER_TEST', 'STATEMENT_CLASSIFIER_TEST', 'STATEMENT_FEEDBACK_TEST',
		'STATEMENT_SPLITTER_TEST', 'STATEMENT_TERMINATOR_TEST', 'UNIT_TESTS', 'MISPLACED_HINTS_TEST')
	and owner = sys_context('userenv', 'current_schema')
	and status <> 'VALID';

--Raise error if any packages are invalid.
--(Because compilation errors may be "warnings" that won't fail the script.)
declare
	v_count number;
begin
	select count(*)
	into v_count
	from all_objects
	where object_name in ('PLSQL_LEXER_TEST', 'STATEMENT_CLASSIFIER_TEST', 'STATEMENT_CLASSIFIER_TEST',
			'STATEMENT_SPLITTER_TEST', 'STATEMENT_TERMINATOR_TEST', 'PLSQL_LEXER_TEST', 'MISPLACED_HINTS_TEST')
		and owner = sys_context('userenv', 'current_schema')
		and status <> 'VALID';

	if v_count >= 1 then
		raise_application_error(-20000, 'Installation failed, the above objects '||
			'are invalid.');
	end if;
end;
/


--#5: Run unit tests and print success message.
prompt Running unit tests, this may take a minute...
set serveroutput on
set linesize 1000
begin
	unit_tests.run_static_tests;
end;
/

prompt
prompt
prompt
prompt
prompt Unit test installation successful.
prompt (But do not trust any packages with a FAIL message above.)


--#6: Return SQL*Plus to normal environment.
whenever sqlerror continue
whenever oserror continue
set feedback on
