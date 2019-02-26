prompt Removing Method5 global data dictionary jobs...


---------------------------------------
--#0: Check the user.
@code/check_user must_be_m5_user
set serveroutput off;


---------------------------------------
--#1: Remove global data dictionary jobs.
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
			'M5_DBA_USERS_JOB',
			'M5_V$PARAMETER_JOB',
			'M5_PRIVILEGES_JOB',
			'M5_USER$_JOB'
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
