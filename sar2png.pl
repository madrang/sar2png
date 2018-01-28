#!/usr/bin/perl
# sar2png - Draws a line chart with data from sar output.
#
# Copyright (C) 2010 Joachim "Joe" Stiegler <blablabla@trullowitsch.de>
# Copyright (C) 2017 Marc-Andre "Madrang" Ferland <madrang+sar2png@gmail.com>
#
# This program is free software; you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program;
# if not, see <http://www.gnu.org/licenses/>.
#
# --
#
# Successfully tested on Debian GNU/Linux 5.0 and Sun Solaris 5.10
#
# On Debian GNU/Linux systems you can find the sar utility in the sysstat package
# On Arch GNU/Linux systems the sysstat package is in the community repository
#
# Uses Chart::Lines from CPAN (http://search.cpan.org/~chartgrp/Chart-2.4.1/Chart.pod)
#
# Version: 1.2.0 - 18.10.2017
# See CHANGELOG for changes

use warnings;
use strict;
use Chart::Lines;
use Getopt::Std;
use Sys::Hostname;
use POSIX;
use Time::Local qw( timegm );

#
# $opt_u,    CPU
# $opt_r,    RAM
# $opt_n,    NET
# $opt_w,    SWAP
# $opt_f,    Display Free/Idle
# $opt_a,    Add usages where usefull to stack usage graph.
# $opt_t,    Apply hysteresis to graph to slow the time response and remove unwanted spikes (Cpu, Network).
# $opt_h,    Help Message
# $opt_s,    skip every x tick
# $opt_x,    Height
# $opt_y,    Width
# $opt_o     Output Path
#
our ($opt_u, $opt_r, $opt_n, $opt_w, $opt_f, $opt_a, $opt_t, $opt_h, $opt_s, $opt_x, $opt_y, $opt_o);	# The commandline options

my @uname = uname();		# Like uname -a
my $sysname = $uname[0];	# Kind of system (Linux or SunOS)
my $hostname = hostname;	# The system hostname
my @data;		# Array which stores the array references of the usage items (e.g. idle stats)
my @current;	# Temporary data storage
my @input;		# sar output
my @legend;		# Legend labels of the chart
my @colors;		# Color labels of the chart
my $height = 320;	# default height of the png
my $width = 480;	# default width of the png
my $sar;		# predefinition only :-)

$colors[0] = [255,0,0];
$colors[1] = [0,255,0];
$colors[2] = [0,0,255];
$colors[3] = [255,0,255];
my $rpname = "";

my $count = 0;
my $rxKBsAvg = 0;
my $txKBsAvg = 0;
my $rxPcksAvg = 0;
my $txPcksAvg = 0;
my $rxCmpsAvg = 0;
my $txCmpsAvg = 0;
my $rxMcstsAvg = 0;

my $usrAvg = 0;
my $sysAvg = 0;
my $iowAvg = 0;
my $idleAvg = 0;

my $memAvg = 0;
my $swapAvg = 0;

my $usedAvg = 0;
my $cacheAvg = 0;
my $bufferAvg = 0;
my $freeAvg = 0;

my @d = localtime(time);	# Time since The Epoch in a 9-element list 
my $year = $d[5] + 1900;
my $month = $d[4] + 1;
my $day = $d[3];
my $hour = $d[2];
my $minute = $d[1];
my $yday = (gmtime(timegm($d[0],$d[1],$d[2],$d[3],$d[4],$d[5]) - 24*60*60))[3];

my $file = $hostname."-".$year."-".$month."-".$day.".png";	# Filename of output png

# If month or day are single digits add a 0 to the digit
if (length($month) < 2) {
	$month = "0".$month;
}

if (length($day) < 2) {
	$day = "0".$day;
}

if (length($yday) < 2) {
	$yday = "0".$yday;
}

if (length($hour) < 2) {
	$hour = "0".$hour;
}

if (length($minute) < 2) {
	$minute = "0".$minute;
}

# The usage message
sub usage {
	print "Usage: $0  -u | -r | -n <iface> | [ -s | -x | -y | -o | -h ]\n";
	print " -u: CPU, -r: RAM, -w: SWAP, -n: NET, -s: skip every x tick, -h: this message\n";
	print " -x: height, -y: width, -o outpath\n\n";
	print "Example; $0 -u -x 480 -y 640 -s 4 -o /home/stats/\n";
	exit (0);
}

# Initialize options or print usage message (also print the usage message if unknown options are given)
if ( (!(getopts("urn:wfaht:s:x:y:o:"))) || (defined($opt_h)) ) {
	usage();
}

# Checks if the options argument is digit only
sub is_numeric {
	my $num = shift(@_);
	if ($num =~ /[^\d]/) {
		die $num." is not numeric.\n"; 
	}   
	else {
		return 1;
	}   
}

$ENV{'LANG'} = "C";

# Where we can found the sar binary on the system
if ($sysname eq "Linux") {
	$sar = "/usr/bin/sar";
}
elsif ($sysname eq "SunOS") {
	$sar = "/usr/sbin/sar";
}
else {
	die "Your OS wasn't identified\n";
}

my $iFile = "";
my $ydayFile = "";

if (-d "/var/log/sysstat") {
	$iFile = "/var/log/sysstat/sa$day";
	if (not -f $iFile) {
		die "Missing \"$iFile\"\n";
	}
	$ydayFile = "/var/log/sysstat/sa$yday";
} elsif (-d "/var/log/sa") {
	$iFile = "/var/log/sa/sa$day";
	if (not -f $iFile) {
		die "Missing \"$iFile\"\n";
	}
	$ydayFile = "/var/log/sa/sa$yday";
} else {
	die "Your OS wasn't identified\n";
}

sub cpustat {
	if (-f $ydayFile) {
		@input = `$sar -u -s $hour:$minute:00 -f $ydayFile`;
		push (@input, `$sar -u -f $iFile`);
	} else {
		@input = `$sar -u -f $iFile`;
	}
	
	$rpname = "CPU";
	$file = $rpname."-".$file;

	$colors[0] = [200,0,200];	# iow
	$colors[1] = [200,0,0];		# sys
	$colors[2] = [0,200,0];		# usr
	$colors[3] = [0,100,200];		# idle

	my @hysteresis = ( 0, 0, 0, 0 );

	if ($sysname eq "Linux") {
		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			@current = split(' ', $line);

			push @{$data[0]}, $current[0];					# time
			
			if (defined($opt_t) && is_numeric($opt_t)) {
				$hysteresis[0] = (($current[5] - $hysteresis[0]) / $opt_t) + $hysteresis[0];
				$hysteresis[1] = (($current[4] - $hysteresis[1]) / $opt_t) + $hysteresis[1];					# sys
				$hysteresis[2] = ((($current[2] + $current[3]) - $hysteresis[2]) / $opt_t) + $hysteresis[2];	# usr
				$hysteresis[3] = (($current[7] - $hysteresis[3]) / $opt_t) + $hysteresis[3];					# idle
				push @{$data[1]}, $hysteresis[0];				# iowait
				if (defined($opt_a)) {
					push @{$data[2]}, $hysteresis[0] + $hysteresis[1];											# sys (display iowait + sys)
					push @{$data[3]}, $hysteresis[0] + $hysteresis[1] + $hysteresis[2];							# usr (display iowait + sys + usr)
					if (defined($opt_f)) {
						push @{$data[4]}, $hysteresis[0] + $hysteresis[1] + $hysteresis[2] + $hysteresis[3];	# idle
					}
				} else {
					push @{$data[2]}, $hysteresis[1];					# sys
					push @{$data[3]}, $hysteresis[2];					# usr
					if (defined($opt_f)) {
						push @{$data[4]}, $hysteresis[3];				# idle
					}
				}
			} else {
				push @{$data[1]}, $current[5];					# iowait
				if (defined($opt_a)) {
					push @{$data[2]}, $current[5] + $current[4];												# sys (display iowait + sys)
					push @{$data[3]}, $current[5] + $current[4] + $current[3] + $current[2];					# usr (display iowait + sys + usr)
					if (defined($opt_f)) {
						push @{$data[4]}, $current[5] + $current[4] + $current[3] + $current[2] + $current[7];	# idle
					}
				} else {
					push @{$data[2]}, $current[4];					# sys
					push @{$data[3]}, $current[2] + $current[3];	# usr
					if (defined($opt_f)) {
						push @{$data[4]}, $current[7];				# idle
					}
				}
			}

			$iowAvg += $current[5];
			$sysAvg += $current[4];
			$usrAvg += $current[2] + $current[3];
			$idleAvg += $current[7];

			$count++;
		}

		$iowAvg = sprintf("%.2f", $iowAvg / $count);
		$sysAvg = sprintf("%.2f", $sysAvg / $count);
		$usrAvg = sprintf("%.2f", $usrAvg / $count);
		$idleAvg = sprintf("%.2f", $idleAvg / $count);
	}
	elsif ($sysname eq "SunOS") {
		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			@current = split(' ', $line);

			push @{$data[0]}, $current[0];	# time
			push @{$data[1]}, 0;			# iowait
			push @{$data[2]}, $current[2];	# sys
			push @{$data[3]}, $current[1];	# usr
			if (defined($opt_f)) {
				push @{$data[4]}, $current[4];	# idle
			}

			$usrAvg += $current[1];
			$sysAvg += $current[2];
			$idleAvg += $current[4];

			$count++;
		}

		$usrAvg = sprintf("%.2f", $usrAvg / $count);
		$sysAvg = sprintf("%.2f", $sysAvg / $count);
		$idleAvg = sprintf("%.2f", $idleAvg / $count);
	}
}

sub ramstat {
	if (-f $ydayFile) {
		@input = `$sar -r -s $hour:$minute:00 -f $ydayFile`;
		push (@input, `$sar -r -f $iFile`);
	} else {
		@input = `$sar -r -f $iFile`;
	}
	
	$rpname = "RAM";
	$file = $rpname."-".$file;

	$colors[0] = [200,0,0];	# used
	$colors[1] = [200,0,200];	# buffer
	$colors[2] = [0,200,0];	# cache
	$colors[3] = [0,100,200];	# free

	if ($sysname eq "Linux") {
		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			@current = split(' ', $line);

			push @{$data[0]}, $current[0];	# time
			if (defined($opt_a)) {
				#Remove cache from used ram and draw it above used ram.
				push @{$data[1]}, $current[2] - $current[5];	# used ((Sys used + buffers) - Cache)
				push @{$data[2]}, $current[4];	# buffer
				push @{$data[3]}, $current[2];	# cache (ram used)
				
				if (defined($opt_f)) {
					push @{$data[4]}, $current[2] + $current[1];	# free
				}
				
				$usedAvg += $current[2] - $current[5];
			} else {
				#Draw cache as used ram.
				push @{$data[1]}, $current[2];	# used
				push @{$data[2]}, $current[4];	# buffer
				push @{$data[3]}, $current[5];	# cache
				
				if (defined($opt_f)) {
					push @{$data[4]}, $current[1];	# free
				}
				
				$usedAvg += $current[2];
			}
			


			$bufferAvg += $current[4];
			$cacheAvg += $current[5];
			$freeAvg += $current[1];

			$count++;
		}

		$usedAvg = sprintf("%.2f", $usedAvg / $count);
		$bufferAvg = sprintf("%.2f", $bufferAvg / $count);
		$cacheAvg = sprintf("%.2f", $cacheAvg / $count);
		$freeAvg = sprintf("%.2f", $freeAvg / $count);
		
	}
	elsif ($sysname eq "SunOS") {
		# You can do the same with 7 lines of code on GNU/Linux :-)

		my $pagesize = `/usr/bin/pagesize`;

		my @prtinput = `/usr/sbin/prtconf`;
		my $memsize;
		my $memfree;
		my $memused;

		my @swapinput = split(' ', `/usr/sbin/swap -s`);
		my $swapsize = $swapinput[1];
		$swapsize =~ tr/[0-9]//cd;
		$swapsize = int($swapsize / (1024 ** 2));	# GByte

		my $swapfree;
		my $swapused;

		my @tmp;

		foreach my $memline (@prtinput) {
			if ($memline =~ /Memory size/) {
				@tmp = split(' ', $memline);
				$memsize = int($tmp[2] / 1024);	# GByte
			}
		}

		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			@current = split(' ', $line);

			$memfree = ($current[1] * $pagesize) / (1024 ** 3);
			$memused = int($memsize - $memfree);
			
			$swapfree = ($current[2] * $pagesize) / (1024 ** 5);
			$swapused = int($swapsize - $swapfree);

			my $memusedpt = int((100 / $memsize) * $memused);

			my $swapusedpt = int((100 / $swapsize) * $swapused);

			push @{$data[0]}, $current[0];	# time
			push @{$data[1]}, $memusedpt;	# mem
			push @{$data[2]}, $swapusedpt;	# swap

			$memAvg += $memusedpt;
			$swapAvg += $swapusedpt;

			$count++;
		}

		$memAvg = sprintf("%.2f", $memAvg / $count);
		$swapAvg = sprintf("%.2f", $swapAvg / $count);
	}
}

sub swapstat {
	if (-f $ydayFile) {
		@input = `$sar -S -s $hour:$minute:00 -f $ydayFile`;
		push (@input, `$sar -S -f $iFile`);
	} else {
		@input = `$sar -S -f $iFile`;
	}
	
	$rpname = "SWAP";
	$file = $rpname."-".$file;

	$colors[0] = [200,0,0];	# used
	$colors[1] = [0,200,0];	# cached
	$colors[2] = [0,100,200];	# free

	if ($sysname eq "Linux") {
		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			@current = split(' ', $line);

			push @{$data[0]}, $current[0];	# time
			if (defined($opt_a)) {
				push @{$data[1]}, $current[2] - $current[4];	# used - cached
				push @{$data[2]}, $current[2];	# cached
				if (defined($opt_f)) {
					push @{$data[3]}, $current[2] + $current[1];	# free
				}
			} else {
				push @{$data[1]}, $current[2];	# used
				push @{$data[2]}, $current[4];	# cached
				if (defined($opt_f)) {
					push @{$data[3]}, $current[1];	# free
				}
			}

			$usedAvg += $current[2];
			$cacheAvg += $current[4];
			$freeAvg += $current[1];

			$count++;
		}

		$usedAvg = sprintf("%.2f", $usedAvg / $count);
		$cacheAvg = sprintf("%.2f", $cacheAvg / $count);
		$freeAvg = sprintf("%.2f", $freeAvg / $count);
	} else {
		die "Sorry, swap statistics are working only for GNU/Linux at the moment...\n";
	}
}

sub netstat {
	if (-f $ydayFile) {
		@input = `$sar -n DEV -s $hour:$minute:00 -f $ydayFile`;
		push (@input, `$sar -n DEV -f $iFile`);
	} else {
		@input = `$sar -n DEV -f $iFile`;
	}

	$rpname = "NET $opt_n";
	$file = "$opt_n-".$file;

	my @hysteresis = ( 0, 0, 0,  0,  0, 0, 0 );

	if ($sysname eq "Linux") {
		foreach my $line (@input) {
			chomp($line);

			next if ($line =~ /^$|^\D|\D$/);

			if (($line =~ /$opt_n/) and ($line =~ /^\d/)) {
				@current = split(' ', $line);

				if (defined($opt_t) && is_numeric($opt_t)) {
					$hysteresis[0] = (($current[2] - $hysteresis[0]) / $opt_t) + $hysteresis[0];  # rxpck/s
					$hysteresis[1] = (($current[3] - $hysteresis[1]) / $opt_t) + $hysteresis[1];  # txpck/s
					$hysteresis[2] = (($current[4] - $hysteresis[2]) / $opt_t) + $hysteresis[2];  # rxkB/s
					$hysteresis[3] = (($current[5] - $hysteresis[3]) / $opt_t) + $hysteresis[3];  # txkB/s
					$hysteresis[4] = (($current[6] - $hysteresis[4]) / $opt_t) + $hysteresis[4];  # rxcmp/s
					$hysteresis[5] = (($current[7] - $hysteresis[5]) / $opt_t) + $hysteresis[5];  # txcmp/s
					$hysteresis[6] = (($current[8] - $hysteresis[6]) / $opt_t) + $hysteresis[6];  # rxmcst/s
					
					push @{$data[0]}, $current[0];  # time
					push @{$data[1]}, $hysteresis[0];  # rxpck/s
					push @{$data[2]}, $hysteresis[1];  # txpck/s
					push @{$data[3]}, $hysteresis[2];  # rxkB/s
					push @{$data[4]}, $hysteresis[3];  # txkB/s
					push @{$data[5]}, $hysteresis[4];  # rxcmp/s
					push @{$data[6]}, $hysteresis[5];  # txcmp/s
					push @{$data[7]}, $hysteresis[6];  # rxmcst/s
				} else {
					push @{$data[0]}, $current[0];  # time
					push @{$data[1]}, $current[2];  # rxpck/s
					push @{$data[2]}, $current[3];  # txpck/s
					push @{$data[3]}, $current[4];  # rxkB/s
					push @{$data[4]}, $current[5];  # txkB/s
					push @{$data[5]}, $current[6];  # rxcmp/s
					push @{$data[6]}, $current[7];  # txcmp/s
					push @{$data[7]}, $current[8];  # rxmcst/s
				}

				$rxPcksAvg += $current[2];
				$txPcksAvg += $current[3];
				$rxKBsAvg += $current[4];
				$txKBsAvg += $current[5];
				$rxCmpsAvg += $current[6];
				$txCmpsAvg += $current[7];
				$rxMcstsAvg += $current[8];

				$count++;
			}
		}
		
		$rxPcksAvg = sprintf("%.2f", $rxPcksAvg / $count);
		$txPcksAvg = sprintf("%.2f", $txPcksAvg / $count);
		$rxKBsAvg = sprintf("%.2f", $rxKBsAvg / $count);
		$txKBsAvg = sprintf("%.2f", $txKBsAvg / $count);
		$rxCmpsAvg = sprintf("%.2f", $rxCmpsAvg / $count);
		$txCmpsAvg = sprintf("%.2f", $txCmpsAvg / $count);
		$rxMcstsAvg = sprintf("%.2f", $rxMcstsAvg / $count);
	}
	else {
		die "Sorry, net statistics are working only for GNU/Linux at the moment...\n";
	}
}

if (defined($opt_u)) {
	cpustat();
	@legend = ("IOWait (Avg: $iowAvg)", "Sys (Avg: $sysAvg)", "Usr (Avg: $usrAvg)");
	if (defined($opt_f)) {
		push @legend, "Idle (Avg: $idleAvg)";
	}

}
elsif (defined($opt_r)) {
	ramstat();
	if ($sysname eq "Linux") {
		@legend = ("RAM (Avg: $usedAvg)", "Buffers (Avg: $bufferAvg)", "Cached (Avg: $cacheAvg)");
		if (defined($opt_f)) {
			push @legend, "Free (Avg: $freeAvg)";
		}
	} else {
		@legend = ("RAM (Avg: $memAvg)", "Swap (Avg: $swapAvg)");
	}
}
elsif (defined($opt_w)) {
	swapstat();
	@legend = ("SWAP (Avg: $usedAvg)", "Cached (Avg: $cacheAvg)");
	if (defined($opt_f)) {
		push @legend, "Free (Avg: $freeAvg)";
	}
}
elsif (defined($opt_n)) {
	netstat();
	@legend = ("rxpck/s (Avg: $rxPcksAvg)", "txpck/s (Avg: $txPcksAvg)", "rxkB/s (Avg: $rxKBsAvg)", "txkB/s (Avg: $txKBsAvg)", "rxcmp/s (Avg: $rxCmpsAvg)", "txcmp/s (Avg: $txCmpsAvg)", "rxmcst/s (Avg: $rxMcstsAvg)");
}
else {
	usage();
}

if ( (defined($opt_x)) && (defined($opt_y)) ) {
	if ( (is_numeric($opt_x)) && (is_numeric($opt_y)) ) {
		$height = $opt_x;
		$width = $opt_y;
	}
}

my $LineDiagram = Chart::Lines->new($width,$height);

$LineDiagram->set('title' => $hostname.": ".$rpname);
$LineDiagram->set('sub_title' => $year."-".$month."-".$day." ".$hour.":".$minute);
$LineDiagram->set('legend' => 'right');
$LineDiagram->set('colors' => { 'background' => [0,0,0], 'text' => [255,255,255], 'grid_lines' => [190,190,190], 'dataset0' => $colors[0], 'dataset1' => $colors[1], 'dataset2' => $colors[2], 'dataset3' => $colors[3] });
$LineDiagram->set('grid_lines' => 'true');
$LineDiagram->set('x_ticks' => 'vertical');
$LineDiagram->set('brush_size' => 4);
$LineDiagram->set('precision' => 1);
$LineDiagram->set('legend_labels' => \@legend);

if (defined($opt_s)) {
	if (is_numeric($opt_s)) {
		$LineDiagram->set('skip_x_ticks' => $opt_s);
	}
}

if (defined($opt_o)) {
	#$file = $opt_o.$file;
	$file = $opt_o;
}

$LineDiagram->png($file, \@data) or die "Error: $!\n";	# build the png
