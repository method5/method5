Method5 v8.0.1
===============

Method5 is an Oracle database automation program that lets administrators easily run SQL statements quickly and securely on hundreds of databases.


Examples
--------

Run a query on all databases:

    SQL> select * from table(m5(q'[ select 'Hello, World!' hello_world from dual ]'));

    DATABASE_NAME  HELLO_WORLD
    -------------  -------------
    DB1            Hello, World!
    DB2            Hello, World!
    DB3            Hello, World!
    ...    

Lock a user on all QA databases:

    SQL> select * from table(m5('alter user rage_quiter account lock', 'QA'));

    DATABASE_NAME  RESULT
    -------------  -------------
    QA01           User altered.
    ...

For a more advanced example, run a PL/SQL block on DEV, QA, and one more databases.  To run this inside a program: 1) call Method5 as a procedure, `M5_PROC`, 2) store the results in a specific table, with`P_TABLE_NAME`, 3) drop and re-create that table if it already exists, with `P_TABLE_EXISTS_ACTION`, and 4) wait for all results are done before returning, with `P_ASYNCHRONOUS`.

    begin
        m5_proc(
            p_code                => q'[ begin dbms_output.put_line('PL/SQL Hello World'); end; ]',
            p_targets             => 'dev,qa,db1',
            p_table_name          => 'hello_world_results',
            p_table_exists_action => 'drop',
            p_asynchronous        => false
        );
    end;
    /

    SQL> select * from hello_world_results order by 1;

    DATABASE_NAME  RESULT
    -------------  --------------------
    DEVDB01        PL/SQL Hello World
    ...

You can run any SQL or PL/SQL statement inside `select * from table(m5(q'[ ... ]'));` or `m5_proc`.

See `user_guide.md` for an explanation of all the features, such as where the data and metadata and errors are stored, how to specify the targets, and different ways to gather and store results.


Advantages
----------

Method5 has many advantages over other tools and processes used to query multiple databases:

1.  **Performance**:  Asynchronous processing and parallelism make Method5 more responsive and orders of magnitude faster than other tools.
2.  **Simple interface**:  The PL/SQL API makes it easy to create and automate tasks.  No need to learn a new GUI or IDE, Method5 seamlessly integrates with your existing IDE.
3.  **Relational storage**: Everything about the database is stored in the database, making it easier to analyze, save, and share.
4.  **Easy administration**:  Method5 is agentless.  Free software (LGPL) only needs to be installed on one central management server.  Individuals do not need to install custom software, manage connections, or modify configuration files.  One administrator can configure Method5 and that configuration automatically applies to all users.
5.  **Security**:  Method5 has been thoroughly hardened to avoid the typical security problems with multi-database tools.  For example, there are no public database links or shared passwords.  See Security.md for more information.
6.  **Exception handling and metadata**:  Exceptions and metadata are stored in tables.  When connecting to hundreds of databases there will usually be a few that are unavailable.  It's important to record the errors but not stop processing on other databases.

There are no more excuses to avoid root cause analysis and massive environment comparisons.  Any diagnostic query or statement you can think of can be run against hundreds of databases in just a few seconds.


Scripts
-------

Pre-built scripts can help with common problems.

*TODO*


How to Install and Administer
-----------------------------

See `install_method5.md` and `administer_method5.md` for details.  Also see `security.md` for an explanation of the security features.


License
--------

Method5 is licensed under the LGPLv3.
