# Contributing to Abbreviations

## Database

The database for abbreviations is based on attribution. Every abbreviation
added has a contributor. Each contributor can contribute more than one
entry. Contributions are progressive. Each contributor manages their own
entries. This means that a contributor can update their entries any time.

To add abbreviations, create a file in [./database/contributions/](./database/contributions/).
Use your github username for the filename. The file is a CSV file with the
following columns:

1. Abbreviation: An abbreviation.
2. Expansion: The expansion for the abbreviation.
3. Category: A category of the abbreviation. Categories are limited to
   - `Common`: An abbreviation for everyday conversation.
   - `STEM`: An abbreviation for topics in Science, Technology, Engineering,
      and Mathematics.

Duplicate abbreviations are allowed. So, if an abbreviation can be expanded in
multiple ways, you can add a separate entry for each expansion.

The contributions are compiled into [a single CSV file](./database/data.csv)
with the same schema as a contributors file. The data file is generated
everytime a contribution has been made. So, you have to run the command
`devab update` in the root directory of the forked repo to make the update.

You are not allowed to add an entry that someone else has already made. An
entry in this case means an abbreviation and its expansion. If your entry has a
different expansion from someone else's, you can add it to your file. To check
whether an entry exists or not, run `devab find <ABBREVIATION>`, where
`<ABBREVIATION>` is the abbreviation you are looking up.

## Branches

You can contribute to the main branch directly or you can create a new branch.

