create or replace procedure method5.m5_purge_sql_from_shared_pool(p_username varchar2) is
--Purpose: Method4 must force statements to hard-parse.  When type information is generated
-- dyanamically it's too hard to tell if "select * from some_table" has changed so it has to
-- be hard-parsed each time.
  type string_table is table of varchar2(32767);
  v_sql_ids string_table;
begin
	--Find SQL_IDs of the SQL statements used to call Method5.
	--Use dynamic SQL to enable roles to select from GV$SQL.
	execute immediate q'!
		select 'begin sys.dbms_shared_pool.purge('''||address||' '||hash_value||''', ''C''); end;' v_sql
		from sys.gv_$sql
		where
			parsing_schema_name = :parsing_schema_name
			and command_type = 3
			and lower(sql_text) like '%m5%(%'
			and lower(sql_text) not like '%quine%'
	!'
	bulk collect into v_sql_ids
	using p_username;

	--Purge each SQL_ID to force hard-parsing each time.
	--This cannot be done in the earlier Describe or Prepare phase or it will generate errors.
	for i in 1 .. v_sql_ids.count loop
		execute immediate v_sql_ids(i);
	end loop;
end;
/
