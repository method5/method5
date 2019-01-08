--------------------------------------------------------------------------------
-- Purpose: Compare schema objects across many databases, all in one view.
-- How to use:
--    Run steps #1 through #5 to generate and query results.
-- Version: 2.1.6
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


--Optional steps to export and format from PL/SQL Developer to Excel.
--	Retrieve all data (click the double-green arrow on the data grid).
--	Right-click on top-left corner of data grid.
--	Select "Copy to Excel", XLSX.
--	In Excel sheet, delete the first column.
--	Highlight all the columns before "A", then double-click on right-edge to minimize their size.
--	Highlight columns "A" to "Z", right-click on header, select "Column Width", enter 10 and hit OK.
--	Right-click on header of highlighted A-Z, select Format Cells, Alignment tab, click "Wrap Text", hit OK.
--	Highlight everything (CTRL+A), right-click on left-hand-side, select Row Height, enter 12.75, click OK.
--	Save the Excel file, email it.  Note that this only shows differences, and only the first 4K of each object.

--Optional step to customize horizontal sort order:
--	Modify the procedure in install_compare_everything_everywhere.sql.  There are
--	four locations with code like "order by case substr(database_name, 5, 2)" that
--	can be customized to sort based on database name prefixes and suffixes.
--	(Or you can simply cut and paste the columns in Excel each time.)


--------------------------------------------------------------------------------
--#5: Ad hoc difference queries (optional).
--------------------------------------------------------------------------------

--Look at single differences.
--This can help for objects larger than 4K that may not show up completely in Excel exports.
select *
from ddl_$SCHEMA$_$RUN_ID$
order by database_name, owner, object_type, object_name;
