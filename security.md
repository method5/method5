Method5 Security
================

Method5 is a great tool to help comply with security policies.  It enables rapid scanning and configuration on a large number of databases.  It allows security jobs to be stored and managed in a single location instead of scattered across hundreds of databases and crontabs.

You want to ensure that Method5 itself does not create any security issues.  To keep your systems secure, Method5 includes the following features:

1. **No password sharing.**  Although Method5 creates a schema, the password for that schema is never displayed or known by anyone.
2. **Password hash management.**  Method5 makes it easy to periodically change the password hashes and removes the insecure DES password hashes when possible.
3. **Prevent direct logons.**  Authorized users can only connect through the Method5 application.  A trigger prevents the Method5 schema from directly connecting.  This means that even if somebody hacks into one of your databases, steals a password hash, and decrypts it, there's not much they can do with it.
4. **Auditing.**  Auditing is performed on the management and target databases, through the database audit trail and the application.  You can always figure out who did what, when.
5. **Multi-step authentication.**  Authentication requires an existing database account, as well as the proper role, profile, account name, account status, and operating system username.
6. **Intrusion detection.**  Un-authorized access attempts will send an email to an administrator.  Even in the worst-case scenario, where someone gains root access to your central management host, they would likely generate an alert.
7. **Open Source.**  All code is available for inspection.  Method5 does not rely on security through obscurity.
