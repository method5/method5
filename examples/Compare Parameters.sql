--------------------------------------------------------------------------------
-- Purpose: Compare database parameters across lifecycles.  Run on GRCTPR02.
-- How to use:
--    Run #3 (one-time) to install procedure.
--      Optionally change code like `when 'pr' then 5` to match your database naming standards.
--      That code only affects order databases are displayed in.
--    Run #1 to generate a view.
--    Run #2 to see the results. 
-- Version: 4.0.0
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
-- #1: Enter target list and run the create a parameter comparison view.
--  The P_TARGETS parameter is just like the Method5 parameter, it accepts comma-
--  separated lists of databases, environments, hosts, wildcards, a query
--  returning a database, a Target Group, etc.
--------------------------------------------------------------------------------

--#1a: Gather the data.  This should only take a few seconds.
begin
	create_parameter_compare_view(p_targets => '&CHANGE_ME');
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



--------------------------------------------------------------------------------
-- #3: Create procedure to create view in your schema.  (One-time step)
--------------------------------------------------------------------------------
create or replace procedure create_parameter_compare_view(p_targets in varchar2) authid current_user is
	v_pivot_database_list varchar2(4000);
	v_select_database_list varchar2(4000);
begin
	--Gather parameter information.
	m5_proc(
		p_table_name => 't_compare_parameter',
		p_code => 'select name, value from v$parameter',
		p_targets => p_targets,
		p_table_exists_action => 'DROP',
		p_asynchronous => false
	);

	--Generate database list based on the results.
	execute immediate
	q'[
		select
			listagg(''''||database_name||''' as '||database_name, ',') within group
			(
				--You may want to customize this list for your environment.
				order by
					case substr(database_name, 5, 2)
						when 'sb' then 0
						when 'dv' then 1
						when 'qa' then 2
						when 'ts' then 2
						when 'vv' then 3
						when 'iv' then 3
						when 'im' then 3
						when 'pf' then 4
						when 'if' then 4
						when 'pr' then 5
						when 'tr' then 5
					end,
					database_name
			) pivot_database_list,
			listagg(database_name||'_value as '||database_name, ',') within group
			(
				--You may want to customize this list for your environment.
				order by
					case substr(database_name, 5, 2)
						when 'sb' then 0
						when 'dv' then 1
						when 'qa' then 2
						when 'ts' then 2
						when 'vv' then 3
						when 'iv' then 3
						when 'im' then 3
						when 'pf' then 4
						when 'if' then 4
						when 'pr' then 5
						when 'tr' then 5
					end,
					database_name
			) select_database_list
		from
		(
			select distinct database_name
			from t_compare_parameter
		)
	]'
	into v_pivot_database_list, v_select_database_list;

	--Create a view 
	execute immediate replace(replace(q'<
		create or replace view parameter_compare_vw as
		select name, same_or_different, $$SELECT_DATABASE_LIST$$
		from
		(
			--Databases, parameters, and values
			select databases.database_name, parameters.name, database_parameters.value
				,case when count(distinct nvl(value, '!!NULL!!')) over (partition by parameters.name) = 1 then 'Same' else 'Different' end same_or_different
			from
			(
				--Databases.
				select distinct lower(database_name) database_name
				from t_compare_parameter
				order by 1
			) databases
			cross join
			(
				--Parameters.
				select distinct name
				from t_compare_parameter
				order by 1
			) parameters
			left join
			(
				select lower(database_name) database_name, name, value
				from t_compare_parameter
				order by name
			) database_parameters
				on databases.database_name = database_parameters.database_name
				and parameters.name = database_parameters.name
			order by parameters.name, databases.database_name
		) database_parameter_value
		pivot
		(
			max(value) value
			--Add database list here.
			for database_name in ($$PIVOT_DATABASE_LIST$$)
		)
		order by name
	>', '$$PIVOT_DATABASE_LIST$$', v_pivot_database_list), '$$SELECT_DATABASE_LIST$$', v_select_database_list);
end;
/

