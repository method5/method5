create or replace package body unit_tests is
--Copyright (C) 2015 Jon Heller.  This program is licensed under the LGPLv3.

--------------------------------------------------------------------------------
--Run all dynamic tests.
--This should be fairly quick and does about 95% of the testing.
procedure run_static_tests is
begin
	misplaced_hints_test.run(p_tests => misplaced_hints_test.c_static_tests);
	statement_classifier_test.run(p_tests => statement_classifier_test.c_static_tests);
	statement_feedback_test.run(p_tests => statement_feedback_test.c_static_tests);
	statement_splitter_test.run(p_tests => statement_splitter_test.c_static_tests);
	statement_terminator_test.run(p_tests => statement_terminator_test.c_static_tests);
	plsql_lexer_test.run(p_tests => plsql_lexer_test.c_static_tests);
end;

--------------------------------------------------------------------------------
--Run all dynamic tests.
--This may take a long time and provides only a little extra value.
procedure run_dynamic_tests is
begin
	statement_classifier_test.run(p_tests => statement_classifier_test.c_dynamic_tests);
	--Statement feedback does not have any dynamic tests.
	--statement_feedback_test.run(p_tests => statement_feedback_test.c_dynamic_tests);
	statement_splitter_test.run(p_tests => statement_splitter_test.c_dynamic_tests);
	statement_terminator_test.run(p_tests => statement_terminator_test.c_dynamic_tests);
	plsql_lexer_test.run(p_tests => plsql_lexer_test.c_dynamic_tests);
end;

--------------------------------------------------------------------------------
--Run all tests for all packages.  This may take a long time.
procedure run_all_tests is
begin
	run_static_tests;
	run_dynamic_tests;
end;

end;
/
