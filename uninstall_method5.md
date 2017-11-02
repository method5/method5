Uninstall Method5
=================

These steps will permanently remove *ALL* Method5 data, configuration, and objects from the management server and any remote targets.  However it will not remove any user-generated data that was given a custom name.

First, let's make sure that nobody accidentally runs this as a script:
	exit;
	exit;

Finally, when you're done uninstall, I'd like to know what went wrong and what we can do to improve things for others.  I'd appreciate it if you could create a GitHub issue or send me an email ad hjon@ventechsolutions.com.


Remove from Management Server
-----------------------------

Run these steps as a DBA on the management server.

Stop current jobs:

	begin
		method5.m5_pkg.stop_jobs;
	end;
	/

Kill any remaining Method5 user sessions:

	begin
		for sessions in
		(
			select 'alter system kill session '''||sid||','||serial#||''' immediate' kill_sql
			from gv$session
			where schemaname = 'METHOD5'
		) loop
			execute immediate sessions.kill_sql;
		end loop;
	end;
	/

Remove all user links:

	begin
		for users in
		(
			select distinct owner
			from dba_db_links
			where db_link like 'M5_%'
				and owner <> 'METHOD5'
			order by owner
		) loop
			method5.method5_admin.drop_m5_db_links_for_user(users.owner);
		end loop;
	end;
	/

Drop the ACL used for sending emails:

	begin
		dbms_network_acl_admin.drop_acl(acl => 'method5_email_access.xml');
	end;
	/

Drop the user.  THERE'S NO TURNING BACK FROM THIS!  To make sure you really want to do this, the step is commented out.  Remove the comments before running.

	--drop user method5 cascade;


Drop a global context used for Method4:

	drop context method4_context;

Drop public synonyms:

	begin
		for synonyms in
		(
			select 'drop public synonym '||synonym_name v_sql
			from dba_synonyms
			where table_owner = 'METHOD5'
			order by 1
		) loop
			execute immediate synonyms.v_sql;
		end loop;
	end;
	/

Drop temporary tables that hold Method5 data retrieved from targets:

	begin
		for tables in
		(
			select 'drop table '||owner||'.'||table_name||' purge' v_sql
			from dba_tables
			where table_name like 'M5_TEMP%'
			order by 1
		) loop
			execute immediate tables.v_sql;
		end loop;
	end;
	/

If you are only uninstalling to re-install, make sure you completely log out of all sessions before installing anything.


Remove from Remote Targets
--------------------------

Login to each remote target as SYS and run the below command.  THERE'S NO TURNING BACK FROM THIS!  To make sure you really want to do this, the step is commented out.  Remove the comments before running.

	--drop user method5 cascade;
	--drop table sys.m5_sys_session_guid;
	--drop package sys.m5_runner;
	--drop procedure sys.m5_run_shell_script;
