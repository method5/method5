--------------------------------------------------------------------------------
-- Purpose: Compare database parameters across lifecycles.
-- How to use:
--    Run #1 to generate a view.
--    Run #2 to see the results. 
--    (Optional) Modify code/addons/install_compare_parameters
--      Optionally change code like `when 'pr' then 5` to match your database naming standards.
--      That code only affects order databases are displayed in.
-- Version: 4.0.2
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
-- #1: Enter target list and run the create a parameter comparison view.
--  The P_TARGETS parameter is just like the Method5 parameter, it accepts comma-
--  separated lists of databases, environments, hosts, wildcards, a query
--  returning a database, a Target Group, etc.
--------------------------------------------------------------------------------

--#1a: Gather the data.  This should only take a few seconds.
begin
	method5.create_parameter_compare_view(p_targets => '&CHANGE_ME');
end;
/

--#1b: Check results, metadata, and errors.
select * from t_compare_parameter order by database_name, 2;
select * from t_compare_parameter_meta order by date_started;
select * from t_compare_parameter_err order by database_name;
--If it's running for a long time, see which database it's stuck on:
select * from dba_scheduler_running_jobs;



--------------------------------------------------------------------------------
-- #2: View the results.
--------------------------------------------------------------------------------
select * from parameter_compare_vw;
