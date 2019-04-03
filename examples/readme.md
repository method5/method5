Method5 Examples
================

Unlike other automation programs, you generally don't need pre-built "recipes" or "playbooks" to use Method5.  Good DBAs already have loads of useful SQL and PL/SQL statements, it's usually trivial to use them in Method5.

But it can still be useful to see some simple examples of common tasks.

And the advanced examples show the full power of Method5.  When the data gathering becomes trivial then advanced analytics become much easier.

**Advanced Examples**

1. [Snare - Configuration Comparison.sql](#snare)
2. [Compare Everything Everywhere.sql](#compare_everything_everywhere)
3. [ASM Forecast.sql](#asm_forecast)
4. [Active Sessions.sql](#active_session_counts)
5. [Compare Parameters.sql](#compare_parameters)
6. [Space Treemap.sql](#space_treemap)
7. [Synchronize DBA Users Job.sql](#synchronize_dba_users_job)

**Simple Examples**

1. [Account Maintenance.sql](#account_maintenance)
2. [Email Active DBA Users Job.sql](#email_active_dba_users_job)
3. [Global Database Statistics.sql](#global_database_statistics)
4. [Load OEM data into M5_DATABASE.sql](#load_oem_data_into_m5_database)

---

<a name="snare"/>

## Snare

Snare lets you quickly gather and compare Oracle database configuration information over time.  

The default configuration contains information about components, crontab, invalid objects, last patch time, miscellaneous database settings, M5_DATABASE, and V$PARAMETER.  For example, if someone modifies a system parameter Snare will let you easily find out when it was changed.

By default the job is installed but disabled.  See the first section of the SQL file for simple instructions to enable the jobs.

Below are examples of how to call Snare.  These simple queries are enough to replace expensive enterprise solutions.

	--Compare configuration snapshots and display a summary.
	select snare.compare_summary(
		p_snapshot_before => 'EVERYTHING_20180710',
		p_snapshot_after  => 'EVERYTHING_20180712'
	)
	from dual;

	--Compare configuration snapshots and display details.
	select * from table(snare.compare_details(
		p_snapshot_before => 'EVERYTHING_20180710',
		p_snapshot_after  => 'EVERYTHING_20180712'
	));


<a name="compare_everything_everywhere"/>

## Compare Everything Everywhere

With a few clicks you can compare schemas between an *unlimited* number of databases, and see all the results in a single view.  This is an easy way to check if a large number of environments are synchronized.

The screenshot shows the output exported to a spreadsheet.  The dense output may look cryptic at first but eventually it will allow you to rapidly identify schema differences.  The letters refer to different versions of the same object.  The columns on the right-hand side contain the entire DDL if you click on the cell.

<img src="images/example_compare_everything_everywhere.png">


<a name="asm_forecast"/>

## ASM Forecast

Storage alerts should be based on forecasts, not simple thresholds.  Some databases are designed to be at 99.9% capacity.  Others are in trouble if the capacity quickly reaches 50%.

Now that collecting all the V$ASM_DISKGROUP data is trivial you can focus on more intelligent forecasts.  This script uses ordinary-least-squares regression to predict the capacity in 30 days based on three different forecasts, using data from 2, 7, and 30 days in the past.

This first chart shows a clear problem.  The diskgroup is only 50% full but it only took 15 days for all that growth.

<img src="images/example_asm_forecast_growing_quickly.png">

This second chart shows a database at 99.9% capacity.  But don't freak out - it hasn't grown at all in the past 30 days so you probably don't need to add space.

<img src="images/example_asm_forecast_not_growing.png">


<a name="active_session_counts"/>

## Active Sessions

Why tune one database when you can tune them all at the same time?  If you've built a query against a view like GV$ACTIVE_SESSION_HISTORY you can easily run it against hundreds of databases.

This chart was created to solve the most painful performance problem - when connections "randomly" fail.  Is there a pattern?

When I aggregated session counts for 400 databases, for 60 hosts, it became obvious that activity spiked at the hour mark.  Drilling down it was clear the spikes were caused by AWR starting at the same time, and needed to be staggered.

<img src="images/example_active_sessions.png">


<a name="compare_parameters"/>

## Compare Parameters

This report makes it trivial to compare all database parameters, for any set of databases, at one time.

<img src="images/example_compare_parameters.png">


<a name="space_treemap"/>

## Space Treemap

These treemap visualizations help you discover exactly where your space is being used.

<img src="images/example_space_treemap.png">


<a name="synchronize_dba_users_job"/>

## Synchronize DBA Users Job

Automatically synchronize DBA accounts, privileges, profiles, status, and profiles across all databases.

<a name="account_maintenance"/>

## Account Maintenance

Activities like creating accounts, locking accounts, and synchronizing passwords across all databases can be done in one line of code.


<a name="email_active_dba_users_job"/>

## Email Active DBA Users Job

Once it's trivial to gather data you can spend more time looking at potential access issues, such as a list of users with the DBA role.  No need to manage hundreds of crontabs or scheduler jobs.


<a name="global_database_statistics"/>

## Global Database Statistics

Convey the complexity of your environment through a few simple statistics, such as database count, schema count, object count, physical I/O per day, connections per day, queries per day, and segment size.


<a name="load_oem_data_into_m5_database"/>

## Load OEM data into M5_DATABASE

Populate the main configuration table M5_DATABASE with data from Oracle Enterprise Manager (OEM).
