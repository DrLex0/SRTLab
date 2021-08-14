# Test files

These are some files that can be used to verify the automatic clean-up routines and other things.
These files may not be used for any other purpose.

Each directory with subtitle files contains a set of raw input files, and a subdirectory 'DesiredOutput' with a mostly hand-crafted target. Ideally, the output of SRTLab should be identical to those files. As you'll see, this is currently not yet the case for most files.
For now, there are mainly files for testing the -H(H) option. Some of these were made with such sloppy OCR, that the HI annotations are often so deformed that there is no hope of removing them automatically.

The ‘AutoScaleOffset’ directory contains some example input files for the `-A` and `-B` options. The expected offset and/or scale values are in the file titles. Mind that the average offset is not necessarily the same as the offset obtained from the least squares estimation.

Ideas for other features and test sets: automatic correction of typical OCR failures (extremely common is capital I being replaced by lowercase L, this also breaks the regular -H feature).

