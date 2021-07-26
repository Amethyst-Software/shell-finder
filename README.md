# ShellFinder
The two scripts here collect various features that I've needed over the years when I had to manage large numbers of files from the command line. Use the appropriate script to find files by either their name or their contents and then print the results to screen or perform an operation on the files (copy/move/delete). Detailed documentation is obtained by running a script without any arguments, but here are some features of the scripts:

[Find By Name](find_by_name.sh)
- Search by file name, suffix, or a set of suffixes, or inverse-search by these (find all items not matching such a pattern).
- Copy or move files in either flat mode (all files go to a single directory) or mirrored mode (recreate the file tree for the copied/moved files).

[Find By Content](find_by_content.sh)
- Search additively by as many terms as you want.
- Apply negative search terms to subtract from the above results.
- Require hits to be within 'n' lines of each other.
- Show 'n' lines of context before/after each hit.

While I have used all the features in these scripts, they have not been tested by anyone else, so please let me know if you find any issues or have a feature request.

![FBN Preview](https://github.com/Amethyst-Software/shell-finder/blob/main/preview-find_by_content.png)
![FBC Preview](https://github.com/Amethyst-Software/shell-finder/blob/main/preview-find_by_name.jpg)