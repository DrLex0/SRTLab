# SRTLab
*SubRip subtitle file converter*<br>
by Alexander Thomas, aka Dr. Lex<br>
Contact: visit https://www.dr-lex.be/lexmail.html<br>
&nbsp;&nbsp;&nbsp;&nbsp;or use my gmail address "doctor.lex".


## What is it?
This is a Perl script that can perform certain operations on SubRip (.srt) subtitle files. For instance, it can scale and offset the time stamps of all subtitles based on two pairs of current and expected time values. It can also check files for subtitles that appear too briefly or overly long, and attempt to fix subs that appear too briefly (which is of course not always possible), as well as remove overlap between subtitles.

It is a bit of a work in progress and I plan to add some more features, but I released it to the public since it is already useful in its current form.

## Installing
Put it anywhere in a place that is in your executable PATH. Or always run it by specifying its full path.

## Usage
To get extended help, run the script with the switch '-h'.

The normal mode of operation is to run the script as:<br>
`srtlab.pl input.srt > output.srt`<br>
Which uses the standard redirect mechanism to write the output to a file. When running the script without the '>' part, it will simply print output on the console.

BEWARE: do not try this:<br>
`srtlab.pl input.srt > input.srt`<br>
This will destroy input.srt and leave you with an empty file. If you want to overwrite the input directly, instead run the script as follows and be aware that you will not be able to fix any mistakes you made unless you have a back-up of the file:
`srtlab -e input.srt`

The -L option can only fix too short subtitles if there is enough empty time after them. Otherwise more manual work will be required to fix the poorly made subtitle file. This option does not shorten 'sticky' subtitles (i.e. that appear too long) because these can sometimes be intentional. You should check the reported sticky subs yourself and fix them if necessary. In case of overlapping subtitles, -L will cut off the first subtitle in an overlapping pair at the time where the second one starts.

The -H switch will cause the script to remove the most common non-verbal annotations in subtitles for the hearing impaired (like [CLEARS THROAT] and character names). This can be useful if you want to play your film silently without missing out on any of the dialogue, or if you want to prepare a subtitle file for translation. In most cases you should combine -H with -c. If you provide the -H switch twice, it will try a wider range of patterns to strip non-dialogue subtitles. You should only use this if a single -H does not work satisfactorily, because -HH has a higher risk of removing parts of regular subtitles.

At this time the script will only work with UTF-8, UTF-16 or Windows Latin 1 encoded files. It will only detect UTF-x encodings if the file starts with a Unicode BOM character, otherwise it will default to Latin 1 (cp1252). If you usually work with subtitles in another encoding, you can adjust the last lines of the script. My goal is to make the script smarter in future versions such that it auto-detects all common encodings. My advice is to convert all your srt files to Unicode unless your media player does not support it. The 8-bit encodings are a thing of the past.

## License
This program is released under the GNU General Public License. See the source file and COPYING for more details.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

