Method5 Security
================

Method5 is a great tool for database security.  This file explains how it can be used to improve security, how the program itself is secured, and how the program privileges can be controlled.



##How Method5 improves security

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



##How Method5 is secured

It's important that Method5 itself does not create any security issues.  To keep your systems secure, Method5 includes the below features by default.  This list might be helpful if you need to demonstrate to an auditor why Method5 is safe.

1. **No password sharing.**  Although Method5 creates a schema, the password for that schema is never displayed or known by anyone.
2. **Password hash management.**  Method5 makes it easy to periodically change the password hashes and removes the insecure DES password hashes when possible.
3. **Prevent direct logons.**  Authorized users can only connect through the Method5 application.  A trigger prevents the Method5 schema from directly connecting.  This means that even if somebody hacks into one of your databases, steals a password hash, and decrypts it, there's not much they can do with it.
4. **Auditing.**  Auditing is performed on the management and target databases, through the database audit trail and the application.  You can always figure out who did what and when, with the table Method5.M5_AUDIT.
5. **Multi-step authentication.**  Authentication requires an existing database account, as well as the proper role, profile, account name, account status, and operating system username.
6. **Intrusion detection.**  Un-authorized access attempts will send an email to an administrator.  Even in the worst-case scenario, where someone gains root access to your central management host, they would likely generate an alert.
7. **SYS protection.**  Method5 has an optional feature to allow authorized users to run remote commands as SYS.  This feature is well protected to ensure that attackers on remote databases cannot use it, even if they get DBA access.  Remote SYS commands are only allowed if they come from the master database.  Those commands must be encrypted using AES 256, using a secret key that is randomly generated for each database, and stored in the SYS.LINK$ table that not even the DBA role can read.  Those commands also include a session GUID to prevent re-running old commands.
8. **Open Source.**  All code is available for inspection.  Method5 does not rely only on security through obscurity.



##Configure Method5 to limit privileges for users, remote Method5 schema, and management Method5 schema.

There are three ways to control Method5 privileges:
1. Limit targets, features, and privileges available for each user.  Temporary sandbox users can be created to precisely limit the privileges available to Method5 users.  For example, this can be useful if you have a junior DBA or a data analyst that should only have read-only access.
2. Limit installed features and privileges granted to Method5 on remote databases.  For example, this can be useful if you want to limit all Method5 users to read-only access.
3. Limit installed features and privileges granted to Method5 on the management database.  This is similar to the above limits on remote databases, but Method5 does require slightly more privileges on the management database.

Options #2 and #3 can be tricky to configure and are not recommended.


**1. Limit targets, features, and privileges available for each user.**

The table METHOD5.M5_ROLE allows complete control over the targets and features available to each user.  The column comments explain how to use each setting:

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

By default Method5 will run commands as the privileged Method5 user.  That works well for DBAs who are allowed full access.  To create a less-privileged user, set RUN_AS_M5_OR_SANDBOX to "SANDBOX" and add relevant rows to the table M5_ROLE_PRIV.

For example, let's say you have a Junior DBA that has full access to development but is read-only on production.  First, create a role for full access to development.  It can run as SYS, shell scripts, has links, and normally uses the M5 account.

	insert into method5.m5_role(ROLE_NAME, TARGET_STRING, CAN_RUN_AS_SYS, CAN_RUN_SHELL_SCRIPT, INSTALL_LINKS_IN_SCHEMA, RUN_AS_M5_OR_SANDBOX)
	values ('Dev Full Access', 'development', 'Yes', 'Yes', 'Yes', 'M5');

Then create create a role for read-only access in production.  Set most flags to No, and set the user to SANDBOX.

	insert into method5.m5_role(ROLE_NAME, TARGET_STRING, CAN_RUN_AS_SYS, CAN_RUN_SHELL_SCRIPT, INSTALL_LINKS_IN_SCHEMA, RUN_AS_M5_OR_SANDBOX)
	values ('Prod Read Only', 'production', 'No', 'No', 'No', 'SANDBOX');

The new sandbox role initially has no privileges and can't do anything.  Grant it "SELECT ANY TABLE":

	insert into method5.m5_role_priv(ROLE_NAME, PRIVILEGE)
	values ('Prod Read Only', 'SELECT ANY TABLE');

Now associate both the development and the production role with any relevant users:

	insert into method5.m5_user_role(ORACLE_USERNAME, ROLE_NAME)
	values ('NEW_DBA1', 'Dev Full Access');

	insert into method5.m5_user_role(ORACLE_USERNAME, ROLE_NAME)
	values ('NEW_DBA1', 'Prod Read Only');


**2. Limit installed features and privileges granted to Method5 on remote databases.**

--TODO

Remote database default Method5 schema privileges and why they are granted:

1. DBA - Because Method5 is primarily intended for database administrators.
2. QUOTA UNLIMITED on default tablespace - Because Method5 needs space to write intermediate results.  In practice it won't use that much space on the remote nodes, since those intermediate results are quickly cleaned up.
3. SELECT ON SYS.USER$ - Access to this table enables password synchronization.

Remote database minimum Method5 schema privileges and why they are granted:

1. CREATE SESSION - Method5 needs to logon.
2. CREATE/DROP TABLE - Method5 must create tables in its own schema to hold results and remove those tables when done.
3. CREATE/DROP PROCEDURE - Method5 must create functions in its own schema to generate results and remove those functions when done.
4. EXECUTE ON DBMS_SQL - Method5 must be able to retrieve column metadata in order to know what kind of table to create to hold the results.
5. Quota on some tablespace - Method5 needs at least a little bit of space to store the intermediate results.

How to change remote database privilege configuration:

1. `administer_method5.md` includes a script to install Method5 on remote databases.  It also contains information about how to customize the remote database privileges.

**Limit installed features and privileges granted to Method5 on the management database.**

Management database privilege configuration:

1. Currently it is not possible to change the privilege configuration of the management database.  This will be changed in a future version.  **TODO**

Management database default Method5 schema privileges and why they are granted:

1. DBA - Because Method5 is primarily intended for database administrators.  (TODO: This will be changed soon.)
2. QUOTA UNLIMITED on default tablespace - Because Method5 needs space to write intermediate results.  In practice it won't use that much space on the remote nodes, since those intermediate results are quickly cleaned up.

Management database minimum Method5 user privileges and why they are granted:

1. The minimum privileges to call Method5 on the management database are very minor.  See the steps to populate the role role_m5_user in install_method5_objects.sql for details.  However it is up to the M5_USER configuration to limit what those users can run through Method5.
