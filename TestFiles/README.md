# Test files

These are some files that can be used to verify the automatic clean-up routines and other things.
These files may not be used for any other purpose.

Each directory with subtitle files contains a set of raw input files, and a subdirectory 'DesiredOutput' with a mostly hand-crafted target. Ideally, the output of SRTLab should be identical to those files. As you'll see, this is currently not yet the case for all the files.

For now, there are mainly files for testing the `-H(H)` option that strips hearing impaired annotations, and a file for testing the `-f` option that fixes typical OCR errors. Usually, these options must be combined, because OCR errors may break the ability to recognise hearing impaired annotations. Some of these files were made with such sloppy OCR, that some characters are so deformed that there is no hope of fixing them automatically, but the script will already help a lot.

The ‘AutoScaleOffset’ directory contains some example input files for the `-A` and `-B` options. The expected offset and/or scale values are in the file titles. Mind that the average offset is not necessarily the same as the offset obtained from the least squares estimation.

