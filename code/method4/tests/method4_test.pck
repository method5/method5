create or replace package method4_test authid current_user is
/*
== Purpose ==

Unit tests for Method4.


== Example ==

begin
	method4_test.run;
end;

When testing it is often helpful to run this block first:

begin
	dbms_session.reset_package;
	execute immediate 'alter system flush shared_pool';
end;

*/

--Run the unit tests and display the results in dbms output.
procedure run;

end;
/
create or replace package body method4_test is

--Global counters.
g_test_count number := 0;
g_passed_count number := 0;
g_failed_count number := 0;

--------------------------------------------------------------------------------
procedure assert_equals(p_test nvarchar2, p_expected nvarchar2, p_actual nvarchar2) is
begin
	g_test_count := g_test_count + 1;

	if p_expected = p_actual or p_expected is null and p_actual is null then
		g_passed_count := g_passed_count + 1;
	else
		g_failed_count := g_failed_count + 1;
		dbms_output.put_line('Failure with: '||p_test);
		dbms_output.put_line('Expected: '||p_expected);
		dbms_output.put_line('Actual  : '||p_actual);
	end if;
end assert_equals;


--------------------------------------------------------------------------------
procedure test_simple is
begin
	--Simple.
	declare
		actual varchar2(1);
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select * from dual'))
		>'
		into actual;

		assert_equals('Simple.', 'X', actual);
	end;

	--DBA objects.
	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.query('select count(*) from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('DBA objects.', '1', actual);
	end;

	--Long column names.
	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.query('select count(*)+0+0+0+0+0+0+0+0+0+0+0 from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('Long, default column name with 30 bytes.', '1', actual);
	end;

	declare
		actual number;
	begin
		execute immediate q'<select * from table(method4.query('select count(*)+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0+0 from dba_users where rownum = 1'))>'
		into actual;
		assert_equals('Long, default column name with > 30 bytes.', '1', actual);
	end;

end test_simple;


--------------------------------------------------------------------------------
procedure test_types is
begin
	-------------------------------------------------------------------------------
	--Listed in order of "Table 2-1 Built-in Data Type Summary" from SQL Language Reference.
	-------------------------------------------------------------------------------

	--Varchar2.
	declare
		actual1 varchar2(1);
		actual2 varchar2(100);
		actual3 varchar2(4000);
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select ''A'', cast(''B'' as varchar2(1)), lpad(''C'', 4000, ''C'') from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Varchar2 1.', 'A', actual1);
		assert_equals('Varchar2 2.', 'B', actual2);
		assert_equals('Varchar2 3.', lpad('C', 4000, 'C'), actual3);
	end;

	--NVarchar2.
	declare
		actual1 nvarchar2(1);
		actual2 nvarchar2(100);
		actual3 nvarchar2(4000);
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select n''A'', cast(''B'' as nvarchar2(1)), lpad(n''C'', 1000, n''C'') from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('NVarchar2 1.', n'A', actual1);
		assert_equals('NVarchar2 2.', n'B', actual2);
		assert_equals('NVarchar2 3.', lpad(n'C', 1000, n'C'), actual3);
	end;

	--Number.
	declare
		actual1 number;
		actual2 number;
		actual3 number;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select 1.1, cast(2.2 as number(10, 1)), 3 from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Number 1.', '1.1', actual1);
		assert_equals('Number 2.', '2.2', actual2);
		assert_equals('Number 3.', '3', actual3);
	end;

	--Float.
	declare
		actual1 float;
		actual2 float;
		actual3 float;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select cast(100.001 as float), cast(20.02 as float(100)), cast(3 as float(1)) from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Float 1.', '100.001', actual1);
		assert_equals('Float 2.', '20.02', actual2);
		assert_equals('Float 3.', '3', actual3);
	end;

	--Long.
	--This view is the same in 11g and 12c, hopefully it's the same in all versions.
	declare
		actual1 clob;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select text from dba_views where view_name = ''DBA_EXP_VERSION'''))
		>'
		into actual1;

		assert_equals('Long 1.', 'select o.expid'||chr(10)||'from sys.incvid o', actual1);
	end;

	--Date.
	--Note that SYSDATE is not always the same as DATE and worth testing.
	declare
		actual1 date;
		actual2 date;
		actual3 date;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select date ''2000-01-01'', to_date(''2000-01-02'', ''YYYY-MM-DD''), sysdate from dual'))
		>'
		into actual1, actual2, actual3;

		assert_equals('Date 1.', '2000-01-01', to_char(actual1, 'YYYY-MM-DD'));
		assert_equals('Date 2.', '2000-01-02', to_char(actual2, 'YYYY-MM-DD'));
		assert_equals('Date 3.', to_char(sysdate, 'YYYY-MM-DD'), to_char(actual3, 'YYYY-MM-DD'));
	end;

	--BINARY_FLOAT.
	declare
		actual1 binary_float;
		actual2 binary_float;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select 1.1f, cast(2.2 as binary_float) from dual'))
		>'
		into actual1, actual2;

		assert_equals('BINARY_FLOAT 1.', '1.1', trim(to_char(actual1, '9.9')));
		assert_equals('BINARY_FLOAT 2.', '2.2', trim(to_char(actual2, '9.9')));
	end;

	--BINARY_DOUBLE.
	declare
		actual1 binary_double;
		actual2 binary_double;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('select 1.1d, cast(2.2 as binary_double) from dual'))
		>'
		into actual1, actual2;

		assert_equals('BINARY_DOUBLE 1.', '1.1', trim(to_char(actual1, '9.9')));
		assert_equals('BINARY_DOUBLE 2.', '2.2', trim(to_char(actual2, '9.9')));
	end;

	--TIMESTAMP [(fractional_seconds_precision)]
	--Note that SYSTIMESTAMP is not always the same as TIMESTAMP and worth testing.
	declare
		actual1 timestamp(9);
		actual2 timestamp(9);
		actual3 timestamp(9);
		actual4 timestamp(9);
		actual5 timestamp(9);
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('
				select
					timestamp ''2000-01-01 12:34:56'',
					to_timestamp(''2000-01-02 12:34:56'', ''YYYY-MM-DD HH24:MI:SS''),
					to_timestamp(''2000-01-01 12:00:00.123456789'', ''YYYY-MM-DD HH24:MI:SS.FF9''),
					cast(date ''2000-01-01'' as timestamp(3)),
					systimestamp
				from dual'))
		>'
		into actual1, actual2, actual3, actual4, actual5;

		assert_equals('Timestamp 1.', '2000-01-01 12:34:56', to_char(actual1, 'YYYY-MM-DD HH24:MI:SS'));
		assert_equals('Timestamp 2.', '2000-01-02 12:34:56', to_char(actual2, 'YYYY-MM-DD HH24:MI:SS'));
		assert_equals('Timestamp 3.', '2000-01-01 12:00:00.123456789', to_char(actual3, 'YYYY-MM-DD HH24:MI:SS.FF9'));
		assert_equals('Timestamp 4.', '2000-01-01', to_char(actual1, 'YYYY-MM-DD'));
		assert_equals('Timestamp 5.', to_char(systimestamp, 'YYYY-MM-DD HH24'), to_char(actual5, 'YYYY-MM-DD HH24'));
	end;

	--TIMESTAMP [(fractional_seconds_precision)] WITH TIME ZONE
	declare
		actual1 timestamp(9) with time zone;
		actual2 timestamp(9) with time zone;
		actual3 timestamp(9) with time zone;
		actual4 timestamp(9) with time zone;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('
				select
					timestamp ''2000-01-01 12:34:56 +01:00'',
					timestamp ''2000-01-02 12:34:56 US/Eastern'',
					cast(date ''2000-01-04'' as timestamp(9) with time zone),
					cast(null as timestamp(9) with time zone)
				from dual'))
		>'
		into actual1, actual2, actual3, actual4;

		assert_equals('Timestamp with time zone 1.', '2000-01-01 12:34:56 +01:00', to_char(actual1, 'YYYY-MM-DD HH24:MI:SS TZH:TZM'));
		assert_equals('Timestamp with time zone 2.', '2000-01-02 12:34:56 US/EASTERN', to_char(actual2, 'YYYY-MM-DD HH24:MI:SS TZR'));
		assert_equals('Timestamp with time zone 3.', '2000-01-04 00:00:00', to_char(actual3, 'YYYY-MM-DD HH24:MI:SS'));
		assert_equals('Timestamp with time zone 4.', '', actual4);
	end;

	--TIMESTAMP [(fractional_seconds_precision)] WITH LOCAL TIME ZONE
	declare
		actual1 timestamp(9) with local time zone;
		actual2 timestamp(9) with local time zone;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('
				select
					cast(timestamp ''2000-01-01 12:34:56.123456789 +01:00'' as timestamp(9) with local time zone),
					cast(null as timestamp(9) with local time zone)
				from dual'))
		>'
		into actual1, actual2;

		assert_equals('Timestamp with local time zone 1.', '123456789', to_char(actual1, 'FF9'));
		assert_equals('Timestamp with local time zone 2.', '', actual2);
	end;

	--INTERVAL YEAR [(year_precision)] TO MONTH
	declare
		actual1 interval year to month;
		actual2 interval year to month;
		actual3 interval year to month;
		actual4 interval year to month;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('
				select
					interval ''1-1'' year to month,
					interval ''2'' year,
					interval ''3'' month,
					cast(null as interval year to month)
				from dual'))
		>'
		into actual1, actual2, actual3, actual4;

		assert_equals('Interval year to month 1.', '+01-01', actual1);
		assert_equals('Interval year to month 2.', '+02-00', actual2);
		assert_equals('Interval year to month 3.', '+00-03', actual3);
		assert_equals('Interval year to month 4.', '', actual4);
	end;

	--INTERVAL DAY [(day_precision)] TO SECOND [(fractional_seconds_precision)]
	declare
		actual1 interval day to second;
		actual2 interval day to second;
		actual3 interval day to second;
		actual4 interval day to second;
	begin
		execute immediate
		q'<
			select *
			from table(method4.query('
				select
					interval ''4 4'' day to hour,
					interval ''5:5'' minute to second,
					interval ''6'' second,
					cast(null as interval day to second)
				from dual'))
		>'
		into actual1, actual2, actual3, actual4;

		assert_equals('Interval day to second 1.', '+04 04:00:00.000000', actual1);
		assert_equals('Interval day to second 2.', '+00 00:05:05.000000', actual2);
		assert_equals('Interval day to second 3.', '+00 00:00:06.000000', actual3);
		assert_equals('Interval day to second 4.', '', actual4);
	end;


/*
TODO:
RAW(size)
LONG RAW
ROWID
UROWID [(size)]
CHAR [(size [BYTE | CHAR])]
NCHAR[(size)]
CLOB
NCLOB
BLOB
BFILE

REF?
TYPE
NESTED TABLE
XMLType
ANYDATA
*/
end test_types;


--------------------------------------------------------------------------------
procedure test_dynamic_query is
begin
	--Dynamic, only one query.
	declare
		actual1 number;
	begin
		execute immediate
		q'<
			select * from table(method4.dynamic_query(
			q'[
				select 'select 1 a from dual' from dual
			]'))
		>' --'--Fix PL/SQL parser bug.
		into actual1;

		assert_equals('Dynamic query 1.', '1', actual1);
	end;

	--Dynamic, multiple queries.
	declare
		actual_count sys.odcivarchar2list;
		actual_name sys.odcivarchar2list;
	begin
		execute immediate
		q'<
			select * from table(method4.dynamic_query(
			q'[
				select 'select count(*) total, '''||view_name||''' view_name from '||owner||'.'||view_name||''
				from dba_views
				where owner = 'SYS'
					--3 views that I know only contain one row.
					and view_name in ('V_$DATABASE', 'V_$INSTANCE', 'V_$TIMER')
				order by view_name
			]'))
		>' --'--Fix PL/SQL parser bug.
		bulk collect into actual_count, actual_name;

		assert_equals('Dynamic query multiple queries 1.', '1', actual_count(1));
		assert_equals('Dynamic query multiple queries 2.', '1', actual_count(2));
		assert_equals('Dynamic query multiple queries 3.', '1', actual_count(3));
		assert_equals('Dynamic query multiple queries 4.', 'V_$DATABASE', actual_name(1));
		assert_equals('Dynamic query multiple queries 5.', 'V_$INSTANCE', actual_name(2));
		assert_equals('Dynamic query multiple queries 6.', 'V_$TIMER', actual_name(3));
	end;

end test_dynamic_query;


--------------------------------------------------------------------------------
procedure test_poll_table is
	v_table_or_view_does_not_exist exception;
	pragma exception_init(v_table_or_view_does_not_exist, -00942);

	--Create objects used for testing.
	procedure setup is
	begin
		execute immediate 'create table m4_temp_test_table1(a number) rowdependencies';
		execute immediate 'insert into m4_temp_test_table1 values(1)';
		commit;
	end;

	--Remove objects used for testing.
	procedure tear_down is
	begin
		begin
			execute immediate 'drop table m4_temp_test_table1 purge';
		exception when v_table_or_view_does_not_exist then null;
		end;
	end;
begin
	--Remove any leftover objects and create new ones.
	tear_down;
	setup;

	--Dynamic, only one query.
	declare
		actual1 number;
	begin
		--Setup

		execute immediate
		q'<
			select * from table(method4.poll_table(
			   p_table_name              => 'm4_temp_test_table1',
			   p_sql_statement_condition => 'select 1 from dual',
			   p_refresh_seconds         => 2
			))
		>'
		into actual1;

		assert_equals('Poll table 1.', '1', actual1);
	end;

	--TODO - more tests.

	--Cleanup.
	tear_down;
end test_poll_table;


--------------------------------------------------------------------------------
procedure run is
begin
	--Reset counters.
	g_test_count := 0;
	g_passed_count := 0;
	g_failed_count := 0;

	--Print header.
	dbms_output.put_line(null);
	dbms_output.put_line('----------------------------------------');
	dbms_output.put_line('Method4 Test Summary');
	dbms_output.put_line('----------------------------------------');

	--Run the tests.
	test_simple;
	test_types;
	test_dynamic_query;
	test_poll_table;

	--Print summary of results.
	dbms_output.put_line(null);
	dbms_output.put_line('Total : '||g_test_count);
	dbms_output.put_line('Passed: '||g_passed_count);
	dbms_output.put_line('Failed: '||g_failed_count);

	--Print easy to read pass or fail message.
	if g_failed_count = 0 then
		dbms_output.put_line('
  _____         _____ _____
 |  __ \ /\    / ____/ ____|
 | |__) /  \  | (___| (___
 |  ___/ /\ \  \___ \\___ \
 | |  / ____ \ ____) |___) |
 |_| /_/    \_\_____/_____/');
	else
		dbms_output.put_line('
  ______      _____ _
 |  ____/\   |_   _| |
 | |__ /  \    | | | |
 |  __/ /\ \   | | | |
 | | / ____ \ _| |_| |____
 |_|/_/    \_\_____|______|');
	end if;
end run;

end;
/
