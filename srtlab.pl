#!/usr/bin/perl
# SRTLab by Alexander Thomas
# A tool to modify .srt files.
#
# Version 0.9  (2009/08): unfinished
# Version 0.91 (2010/03): added CRLF option
# Version 0.92 (2010/04): split parser & renderer, added time check & fix
# Version 0.93 (2011/01): more robustness against crappy files
# Version 0.94 (2011/08): improved hearing-aid filtering
# Version 0.95 (2011/09): added extra hearing-aid filtering mode
# Version 0.96 (2012/07): overlap detection and removal
# Version 0.97 (2017/01): URL removal, more robust against poor formatting, much
#   better encoding detection; [Idiomdrottning] whitespace removal, -HH tweaks.
# Version 0.98 (2017/09): rudimentary OCR error fix option
#
# Copyright (C) 2017  Alexander Thomas & Idiomdrottning
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);
use Encode::Guess;

my $VERSION = '0.98';

# TODO: allow the user to override input encoding detection, or to configure it.
# TODO: further improve -HH to remove more variants without breaking regular dialogue.
# For instance: "one purpose, and one purpose only:\n\n" risks losing everything after
#   the comma if we would merely look for case insensitive [A-Z ]:.
#   Also, -HH will destroy anything that looks like "Name:", even in a line like:
#   'Same thing: "Deliver the Galaxy."' This is hard to avoid.
# A first step to be able to do this in a sane way, is to make abstraction of $LE:
#   convert everything internally to \n and render again with $LE. This avoids having
#   to use $LE everywhere (there are certainly errors in the current code due to this).
# The whole H option is dodgy anyway because people keep on inventing new lay-outs for
#   these hearing-aid annotations instead of using a single standard. I imagine this must
#   also be terribly annoying to the hearing impaired who have to get used to each
#   different lay-out.
# Therefore proposal: ideally, the script should be able to guess the particular
#   lay-out automatically, a bit like detecting the encoding.
# These lay-outs consist of two major parts: 1. annotation of sounds, 2. persons speaking,
#   and often they will also contain 3. music lyrics: if you're lucky, indicated with ♪
#   symbol, also sometimes with ~ or # instead. Proposal: first run through the entire
#   file and check for every part which formatting is most likely used, then do the actual
#   processing.
# Only make it optional to leave lyrics, the rest must be fully automatic.
# Some flavours I have seen:
# For noises:
#  [CLEARS THROAT]
#    [Clears throat]
#  (Clears throat)
#    [clears throat]
#  - (Cameraman gasps)
#  - [ Bats Screeching ]
# For speakers:
#  [BOY1] Blah blah!
#    [Boy 1] Blah blah!
#  - (In unison) Blah, blah, blah!
#    DRIVER:
#    Oh, crap.
#  JANUS: Division 6?
#  I never heard of Division 6.
#    JANUS [IN SPANISH]:
#
# Ideas for new features:
# Extension of auto-correction: when of two single-line consecutive subs, one
#  is shown too long and one too short, and they're within a reasonable time,
#  they can be merged. But this will require manual intervention to include
#  the mandatory "- " indicator when fusing dialogue from different actors.
# Similarly, too long subs could be split up (although those mostly stem from
#  hopelessly poor translation anyway)
#
# Repair typical OCR errors. Many of the typical mistakes can be corrected
#  automatically with reasonable confidence (for instance “l'm a bad OCR program
#  and l like the letter L”). For this to work really reliably though, it would
#  need to be tied to a spell checker and perhaps even a language model, so this
#  is not trivial. This is a prerequisite to make -H work reliably.
#
# Automatic syncing of a subtitle file given another file with correct sync
#  (e.g. in another language or a worthless translation with good sync):
# This boils down to a least squares estimation of S and O but with possibly
#  missing and/or superfluous data points. Subtitles may be split up in the
#  other language, some may be omitted, or there may be extra subs that aren't
#  in the target file. Most weight should be given to subs after a period of
#  silence, because those are the most reliable points for syncing.
# In other words, this is a whole lot of work so it's unlikely that I'll ever
#  implement it.
# If it works however, it's not a big step up to actually detect speech in the
#  film soundtrack and use that data as the reference. Full auto-sync, yeah!


#===== Defaults =====#
# Minimum ratio of seconds/#characters in a subtitle for length check.
# This number is tuned for Dutch, it may be different for other languages.
my $minRatio = .034;
# Maximum ratio of seconds/#characters, above which a subtitle will be
# marked as 'sticky' if it appears longer than 3 seconds.
my $stickRatio = .22;
# Absolute minimum duration in seconds for any subtitle, no matter how short
my $minDur = .8;
# Gap to leave between end of this subtitle and start of next when auto-correcting
my $gap = .08;

my $scale = 1.0;
my $offset = 0.0;
my ($encodingIn,$encodingOut);
my ($bAuto,$bVerbose,$bClean,$bCRLF,$bHasBOM);
my $tSaveBOM = -1;
my ($bCheckLength,$bFixLength,$bInPlace,$bTextOnly,$bNukeHA,$bNukeHarder,$bNukeURLs,$bWhitespace,$bFixOCR);
my @insertInd = ();
my @inserTime = ();

sub printUsage
{
	#      12345678901234567890123456789012345678901234567890123456789012345678901234567890
	print "srtlab [options] file1.srt [file2.srt ...] > output.srt\n"
	     ."SRT file editing tool.\n"
	     ."  Multiple input files are joined. You should make sure in such case that the\n"
	     ."    time stamps do not overlap and the character encodings are the same.\n"
	     ."  Options:\n"
	     ."  Time values must be in the format [-]HH:MM:SS.sss, or a floating-point number\n"
	     ."    representing seconds.\n"
	     ."  -e: in-place editing: overwrite first file instead of printing to stdout\n"
	     ."    (BE CAREFUL!)\n"
	     ."  -c: remove empty subtitles (empty = really empty, no whitespace characters).\n"
	     ."  -s S: scale all timestamps.\n"
	     ."    S can be a floating-point number or any of these shortcuts:\n"
	     ."    NTSCPAL:  0.95904    = 23.976/25 (subs for NTSC framerate to PAL video)\n"
	     ."    PALNTSC:  1.04270938 = 25/23.976 (PAL framerate to NTSC)\n"
	     ."    NTSCFILM: 0.999      = 23.976/24 (NTSC framerate to film)\n"
	     ."    PALFILM:  1.04166667 = 25/24     (PAL framerate to film)\n"
	     ."    FILMNTSC: 1.001001   = 24/23.976 (film framerate to NTSC)\n"
	     ."    FILMPAL:  0.96       = 24/25     (film framerate to PAL)\n"
	     ."  -o O: offset all timestamps by time O.  Offset is added after scaling, i.e.\n"
	     ."    new times are calculated as S*t+O.\n"
	     ."  -a Ta1 Ta2 Tb1 Tb2: automatically calculate S and O.\n"
	     ."    Ta1 is the time at which a subtitle appears in the current SRT file, Ta2 is\n"
	     ."    where it should appear in the output. The same for Tb1 and Tb2, for another\n"
	     ."    subtitle.  For best accuracy, use the earliest and latest subtitles.\n"
	     ."  -b Ta1 Ta2: like -a, but only calculate the offset O.\n"
	     ."  -i I: insert a new subtitle at index I (in the original file). This command\n"
	     ."    can be repeated, e.g. to insert two subs at index 3, use -ii 3 3.\n"
	     ."  -j J: insert a new subtitle at original time J (can be repeated as well).\n"
	     ."  -f: try to fix common OCR errors (tuned for English only). This may help to\n"
	     ."      obtain a better result with -H.\n"
	     ."  -H: attempt to remove typical non-verbal annotations in subs for the hearing\n"
	     ."    impaired, e.g. (CLEARS THROAT).  You should combine this with -c.\n"
	     ."    Repeat -H to try to remove non-capitalized annotations (mind that this has\n"
	     ."    a higher risk to mess things up, so only use when necessary).\n"
	     ."  -l: report subtitles that appear too briefly or overly long, or overlap.\n"
	     ."  -L: report and attempt to repair subtitles that appear too briefly or overlap.\n"
	     ."  -m: add BOM character to output file if it is Unicode.\n"
	     ."  -M: do not add BOM character to output file (default is same as input).\n"
	     ."  -r: maintain Redmond-style compatibility with typewriters (CRLF). If this\n"
	     ."    option is not enabled, any existing CR will be obliterated.\n"
	     ."  -u: save output in UTF-8.\n"
	     ."  -U: erase all subtitles that have a URL in them (should combine with -c).\n"
	     ."  -w: Strip whitespace from beginning and end of lines\n"
	     ."  -t: strip all SRT formatting and only output the text.\n"
	     ."  -v: verbose mode.\n"
	     ."  -V: print version and exit.\n";
}


my @files = ();

if( $#ARGV < 0 ) {
	printUsage();
	exit(1);
}

# Parse command line arguments
while( $#ARGV >= 0 ) {
	my $arg = shift;
	if( substr( $arg, 0, 1 ) eq '-' ) {
		my @switches = split(//,$arg);
		shift(@switches);
		foreach my $sw (@switches) {
			if( $sw eq 's' ) {
				$scale = shift;
				if( ! defined($scale) || ! isScale($scale) ) {
					print STDERR "Scale must be a positive floating-point number or a supported symbol\n";
					exit(2);
				}
				$scale = fromScale($scale);
			}
			elsif( $sw eq 'o' ) {
				$offset = shift;
				if( ! defined($offset) || ! (isFloat($offset) || isHMS($offset)) ) {
					print STDERR "Offset must be a floating-point number or [-]HH:MM:SS.sss\n";
					exit(2);
				}
				if( isHMS($offset) ) {
					$offset = fromHMS($offset);
				}
			}
			elsif( $sw eq 'a' ) {
				my ($Ta1,$Ta2,$Tb1,$Tb2) = (shift, shift, shift, shift);
				if( ! defined($Ta1) || ! (isFloat($Ta1) || isHMS($Ta1)) ||
				    ! defined($Ta2) || ! (isFloat($Ta2) || isHMS($Ta2)) ||
				    ! defined($Tb1) || ! (isFloat($Tb1) || isHMS($Tb1)) ||
				    ! defined($Tb2) || ! (isFloat($Tb2) || isHMS($Tb2)) ) {
					print STDERR "-a expects four arguments, which must be floating-point numbers or [-]HH:MM:SS.sss\n";
					exit(2);
				}
				($Ta1,$Ta2,$Tb1,$Tb2) = (fromHMS($Ta1), fromHMS($Ta2), fromHMS($Tb1), fromHMS($Tb2));
				$scale = ($Ta2-$Tb2)/($Ta1-$Tb1);
				$offset = ($Tb2*$Ta1-$Ta2*$Tb1)/($Ta1-$Tb1);
				$bAuto = 1;
			}
			elsif( $sw eq 'b' ) {
				my ($Ta1,$Ta2) = (shift, shift);
				if( ! defined($Ta1) || ! (isFloat($Ta1) || isHMS($Ta1)) ||
				    ! defined($Ta2) || ! (isFloat($Ta2) || isHMS($Ta2)) ) {
					print STDERR "-b expects two arguments, which must be floating-point numbers or [-]HH:MM:SS.sss\n";
					exit(2);
				}
				$offset = fromHMS($Ta2)-fromHMS($Ta1);
				$bAuto = 1;
			}
			elsif( $sw eq 'i' ) {
				my $ind = shift;
				if( ! defined($ind) || $ind < 1 ) {
					print STDERR "-i expects an integer greater than 0 as next argument.\n";
					exit(2);
				}
				push(@insertInd,$ind);
			}
			elsif( $sw eq 'j' ) {
				my $tim = shift;
				if( ! defined($tim) || ! (isFloat($tim) || isHMS($tim)) ) {
					print STDERR "-j expects a floating-point number or HH:MM:SS.sss time as next argument.\n";
					exit(2);
				}
				push(@inserTime,fromHMS($tim));
			}
			elsif( $sw eq 'l' ) { $bCheckLength = 1; }
			elsif( $sw eq 'L' ) {
				$bCheckLength = 1;
				$bFixLength = 1;
			}
			elsif( $sw eq 'c' ) { $bClean = 1; }
			elsif( $sw eq 'r' ) { $bCRLF = 1; }
			elsif( $sw eq 'u' ) { $encodingOut = 'UTF-8'; }
			elsif( $sw eq 'm' ) { $tSaveBOM = 1; }
			elsif( $sw eq 'M' ) { $tSaveBOM = 0; }
			elsif( $sw eq 'e' ) { $bInPlace = 1; }
			elsif( $sw eq 't' ) { $bTextOnly = 1; }
			elsif( $sw eq 'f' ) { $bFixOCR = 1; }
			elsif( $sw eq 'H' ) {
				if($bNukeHA) {
					$bNukeHarder = 1;
				} else {
					$bNukeHA = 1;
				}
			}
			elsif( $sw eq 'U' ) { $bNukeURLs = 1; }
			elsif( $sw eq 'w' ) { $bWhitespace = 1; }
			elsif( $sw eq 'v' ) { $bVerbose = 1; }
			elsif( $sw eq 'V' ) {
				print "SRTLab $VERSION by Alexander Thomas & Idiomdrottning\n";
				exit(0);
			}
			elsif( $sw eq 'h' ) {
				printUsage();
				exit(0);
			}
			else {
				print STDERR "Ignoring unknown switch -$sw\n"; }
		}
	}
	else {
		push( @files, $arg ); }
}

if($bVerbose) {
	if($bAuto) {
		printf STDERR ("Automatically calculated scale $scale and offset %1.3f\n", $offset);
	}
	else {
		print STDERR "Using scale $scale and offset $offset\n";
	}
}

@insertInd = sort(@insertInd);
@inserTime = sort(@inserTime);

my $LE = "\n";
if($bCRLF) {
	$LE = "\r\n"; }
my $nCleaned = 0;
my @starts = ();
my @ends = ();
my @subs = ();

# Parse the file into subs
foreach my $file (@files) {
	my $malform = 0;

	# Sniff the encoding of the file
	my $enc = sniffEncoding($file);
	($bHasBOM,$encodingIn) = split(',',$enc);
	binmode STDERR, ":encoding($encodingIn)";
	if($bVerbose) {
		print STDERR "Encoding for file `$file' detected as `$encodingIn'";
		if($bHasBOM) { print STDERR ", with BOM\n"; }
		else { print STDERR "\n"; }
	}
	# Set the 'tri-state' to the input state if it is 'high impedance'.
	if( $tSaveBOM < 0 ) {
		$tSaveBOM = $bHasBOM; }
	# TODO: allow choosing any output encoding.
	if( !defined($encodingOut) ) {
		$encodingOut = $encodingIn; }

	open( FILE, "<:encoding($encodingIn)", $file ) or die "Can't open file `$file'\n";
	my $state = 0; # 0 = looking for next time stamp, 1 = inside sub
	my $idxOld = 0;
	my $bFirst = 1;

	foreach my $line (<FILE>) {
		chomp($line);
		$line =~ s/\r$//;
		if($bFirst) {
			$bFirst = 0;
			if( $bHasBOM && $line =~ /^\x{feff}/ ) {
				$line =~ s/^\x{feff}//; } # The BOM is unicode character U+FEFF, regardless of encoding
		}
		if( $state == 0 ) {
			if( ($idxOld) = $line =~ /^\s*(\d+)\s*$/ ) { # Subtitle index
				while( $#insertInd > -1 && $idxOld >= $insertInd[0] ) { # -i
					my $tm = 0;
					if( $#ends > -1 ) { $tm = $ends[$#ends]; }
					push(@starts, $tm);
					push(@ends, $tm);
					push(@subs, "NEW SUB$LE");
					shift(@insertInd);
				}
			}
			elsif( $line =~ /^\d\d:\d\d:\d\d,\d+ +--?> +\d\d:\d\d:\d\d,\d+/ ) {
				$state = 1;
				my ($tStart,$tEnd) = split(/ +--?> +/, $line);
				($tStart,$tEnd) = (fromHMS($tStart),fromHMS($tEnd));
				while( $#inserTime > -1 && $tStart >= $inserTime[0] ) { # -j
					my $tNext = $tStart;
					if( $#inserTime > 0 && $tStart > $inserTime[1] ) {
						$tNext = $inserTime[1]; }
					push(@starts, $scale*$inserTime[0]+$offset);
					push(@ends, $scale*$tNext+$offset);
					push(@subs, "NEW SUB$LE");
					shift(@inserTime);
				}

				push(@starts, $scale*$tStart+$offset);
				push(@ends, $scale*$tEnd+$offset);
				push(@subs, '');
			}
			elsif( $line ne '' ) {
				$malform++;
				if( $malform > 20 ) {
					print STDERR "Too many unparseable lines, this file probably has bad syntax or is not an SRT file. Aborting.\n";
					exit(1);
				}
				if($bVerbose) {
					print STDERR "Ignoring spurious line `$line'\n"; }
			}
		}
		elsif( $state == 1 ) {
			# FIXME: maybe better to demand a strictly empty line. Using whitespace to
			# make gaps in a single subtitle could be useful.
#			if( $line =~ /^\s*$/ ) { # End of the sub
			if( $line eq '' ) { # End of the sub
				$state = 0;
			}
			else {
				$subs[$#subs] .= "$line$LE";
			}
		}
	}

	close FILE;
}

if($bInPlace) {
	open FILE, ">:encoding($encodingOut)", $files[0] or die "Can't open file `$files[0]' for writing\n";
	select(FILE);
}

# Process the subs (if needed) and output
binmode STDOUT, ":encoding($encodingOut)";
if( $encodingOut =~ /^UTF-/i && $tSaveBOM ) {
	printf( '%c', 0xfeff ); }
my $idxNew = 1;
my $ocrFixes = 0;

for( my $s=0; $s<=$#subs; $s++ ) {
	if($bWhitespace) {  # Do this twice, once before (to make it easier for -H)...
		$subs[$s] =~ s/^[ \t]+//mg;
		$subs[$s] =~ s/[ \t]+$//mg;
	}
	if($bFixOCR) {
		# Fix obvious OCR errors, only for English at the moment. This is just a bunch of
		# ugly heuristics, there are better ways to do this, but it's a lot better than nothing.
		# Many of these errors are caused by the dumb idea of making 'l' and 'I' look
		# identical in sans-serif fonts, and the lack of smartness in OCR programs.
		my $orig = $subs[$s];

		# Fix "I ", "I'", "If", "In", "Is", and "It" and any words starting with the latter
		# (AFAIK there are no words in English starting with "ln", "ls", etc).
		# Take care not to break e.g. "nice-looking", so don't just assume '-' marks a new word.
		$subs[$s] =~ s/(^-?|\s-?|[.…"“])l([ '’.,fnst]|$)/$1I$2/gm;
		# OCR programs also often drop spaces around 'f' or 'j'. Fixing all these is difficult,
		# but we can be sure no English words start with any character followed by "fj".
		$subs[$s] =~ s/(^|\s|[.-…"“])(\w)fj/$1$2f j/gm;

		# Fix capital 'I' in all-caps word (why do OCR programs keep making this obvious mistake?)
		$subs[$s] =~ s/(^|\s|\[|\(|-)l([A-Z])/$1I$2/gm;  # at start of word
		$subs[$s] =~ s/([A-Z]{2,})l/$1I/gm;  # at end or inside, preceded by at least two capitals
		$subs[$s] =~ s/([A-Z])l([A-Z])/$1I$2/gm;  # in between two capitals

		# Fix spurious spaces after '1' in numbers (this will probably mess up a few cases
		# where the space was intended, but most often by far it is an error).
		$subs[$s] =~ s/1 (\d+|[.,:])/1$1/gm;
		$subs[$s] =~ s/1 (\d+|[.,:])/1$1/gm; # Do this twice because the \d may also have been a 1.
		if($subs[$s] ne $orig) {
			$ocrFixes++;
			print STDERR "OCR corrected: $subs[$s]\n" if($bVerbose);
		}
	}
	if($bNukeHA) {
		# Remove simple hearing-impaired annotations like "(CLEARS THROAT)" or "[NOISE]"
		$subs[$s] =~ s/\([A-Z0-9 ,.\-'"\&\n]+?\)//g;
		$subs[$s] =~ s/\[[A-Z0-9 ,.\-'"\&\n]+?\]//g;
		if($bNukeHarder) { # Case insensitive and more varied formatting
			$subs[$s] =~ s/-? ?\([A-Z0-9 ,.!\-'"\&\/\n]+?\)//gi;
			$subs[$s] =~ s/-? ?\[[A-Z0-9 ,.!\-'"\&\/\n]+?\]//gi;
			# "Name: Text" on new line, should therefore become "- Text"
			$subs[$s] =~ s/^[A-Z0-9 '"#]+?: /- /mgi;
			# This has a high risk of affecting regular lines, therefore keep it case sensitive. TODO: improve
			$subs[$s] =~ s/[A-Z0-9 '"#]+?: *$//mg;
			$subs[$s] =~ s/^-[A-Z0-9 '"#]+?: /- /mgi;
			$subs[$s] =~ s/^[A-Z0-9 '"#]+?: //mgi;
		}
		else {
			# "NAME: Text" on new line, should therefore become "- Text"
			$subs[$s] =~ s/^[A-Z0-9 '"#]+?: /- /mg;
			$subs[$s] =~ s/[A-Z0-9 '"#]+?:[ \n]//g;
		}
		$subs[$s] =~ s/^\n+([^\n])/$1/g; # Remove trailing empty lines
	}
	if($bNukeURLs) {
		# These atrocious regexes should catch most common URLs, at least they did when I tweaked them long ago.
		if($subs[$s] =~ m~([^\w\"\=\[\]]|[\n\b]|\A)\\*(\w+://[\w\~\.\;\:\,\$\-\+\!\*\?/\=\&\@\#\%]+\.[\w\~\;\:\$\-\+\!\*\?/\=\&\@\#\%]+[\w\~\;\:\$\-\+\!\*\?/\=\&\@\#\%])~i) {
			$subs[$s] = '';
		} elsif($subs[$s] =~ m~([^(?:\://\S*)\"\=\[\]/\:\.]|[>\(\n\b]|\A)(www\.[^\.][\w\~\.\;\:\,\$\-\+\!\*\?/\=\&\@\#\%]+\.[\w\~\;\:\$\-\+\!\*\?/\=\&\@\#\%]+[\w\~\;\:\$\-\+\!\*\?/\=\&\@\#\%])~i) {
			$subs[$s] = '';
		}
	}

	if($bWhitespace) {  # ... and once after to clean up any remains.
		$subs[$s] =~ s/^[ \t]+//mg;
		$subs[$s] =~ s/[ \t]+$//mg;
	}

	if( $bClean && $subs[$s] =~ /^(<.>\n*<\/.>)?\n*$/ ) { # -c: Skip if empty
		$nCleaned++;
		next;
	}
	if($bCheckLength) {
		# First, check for and optionally fix overlap
		if( $s < $#subs && $starts[$s+1]-$ends[$s] < 0 ) {
			print STDERR ("Sub $idxNew overlaps with next");
			if($bFixLength) {
				$ends[$s] = $starts[$s+1]-$gap;
				print STDERR " -> Fixed";
			}
			print STDERR "\n";
		}

		# Check the duration of a sub vs. the length of its 'canonical form'
		my $sub = ']'.$subs[$s];
		$sub =~ s/\s\s+/ /g;
		$sub =~ s/\s?$LE/]/g;
		$sub =~ s/\]\s/]/g;
		$sub =~ s/\.\.\././g;
		my $dur = $ends[$s]-$starts[$s];
		my $okDur = $minRatio*length($sub);
		if( $okDur < $minDur ) { $okDur = $minDur; }
		if( $dur < $okDur ) {
			printf STDERR ("Sub $idxNew too fast: %.2f < %.2f (at %s)",
			               $dur, $okDur, toHMS($starts[$s]) );
			if($bFixLength) {
				my $newEnd = $starts[$s]+1.05*$okDur;
				if( $s == $#subs || int(.5+1000*$starts[$s+1]) >= int(.5+1000*($newEnd+$gap)) ) {
					$ends[$s] = $newEnd;
					print STDERR " -> Fixed";
				}
				elsif( int(.5+1000*($starts[$s+1]-$gap)) > int(.5+1000*$ends[$s]) ) {
					$ends[$s] = $starts[$s+1]-$gap;
					printf STDERR (" -> Partially fixed (%.2f)", ($starts[$s+1]-$gap-$starts[$s]) );
				}
				else {
					print STDERR " -> Cannot fix"; }
			}
			print STDERR "\n";
		}
		elsif( $dur > 3 && $dur > $stickRatio*length($sub) ) {
			printf STDERR ("Sub $idxNew seems sticky: %.2f secs, expected %.2f (at %s)\n",
			               $dur, $stickRatio*length($sub), toHMS($starts[$s]) ); }
	}
	if($bTextOnly) {
		print $subs[$s] . $LE;
	}
	else {
		print "$idxNew$LE".
		      toHMS($starts[$s]) .' --> '. toHMS($ends[$s]) . $LE .
		      $subs[$s] . $LE;
	}
	$idxNew++;
}

if( $bClean && $bVerbose) {
	print STDERR "Removed $nCleaned empty subtitles.\n";
}
if( $ocrFixes && $bVerbose ) {
	print STDERR "Fixed ${ocrFixes} subtitles with presumed OCR errors.\n";
}


##############################################################
# SUBROUTINES

sub isFloat
{
	return ( $_[0] =~ /^-?\d*\.?\d+$/ );
}

sub isHMS
{
	return ( $_[0] =~ /^-?\d\d:\d\d:\d\d([,\.]\d+)?$/ );
}

# Convert HH:MM:SS[.,]mmm to floating-point number
sub fromHMS
{
	my ($hms) = @_;
	if( isFloat($hms) ) { return $hms; }
	my $neg = 1;
	if( $hms =~ /^-/ ) {
		$neg = -1;
		$hms = substr($hms,1);
	}
	my ($h,$m,$s) = (substr($hms,0,2), substr($hms,3,2), substr($hms,6,2));
	if( length($hms) > 9 ) {
		$hms =~ s/,/./;
		$s += substr($hms,8);
	}
	return $neg*($s+60*($m+60*$h));
}

# Convert floating-point number to HH:MM:SS,mmm
sub toHMS
{
	my $neg = '';
	my ($ip,$fp) = split(/\./, $_[0]);
	if($ip < 0) {
		$neg = '-';
		$ip *= -1;
	}
	if( ! defined($fp) ) { $fp = 0; }
	my $s = ($ip % 60) . ".$fp";
	my $m = int($ip/60)%60;
	my $h = int($ip/3600);
	my $hms = sprintf("%02d:%02d:%06.3f", $h,$m,$s);
	$hms =~ s/\./,/;
	return "$neg$hms";
}

sub isScale
{
	return ((isFloat($_[0]) && $_[0] >= 0) || $_[0] =~ /^(NTSC(PAL|FILM)|PAL(NTSC|FILM)|FILM(NTSC|PAL))$/i);
}

sub fromScale
{
	if( isFloat($_[0]) ) { return $_[0]; }
	my ($from,$to) = (1,1);
	if   ( $_[0] =~ /^NTSC/i ) { $from = 23.976; }
	elsif( $_[0] =~ /^PAL/i )  { $from = 25; }
	elsif( $_[0] =~ /^FILM/i ) { $from = 24; }
	if   ( $_[0] =~ /NTSC$/i ) { $to = 23.976; }
	elsif( $_[0] =~ /PAL$/i )  { $to = 25; }
	elsif( $_[0] =~ /FILM$/i ) { $to = 24; }
	return $from/$to;
}

sub sniffEncoding
# 'Sniff' the encoding of a file, and the presence of a BOM character.
# Return value is "$bHasBOM,$encoding".
# The only encodings currently supported are UTF-8, UTF-16, cp1252, shiftjis,
#   and ascii.
# Ideally, this function would be able to identify any encoding on any file,
#   even without the presence of any BOM.
# I currently rely on direct detection of the BOM (because this is trivial), and
#   otherwise I either try guess_encoding or attempt to decode the data as UTF8
#   (because guess_encoding seems to have problems detecting UTF-8 reliably).
# To improve upon this and reliably detect 8-bit encodings like the ISO-8859
#   family, something more advanced would be required that looks at statistics
#   of occurring code points to make an educated guess. However, that is a bit
#   beyond the scope of this simple tool. What would be useful though, is to
#   allow the user to force a specific encoding, or provide their own set of
#   candidates to steer guess_encoding.
{
	my $fHandle;
	open($fHandle, '<:bytes', $_[0]) or die "Can't open file `$_[0]'\n";
	my $line = <$fHandle>;
	close($fHandle);

	# Beware that this is different if perl treats the string as utf-8/16, in
	# that case the BOM is represented by by \x{feff}
	if($line =~ /^\x{ef}\x{bb}\x{bf}/) {
		return '1,UTF-8';
	} elsif($line =~ /^\x{fe}\x{ff}/) {
		return '1,UTF-16BE';
	} elsif($line =~ /^\x{ff}\x{fe}/) {
		return '1,UTF-16LE';
	}

	# No BOM found, try a more elaborate method. We need the entire file for
	# this because we cannot just read any chunk without risking to truncate a
	# multi-byte code point. Luckily, SRT files are never very big.
	open($fHandle, '<:bytes', $_[0]) or die "Can't open file `$_[0]'\n";
	my ($data, $chunk) = ('', '');
	while(read($fHandle, $chunk, 16384)) {
		$data .= $chunk;
	}
	close($fHandle);

	my $enc = guess_encoding($data, qw'UTF-16BE UTF-16LE cp1252 shiftjis ascii');
	if(! ref($enc)) {
		# Guessing failed. Try decoding as UTF-8 instead. If this works, there
		# is a good chance it actually is UTF-8.
		eval{$chunk = decode("UTF-8", $data, Encode::FB_CROAK);};
		if(!$@) {
			return '0,UTF-8';
		} else {
			# Falling back to cp1252 is a desperate measure to let the program
			# continue, but the output will probably be corrupted.
			print STDERR "ERROR: encoding detection failed. Assuming cp1252, which is probably wrong.\n  You should try again after converting the input file to a known encoding like UTF-8.\n";
			return '0,cp1252';
		}
		} else {
		return '0,'. $enc->name;
	}
}

# note: to get list of supported encodings:
# perl -MEncode -le "print for Encode->encodings(':all')"
