--------------------------------------------------------------------------------
-- Purpose: Forecast ASM growth.
-- How to use: Follow steps #2 and #3 to install.  Follow steps #1 to check job status.
-- Prerequisites: A configured target group named "AWR" for selecting one database
--                from every AWR instance.
-- Version: 2.0.0
--------------------------------------------------------------------------------



--------------------------------------------------------------------------------
--#1: Check job status (check periodically)
--------------------------------------------------------------------------------
--Check job status - there should be a "SUCCEEDED" this morning or yesterday.
select * from dba_scheduler_job_run_details where job_name = 'GATHER_V$ASM_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'GATHER_V$ASM_JOB';

select * from dba_scheduler_job_run_details where job_name = 'EMAIL_ASM_FORECAST_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'EMAIL_ASM_FORECAST_JOB';

--Check database results.  It should work about 99% of the time.
select * from v$asm_diskgroup_fcst_meta order by date_started desc;
select * from v$asm_diskgroup_fcst_err order by date_error desc;



--------------------------------------------------------------------------------
--#2: Install objects to gather ASM data (one-time step)
--------------------------------------------------------------------------------

--#2a: Install procedure.
create or replace procedure gather_asm_disk_and_disgroup authid current_user is
--Purpose: Gather ASM forecast data.
--Warning: Do not directly modify this procedure, the official copy is version controlled.
begin
	m5_proc(
		p_table_name => 'v$asm_diskgroup_fcst',
		p_table_exists_action => 'APPEND',
		p_asynchronous => false,
		p_targets => '$asm',
		p_code => '
			--11gR2 values:
			select trunc(sysdate) the_date,
				group_number, name, sector_size, block_size, allocation_unit_size, state, type, 
				total_mb, free_mb, hot_used_mb, cold_used_mb, required_mirror_free_mb, usable_file_mb, offline_disks, 
				compatibility, database_compatibility, voting_files
			from v$asm_diskgroup'
	);
end;
/


--#2b: Create daily job.
begin
	dbms_scheduler.create_job(
		job_name => 'GATHER_V$ASM_JOB',
		job_type => 'PLSQL_BLOCK',
		start_date => systimestamp at time zone 'US/Eastern',
		enabled => true,
		repeat_interval => 'freq=daily; byhour=1; byminute=50; bysecond=0',
		job_action => 'begin gather_asm_disk_and_disgroup; end;');
end;
/


--#2c: Force the job to run immediately to create table.
begin
	dbms_scheduler.run_job('GATHER_V$ASM_JOB');
end;
/


--#2d: Check job status.
select * from dba_scheduler_job_run_details where job_name = 'GATHER_V$ASM_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'GATHER_V$ASM_JOB';


--#2d: Create a unique constraint.
--This helps in case a job runs late and tries to create two entries on one day.
alter table v$asm_diskgroup_fcst add constraint v$asm_diskgroup_fcst_uq unique (database_name, the_date, name);


--#2e: Wait 16 days.  It takes time to build enough history for a forecast.



--------------------------------------------------------------------------------
--#3: Install Forecast objects (one-time step)
--------------------------------------------------------------------------------

--#3a: Create configuration table.
create table asm_forecast_config
(
	config_name varchar2(4000),
	config_string varchar2(4000),
	config_number number,
	constraint asm_forecast_config_pk primary key (config_name)
);


--#3b: Modify the below statements with the real values and then insert the configuration data.
insert into asm_forecast_config(config_name, config_string) values ('MAIL_HOST', '&MAIL_HOST');
insert into asm_forecast_config(config_name, config_number) values ('MAIL_PORT', &MAIL_PORT);
insert into asm_forecast_config(config_name, config_string) values ('SENDER_AND_FROM_AND_REPLY_TO', '&SENDER');
insert into asm_forecast_config(config_name, config_string) values ('RECIPIENT_AND_TO', '&RECIPIENT_AND_TO');


--#3c: Create procedure to email results.
create or replace procedure email_asm_forecast authid current_user is
/*
	Purpose: Send an email of the Top N forecasted ASM diskgroups.

	WARNING: Do not directly modify this procedure.  The official copy is in SVN.

*/
	v_mail_host varchar2(4000);
	v_mail_port varchar2(4000);
	v_sender_and_from_and_reply_to varchar2(4000);
	v_recipient_and_to varchar2(4000);

	v_email_body varchar2(32767);
	conn utl_smtp.connection;
	v_background_color varchar2(100);
begin
	--Get configuration data.
	select
		max(case when config_name = 'MAIL_HOST' then config_string else null end),
		max(case when config_name = 'MAIL_PORT' then config_number else null end),
		max(case when config_name = 'SENDER_AND_FROM_AND_REPLY_TO' then config_string else null end),
		max(case when config_name = 'RECIPIENT_AND_TO' then config_string else null end)
	into v_mail_host, v_mail_port, v_sender_and_from_and_reply_to, v_recipient_and_to
	from asm_forecast_config;

	--Use UTL_SMTP to avoid 32K limit of UTL_MAIL.
	conn := utl_smtp.open_connection(host => v_mail_host, port => v_mail_port);
	utl_smtp.helo(conn, domain => v_mail_host);
	utl_smtp.mail(conn, sender => v_sender_and_from_and_reply_to);
	utl_smtp.rcpt(conn, recipient => v_recipient_and_to);
	utl_smtp.open_data(conn);
	utl_smtp.write_data(conn, 'MIME-version: 1.0' || utl_tcp.CRLF);
	utl_smtp.write_data(conn, 'Content-Type: text/html; charset=iso-8859-6' || utl_tcp.CRLF);
	utl_smtp.write_data(conn, 'Content-Transfer-Encoding: 8bit' || utl_tcp.CRLF);
	utl_smtp.write_data(conn, 'From:' || v_sender_and_from_and_reply_to || utl_tcp.CRLF);
	utl_smtp.write_data(conn, 'To:' || v_recipient_and_to || utl_tcp.CRLF);
	utl_smtp.write_data(conn, 'Reply-To:' || v_sender_and_from_and_reply_to || utl_tcp.CRLF); 
	utl_smtp.write_data(conn, 'Subject: ASM Forecast' || utl_tcp.CRLF);
	utl_smtp.write_data(conn, utl_tcp.crlf); 

	--Add header.
	utl_smtp.write_data(conn, '
<html>
<head>
	<STYLE TYPE="text/css">
	<!--
	TD{font-family: Courier New; font-size: 10pt; border: 1px solid gray;}
	TH{font-family: Courier New; font-size: 10pt; border: 1px solid gray;}
	table {border-collapse: collapse;}
	--->
	</STYLE>
</head>

Use this email to determine when to add disks.<br><br>

The table below shows the 10 diskgroups that are predicted as most likely to run out of space.
These predictions are based on the worst of three forecasts.
The forecasts use the last 2, 7, and 30 days of data to predict diskgroup growth over the next month.
Diskgroups with less than two weeks of data are excluded.
Use the data and charts below to identify meaningful trends.<br><br>

If the pictures do not display add the sender to your safe list and restart Outlook.
<br><br>

	<body>
	<table border="1">
	<tr>
		<th>Diskgroup</th>
		<th>Hosts</th>
		<th>Now</th>
		<th>FCST 2</th>
		<th>FCST 7</th>
		<th>FCST 30</th>
		<th>Last Total GB</th>
		<th>Last Used GB</th>
		<th>Last Free GB</th>
		<th>Chart</th>
	</tr>
');

	--Add each row for Top N
	for diskgroups in
	(
		--Create table of data.
		select
			'<tr><td>'||
			diskgroup||'</td><td>'||
			hosts||'</td><td>'||
			current_percent_used ||'%</td><td>'||
			forecast_2 ||'%</td><td>'||
			forecast_7 ||'%</td><td>'||
			forecast_30 ||'%</td><td>'||
			trim(to_char(round(last_total_mb/1024),'999,999'))||'</td><td>'||
			trim(to_char(round(last_used_mb/1024),'999,999'))||'</td><td>'||
			trim(to_char(round(last_free_mb/1024),'999,999'))||'</td><td>'||
			'<img alt="'||diskgroup||' chart" src="'||chart||'">'||'</td></tr>'||
			chr(10) html
			,user_friendly_values.*
		from
		(
			--User-friendly values, sort for top N reporting.
			select distinct diskgroup, hosts, round(last_percent_used) current_percent_used
				,round(forecast_2 / last_total_mb * 100) forecast_2
				,round(forecast_7 / last_total_mb * 100) forecast_7
				,round(forecast_30 / last_total_mb * 100) forecast_30
				,last_total_mb, last_used_mb, last_free_mb
				,chart
			from
			(
				--Chart.
				select
					--Create a Google chart.
					--See here for documentation: https://developers.google.com/chart/image/docs/gallery/line_charts
					replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
						'https://chart.googleapis.com/chart?' ||                        --Base URL.
						'chxt=x,y$AMP$chxl=0:|-30|-15|0|15|30|1:|0|$GREATEST_VALUE$' || --X and Y axis labels.
						'$AMP$cht=lxy$AMP$chs=1000x300$AMP$chd=t:$X$|$Y$' ||            --X and Y data for the past 30 days.
						'|0,100|$AVAILABLE_SPACE$,$AVAILABLE_SPACE$' ||                 --Available space line.
						'|$FCST2_X1$,$FCST2_X2$|$FCST2_Y1$,$FCST2_Y2$' ||               --Forecast 2 line.
						'|$FCST7_X1$,$FCST7_X2$|$FCST7_Y1$,$FCST7_Y2$' ||               --Forecast 7 line.
						'|$FCST30_X1$,$FCST30_X2$|$FCST30_Y1$,$FCST30_Y2$' ||           --Forecast 30 line.
						'$AMP$chco=000000,FF0000,00FF00,0000FF,FFC0CB'||                --Chart colors.  Black for real values, red for max available, then green, blue, pink for forecasts.
						'$AMP$chls=5,5,0|1,1,0|4,4,4|4,4,4|4,4,4'||                     --Line style.  Solid for real values, solid for max available used, dashed for forecasts.
						'$AMP$chdl=Past|Available|2-day|7-day|30-day'||                 --Chart labels.
						'$AMP$chtt=$DISKGROUP$+Growth+and+Forecasts'                    --Chart title.
						--
						--REPLACE:
						--
						--Some IDEs will interpret the ampersand as a variable.
						, '$AMP$', chr(38))
						--Display in TB if large, or GB if small
						, '$GREATEST_VALUE$', case when greatest_value_mb > 1024*1024 then round(greatest_value_mb/1024/1024, 1) || '+T' else round(greatest_value_mb/1024) || '+G' end)
						, '$X$', x)
						, '$Y$', y)
						, '$AVAILABLE_SPACE$', round(last_total_mb/greatest_value_mb*100, 1))
						, '$FCST2_X1$', round(FCST2_X1, 1))
						, '$FCST2_X2$', round(adjusted_FCST2_X2, 1))
						--Use NVL(..., -1) because negative values do not appear, but missing values break the chart.
						, '$FCST2_Y1$', nvl(round(FCST2_Y1, 1), -1))
						, '$FCST2_Y2$', nvl(round(adjusted_FCST2_Y2, 1), -1))
						, '$FCST7_X1$', round(FCST7_X1, 1))
						, '$FCST7_X2$', round(adjusted_FCST7_X2, 1))
						, '$FCST7_Y1$', nvl(round(FCST7_Y1, 1), -1))
						, '$FCST7_Y2$', nvl(round(adjusted_FCST7_Y2, 1), -1))
						, '$FCST30_X1$', round(FCST30_X1, 1))
						, '$FCST30_X2$', round(adjusted_FCST30_X2, 1))
						, '$FCST30_Y1$', nvl(round(FCST30_Y1, 1), -1))
						, '$FCST30_Y2$', nvl(round(adjusted_FCST30_Y2, 1), -1))
						, '$DISKGROUP$', diskgroup)  chart
						,chart_axes.*
				from
				(
					--Chart axes.
					select
						adjusted_coordinates.*,
						--X-axis.  Convert the 1-30 to 1-50 to fill up 50% of the chart.
						listagg(round((30 - date_number_desc + 1) * 5/3, 1), ',') within group (order by date_number_desc desc) over (partition by diskgroup, hosts) x,
						--Y-axis.  Percent of the greatest value.
						listagg(round(used_mb/greatest_value_mb*100), ',') within group (order by date_number_desc desc) over (partition by diskgroup, hosts) y
					from
					(
						--Adjust final X coordinates.
						--If the Y goes negative the X will not be 100, but depends on where the line intercepts.
						--y = mx+b, where y=0, so x = (0-b)/m
						select chart_slopes_and_intercepts.*
							,case when fcst2_y2 < 0 then (0 - intercept2)/slope2 else fcst2_x2 end adjusted_fcst2_x2
							,case when fcst7_y2 < 0 then (0 - intercept7)/slope7 else fcst7_x2 end adjusted_fcst7_x2
							,case when fcst30_y2 < 0 then (0 - intercept30)/slope30 else fcst30_x2 end adjusted_fcst30_x2
							,case when fcst2_y2 < 0 then 0 else fcst2_y2 end adjusted_fcst2_y2
							,case when fcst7_y2 < 0 then 0 else fcst7_y2 end adjusted_fcst7_y2
							,case when fcst30_y2 < 0 then 0 else fcst30_y2 end adjusted_fcst30_y2
						from
						(
							--Chart with slopes and intercepts.
							select chart_coordinates.*
								,(fcst2_y2 - fcst2_y1)/(fcst2_x2 - fcst2_x1) slope2
								,(fcst7_y2 - fcst7_y1)/(fcst7_x2 - fcst7_x1) slope7
								,(fcst30_y2 - fcst30_y1)/(fcst30_x2 - fcst30_x1) slope30
								--y = mx + b, so b = y - mx
								,fcst2_y1 - ((fcst2_y2 - fcst2_y1)/(fcst2_x2 - fcst2_x1)) * fcst2_x1 intercept2
								,fcst7_y1 - ((fcst7_y2 - fcst7_y1)/(fcst7_x2 - fcst7_x1)) * fcst7_x1 intercept7
								,fcst30_y1 - ((fcst30_y2 - fcst30_y1)/(fcst30_x2 - fcst30_x1)) * fcst30_x1 intercept30
							from
							(
								--Chart data with forecast coordinates.
								select chart_data.*
									--Forecast 2 coordinates:
									,29 * 5 / 3 fcst2_x1
									,used_2/greatest_value_mb*100 fcst2_y1
									,100  fcst2_x2
									,forecast_2/greatest_value_mb*100 fcst2_y2
									--Forecast 7 coordinates:
									,24 * 5 / 3 fcst7_x1
									,used_7/greatest_value_mb*100 fcst7_y1
									,100  fcst7_x2
									,forecast_7/greatest_value_mb*100 fcst7_y2
									--Forecast 30 coordinates:
									--There may not be 30 days of data, use the last available X coordinate.
									,round((31 - max(date_number_desc) over (partition by diskgroup, hosts)) * 5/3, 1) fcst30_x1
									,first_used_mb/greatest_value_mb*100 fcst30_y1
									,100  fcst30_x2
									,forecast_30/greatest_value_mb*100 fcst30_y2
								from
								(
									--Chart data
									select
										forecasts.*,
										--Largest possible value, others will be compared to it for the y-axis.
										greatest(nvl(last_total_mb, 0), nvl(last_used_mb, 0), nvl(forecast_2, 0), nvl(forecast_7, 0), nvl(forecast_30, 0)) greatest_value_mb,
										max(case when date_number_desc = 2 then used_mb else null end) over (partition by diskgroup, hosts) used_2,
										max(case when date_number_desc = 7 then used_mb else null end) over (partition by diskgroup, hosts) used_7
									from
									(
										--Forecast size for next month, based on ordinary least squares regression.
										select diskgroup, hosts, the_date, total_mb, used_mb, free_mb, date_number_asc, date_number_desc
											,last_value(total_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) last_total_mb
											,first_value(used_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) first_used_mb
											,last_value(used_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) last_used_mb
											,last_value(free_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) last_free_mb
											,last_value(used_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) /
											 last_value(total_mb) over (partition by diskgroup, hosts order by date_number_asc rows between unbounded preceding and unbounded following) * 100 last_percent_used
											,count(*) over (partition by diskgroup) number_of_days 
											--y = mx + b
											,regr_slope(used_mb, case when date_number_desc <= 2 then date_number_asc else null end) over (partition by diskgroup, hosts)
												* (max(date_number_asc) over (partition by diskgroup, hosts) + 30)
											 + regr_intercept(used_mb, case when date_number_desc <= 2 then date_number_asc else null end) over (partition by diskgroup, hosts)
											forecast_2
											,regr_slope(used_mb, case when date_number_desc <= 7 then date_number_asc else null end) over (partition by diskgroup, hosts)
												* (max(date_number_asc) over (partition by diskgroup, hosts) + 30)
											 + regr_intercept(used_mb, case when date_number_desc <= 7 then date_number_asc else null end) over (partition by diskgroup, hosts)
											forecast_7
											,regr_slope(used_mb, case when date_number_desc <= 30 then date_number_asc else null end) over (partition by diskgroup, hosts)
												* (max(date_number_asc) over (partition by diskgroup, hosts) + 30)
											 + regr_intercept(used_mb, case when date_number_desc <= 30 then date_number_asc else null end) over (partition by diskgroup, hosts)
											forecast_30
										from
										(
											--Convert dates to numbers
											select diskgroup, hosts, the_date, total_mb, used_mb, free_mb
												,the_date - min(the_date) over () + 1 date_number_asc
												,max(the_date) over () - the_date + 1 date_number_desc

											from
											(
												--Historical diskgroup sizes.
												select name diskgroup, hosts, the_date, total_mb, total_mb - free_mb used_mb, free_mb
												from v$asm_diskgroup_fcst
												join
												(
													--Databases and hosts.
													select
														lower(database_name) database_name,
														--Remove anything after a "." to keep the display name short.
														listagg(regexp_replace(host_name, '\..*'), chr(10)) within group (order by host_name) hosts
													from m5_database
													group by lower(database_name)
												) databases
													on v$asm_diskgroup_fcst.database_name = databases.database_name
												where total_mb <> 0
													and the_date > sysdate - 30
													--Exclude some diskgroups that constantly grow and shrink.
													and name not like '%TEMP%'
													and name not like '%FRADG%'
												order by diskgroup, hosts, the_date
											) historical_data
										) convert_dates_to_numbers
										order by diskgroup, hosts, the_date desc
									) forecasts
								) chart_data
							) chart_coordinates
						) chart_slopes_and_intercepts
					) adjusted_coordinates
				) chart_axes
				--Only display diskgroups with 14 or more days of data.
				where number_of_days >= 14
			) chart
			order by greatest(forecast_2, forecast_7, forecast_30) desc nulls last
		) user_friendly_values
		--Top N.
		where rownum <= 10
	) loop
		--Write line to email.
		utl_smtp.write_data(conn, diskgroups.html || chr(10));
	end loop;

	--Add footer.
	utl_smtp.write_data(conn, q'[</table></body></html>]');

	--Send the email.
	utl_smtp.close_data(conn);
	utl_smtp.quit(conn);
end;
/


--#3d: Create a daily job to email the forecast.
begin
	dbms_scheduler.create_job(
		job_name => 'EMAIL_ASM_FORECAST_JOB',
		job_type => 'PLSQL_BLOCK',
		start_date => systimestamp at time zone 'US/Eastern',
		enabled => true,
		--Make sure this is scheduled *after* the ASM gather step above.
		repeat_interval => 'freq=daily; byhour=2; byminute=10; bysecond=0',
		job_action => 'begin email_asm_forecast; end;');
end;
/


--#3d: Force the job to run once, for testeing.  Check your email.
begin
	dbms_scheduler.run_job('EMAIL_ASM_FORECAST_JOB');
end;
/


--#3e: Check the job status.
select * from dba_scheduler_job_run_details where job_name = 'EMAIL_ASM_FORECAST_JOB' order by log_date desc;
select * from dba_scheduler_jobs where job_name = 'EMAIL_ASM_FORECAST_JOB';
