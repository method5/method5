prompt Removing Method5 housekeeping jobs...


---------------------------------------
--#0: Check the user.
@code/check_user must_be_m5_user
set serveroutput off;


---------------------------------------
--#1: Remove housekeeping jobs.
declare
	v_job_not_running exception;
	pragma exception_init(v_job_not_running, -27366);
begin
	for jobs_to_remove in
	(
		select owner||'.'||job_name job_name
		from dba_scheduler_jobs
		where job_name in
		(
			'CLEANUP_M5_TEMP_TRIGGERS_JOB',
			'CLEANUP_M5_TEMP_TABLES_JOB',
			'DIRECT_M5_GRANTS_JOB',
			'CLEANUP_REMOTE_M5_OBJECTS_JOB',
			'EMAIL_M5_DAILY_SUMMARY_JOB',
			'STOP_TIMED_OUT_JOBS_JOB',
			'BACKUP_M5_DATABASE_JOB',
			'CLEANUP_UNUSED_M5_LINKS_JOB'
		)
		order by 1
	) loop
		begin
			dbms_scheduler.stop_job(job_name => jobs_to_remove.job_name, force => true);
		exception when v_job_not_running then
			null;
		end;
		dbms_scheduler.drop_job(job_name => jobs_to_remove.job_name, force => true);
	end loop;
end;
/


prompt Done.
