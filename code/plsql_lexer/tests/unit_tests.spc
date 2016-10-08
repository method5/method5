create or replace package unit_tests is
--Copyright (C) 2015 Jon Heller.  This program is licensed under the LGPLv3.

/*
== Purpose ==

Store constants used by multiple packages for PLSQL_LEXER unit tests, and
procedures that call multiple tests at once.
*/

C_PASS_MESSAGE varchar2(200) := '
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/';

C_FAIL_MESSAGE varchar2(200) := '
  ______      _____ _
 |  ____/\   |_   _| |
 | |__ /  \    | | | |
 |  __/ /\ \   | | | |
 | | / ____ \ _| |_| |____
 |_|/_/    \_\_____|______|';

procedure run_static_tests;
procedure run_dynamic_tests;
procedure run_all_tests;

end;
/
