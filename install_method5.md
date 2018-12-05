Install Method5
===============

Installing Method5 is a one-time, semi-automated process.  Pick one person to install and administer Method5.  That person should have intermediate DBA skills, and preferably some development experience.

Testing Method5 only requires a single database.  A multi-database environment can be simulated by inserting fake values in step 4, "Configure M5_DATABASE".

If you are using the multitenant architecture, Method5 has currently only been tested on pluggable databases, not container databases.

If you want help with the installation please send an email to Jon Heller, jon@jonheller.org.  Or you can submit an issue to the GitHub repository.


1: Check pre-requisites.
------------------------

Read and understand these requirements:

1. You must have a central management server that can connect to all databases.

2. You must have SYSDBA access to all databases to install and administer Method5, although most steps only require DBA.  Access requirements are labeled on each step.  If you are using the multitenant architecture, Method5 currently only runs on pluggable databases and not container databases.

3. You must have access to both SQL*Plus and an Integrated Development Environment, such as SQL Developer, Toad, PL/SQL Developer, etc.  SQL*Plus is great for running the installation scripts but you will almost certainly want to use a GUI for administration steps and running Method5.

4. Run this script on the central management server, in SQL*Plus, as SYS.  For example:

	C:\> cd Method5
	C:\Method5> sqlplus / as sysdba
	...
	SQL> @code/check_m5_prerequisites.sql
	SQL> quit


2: Install SYS components.
--------------------------

Run this script on the management server as SYS.  It's a small script, you can either copy and paste the statements or run it in SQL*Plus.  It should not generate any errors.  For example:

	C:\> cd Method5
	C:\Method5> sqlplus / as sysdba
	...
	SQL> @code/install_method5_sys_components.sql
	SQL> quit


3: Install Method5 objects.
---------------------------

Run this script on the management server as a user with the DBA role, in SQL*Plus.  This user will be the default Method5 administrator so you should use a personal account.  Ths script should not generate any errors.

	SQL> @code/install_method5_objects.sql
	SQL> quit


4: Configure M5_DATABASE.
-------------------------

Run this step on the management server as a user with the DBA role.

Manually add rows to the main configuration table, METHOD5.M5_DATABASE.  This table is critical to the configuration of the system, it is used for filtering databases and creating links.  Pay close attention to the details.

The host and database columns have size and value restrictions, since those names are both used to create a database link names.  If you have a host or database name that doesn't fit those rules, use an alias in those columns.  Later in the installation, in step #3 in administer_method5.md, you will be able to customize the connection string for the database links and use whatever names are necessary.

Four sample rows were inserted by default, use them to get started.  Don't worry about adding all your databases or getting it 100% perfect right away.  Come back to this step later after you've used Method5 for a while.


5: Configure default targets.
-----------------------------

Run this code on the management server as a user with the DBA role.

By default, Method5 runs against all targets.  This default can be changed from `%` to some other string like this:

	update method5.m5_config
	set string_value = 'DEV,TEST,PROD'  --Change this line
	where config_name = 'Default Targets';
	commit;


6: Set Method5 profile.
-----------------------

Run this optional code on the management server as a user with the DBA role.

You probably want to use a meaningful profile for Method5.  Whatever you select here will also be used in remote databases.

	alter user method5 profile &PROFILE_NAME ;


7: Run steps in administer_method5.md.
--------------------------------------

See the file administer_method5.md for details.


8: Install Method5 housekeeping jobs and global data dictionary.
----------------------------------------------------------------

Run these scripts on the management server as a user with the DBA role, in SQL*Plus.  They must NOT be run by SYS.  They should not generate any errors.

	SQL> @code/install_method5_housekeeping_jobs.sql
	SQL> @code/install_method5_global_data_dictionary.sql


9: Run integration tests to verify installation. (optional)
-----------------------------------------------------------

Run this code on the management server, as a user who has the DBA role and is a Method5 administrator.

Replace the "&" values with real values.  If possible, pick two databases that use a different version of Oracle - that will more thoroughly test all features.

	select method5.method5_test.get_run_script(
		p_database_name_1   => '&database1',
		p_database_name_2   => '&database2',
		p_other_schema_name => '&other_user_that_exists_in_both_dbs',
		p_test_run_as_sys   => '&sys_yes_or_no',
		p_test_shell_script => '&shell_yes_or_no',
		p_tns_alias         => '&tns_alias')
	from dual;

That command will output a SQL*Plus script to run to test several temporary users.  Run that script on a command line.  The output should display multiple "PASS" messages, but no "FAIL" messages.


11: Populate M5_DATABASE with OEM data. (optional)
--------------------------------------------------

If you use Oracle Enterprise Manager (OEM) and want to use it to populate the table M5_DATABASE see the file examples/Load OEM data into M5_DATABASE.sql.
