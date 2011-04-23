#! /usr/bin/perl

# $Header:$

# Handle syscall names which vary in location and available from
# one kernel and architecture to the next.

# Author: Paul Fox
# Date: June 2008

# 26-Jan-2011 PDF Need to generate both i386 and amd64 syscall tables
#                 if this is a 64b kernel, because 64b kernel can run
#                 32b apps.

use strict;
use warnings;

use File::Basename;
use FileHandle;
use Getopt::Long;
use IO::File;
use POSIX;

#######################################################################
#   Command line switches.					      #
#######################################################################
my %opts;

sub main
{
	Getopt::Long::Configure('no_ignore_case');
	usage() unless GetOptions(\%opts,
		'help',
		);

	usage() if ($opts{help});
#	usage() if !$ARGV[0];

	die "\$BUILD_DIR must be defined before running this script" if !$ENV{BUILD_DIR};

	my $ver = `uname -r`;
	chomp($ver);

	foreach my $bits (qw/32 64/) {
#	        my $machine = `uname -m`;
#	        if ($machine =~ /x86_64/) {
#	        	$bits = 64;
#	        } elsif ($machine =~ /i[34567]86/) {
#	        	$bits = 32;
#	        } else {
#	        	die "Unexpected machine: $machine";
#	        }

		my %calls;
		###############################################
		#   OpenSuse bizarreness.		      #
		###############################################
		my $ver2 = $ver;
		$ver2 =~ s/-[a-z]*$//;
	        my @unistd_h_candidates = (
		     # 2.6.9-78.EL
	             "/lib/modules/$ver/build/include/asm-x86_64/ia${bits}_unistd.h",
	             # linux-2.6.15, 2.6.23:
	             "/lib/modules/$ver/build/include/asm/unistd.h",
	             # linux-2.6.26:
	             "/lib/modules/$ver/build/include/asm-x86/unistd_$bits.h",
	             # linux-2.6.28-rc7:
	             "/lib/modules/$ver/build/arch/x86/include/asm/unistd_$bits.h",
		     # Opensuse 11.1 wants this
		     "/usr/src/linux-$ver2/arch/x86/include/asm/unistd_$bits.h",
	             );

	        my $syscall_count = 0;
		my $src_h = '';
	        foreach my $f (@unistd_h_candidates) {
			if (! -e $f) {
				print "(no file: $f)\n";
				next;
			}

			print "Processing: $f\n";
			my $fh = new FileHandle($f);
			if (!$fh) {
				die "Cannot open $f: $!";
			}
			while (<$fh>) {
				next if !/define\s+(__NR[A-Z_a-z0-9]+)\s+(.*)/;
				$calls{$1} = map_define($2, $1, \%calls);
	                        $syscall_count += 1;
			}
			###############################################
			#   We  may  hit  unistd.h  which  in  turn,  #
			#   includes  unistd_32.h or unistd_64.h, so  #
			#   see  if  we  can go for one of the other  #
			#   files, if we got nothing useful.	      #
			###############################################
			$src_h = $f;
	                last if scalar(keys(%calls));
		}

		my $name = $bits == 32 ? "x86" : "x86-64";

		###############################################
		#   Create an empty file, even if we are 32b  #
		#   kernel, and have no 64b syscalls.	      #
		###############################################
		my $dir = dirname($0);
		my $fname = "$ENV{BUILD_DIR}/driver/syscalls-$name.tbl";
		my $fh = new FileHandle(">$fname");

	        # Make sure we've found reasonable number of system calls.
	        # 2.6.15 i386 has 300+, x86_64 has 255
		if ($syscall_count < 200) {
		        warn "mksyscall.pl: [$name] Unable to generate syscall table, syscall_count==$syscall_count, which looks\nsuspiciously too low. Might have misparsed the sys_call_table\n";
			next;
		}

		print "Creating: $fname - ", scalar(keys(%calls)), " entries\n";
		die "Cannot create: $fname -- $!" if !$fh;

		print $fh "/* This file is automatically generated from mksyscall.pl */\n";
		print $fh "/* Source: $src_h */\n";
		print $fh "/* Do not edit! */\n";
		my %vals;
		foreach my $c (keys(%calls)) {
			$vals{$calls{$c}} = $c;
		}
		foreach my $c (sort {$a <=> $b} (keys(%vals))) {
			my $name = $vals{$c};
			$name =~ s/^__NR_//;
			$name =~ s/^ia32_//;
			my $val = $vals{$c};
			print $fh " [$c] = \"$name\",\n";
		}
	}

}
sub map_define
{	my $val = shift;
	my $name = shift;
	my $calls = shift;

	$val =~ s/\s+.*$//;
	return $val if $val =~ /^\d+$/;
	$val =~ s/[()]//g;
	if ($val =~ /^(.*)\+(\d+)/) {
		my ($name, $addend) = ($1, $2);
		return $calls->{$name} + $addend;
	}
	print "$name: unknown value: $val\n";
	return 0;
}
#######################################################################
#   Print out command line usage.				      #
#######################################################################
sub usage
{
	print <<EOF;
mksyscall.pl: Compile up the sys_call_table string entries for the driver.
Usage: mksyscall.pl [x86 | x86-64]
EOF
	exit(1);
}

main();
0;

