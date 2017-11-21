Method5 Security
================

Method5 is a great tool for database security.  This file explains how it can be used to improve security, how the program itself is secured, and how the program privileges can be controlled.



##How Method5 improves security

Method5 is a great tool to help comply with security policies.  It enables rapid scanning and configuration of a large number of databases.  It allows security jobs to be stored and managed in a single location instead of scattered across hundreds of databases and crontabs.

Many organizations have procedures to control the changes made to database but few of them have a system that can rapidly and periodically verify those changes.

Below is a list of security issues that can be trivially checked with Method5 on all databases:
1. List all users granted DBA.  See /scripts/Email Active DBA Users Job.sql for code to send a weekly email of all administrators.
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
8. **Open Source.**  All code is available for inspection.  Method5 does not rely on security through obscurity.



##Configure Method5 to limit privileges for users, remote Method5 schema, and management Method5 schema.

There are three ways to control Method5 privileges:
1. Limit features, databases, and privileges available for each user.  For example, this can be useful if you have a junior DBA or a data analyst that should only have read-only access.
2. Limit installed features and privileges granted to Method5 on remote databases.  For example, this can be useful if you want to limit all Method5 users to read-only access.
3. Limit installed features and privileges granted to Method5 on the management database.  This is similar to the above limits on remote databases, but Method5 does require slightly more privileges on the management database.


**Limit features, databases, and privileges available for each user.**

TODO

**Limit installed features and privileges granted to Method5 on remote databases.**

Remote database default Method5 schema privileges and why they are granted:

1. DBA - Because Method5 is primarily intended for database administrators.
2. QUOTA UNLIMITED on default tablespace - Because Method5 needs space to write intermediate results.  In practice it won't use that much space on the remote nodes, since those intermediate results are quickly cleaned up.

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

1. DBA - Because Method5 is primarily intended for database administrators.
2. QUOTA UNLIMITED on default tablespace - Because Method5 needs space to write intermediate results.  In practice it won't use that much space on the remote nodes, since those intermediate results are quickly cleaned up.

Management database minimum Method5 schema privileges and why they are granted:

**TODO** Currently the minimum and the default are the same.  This will be changed in a future release.

