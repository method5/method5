--Purpose: Uninstall PLSQL_LEXER.
--How to run:
--	alter session set current_schema=&schema_name;
--	@uninstall

--#1: Stop the script at first error, make the uninstall less noisy.
whenever sqlerror exit failure
whenever oserror exit failure
set feedback off


--#2: Uninstallation banner
prompt
prompt ==============================
prompt = PLSQL_LEXER Uninstallation =
prompt ==============================
prompt


--#3: Drop objects.
prompt Dropping types and packages...
--Drop types without displaying errors if they do not exist.
declare
	v_object_does_not_exist exception;
	pragma exception_init(v_object_does_not_exist, -04043);

	procedure drop_object_ignore_dne_error(p_drop_sql in varchar2) is
	begin
		execute immediate p_drop_sql;
	exception
		when v_object_does_not_exist then null;
		when others then
			raise_application_error(-20000, 'Error with this drop statement: '||p_drop_sql||chr(10)||
				sqlerrm||chr(10)||dbms_utility.format_call_stack);
	end drop_object_ignore_dne_error;
begin
	--Drop types, in reverse order so dependent objects are dropped first.
	drop_object_ignore_dne_error('drop type misplaced_hints_schema_table');
	drop_object_ignore_dne_error('drop type misplaced_hints_schema_type');
	drop_object_ignore_dne_error('drop type misplaced_hints_code_table');
	drop_object_ignore_dne_error('drop type misplaced_hints_code_type');

--Parser objects not ready yet:
--	drop_object_ignore_dne_error('drop type node_table');
--	drop_object_ignore_dne_error('drop type node');
--	drop_object_ignore_dne_error('drop type number_table');

	drop_object_ignore_dne_error('drop type clob_table');
	drop_object_ignore_dne_error('drop type varchar2_table');
	drop_object_ignore_dne_error('drop type token_table_table');
	drop_object_ignore_dne_error('drop type token_table');
	drop_object_ignore_dne_error('drop type token');

	--Drop regular packages.
--Parser objects not ready yet:
--	drop_object_ignore_dne_error('drop package plsql_parser');
--	drop_object_ignore_dne_error('drop package syntax_tree');
	drop_object_ignore_dne_error('drop package plsql_lexer');
	drop_object_ignore_dne_error('drop package statement_classifier');
	drop_object_ignore_dne_error('drop package statement_splitter');
	drop_object_ignore_dne_error('drop package statement_feedback');
	drop_object_ignore_dne_error('drop package statement_terminator');
	drop_object_ignore_dne_error('drop package misplaced_hints');

	--Drop unit test packages.
	drop_object_ignore_dne_error('drop package plsql_lexer_test');
	drop_object_ignore_dne_error('drop package statement_classifier_test');
	drop_object_ignore_dne_error('drop package statement_feedback_test');
	drop_object_ignore_dne_error('drop package statement_splitter_test');
	drop_object_ignore_dne_error('drop package statement_terminator_test');
	drop_object_ignore_dne_error('drop package plsql_lexer_test');
	drop_object_ignore_dne_error('drop package misplaced_hints_test');
end;
/


--#4: Print success message.
prompt
prompt Uninstallation successful.


--#5: Return SQL*Plus to normal environment.
whenever sqlerror continue
whenever oserror continue
set feedback on
