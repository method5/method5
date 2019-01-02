/*******************************************************************************
  _____                      
 / ____|                     
| (___  _ __   __ _ _ __ ___ 
 \___ \| '_ \ / _` | '__/ _ \
 ____) | | | | (_| | | |  __/
|_____/|_| |_|\__,_|_|  \___|
                             
Snare is a Method5 extension that lets you quickly gather and compare
Oracle database configuration information over time.

Snare runs daily and gathers information about:
* Components
* Crontab
* Invalid objects
* Last patch
* Miscellaneous database settings
* M5_DATABASE
* V$PARAMETER

You can easily compare different snapshots, and you can see the differences as
a summary report or as a table with all the details.

You can also gather and delete custom snapshots, and you can change the default
configuration items gathered through a simple table of queries.

How to use this file:
	#1 Enable Snare (it is disabled by default).
	#2 Compare snapshots.
	#3 Create custom snapshots.
	#4 Maintain snapshots and jobs.
	#5 Disable Snare.

Version: 1.0.1
*******************************************************************************/



--------------------------------------------------------------------------------
--#1: Enable Snare.
--------------------------------------------------------------------------------

--Enable Snare job.
declare
	v_owner varchar2(128);
begin
	select owner
	into v_owner
	from dba_scheduler_jobs
	where job_name = 'SNARE_DAILY_JOB';

	dbms_scheduler.enable('"'||v_owner||'".SNARE_DAILY_JOB');
end;
/



--------------------------------------------------------------------------------
--#2: Compare snapshots.
--------------------------------------------------------------------------------

--Compare configuration snapshots and display a summary.
--The output also contains queries to drill down into details and errors.
--For example:
select snare.compare_summary(
	p_snapshot_before => 'EVERYTHING_20180710',
	p_snapshot_after  => 'EVERYTHING_20180717'
)
from dual;



--------------------------------------------------------------------------------
--#3: Create custom snapshots.
--	You probably don't need to do this since there's already a job that gather
--	all the data once a day.
--------------------------------------------------------------------------------

--A: Look at existing snapshots since you may want to use a similar naming
--	scheme and target string.
select * from snapshots order by the_date desc;


--B: Create a configuration snapshot.
--	This may take a while depending on the targets.
--	I recommend you use a name format like this: short_description_YYYYMMDD
--	Check the table CONFIGS for a list of all possible configurations.
begin
	snare.create_snapshot(
		p_snapshot_name => 'TEST1',
		p_targets => 'dev,qa,itf,vv,prod'
		--This optional parameter lets you limit the configs to compare.
		--For example:
		,p_configs => method5.string_table('Components', 'Misc database settings')
	);
end;
/


--C: Check for configuration errors.
select * from snapshot_metadata order by date_started desc;
select * from snapshot_errors order by date_error desc, target;


--D: (OPTIONAL) If there are critical errors, such as an unavailable database,
--	you may want to fix the errors, delete the old snapshot, and go back
--	a few steps and recreate the snapshot.
--
--	You can delete a snapshot like this:
/*
	begin
		snare.delete_snapshot('EVERYTHING_20180712');
	end;
*/


--E: Compare configuration snapshots and display a summary.
select snare.compare_summary(
	p_snapshot_before => 'EVERYTHING_20180710',
	p_snapshot_after  => 'EVERYTHING_20180712'
)
from dual;


--F: (OPTIONAL) Compare configuration snapshots and display details.
select * from table(snare.compare_details(
	p_snapshot_before => 'EVERYTHING_20180710',
	p_snapshot_after  => 'EVERYTHING_20180712'
));


--G: (OPTIONAL) View raw tables.
select * from snapshots order by the_date desc;
select * from snapshot_results order by 1,2,3,4;
select * from snapshot_metadata order by 1,2;
select * from snapshot_errors order by 1,2;
select * from configs;



--------------------------------------------------------------------------------
--#4: Maintain tables and check on job status.
--------------------------------------------------------------------------------

--A: (OPTIONAL, run every few months) Move the table to compress it and save disk space.
--  WARNING: This will lock the table while the operation is running.
--	WARNING: If you run the MOVE you must also run the REBUILD to make the index usable.
alter table method5.snapshot_results move;
alter index method5.snapshot_results_pk rebuild;


--B: Check job results.  The job status should be "SUCCEEDED".
--	If it's something else, investigate the errors.
select * from dba_scheduler_jobs where job_name = 'SNARE_DAILY_JOB';
select * from dba_scheduler_job_run_details where job_name = 'SNARE_DAILY_JOB' order by log_date desc;
select * from dba_scheduler_running_jobs;

select * from snapshots where snapshot_name = 'EVERYTHING_20180712';
select * from snapshot_results where snapshot_name = 'EVERYTHING_20180712' order by 1,2,3,4;
select * from snapshot_metadata where snapshot_name = 'EVERYTHING_20180712' order by 1,2;
select * from snapshot_errors where snapshot_name = 'EVERYTHING_20180712' order by 1,2;
select * from configs order by config_type;



--------------------------------------------------------------------------------
--#5: Disable Snare.
--------------------------------------------------------------------------------

--Disable Snare job.
declare
	v_owner varchar2(128);
begin
	select owner
	into v_owner
	from dba_scheduler_jobs
	where job_name = 'SNARE_DAILY_JOB';

	dbms_scheduler.disable('"'||v_owner||'".SNARE_DAILY_JOB');
end;
/
