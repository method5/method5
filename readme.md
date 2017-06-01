Method5 v8.6.0
==============

Method5 extends Oracle SQL to allow parallel remote execution.  It lets database administrators easily run SQL statements quickly and securely on hundreds of databases.


Examples
--------

    SQL> select * from table(m5('select * from dual'));
    
    DATABASE_NAME  DUMMY
    -------------  -----
    db01           X
    db02           X
    db03           X
    ...

You can run any SQL or PL/SQL statement inside the `M5` function.  The function works with any SQL client and runs on any currently-supported platform, version, or edition of Oracle.

See [the Method5 User Guide](user_guide.md) for an explanation of all the features, such as: parameters that control the targets and how the statements are run; where the data, metadata, and errors are stored; running as a procedure; and many more features.

See [the scripts folder](scripts/) for more examples and pre-built solutions to some complex problems.


Advantages
----------

Method5 has many advantages over other tools and processes used to query multiple databases:

1.  **Performance**:  Asynchronous processing and parallelism make Method5 more responsive and orders of magnitude faster than other tools.
2.  **Simple interface**:  The PL/SQL API makes it easy to create and automate tasks.  No need to learn a new GUI or IDE, Method5 seamlessly integrates with your existing IDE.
3.  **Relational storage**: Everything about the database is stored in the database, making it easier to analyze, save, and share.
4.  **Easy administration**:  Method5 is agentless.  Free software (LGPL) only needs to be installed on one central management server.  Users do not need to install custom software, manage connections, or modify configuration files.  One administrator can configure Method5 and that configuration automatically applies to all users.
5.  **Security**:  Method5 has been thoroughly hardened to avoid the typical security problems with multi-database tools.  For example, there are no public database links or shared passwords.  See the Security section in `user_guide.md` for more information.
6.  **Exception handling and metadata**:  Exceptions and metadata are stored in tables.  When connecting to hundreds of databases there will usually be a few that are unavailable.  It's important to record the errors but not stop processing on other databases.

There are no more excuses to avoid root cause analysis and massive environment comparisons.  Any diagnostic query or statement you can think of can be run against hundreds of databases in just a few seconds.


How to Install and Administer
-----------------------------

On the GitHub repository click on the "Clone or download" button.  Download and extract the zip file.  Then follow the steps in `install_method5.md` and `administer_method5.md`.


License
-------

Method5 is licensed under the LGPLv3.
