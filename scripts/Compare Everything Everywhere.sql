--------------------------------------------------------------------------------
-- Purpose: Compare schema objects across many databases, all in one view.
-- How to use:
--    Run steps #1 through #5 to generate and query results.
--    Run step #6 to install objects (one-time step).
-- Version: 2.1.2
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
--#1: Create a list of databases with the relevant schema.
--------------------------------------------------------------------------------
select username, listagg(database_name, ',') within group (order by database_name) database_list
from m5_dba_users
where username like '&SCHEMA'
group by username
order by username;



--------------------------------------------------------------------------------
--#2: Gather data and create view.  This may take a long time for complex schemas.
--------------------------------------------------------------------------------
begin
	method5.compare_everything_everywhere(
		--The schema to compare:
		p_schema_name   => '&SCHEMA',
		--Database target list generated from above step.
		--For example: acmedb1,acmedb2
		p_database_list => '&DATABASE_LIST_FROM_STEP_1'
	);
end;
/



--------------------------------------------------------------------------------
--#3: Monitor the job.  This is optional, if the above step is taking too long.
--Run these steps in a separate session.
--------------------------------------------------------------------------------

--#3a: How many databases are waiting for results?  (One database per job.)
select * from dba_scheduler_running_jobs where owner = user;

--#3b: How many objects have had their DDL generated? 
select count(*) from method5.temp_table_ddl@m5_$$DBNAME$$;

--#3c: How many objects will there need to be eventually?
--This number and the number above will not exatly match.
select count(*) from dba_objects@m5_$$DBNAME$$ where owner = '$$SCHEMA_NAME$$';



--------------------------------------------------------------------------------
--#4: View and export data.
--------------------------------------------------------------------------------
--Limitations of output:
--	Some differences may not look like real differences in the spreadsheet because:
--		1. Comparisons use entire object but Excel output is limited to the first 4000 bytes.
--		2. Excel trims leading and trailing newlines.
--		3. Non-ASCII characters may differ on databases but look the same on your PC.
--	DDL differences may be a false positive in these cases:
--		1. Materialized views with an index and no data may not show "PCTFREE ...".
--		2. Objects that use system-generated names instead of explicit names.
select *
from ddl_compare_view
order by owner, object_type, object_name;


--Steps to export and format from PL/SQL Developer to Excel.
--	Retrieve all data (click the double-green arrow on the data grid).
--	Right-click on top-left corner of data grid.
--	Select "Copy to Excel", XLSX.
--	In Excel sheet, delete the first column.
--	Highlight all the columns before "A", then double-click on right-edge to minimize their size.
--	Highlight columns "A" to "Z", right-click on header, select "Column Width", enter 10 and hit OK.
--	Right-click on header of highlighted A-Z, select Format Cells, Alignment tab, click "Wrap Text", hit OK.
--	Highlight everything (CTRL+A), right-click on left-hand-side, select Row Height, enter 12.75, click OK.
--	Save the Excel file, email it.  Note that this only shows differences, and only the first 4K of each object.



--------------------------------------------------------------------------------
--#5: Ad hoc difference queries (optional).
--------------------------------------------------------------------------------

--Look at single differences.
--This can help for objects larger than 4K that may not show up completely in Excel exports.
select *
from ddl_$SCHEMA$_$RUN_ID$
order by database_name, owner, object_type, object_name;



--------------------------------------------------------------------------------
--#6: Create compare objects.  (one-time step)
--------------------------------------------------------------------------------

--#6a: Create sequence and granct access to DBAs.
create sequence method5.compare_seq;
grant select on method5.compare_seq to dba;


--#6b: Create procedure to compare.
create or replace procedure method5.compare_everything_everywhere(
	p_schema_name varchar2,
	p_database_list varchar2
) authid current_user
is
	v_run_id number;
	v_count number;
	v_databases sys.odcivarchar2list;
	v_database_list varchar2(32767);
	v_letter_select varchar2(32767);
	v_letter_pivot varchar2(32767);
	v_query varchar2(32767);
begin
	--Generate unique run id.
	execute immediate 'select method5.compare_seq.nextval from dual' into v_run_id;

	--Check that table to hold results does not already exist.
	select count(*) into v_count
	from user_tables
	where table_name = upper('COMPARE_DDL_'||v_run_id);

	if v_count >= 1 then
		raise_application_error(-20000, 'The table COMPARE_DDL_'||v_run_id||' already exists.  '||
			'Drop that table or use a different name.');
	end if;

	--Gather data.
	m5_proc(
		p_table_name => 'compare_run_'||v_run_id,
		p_table_exists_action => 'DROP',
		p_asynchronous => false,
		p_targets => p_database_list,
		p_code => replace(replace(q'<
			--Save all the DDL for a schema.
			declare
				v_owner constant varchar2(128) := upper('$SCHEMA$');
				v_run_id number := $RUN_ID$;
				v_exclusions sys.ora_mining_varchar2_nt := sys.ora_mining_varchar2_nt('TABLE_STATISTICS', 'INDEX_STATISTICS');
				v_count number;
				v_ddl clob;
				v_hash varchar2(32);
				v_object_does_not_exist exception;
				pragma exception_init(v_object_does_not_exist, -31608);
				v_invalid_name exception;
				pragma exception_init(v_invalid_name, -31604);

				function sort_dependent_ddl(p_table_name varchar2, p_schema_name varchar2, p_object_type varchar2) return clob is
					v_ddls clob;

					v_alter clob;
					v_start_position number := 2;
					v_end_position number;

					type clob_aat is table of clob index by varchar2(32767);
					v_ordered_alters clob_aat;
				begin
					--Disable pretty-printing so that each ALTER only takes up one line.
					dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', false);

					--Get the CLOB of DDLs.
					v_ddls := dbms_metadata.get_dependent_ddl(p_object_type, p_table_name, p_schema_name);

					--Split the CLOB into strings.
					loop
						--Find the next newline.
						v_end_position := dbms_lob.instr(v_ddls, chr(10), offset => v_start_position);

						--Go to end and quit if there are no more newlines.
						if v_end_position = 0 then
							v_alter := dbms_lob.substr(v_ddls, offset => v_start_position, amount => dbms_lob.getLength(v_ddls) - v_start_position + 1);
							v_ordered_alters(v_alter) := v_alter;
							exit;
						--Increment if there are more newlines.
						else
							v_alter := dbms_lob.substr(v_ddls, offset => v_start_position, amount => v_end_position - v_start_position);
							v_ordered_alters(v_alter) := v_alter;
							v_start_position := v_end_position + 1;
						end if;
					end loop;

					--Recreate DDL, in order.
					declare
						v_index varchar2(32767);
					begin
						--Clear out old DDL.
						v_ddls := null;

						--Concatenate ordered ALTERs.
						v_index := v_ordered_alters.first;
						while (v_index is not null) loop
							v_ddls := v_ddls || v_ordered_alters(v_index) || chr(10);
							v_index := v_ordered_alters.next(v_index);
						end loop;
					end;

					--Re-enable pretty-printing.
					dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'PRETTY', true);

					--Return the value.
					return v_ddls;
				end;

			begin
				--Create table to hold DDL, if it doesn't already exist.
				select count(*) into v_count from dba_tables where owner = 'METHOD5' and table_name = 'TEMP_TABLE_DDL';
				if v_count = 0 then
					execute immediate 'create table method5.temp_table_ddl(run_id number, the_date date, owner varchar2(128), object_type varchar2(128), object_name varchar2(128), hash varchar2(32), ddl clob) ';
				end if;

				--Remove old data from remote table.
				--(If the last run failed it may not have cleared out data.)
				execute immediate '
					delete from method5.temp_table_ddl
					where the_date < sysdate - 7';
				commit;

				--Disable storage metadata.
				--This removes "STORAGE(INITIAL 65536 NEXT 1048576 ... )" but keeps PCTFREE, COMPRESS, LOGGING, and TABLESPACE.
				dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', false);

				--Enable semicolon so that output is more runnable.
				dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SQLTERMINATOR', true);

				--These are handled separately from the table so that differences can be more granular.
				dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS', false);
				dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', false);

				--Loop through all objects
				for objects in
				(
					--Main objects without recycle bin objects.
					select *
					from
					(
						--Main objects.  Tables, views, code, etc.
						--Kind of based off of: http://stackoverflow.com/questions/10886450/how-to-generate-entire-ddl-of-an-oracle-schema-scriptable
						select distinct
							owner,
							decode(object_type,
								'DATABASE LINK',      'DB_LINK',
								'JOB',                'PROCOBJ',
								'RULE SET',           'PROCOBJ',
								'RULE',               'PROCOBJ',
								'EVALUATION CONTEXT', 'PROCOBJ',
								'PACKAGE',            'PACKAGE_SPEC',
								'PACKAGE BODY',       'PACKAGE_BODY',
								'TYPE',               'TYPE_SPEC',
								'TYPE BODY',          'TYPE_BODY',
								'MATERIALIZED VIEW',  'MATERIALIZED_VIEW',
								'QUEUE',              'AQ_QUEUE',
								'JAVA CLASS',         'JAVA_CLASS',
								'JAVA TYPE',          'JAVA_TYPE',
								'JAVA SOURCE',        'JAVA_SOURCE',
								'JAVA RESOURCE',      'JAVA_RESOURCE',
								object_type) object_type,
							object_name,
							1 ddl_1_dependent_2_granted_3
						from dba_objects
						where owner = v_owner
							--These objects are included with other object types.
							and object_type not in ('INDEX PARTITION','INDEX SUBPARTITION','LOB','LOB PARTITION','TABLE PARTITION','TABLE SUBPARTITION')
							--Ignore system-generated types that support collection processing.
							and not (object_type like 'TYPE' and object_name like 'SYS_PLSQL_%')
							--Exclude nested tables, their DDL is part of their parent table.
							and object_name not in (select table_name from dba_nested_tables where owner = v_owner)
							--Exlclude overflow segments, their DDL is part of their parent table.
							and object_name not in (select table_name from dba_tables where iot_type = 'IOT_OVERFLOW' and owner = v_owner)
						--Items not covered as "objects", usually dependent objects.
						--
						--Comments.
						union
						select owner, 'COMMENT', table_name, 2 ddl_1_dependent_2_granted_3 from dba_col_comments where table_name not like 'BIN$%' and comments is not null and owner = v_owner
						union
						select owner, 'COMMENT', table_name, 2 ddl_1_dependent_2_granted_3 from dba_tab_comments where table_name not like 'BIN$%' and comments is not null and owner = v_owner
						union
						select owner, 'COMMENT', mview_name, 2 ddl_1_dependent_2_granted_3 from dba_mview_comments where mview_name not like 'BIN$%' and comments is not null and owner = v_owner
						--Constraints.
						union
						select owner, case when constraint_type = 'R' then 'REF_CONSTRAINT' else 'CONSTRAINT' end object_type, table_name, 2 ddl_1_dependent_2_granted_3
						from dba_constraints
						where owner = v_owner
							--View constraints are already included in DDL.
							and constraint_type not in ('V', 'O')
						--User
						union
						select v_owner owner, 'USER', v_owner, 1 ddl_1_dependent_2_granted_3  from dba_users where username = v_owner
						--Privileges on user.
						union
						select grantee owner, 'SYSTEM_GRANT', null object_name, 3 ddl_1_dependent_2_granted_3  from dba_sys_privs where grantee = v_owner
						union
						select grantee owner, 'ROLE_GRANT', null object_name, 3 ddl_1_dependent_2_granted_3  from dba_role_privs where grantee = v_owner
						union
						select grantee owner, 'OBJECT_GRANT', null object_name, 3 ddl_1_dependent_2_granted_3  from dba_tab_privs where grantee = v_owner
						--Privileges on objects.
						union
						select distinct owner, 'OBJECT_GRANT', table_name, 2 ddl_1_dependent_2_granted_3 from dba_tab_privs where owner = v_owner
						order by 1,2,3
					)
					where object_name not like 'BIN$%'
				) loop
					begin
						--Add DDL if it's not an excluded type.
						if not objects.object_type member of v_exclusions then

							--Get DDL.
							if objects.ddl_1_dependent_2_granted_3 = 1 then
								--USER is retrieved differently and also the password must be removed.
								if objects.object_type = 'USER' then
									v_ddl := dbms_metadata.get_ddl(objects.object_type, objects.object_name);
									v_ddl := regexp_replace(v_ddl, 'IDENTIFIED BY VALUES ''.*?''', '*password removed*');
								--Remove the number from sequences.
								elsif objects.object_type = 'SEQUENCE' then
									v_ddl := dbms_metadata.get_ddl(objects.object_type, objects.object_name, objects.owner);
									v_ddl := regexp_replace(v_ddl, 'START WITH [0-9]*', 'START WITH *removed from comparison*');
								--"JAVA CLASS" is a problem.  It cannot be retrived from DBMS_METADATA and DBMS_JAVA.EXPORT_CLASS doesn't always work either.
								--Since JAVA CLASS cannot be truly compared, return a warning and unique results so they show as a difference.
								elsif objects.object_type = 'JAVA CLASS' then
									declare
										v_global_name varchar2(100);
									begin
										select global_name into v_global_name from global_name;
										v_ddl := 'WARNING: JAVA CLASS cannot be reliably read from the database.  The program '||
											'cannot determine if the classes are different or identical.  '||v_global_name;
									end;
								else
									v_ddl := dbms_metadata.get_ddl(objects.object_type, objects.object_name, objects.owner);
								end if;
							elsif objects.ddl_1_dependent_2_granted_3 = 2 then
								--Sort some dependent DDL that may print in different orders on different databases.
								if objects.object_type in ('CONSTRAINT', 'REF_CONSTRAINT', 'OBJECT_GRANT', 'COMMENT') then
									v_ddl := sort_dependent_ddl(objects.object_name, objects.owner, objects.object_type);
								else
									v_ddl := dbms_metadata.get_dependent_ddl(objects.object_type, objects.object_name, objects.owner);
								end if;
							elsif objects.ddl_1_dependent_2_granted_3 = 3 then
								v_ddl := dbms_metadata.get_granted_ddl(objects.object_type, objects.owner);
							end if;

							--Get hash.  2 = dbms_crypto.hash_md5.
							v_hash := rawtohex(sys.dbms_crypto.hash(v_ddl, 2));

							--Store the DDL.
							execute immediate 'insert into method5.temp_table_ddl values(:run_id, sysdate, :owner, :object_type, :object_name, :hash, :ddl) '
							using v_run_id, v_owner, objects.object_type, objects.object_name, v_hash, v_ddl;
							commit;
						end if;
					exception when others then
						--Ignore some errors with object-relational tables.
						--if objects.ddl_1_dependent_2_granted_3 = 2 and objects.object_type = 'OBJECT_GRANT' and sqlcode =

						raise_application_error(-20000, 'Error with this object '||objects.owner||'.'||objects.object_name||' ('
							||objects.object_type||'). '||dbms_utility.format_error_stack||sys.dbms_utility.format_error_backtrace);
					end;
				end loop;
			end;
		>', '$SCHEMA$', p_schema_name), '$RUN_ID$', v_run_id)
	);

	--Raise error if there were any errors generating DDL.
	execute immediate 'select targets_with_errors from compare_run_'||v_run_id||'_meta'
	into v_count;
	if v_count >0 then
		raise_application_error(-20000, v_count||' jobs failed.  '||
			'Look at compare_run_'||v_run_id||'_err for the error messages.');
	end if;

	--Create table to hold DDL from all remote databases.
	execute immediate 'create table compare_ddl_'||v_run_id||'(database_name varchar2(30), run_id number, the_date date,
		owner varchar2(128), object_type varchar2(128), object_name varchar2(128), hash varchar2(32), ddl clob)';

	--Move data to a local table for quicker comparisons.
	--(Data must be pushed because CLOBs cannot be pulled over database links.)
	execute immediate '
		select distinct database_name
		from compare_run_'||v_run_id||'
		order by 1'
	bulk collect into v_databases;

	for i in 1 .. v_databases.count loop
		--Insert data into local table.
		execute immediate '
			insert into compare_ddl_'||v_run_id||'
			select '''||v_databases(i)||''', temp_table_ddl.*
			from method5.temp_table_ddl@m5_'||v_databases(i)||'
			where run_id = '||v_run_id;
		commit;

		--Remove data from remote table.
		execute immediate '
			delete from method5.temp_table_ddl@m5_'||v_databases(i)||'
			where run_id = '||v_run_id;
		commit;
	end loop;


	--Get lists used to build the view.
	execute immediate replace(q'[
		--Lists used to build query.
		select database_list, letter_select, letter_pivot
		from
		(
			--Database list.
			select listagg(''''||database_name||''' as '||database_name, ',') within group (
				--Order by environment.
				order by case substr(database_name, 5, 2)
					when 'sb' then 0
					when 'dv' then 1
					when 'qa' then 2
					when 'ts' then 2
					when 'vv' then 3
					when 'iv' then 3
					when 'im' then 3
					when 'pf' then 4
					when 'if' then 4
					when 'tr' then 5
					when 'pr' then 6
					else -1
				end,
				database_name) database_list
			from compare_run_$RUN_ID$
		)
		cross join
		(
			--Difference letters.  Only include hash-key references with data.
			select
				listagg(chr(64 + level), ',') within group (order by level) letter_select,
				listagg(''''||chr(64 + level)||''' as '||chr(64 + level), ',') within group (order by level) letter_pivot
			from dual
			connect by level <=
			(
				--The maximum number of distinct hashes per object.
				select max(distinct_hash_count) max_distinct_hash_count
				from
				(
					--Distinct hashes per object.
					select count(distinct hash) over (partition by owner, object_type, object_name) distinct_hash_count
					from compare_ddl_$RUN_ID$
				)
			)
		)
	]', '$RUN_ID$', v_run_id)
	into v_database_list, v_letter_select, v_letter_pivot;


	--Query for view
	v_query := replace(replace(replace(replace(
	q'[
		--Differences and DDL.
		select differences.*, #LETTER_SELECT#
		from
		(
			--Differences.
			select *
			from
			(
				--Objects and hashes.
				select
					objects_with_counts.owner,
					objects_with_counts.object_type,
					objects_with_counts.object_name,
					objects_with_counts.database_name,
					distinct_version_count versions,
					hash_key
				from
				(
					--Objects with counts
					select database_name, owner, object_type, object_name, hash
						--Count hashes and missing hashes for distinct versions.
						,count(distinct hash) over (partition by owner, object_type, object_name)
						+
						--Add 1 if something is missing - if the object count and database count are different.
						case
							when count(*) over (partition by owner, object_type, object_name)
								<>
								count(distinct database_name) over ()
								then 1
							else 0
						end distinct_version_count
					from compare_ddl_$RUN_ID$
				) objects_with_counts
				left join
				(
					--Generate a user-friendly hash key, a letter, instead of a huge MD5 hash.
					--For display, the MD5 doesn't matter, we only need to compare a small number of items on the same row.
					select owner, object_type, object_name, hash
						,chr(64 + row_number() over (partition by owner, object_type, object_name
							--Order by environment.
							order by case substr(first_database, 5, 2)
								when 'sb' then 0
								when 'dv' then 1
								when 'qa' then 2
								when 'ts' then 2
								when 'vv' then 3
								when 'iv' then 3
								when 'im' then 3
								when 'pf' then 4
								when 'if' then 4
								when 'tr' then 5
								when 'pr' then 6
								else -1
							end,
							first_database)
						) hash_key
					from
					(
						--Distinct hashes for objects.
						select owner, object_type, object_name, hash
							,min(database_name) keep (dense_rank first
								--Order by environment.
								order by case substr(database_name, 5, 2)
									when 'sb' then 0
									when 'dv' then 1
									when 'qa' then 2
									when 'ts' then 2
									when 'vv' then 3
									when 'iv' then 3
									when 'im' then 3
									when 'pf' then 4
									when 'if' then 4
									when 'tr' then 5
									when 'pr' then 6
									else -1
								end,
								database_name) first_database
						from compare_ddl_$RUN_ID$
						group by owner, object_type, object_name, hash
						order by owner, object_type, object_name, first_database, hash
					)
				) hash_keys
					on objects_with_counts.owner = hash_keys.owner
					and objects_with_counts.object_type = hash_keys.object_type
					and objects_with_counts.object_name = hash_keys.object_name
					and objects_with_counts.hash = hash_keys.hash
				--Uncomment this to only show objects with differences.
				--where distinct_version_count > 1
			) objects_with_counts
			pivot
			(
				max(hash_key)
				for database_name
				in (#DATABASE_LIST#)
			)
			order by owner, object_type, object_name
		) differences
		join
		(
			--DDL for differences.
			--Pivot by hash_keys
			select *
			from
			(
				--Generate a user-friendly hash key, a letter, instead of a huge MD5 hash.
				--For display, the MD5 doesn't matter, we only need to compare a small number of items on the same row.
				select owner, object_type, object_name, ddl_4k
					,chr(64 + row_number() over (partition by owner, object_type, object_name
						--Order by environment.
						order by case substr(first_database, 5, 2)
							when 'sb' then 0
							when 'dv' then 1
							when 'qa' then 2
							when 'ts' then 2
							when 'vv' then 3
							when 'iv' then 3
							when 'im' then 3
							when 'pf' then 4
							when 'if' then 4
							when 'tr' then 5
							when 'pr' then 6
							else -1
						end,
						first_database)
					) hash_key
				from
				(
					--Distinct hashes for objects.
					--Cannot really use 4,000 characters because a few of them will be multi-byte and go over 4K byte limit.
					select owner, object_type, object_name, hash, dbms_lob.substr(ddl, offset => 1, amount => 3900) ddl_4k, min(database_name) first_database
					from compare_ddl_$RUN_ID$
					group by owner, object_type, object_name, hash, dbms_lob.substr(ddl, offset => 1, amount => 3900)
					order by owner, object_type, object_name, first_database, hash
				)
			)
			pivot
			(
				max(ddl_4k)
				for hash_key
				--Assumes a maximum of 26 differences for the same object.
				in (#LETTER_PIVOT#)
			)
		) diff_ddl
			on differences.owner = diff_ddl.owner
			and differences.object_type = diff_ddl.object_type
			and differences.object_name = diff_ddl.object_name
		order by differences.owner, differences.object_type, differences.object_name
	]', '#DATABASE_LIST#', v_database_list), '#LETTER_SELECT#', v_letter_select), '#LETTER_PIVOT#', v_letter_pivot)
	, '$RUN_ID$', v_run_id);

	--For debugging, print the query used.
	dbms_output.put_line(substr(v_query, 1, 3000));
	dbms_output.put_line(substr(v_query, 3000));

	--Create a view with the query.
	execute immediate 'create or replace view ddl_compare_view as'||chr(10)||v_query;

end compare_everything_everywhere;
/

--#6c: Create public synonym on procedure.
create public synonym compare_everything_everywhere for method5.compare_everything_everywhere;
