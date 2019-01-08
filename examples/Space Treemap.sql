--Purpose: Create a treemap visualization of space usage.
--How to use:
--	Run #1 to gather data, it may take a few minutes.
--	Run #2 to check that lifecycles and LOBs are correct.
--	Run #3 to call the function with different group settings.
--Version: 1.0.4



--------------------------------------------------------------------------------
--#1: Gather data.  This step can take a few minutes.
--------------------------------------------------------------------------------

--Start gathering.
begin
	m5_proc(
		p_code                => q'<select owner, sum(bytes) bytes from dba_segments group by owner>',
		p_table_name          => 'space_treemap',
		p_table_exists_action => 'DROP'
	);
end;
/


--Check results.  Resolve any errors and re-run if necessary.
select * from space_treemap order by 1, 2;
select * from space_treemap_meta;
select * from space_treemap_err order by 1;
--Jobs that have not finished yet.
select * from sys.dba_scheduler_running_jobs where owner = user;



--------------------------------------------------------------------------------
--#2: Check metadata.  There should not be any relevant databases without a
--	lifecycle or line of business.  Fix any missing values before proceeding.
--------------------------------------------------------------------------------
select *
from m5_database
where lifecycle_status is null
	or line_of_business is null;



--------------------------------------------------------------------------------
--#3: Build HTML files to contain the visualization.
--------------------------------------------------------------------------------

--#3a: Change the order of the 4 values to genearate different charts.
select method5.get_space_treemap('Owner, Lifecycle, LOB, DB', 'lifecycle_status value2, line_of_business value3, space_treemap.database_name value4, owner value1,') from dual;
select method5.get_space_treemap('Lifecycle, LOB, DB, owner', 'lifecycle_status value1, line_of_business value2, space_treemap.database_name value3, owner value4,') from dual;
select method5.get_space_treemap('Lifecycle, DB, owner', 'lifecycle_status value1, space_treemap.database_name value2, owner value3, null value4,') from dual;


--#3b: Save the CLOB as an .HTML file and open in a browser.

