#!/usr/bin/perl

use warnings;
use strict;

use Carp;
use Cwd;
use File::Basename;

###############################
# Compare multiple files together.
# Output single file as HTML with coloured lines to indicate amount of similarity.
# Anchor tags can be used to jump to the file that is least similar.
###############################

my @filenames;
my @filehandles;
my @fileLines;	# Array of arrays

my @results;
my $H_OUTPUT;

# User supplies a list of files to compare.
@filenames = getFilenames(@ARGV);

# Each file is opened simultaneously.
foreach my $filename (@filenames){
	push(@filehandles, openFile($filename));
}


# Files are read line by line.
@fileLines = slurpFiles(@filehandles);
for(0..@filehandles-1){	# Short version of for loop (actually foreach). $_ gets set to a number used to reference both filenames and filehandles arrays.
	close($filehandles[$_]) or die "Failed to close $filenames[$_]: $!\n";
}

# Lines are scored as a percentage of lines being identical.
@results = compareLines(@fileLines);

# The most common line is written to a new HTML file and colour coded based on % match.
open($H_OUTPUT,'>','diff_output.html') or die "Failed to open diff_output.html for writing: $!\n";
formatResults(\@results, \@filenames, $H_OUTPUT);

# Finish
close($H_OUTPUT) or die "Failed to close diff_output.html after writing: $!\n";


##############
##############

# Want to have all the files being read at the same time for comparison.
sub slurpFiles{
	my @handles = @_;
	my @files;
	
	foreach my $handle (@handles){
		my @lines = <$handle>;
		# If there is only one line, check that we're looking for the right kind of line break
		if (@lines == 1){
			@lines = split(/\r/, $lines[0]);
		}
		
		push(@files, [@lines]);
	}
	
	print("Slurped ",scalar(@files)," files.\n"); 
	
	return @files;
}

sub formatResults{
	my $resultsRef = $_[0];
	my @results = @$resultsRef;
	my $namesRef = $_[1];
	my @filenames = @$namesRef;
	my $H_OUTPUT = $_[2];
	
	my $styleSheet = <<"END_STYLE";
	.mono{
		font-family:"monospace";
	}
	.centered{
		text-align:center;
	}
	
	.group0{
		background-color:#FFF;
	}
	.group1{
		background-color:#F00;
	}
	.group2{
		background-color:#0F0;
	}
	.group3{
		background-color:#00F;
	}
	.group4{
		background-color:#FF0;
	}
	.group5{
		background-color:#0FF;
	}
	.group6{
		background-color:#F0F;
	}
END_STYLE
	
	print $H_OUTPUT "<html><head><style type=\"text/css\">$styleSheet</style></head><body><table>";
	my $tableHeaders = '';
	my $fileNum = 0;
	foreach my $filename (@filenames){
		$fileNum++;
		$tableHeaders.= "<th><a href=\"#\" title=\"$filename\">File $fileNum</a></th>";
	}
	print $H_OUTPUT "<tr><th>#</th><th>Most Common</th>$tableHeaders</tr>";
	
	my $currentLine = 0;
	foreach my $lineRef (@results){
		my $topGroupRef = $lineRef->[0];
		my $topLineRef = $topGroupRef->[0];
		my $topLineText = $topLineRef->[1];
		
		$currentLine++;
		
		my $numGroups = scalar(@$lineRef);
		
		my @fileGroupIds;	# For each file, will have a number for the group
		my @lineTexts;	# For each file, get the actual line at this position
		
		# Each line has multiple groups, go through and find out which files are in each one.
		for (0..$numGroups-1){
			my $groupNumber = $_;
			my $groupRef = $lineRef->[$groupNumber];
			my @group = @$groupRef;
			foreach my $entryRef (@group){
				my $fileId = $entryRef->[0];
				my $lineText = $entryRef->[1];
				#print ("Extracted: $fileId $lineText");
				$fileGroupIds[$fileId] = $groupNumber;
				$lineTexts[$fileId] = $lineText;
			}
		}
		
		print $H_OUTPUT "<tr><td>$currentLine</td><td class=\"mono\">$topLineText</td>";
		for (0..@fileGroupIds-1){
			$lineTexts[$_] =~s/"/'/g; #"
			print $H_OUTPUT "<td class=\"centered group$fileGroupIds[$_]\"><a href=\"#1\" alt=\"$lineTexts[$_]\" title=\"$lineTexts[$_]\">$fileGroupIds[$_]</a></td>";
		}
#		foreach my $groupId (@fileGroupIds){
#			print $H_OUTPUT "<td><a href=\"#1\" alt=\"Text\" >$groupId</a></td>";
#		}
		print $H_OUTPUT "</tr>";
	}
	
	print $H_OUTPUT "</table></body></html>";
}

sub compareLines{
	my @files = @_;
	
	my @outputLines;
	
	my $maxLines = countLines(@files);
	
	# Go through one line at a time, checking that position across all files simultaneously.
	for (0..$maxLines-1){
		my $lineNum = $_;
		
		# Get references to that line of each file (empty string if line doesn't exist).
		my @currentLines = getCurrentLines($lineNum, \@files);
		
		# Sort the lines
		my @sortedLines = sortLines(@currentLines);
		#map {print($_->[0],": ",$_->[1]);} @sortedLines;	# This is just printing the multidimensional array
		
		# Work out which ones are identical to each other. (eg AAA BBB C, would be 3 files the same, another 3 files same as each other, 1 is different).
		my @lineGroups = groupLines(@sortedLines);
		
		push(@outputLines, \@lineGroups);
	}
	return @outputLines;
}

sub groupLines{
	my @lines = @_;
	my $numLines = scalar(@lines);
	
	my @groups;

	my $currentGroupIndex = 0;
	my $currentGroupString = $lines[0][1];
	
	for (my $i = 0; $i < $numLines; $i++){
		print("Grouping line $i\n");
		my $lineArrayRef = $lines[$i];
		if ($lineArrayRef->[1] ne $currentGroupString){
			$currentGroupIndex++;
			$currentGroupString = $lineArrayRef->[1];
			print("Line $i belongs in new group.\n");
		}
		# Add line object to current group.
		my $groupRef = $groups[$currentGroupIndex];
		my @group;
		if ($groupRef){
			print("Line $i continues existing group.\n");
			@group = @$groupRef;
		}
		push(@group, $lineArrayRef);
		$groups[$currentGroupIndex] = \@group; 		
	}
	
	my @sortedGroups = sort {scalar(@$b) <=> scalar(@$a)} @groups;	#Put most common group first
		
	return @sortedGroups;
}

sub sortLines{
	my @lines = @_;
	my $numLines = scalar(@lines);
	
	my @numberedLines;
	for (my $i = 0; $i < $numLines; $i++){
		my @entry = ($i, $lines[$i]);
		push(@numberedLines, \@entry);	#Add as array reference
	}

	my @sortedLines = sort {$a->[1] cmp $b->[1]} @numberedLines;
	
	return @sortedLines;
}

sub getCurrentLines{

	my $lineNum = $_[0];
	my $filesRef = $_[1];
	my @files = @$filesRef;
	
	my @lines = map {@$_[$lineNum] || ''} @files;	# Pull out the appropriate line from each file. If the file isn't that long, add an empty string.
	
	return @lines;
}

sub countLines{
	my @files = @_;
	
	my $numFiles = scalar(@files);
	my $maxLines = 0;
	
	print("Comparing lines from $numFiles files.\n");
	for (0..$numFiles-1){
		my $fileReference = $files[$_];
		my @file = @$fileReference;	# Deference the array.
		my $fileLength = scalar(@file);
		print("File contains ",$fileLength," lines.\n"); 
		
		if ($maxLines < $fileLength){
			$maxLines = $fileLength;
		}
	}
	return $maxLines;
}

# If there are several arguments, return them all in an array.
# If there is just one argument, check if it points to a file.
# If it is a file, return an array of each line in the file.
sub getFilenames{
	my @filenames;
	if (@_ == 0){
		croak "Run with no arguments.\n";
	} elsif (@_ == 1){
		print "Run with one argument.\n";
		@filenames = getFilenamesFromFile(@_);
	} else {
		print "Run with multiple arguments.\n";
		@filenames = @_;
		print @filenames;
	}
	
	return @filenames;
}

sub getFilenamesFromFile{
	my $listFile = $_[0];
	my $H_LISTFILE = openFile($listFile);
	
	my @filelist;
	
	while(my $line = <$H_LISTFILE>){
		chomp($line);
		unless (-e $line){
			croak "Did not find file '$line' referenced on line $. of $listFile.\n";
		}
		push(@filelist, $line);
	}
	
	close($H_LISTFILE) or croak "Unable to close $listFile after reading: $!\n";
	
	return @filelist;
}

sub openFile{
	my $file = $_[0];
	unless (-e $file){
		croak "Did not find the list file.\n";
	}
	
	my $cwd = cwd();
	
	my($filename, $directory) = fileparse($file);
	
	chdir($directory) or croak "Failed to change to $directory: $!\n";
	open(my $FH, '<', $filename) or croak "Failed to open file $file for reading: $!\n";
	chdir($cwd) or croak "Failed to return to working directory: $!\n";
	
	return $FH;
}