Upgrade Method5
===============

Follow the below steps to upgrade your installation.  The steps are incremental.

8.0.2 --> 8.1.0
---------------

Run all these steps on the central management server.

1. Change M5_DATABASE and M5_DATABASE_HIST tables to support a new column:

	alter table method5.m5_database add (cluster_name varchar2(1024));
	alter table method5.m5_database add (refresh_date_temp date);
	update method5.m5_database set refresh_date_temp = refresh_date;
	alter table method5.m5_database drop column refresh_date;
	alter table method5.m5_database rename column refresh_date_temp to refresh_date;

	alter table method5.m5_database_hist add (cluster_name varchar2(1024));
	alter table method5.m5_database_hist add (refresh_date_temp date);
	update method5.m5_database_hist set refresh_date_temp = refresh_date;
	alter table method5.m5_database_hist drop column refresh_date;
	alter table method5.m5_database_hist rename column refresh_date_temp to refresh_date;

2. Find the DDL to generate the job that refreshes the M5_DATABASE table.

	select replace(dbms_metadata.get_ddl('PROCOBJ', 'REFRESH_M5_DATABASE', 'METHOD5'), '"REFRESH_M5_DATABASE"', 'METHOD5.REFRESH_M5_DATABASE') from dual;

3. SAVE the output from the above step for later but make one change to it - add the CLUSTER_NAME column logic.  See install_method5.md for an example.

4. Drop the old job.

	begin
		dbms_scheduler.drop_job('METHOD5.REFRESH_M5_DATABASE');
	end;
	/

5. Run the code saved in step #3.

6. Test job and check the new CLUSTER_NAME column.

	begin
		dbms_scheduler.run_job('METHOD5.REFRESH_M5_DATABASE');
	end;
	/

	select * from m5_database;

7. Change the database name query.  Look at your existing value in METHOD5.M5_CONFIG and also look at "5: Configure Database Name query." in install_method5.md for the new `CLUSTER_NAME` column.  Modify your query and then update the configuration table with a SQL like this:

	update method5.m5_config
	set string_value = q'[
		--ENTER NEW QUERY HERE
	]'
	where config_name = 'Database Name Query';
	commit;

8. Run "10: Configure Target Groups." in administer_method5.md.

9. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.
