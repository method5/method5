--Purpose: Install PLSQL_LEXER.
--How to run:
--	alter session set current_schema=&schema_name;
--	@install

--#1: Stop the script at first error, make the installation less noisy.
whenever sqlerror exit failure
whenever oserror exit failure
set feedback off


--#2: Installation banner
prompt
prompt ============================
prompt = PLSQL_LEXER Installation =
prompt ============================
prompt


--#3: Quit if program is already installed.
prompt Looking for existing installation...
--Look for type names, throw error if any are found.
declare
	v_installed_types varchar2(4000);
begin
	select listagg(type_name, ',') within group (order by type_name)
	into v_installed_types
	from all_types
	where type_name in
		(
			'CLOB_TABLE', 'VARCHAR2_TABLE',
			'TOKEN', 'TOKEN_TABLE', 'TOKEN_TABLE_TABLE',
--Parser objects not ready yet:
--			'NODE', 'NODE_TABLE', 'NUMBER_TABLE',
			'MISPLACED_HINTS_CODE_TYPE', 'MISPLACED_HINTS_CODE_TABLE',
			'MISPLACED_HINTS_SCHEMA_TYPE', 'MISPLACED_HINTS_SCHEMA_TABLE'
		)
		and owner = sys_context('userenv', 'current_schema');

	if v_installed_types is not null then
		raise_application_error(-20000, 'Installation failed, the following '||
			'types already exist.  Either run @uninstall.sql or manually remove '||
			'these types: '||v_installed_types);
	end if;
end;
/


--#4: Install types.
prompt Installing types...
@code/plsql_lexer/types.sql


--#5: Install packages.
prompt Installing packages...

@code/plsql_lexer/packages/plsql_lexer.plsql
--Parser objects not ready yet:
--@@plsql_lexer/packages/syntax_tree.plsql
--@@plsql_lexer/packages/plsql_parser.spc
--@@plsql_lexer/packages/plsql_parser.bdy
@code/plsql_lexer/packages/statement_classifier.plsql
@code/plsql_lexer/packages/statement_splitter.plsql
@code/plsql_lexer/packages/statement_feedback.plsql
@code/plsql_lexer/packages/statement_terminator.plsql
@code/plsql_lexer/packages/misplaced_hints.plsql


--#6: Verify installation and print success message.
prompt Verifying installation...

--Display all invalid objects.
column owner format a30;
column object_name format a30;
column object_type format a13;

select owner, object_name, object_type
from all_objects
where object_name in
	(
		'PLSQL_LEXER', 'STATEMENT_CLASSIFIER', 'STATEMENT_SPLITTER', 'STATEMENT_FEEDBACK', 'STATEMENT_TERMINATOR', 'MISPLACED_HINTS'
		--Parser objects not ready yet:
		--,'PLSQL_PARSER', 'SYNTAX_TREE'
	)
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
	where object_name in
	(
		'PLSQL_LEXER', 'STATEMENT_CLASSIFIER', 'STATEMENT_SPLITTER', 'STATEMENT_FEEDBACK', 'STATEMENT_TERMINATOR', 'MISPLACED_HINTS'
		--Parser objects not ready yet:
		--,'PLSQL_PARSER', 'SYNTAX_TREE'
	)
		and owner = sys_context('userenv', 'current_schema')
		and status <> 'VALID';

	if v_count >= 1 then
		raise_application_error(-20000, 'Installation failed, the above objects '||
			'are invalid.');
	end if;
end;
/


prompt
prompt Installation successful.

--#7: Return SQL*Plus to normal environment.
whenever sqlerror continue
whenever oserror continue
set feedback on
