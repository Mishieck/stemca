# Contributing to Abbreviations

## Database

The database is made up of tables of abbreviations. Each table is created by a
contributor. A table is a CSV file. Contributions are progressive. Each
contributor manages their own table. This means that a contributor can update
their table at any time.

To add a table, create a file in [./database/tables/](./database/tables/).
Use your github username for the filename. Your username is case-insensitive.
So, `Mishieck` is the same as `mishieck`. The table has the following columns:

1. Abbreviation: An abbreviation.
2. Expansion: The expansion for the abbreviation.
3. Category: A category of the abbreviation. Categories are limited to
   - `Common`: An abbreviation for everyday conversation.
   - `STEM`: An abbreviation for topics in Science, Technology, Engineering,
      and Mathematics.

An abbreviation with more than one expansion should have separate entries for
each expansion.

You are not allowed to add an entry that someone else has already added. That
is, an entry with the same abbreviation and expansion as someone else's entry.
If your entry has a different expansion from someone else's, you can add it to
your table. To check whether an entry exists or not, run
`stemca lookup <abbreviation>`, where`<abbreviation>` is the abbreviation you
are looking up.

You can verify that your contribution is valid by running the command
`stemca verify` in the root directory of the forked repo. If there is anything
wrong with your contribution, you will be notified.

## Branches

You can contribute to the main branch directly or you can create a new branch.

