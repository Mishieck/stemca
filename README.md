# STEMCA

A CLI app for looking up Science, Technology, Engineering, Mathematics, and
Common Abbreviations (STEMCA).

## Installation

Download and install the appropriate package for operating system from the
[releases](https://github.com/mishieck/stemca/releases).

## Features

### Lookup

Find matches for an abbreviation. Abbreviations may have multiple entries.
Lookups have the syntax `stemca lookup <abbreviation>`. To lookup `AI`, you
can use:

**Command**

```sh
stemca lookup ai
```

**Output**

```
1 match found

Abbreviation: AI
Expansion:    Artificial Intelligence
Category:     STEM 
```

The abbreviations are case-insensitive. So, `ai` could be replaced with `AI`,
`Ai`, or `aI`.
 
### List

List all the available abbreviations in a table. 

**Command**

```sh
stemca list  
```

**Output**:

```
Abbreviation    Expansion                                        Category
-------------------------------------------------------------------------
AI              Artificial Intelligence                          STEM
AKA             Also Known As                                    Common
API             Application Programming Interface                STEM
ASAP            As Soon As Possible                              Common
BTW             By The Way                                       Common
CAD             Computer-Aided Design                            STEM
CEO             Chief Executive Officer                          Common
COB             Close of Business                                Common
CPU             Central Processing Unit                          STEM
DIY             Do It Yourself                                   Common
DNA             Deoxyribonucleic Acid                            STEM
ETA             Estimated Time of Arrival                        Common
FYI             For Your Information                             Common
FWIW            For What It's Worth                              Common
HTML            HyperText Markup Language                        STEM
IoT             Internet of Things                               STEM
MRI             Magnetic Resonance Imaging                       STEM
NASA            National Aeronautics and Space Administration    STEM
OOO             Out of Office                                    Common
RAM             Random Access Memory                             STEM
ROI             Return on Investment                             Common
RSVP            Please Respond                                   Common
TBD             To Be Determined                                 Common
TBH             To Be Honest                                     Common
TL;DR           Too Long; Didn't Read                            Common
URL             Uniform Resource Locator                         STEM
WFH             Work From Home                                   Common
...             ...                                              ...
```

### Verify

This command is used by abbreviation contributors to verify that the latest
added or modified table has valid entries. After you have added or updated a
table, run:

```sh
stemca update
```

All tables are included in the releases.
