Upgrade Method5
===============

Follow the below steps to upgrade your installation.  The steps are incremental.


8.3.0 --> 8.4.0: Add version star.
----------------------------------

1. Run these files to install new packages: /code/m5_pkg.pck, /code/tests/method5_test.pck.


8.2.0 --> 8.3.0: Improve admin email, simplify installation.
------------------------------------------------------------

1. Run these commands as-is:

	--Add new columns.
	alter table method5.m5_database add (connect_string varchar2(4000));
	alter table method5.m5_database add (refresh_date_temp date);
	update method5.m5_database set refresh_date_temp = refresh_date;
	alter table method5.m5_database drop column refresh_date;
	alter table method5.m5_database rename column refresh_date_temp to refresh_date;

	alter table method5.m5_database_hist add (connect_string varchar2(4000));
	alter table method5.m5_database_hist add (refresh_date_temp date);
	update method5.m5_database_hist set refresh_date_temp = refresh_date;
	alter table method5.m5_database_hist drop column refresh_date;
	alter table method5.m5_database_hist rename column refresh_date_temp to refresh_date;

	--Add new constraints.
	alter table method5.m5_database modify database_name not null;
	alter table method5.m5_database modify connect_string not null;
	alter table method5.m5_database add constraint m5_database_ck_numbers_only check (regexp_like(target_version, '^[0-9\.]*$'))

	--Add new comments to explain configuration table.
	comment on table method5.m5_database                   is 'This table is used for selecting the target databases and creating database links.  The columns are similar to the Oracle Enterprise Manager tables SYSMAN.MGMT$DB_DBNINSTANCEINFO and SYSMAN.EM_GLOBAL_TARGET_PROPERTIES.  It is OK if this table contains some "extra" databases - they can be filtered out later.  To keep the filtering logical, try to keep the column values distinct.  For example, do not use "PROD" for both a LIFECYCLE_STATUS and a HOST_NAME.';
	comment on column method5.m5_database.target_guid      is 'This GUID may be useful for matching to the Oracle Enterprise Manager GUID.';
	comment on column method5.m5_database.host_name        is 'The name of the machine the database instance runs on.';
	comment on column method5.m5_database.database_name    is 'A short string to identify a database.  This name will be used for database links, temporary objects, and the "DATABASE_NAME" column in the results and error tables.';
	comment on column method5.m5_database.instance_name    is 'A short string to uniquely identify a database instance.  For standalone databases this will probably be the same as the DATABASE_NAME.  For a Real Application Cluster (RAC) database this will probably be DATABASE_NAME plus a number at the end.';
	comment on column method5.m5_database.lifecycle_status is 'A value like "DEV" or "PROD".  (Your organization may refer to this as the "environment" or "tier".)';
	comment on column method5.m5_database.line_of_business is 'A value to identify a database by business unit, contract, company, etc.';
	comment on column method5.m5_database.target_version   is 'A value like "11.2.0.4.0" or "12.1.0.2.0".  This value may be used to select the lowest or highest version so only use numbers.';
	comment on column method5.m5_database.operating_system is 'A value like "SunOS" or "Windows".';
	comment on column method5.m5_database.user_comment     is 'Any additional comments.';
	comment on column method5.m5_database.cluster_name     is 'The Real Application Cluster (RAC) name for the cluster.';
	comment on column method5.m5_database.connect_string   is 'Used to create the database link.  You may want to use an existing TNSNAMES.ORA file as a guide for how to populate this column (for each entry, use the text after the first equal sign).  You may want to remove spaces and newlines, it is easier to compare the strings without them.  It is OK if not all CONNECT_STRING values are 100% perfect, problems can be manually adjusted later if necessary.';
	comment on column method5.m5_database.refresh_date     is 'The date this row was last refreshed.';

2. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.

3. Save this result for later: 

	select job_action from dba_scheduler_jobs where job_name = 'REFRESH_M5_DATABASE_JOB';

4. Delete the old job and data:

	delete from method5.m5_config where config_name = 'Database Name Query';

	begin
		dbms_scheduler.drop_job('method5.refresh_m5_database');
	end;
	/

5. Recreate the job REFRESH_M5_DATABASE_JOB based on the string from step 3 above, and the hints from step 10 of install_method5.md.new based on install document.

6. Drop this table if you're not using it.  If you are using it, use a different LIFECYCLE_STATUS instead of this table.

	drop table method5.m5_database_not_queried;


8.1.0 --> 8.2.0: Performance improvement.
-----------------------------------------

1. Run the INSERT statement for "Job Timeout (seconds)" and create the table M5_JOB_TIMEOUT, from install_method5_objects.sql.

2. Run the section "Create JOB to stop timed out jobs." in install_method5_housekeeping_jobs.sql.

3. Re-create the procedure "SYS.GET_METHOD5_HASHES" from install_method5_sys_components.sql.

4. Run these files to install new packages: /code/m5_pkg.pck, /code/method5_admin.pck.


8.0.2 --> 8.1.0: Added Target Groups and CLUSTER_NAME.
------------------------------------------------------

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

