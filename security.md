Method5 Security
================

Method5 is a great tool for database security.  This file explains how it can be used to improve security, how the program itself is secured, and how to control the program privileges.



How Method5 improves security
-----------------------------

Method5 is a great tool to help comply with security policies.  It enables rapid scanning and configuration of a large number of databases.  It allows security jobs to be stored and managed in a single location instead of scattered across hundreds of databases and crontabs.

Many organizations have procedures to control the changes made to database but few of them have a system that can rapidly and periodically verify those changes.

Below is a list of security issues that can be trivially checked with Method5 on all databases:
  1. List all users granted DBA.  See /examples/Email Active DBA Users Job.sql for code to send a weekly email of all administrators.
  2. Check any other privilege using M5_DBA_*_PRIVS global data dictionary.
  3. Compare sqlnet.ora files.
  4. Compare cron jobs.
  5. Compare parameters in V$PARAMETER.
  6. Compare DBA_PROFILES.
  7. Disable users everywhere or verify that they are disabled.



How Method5 is secured
----------------------

It's important that Method5 itself does not create any security issues.  To keep your systems secure, Method5 includes the below features by default.  This list might be helpful if you need to demonstrate to an auditor why Method5 is safe.

  1. **No password sharing.**  Although Method5 creates a schema, the password for that schema is never displayed or known by anyone.
  2. **Password hash management.**  Method5 makes it easy to periodically change the password hashes and removes the insecure DES password hashes when possible.
  3. **Prevent direct logons.**  Authorized users can only connect through the Method5 application.  A schema trigger prevents the Method5 schema from directly connecting.  This means that even if somebody hacks into one of your databases, steals a password hash, and decrypts it, there's not much they can do with it.
  4. **Auditing.**  Auditing is performed on the management and target databases, through the database audit trail and the application.  You can always figure out who did what and when, with the table Method5.M5_AUDIT.
  5. **Multi-step authentication.**  Authentication requires an existing database account as well as the operating system username.
  6. **Intrusion detection.**  Un-authorized access attempts or changes to key configuration tables will send an email to an administrator.  Even in the worst-case scenario, where someone gains root access to your master database, they would likely generate an alert.
  7. **Shell script and SYS protection.**  Method5 has optional features to allow authorized users to run shell scripts and commands as SYS.  These features are well protected to ensure that attackers on remote databases cannot use them, even if they get DBA access.  Shell scripts and remote SYS commands are only allowed if they come from the master database.  Those commands must be encrypted using AES 256, using a secret key that is randomly generated for each database, and stored in the SYS.LINK$ table that not even the DBA role can read.  Those commands also include a session GUID to prevent re-running old commands.
  8. **Configuration table protection.** All important configuration tables are tracked and protected by SYS triggers that only let administrators change them.
  9. **Open Source.**  All code is available for inspection.  Method5 does not rely only on security through obscurity.



Configure Method5 to limit privileges for users and Method5 schema
------------------------------------------------------------------

With remote execution programs you have to think about four different types of privileges.  The table below lists the different types of privileges and a brief summary of the minimum possible privileges for each type:

                   Method5          User
           +-------------------+---------+
    Master | 1) High           | 3) Low  |
           +-----------------------------+
    Remote | 2) Medium to High | 4) None |
           +-------------------+---------+

Most users only need to worry about configuring #4 - user privileges on remote targets.



#1: Privileges for Method5 on the master database
-------------------------------------------------

It is strongly recommended that you not change the default privileges for Method5 on the master database.  Method5 requires a lot of elevated privileges to create, monitor, and run jobs.

The file code/install_method5_sys_components_pre.sql lists all required and optional privileges granted to the Method5 schema on the master database, and why they are granted.  Search for the word "optional" to find privileges that you could theoretically revoke.


#2: Privileges for Method5 on the remote databases
--------------------------------------------------

It is recommended that you not change the default privileges for Method5 on the remote databases.  Method5 is designed to run "anything" and it needs full privileges to do so.  If your organization cannot allow that there are two ways to limit these privileges.

First, you can choose to not install the run-as-sys and shell script features.  Add optional parameters when generating the remote install script, as described in the first section of administer_method5.md:

	select method5.method5_admin.generate_remote_install_script
		(
			p_allow_run_as_sys       => 'No',
			p_allow_run_shell_script => 'No'
		)
	from dual;

Second, if you want to limit privileges granted to Method5, look at the output generated by that statement.  It explains the required and optional privileges and why they are needed.  Changing the "OPTIONAL" sections can disable functionality.  For example, you can make Method5 read-only if you replace "grant dba" with "grant select any table" and "select catalog_role".

However, if you limit these privileges then the user sandbox feature will not work.  That is, you cannot configure both #2 (Method5 on remote) and #4 (user on remote).


#3: Privileges for users on the master database
-----------------------------------------------

There's nothing to configure here.  The privileges are tiny and can't be changed.

Method5 users must have an active database account on the master database.  That database account only needs a small amount of privileges: M5_RUN, CREATE DATABASE LINK, and quota on the default tablespace.

The role M5_RUN grants access to Method5 objects and a few privileges that only allow users to create objects on their own schema.  See code/install_method5_objects.sql for the full list of privileges.


#4: Privileges for users on the remote databases
------------------------------------------------

(This section covers the most important Method5 security configuration.)

Method5 gives you complete control over the access of each Method5 user.  You can limit their targets, features, and privileges through four simple tables: M5_USER, M5_ROLE, M5_ROLE_PRIV, and M5_USER_ROLE.

In short you have to make a choice for each user - let them run as the Method5 user with full privileges, or let them run as a temporary sandbox user with completely custom privileges.  For example, you may want to allow senior database administrators to run with full privileges on all targets, but give data analysts a read-only role on a subset of targets.

**METHOD5.M5_USER** is mostly used for authentication and authorization.
  * ORACLE_USERNAME: Individual Oracle account used to access Method5.  Do not use a shared account.
  * OS_USERNAME: Individual operating system account used to access Method5.  Depending on your system and network configuration enforcing this username may also ensure two factor authentication.  Do not use a shared account.
  * EMAIL_ADDRESS: Only necessary for administrators so they can be notified when configuration tables are changed.
  * IS_M5_ADMIN: Can this user change Method5 configuration tables.  This user will also receive emails about configuration problems and changes.  Either Yes or No.
  * DEFAULT_TARGETS: Use this target list if none is specified.  Leave NULL to use the global default set in M5_CONFIG.
  * CAN_USE_SQL_FOR_TARGETS: Can use a SELECT SQL statement for choosing targets.  Target SELECT statements are run as Method5 so only grant this to trusted users.  Either Yes or No.
  * CAN_DROP_TAB_IN_OTHER_SCHEMA: Can set P_TABLE_NAME to be in a different schema.  That may sound innocent but it also implies the user can drop or delete data from other schemas on the management database.  Only give this to users you trust on the management database.  Either Yes or No.

**METHOD5.M5_ROLE** allows complete control over the targets and features available to each user.  The column comments explain how to use each setting:
  * ROLE_NAME: Name of the role.
  * TARGET_STRING: String that describes available targets.  Works the same way as the parameter P_TARGETS.  Use % to mean everything.
  * CAN_RUN_AS_SYS: Can run commands as SYS.  Either Yes or No.
  * CAN_RUN_SHELL_SCRIPT: Can run shell scripts on the host.  Either Yes or No.
  * INSTALL_LINKS_IN_SCHEMA: Are private links installed in the user schemas.  Either Yes or NO.
  * RUN_AS_M5_OR_SANDBOX: Run as the user Method5 (with all privileges) or as a temporary sandbox users with precisely controlled privileges.  Either M5 or SANDBOX.
  * SANDBOX_DEFAULT_TS: The permanent tablespace for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the tablespace is not found the default permanent tablespace is used.
  * SANDBOX_TEMPORARY_TS: The temporary tablespace for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the tablespace is not found the default temporary tablespace is used.
  * SANDBOX_QUOTA: The quota on the permanent tablespace for the sanbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  This string can be a SIZE_CLAUSE.  For example, the values can be 10G, 9999999, 5M, etc.  If NULL then UNLIMITED will be used.
  * SANDBOX_PROFILE: The profile used for the sandbox user.  Only used if RUN_AS_M5_OR_SANDBOX is set to SANDBOX.  If NULL or the profile is not found the DEFAULT profile is used.

**METHOD5.M5_USER_ROLE** grants a M5_ROLE to an M5_USER.
  * ORACLE_USERNAME: Oracle username from METHOD5.M5_USER.ORACLE_USERNAME.
  * ROLE_NAME: Role name from METHOD5.ROLE.ROLE_NAME.

**METHOD5.M5_ROLE_PRIV** grants privileges to an M5_ROLE.
  * ROLE_NAME: Role name from METHOD5.ROLE.ROLE_NAME.
  * PRIVILEGE: An Oracle system privilege, object privilege, or role.  This string will be placed in the middle of:  grant <privilege> to m5_temp_sandbox_XYZ;  For example: select_catalog_role, select any table, delete any table.

After configuring the users you can view them with these queries:

	select * from method5.m5_priv_vw;
	select * from method5.m5_user;
	select * from method5.m5_role;
	select * from method5.m5_role_priv;
	select * from method5.m5_user_role;

For example, let's say you have a Junior DBA that has full access to development but is read-only on production.  First, create a role for full access to development.  It can run as SYS, shell scripts, has links, and normally uses the M5 account.

	insert into method5.m5_role(ROLE_NAME, TARGET_STRING, CAN_RUN_AS_SYS, CAN_RUN_SHELL_SCRIPT, INSTALL_LINKS_IN_SCHEMA, RUN_AS_M5_OR_SANDBOX)
	values ('Dev Full Access', 'development', 'Yes', 'Yes', 'Yes', 'M5');

Then create create a role for read-only access in production.  Set most flags to No, and set the user to SANDBOX.

	insert into method5.m5_role(ROLE_NAME, TARGET_STRING, CAN_RUN_AS_SYS, CAN_RUN_SHELL_SCRIPT, INSTALL_LINKS_IN_SCHEMA, RUN_AS_M5_OR_SANDBOX)
	values ('Prod Read Only', 'production', 'No', 'No', 'No', 'SANDBOX');

The new sandbox role initially has no privileges and can't do anything.  Give it some read-only access:

	insert into method5.m5_role_priv(ROLE_NAME, PRIVILEGE)
	values ('Prod Read Only', 'SELECT ANY TABLE');
	insert into method5.m5_role_priv(ROLE_NAME, PRIVILEGE)
	values ('Prod Read Only', 'SELECT CATALOG_ROLE');

Now associate both the development and the production role with any relevant users:

	insert into method5.m5_user_role(ORACLE_USERNAME, ROLE_NAME)
	values ('NEW_DBA1', 'Dev Full Access');

	insert into method5.m5_user_role(ORACLE_USERNAME, ROLE_NAME)
	values ('NEW_DBA1', 'Prod Read Only');
