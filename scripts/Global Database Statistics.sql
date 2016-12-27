--------------------------------------------------------------------------------
-- Purpose: Gather global database statistics to help understand your environment.
-- How to use: Run #1 to gather data, #2 to check results, and #3 for final report.
-- Prerequisites: AWR for "Physical I/O per day" and "Queries per day", auditing
--   on logons for "Connections per day".
-- Version: 1.0.0
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
--#1: Gather raw data.
--------------------------------------------------------------------------------

begin
	m5_proc(
		p_code => q'[
			select
				(
					--Count of all database users.
					select count(*)
					from dba_users
				) user_count,
				(
					--Count of all non-Oracle database users.
					select count(*)
					from dba_users
					where username not in
						(
							'ANONYMOUS','APPQOSSYS','AQMONITOR','AUDSYS','BIBPM','BIFOD','BISAMPLE','CTXSYS','DBSNMP',
							'DIP','DMSYS','EXFSYS','FLOWS_FILES','GSMADMIN_INTERNAL','GSMCATUSER','GSMUSER','LBACSYS',
							'MDDATA','MDSYS','ODI_STAGING','OJVMSYS','OLAPSYS','OPS$ORACLE','ORACLE','ORACLE_OCM',
							'ORDDATA','ORDPLUGINS','ORDSYS','OUTLN','OWBSYS','OWBSYS_AUDIT','PERFSTAT','PROFILER',
							'SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','SQLTXADMIN',
							'SQLTXPLAIN','SYS','SYSBACKUP','SYSDG','SYSKM','SYSTEM','TRACESVR','WMSYS','XDB','XS$NULL'
						)
						and username not like 'APEX%'
				) non_oracle_user_count,
				(
					--Segment size.
					select sum(bytes) bytes
					from dba_segments
				) segment_size_bytes,
				(
					--Connections per day.
					select count(*) total
					from dba_audit_trail
					where action_name = 'LOGON'
						and trunc(timestamp) = trunc(sysdate-1)
				) connections_per_day,
				(
					--Non-Oracle object count.
					select count(*) total
					from dba_objects
					where owner not in
					(
						'ANONYMOUS','APPQOSSYS','AQMONITOR','AUDSYS','BIBPM','BIFOD','BISAMPLE','CTXSYS','DBSNMP',
						'DIP','DMSYS','EXFSYS','FLOWS_FILES','GSMADMIN_INTERNAL','GSMCATUSER','GSMUSER','LBACSYS',
						'MDDATA','MDSYS','ODI_STAGING','OJVMSYS','OLAPSYS','OPS$ORACLE','ORACLE','ORACLE_OCM',
						'ORDDATA','ORDPLUGINS','ORDSYS','OUTLN','OWBSYS','OWBSYS_AUDIT','PERFSTAT','PROFILER',
						'SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR','SPATIAL_WFS_ADMIN_USR','SQLTXADMIN',
						'SQLTXPLAIN','SYS','SYSBACKUP','SYSDG','SYSKM','SYSTEM','TRACESVR','WMSYS','XDB','XS$NULL'
					)
					and owner not like 'APEX%'
				) object_count,
				(
					--Physical I/O per day.
					select avg(average) average
					from dba_hist_sysmetric_summary
					where metric_name = 'I/O Megabytes per Second'
						and trunc(begin_time) = trunc(sysdate-1)
					group by metric_name
				) physical_io_per_day,
				(
					--Queries per day.
					select avg(average) average
					from dba_hist_sysmetric_summary
					where metric_name = 'User Calls Per Sec'
						and trunc(begin_time) = trunc(sysdate-1)
					group by metric_name
				) queries_per_day
			from dual
		]',
		p_targets => 'dev,qa,itf,vv,prod',
		p_table_name => 'global_db_stats',
		p_table_exists_action => 'drop'
	);
end;
/



--------------------------------------------------------------------------------
--#2: Wait for data, fix any errors.
--------------------------------------------------------------------------------

-- The above query may take a long time to return for databases with a lot of
-- data in DBA_SEGMENTS, AWR, or the audit trail.
select * from global_db_stats order by database_name, 2;
select * from global_db_stats_meta order by date_started;
select * from global_db_stats_err order by database_name;




--------------------------------------------------------------------------------
--#3: Format and display final report.
--------------------------------------------------------------------------------

select metric_name, metric_value
from
(
	select 1 order_by, 'Total Databases' metric_name, to_char(targets_expected) metric_value from global_db_stats_meta union all
	select 2 order_by, 'Databases in Results' metric_name, to_char(targets_completed) metric_value from global_db_stats_meta union all
	select 3 order_by, 'Space (Segments)' metric_name, to_char(round(sum(segment_size_bytes)/1024/1024/1024/1024))||' TB' metric_value from global_db_stats union all
	select 4 order_by, 'Schema count' metric_name, trim(to_char(sum(non_oracle_user_count), '999,999')) metric_value from global_db_stats union all
	select 5 order_by, 'Connections per day' metric_name, trim(to_char(sum(connections_per_day), '999,999,999')) metric_value from global_db_stats union all
	select 6 order_by, 'Object counts' metric_name, trim(to_char(sum(object_count), '999,999,999')) metric_value from global_db_stats union all
	select 7 order_by, 'Physical I/O per day' metric_name, to_char(round(sum(physical_io_per_day)/1024/1024 * 60 * 60 * 24))||' TB' metric_value from global_db_stats union all
	select 8 order_by, 'Queries per day' metric_name, trim(to_char(sum(queries_per_day)*60*60*24, '999,999,999,999')) metric_value from global_db_stats
)
order by order_by;

