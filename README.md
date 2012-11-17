#MultiDiff

A perl script to identify line differences between several closely related text files.

Files to compare can either be passed in individually:

    $multi_diff.pl files/file1 files/file2 files/file3

... or described in a text file:

    $cat filelist.txt
    files/file1
    files/file2
    files/file3
    $multi_diff.pl filelist.txt

The output is an html file named diff_output.html. Lines are assigned to groups based on their similarity. Hovering over the group number for a line in a file will show the text of that line in the tooltip.
