# Test files

These are some files that can be used to verify the automatic clean-up routines.
These files may not be used for any other purpose.
Each directory contains a set of raw input files, and a subdirectory 'DesiredOutput' with a mostly hand-crafted target. Ideally, the output of SRTLab should be identical to those files. As you'll see, this is currently not yet the case for most files.
For now, there are mainly files for testing the -H(H) option. Some of these were made with such sloppy OCR, that the HI annotations are often so deformed that there is no hope of removing them automatically.

Ideas for other features and test sets: automatic correction of typical OCR failures (extremely common is capital I being replaced by lowercase L, this also breaks the regular -H feature).

