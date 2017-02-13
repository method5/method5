--------------------------------------------------------------------------------
-- Purpose: Active Session comparisons.  This example of how to use Active
--    Session data shows how to compare all database activity during a period of
--    time, to look for any patterns or outliers.
-- How to use:
--    Run step #1 to gather the data.
--    Run step #2 to generate data for an Excel spreadsheet.
-- Version: 1.0.0
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
--#1: Gather data between between 50 and 10 minute mark.
--(Adjust the time period in this query as needed.)
--------------------------------------------------------------------------------

--#1a: Start gathering data.
begin
	m5_proc(
		p_code =>
			q'[
				--Column list is based on 11.2.0.4
				select dba_users.username,
					inst_id, sample_id, sample_time, is_awr_sample, session_id, session_serial#, session_type, flags, dba_users.user_id, 
					sql_id, is_sqlid_current, sql_child_number, sql_opcode, force_matching_signature, top_level_sql_id, 
					top_level_sql_opcode, sql_opname, sql_plan_hash_value, sql_plan_line_id, sql_plan_operation, sql_plan_options, sql_exec_id, 
					sql_exec_start, plsql_entry_object_id, plsql_entry_subprogram_id, plsql_object_id, plsql_subprogram_id, qc_instance_id, 
					qc_session_id, qc_session_serial#, px_flags, event, event_id, event#, seq#, p1text, p1, p2text, p2, p3text, p3, wait_class, 
					wait_class_id, wait_time, session_state, time_waited, blocking_session_status, blocking_session, blocking_session_serial#, blocking_inst_id, 
					blocking_hangchain_info, current_obj#, current_file#, current_block#, current_row#, top_level_call#, top_level_call_name, consumer_group_id, 
					xid, remote_instance#, time_model, in_connection_mgmt, in_parse, in_hard_parse, in_sql_execution, in_plsql_execution, 
					in_plsql_rpc, in_plsql_compilation, in_java_execution, in_bind, in_cursor_close, in_sequence_load, capture_overhead, replay_overhead, 
					is_captured, is_replayed, service_hash, program, module, action, client_id, machine, port, ecid, dbreplay_file_id, dbreplay_call_counter, 
					tm_delta_time, tm_delta_cpu_time, tm_delta_db_time, delta_time, delta_read_io_requests, delta_write_io_requests, delta_read_io_bytes, 
					delta_write_io_bytes, delta_interconnect_io_bytes, pga_allocated, temp_space_allocated
				from gv$active_session_history
				join dba_users
					on gv$active_session_history.user_id = dba_users.user_id
				where sample_time between
					trunc(systimestamp, 'HH24') - interval '2' hour + interval '50' minute and
					trunc(systimestamp, 'HH24') - interval '2' hour + interval '70' minute
			]',
		p_targets => null,
		p_table_name => 'ash_between_times',
		p_table_exists_action => 'drop'
	);
end;
/

--#1b: Check status of data gathering.
select * from ash_between_times order by database_name, 2;
select * from ash_between_times_meta order by date_started;
select * from ash_between_times_err order by database_name;
--Find jobs that have not finished yet:
select * from sys.dba_scheduler_running_jobs where owner = user;



--------------------------------------------------------------------------------
--#2: Generate pivoted data for Excel.
--------------------------------------------------------------------------------

--#2a: Run this to generate the data.
select *
from table(method5.method4.dynamic_query(
	p_stmt =>
		q'[
			--A query that generates a query string.
			--This is confusing, but it allows for a completley dynamic SQL pivot.
			select
				q'!
					--A pivoted table of activity per host, per minute, around the hour mark.
					select *
					from
					(
						--Convert minute into a series minute.
						select
							host_or_cluster,
							case
								when the_minute >= 50 then -(60-the_minute)
								when the_minute <= 10 then the_minute
							end series_minute
							,total
						from
						(
							--Aggregated per host/cluster and minute.
							select host_or_cluster, to_number(to_char(sample_time, 'MI')) the_minute, count(*) total
							from ash_between_times
							join
							(
								select
									lower(database_name) database_name,
									min(nvl(cluster_name, host_name)) host_or_cluster
								from m5_database
								where lower(database_name) in (select database_name from ash_between_times)
								group by database_name
							) databases
								on ash_between_times.database_name = databases.database_name
							group by host_or_cluster, to_number(to_char(sample_time, 'MI'))
						)
						order by 1
					)
					pivot (sum(total) for host_or_cluster in (
						!'||
						--List of strings of all clusters or hosts in the results.
						(
							select listagg(''''||host_or_cluster||'''', ',') within group (order by host_or_cluster) host_or_clusters
							from
							(
								select distinct nvl(cluster_name, host_name) host_or_cluster
								from m5_database
								where lower(database_name) in (select database_name from ash_between_times)
							)
						)
						||q'!
					))
					order by series_minute
				!' the_query
			from dual
		]'
));


--#2b: Steps to create an Excel chart of data.
/*
1. Export to Excel.
2. In Excel, higlight all the data by pressing CTRL+A.
3. Insert --> Line --> 2-D Line --> Line (the first chart in the top-left).
4. Right-click on the chart and choose "Select Data...".
5. Click on "Switch Row/Column".
6. Remove "SERIES_MINUTE" from the left-hand side.
7. Click on "Edit" on the right-hand side "Horizontal (Category) Axis Label".
8. Select the values in the SERIES_MINUTE column, the rows with values -10 to 10, click OK, then click OK again.

Now the chart should look similar to the example chart.
It should show you the activity per host, for all hosts.
*/
