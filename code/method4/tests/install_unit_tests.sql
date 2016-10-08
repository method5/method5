prompt
prompt
prompt **************************************************************************
prompt    Method4 Unit Tests Installer
prompt **************************************************************************
prompt

prompt Installing unit test package...
@@method4_test.pck
prompt Running unit tests, this may take a minute...
set serveroutput on
set linesize 1000
begin
	method4_test.run;
end;
/

prompt
prompt **************************************************************************
prompt    Unit Test Installation complete.
prompt **************************************************************************
