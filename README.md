FileUtils
=========

File utilities for Elixir. This is a collection of utilities, some of which
should probably be in the standard library but aren't.

  * `lstat/2`
  * `install_file_tree/2`
  * `path_tree_walk/2`

Installation
------------

Add `FileUtils` to your project's dependencies in `mix.exs`:

    defp deps do
      [
        {:fileutils, github: "mjochimsen/fileutils_ex", tag: "v0.1.1"}
      ]
    end

Then fetch your project's dependencies:

    $ mix deps.get

Usage
-----

### `lstat/2`

This function works just like `File.stat/2`, but if the file at the path is a
symbolic link then the function returns information for the link instead of
for the file it points to. Like `File.stat/2`, there is a `:time` option which
can be set to `:local`, `:universal`, or `:posix` to control the format of the
`atime`, `ctime`, and `mtime` results.

### `install_file_tree/2` 

This function can be used to write an entire tree of files to a file system,
with the ability to set the permissions of each file or directory in the tree.
It can be particularly useful for installing configuration files or test data.

### `path_tree_walk/2`

This function walks one or more directory trees depth first, returning the
path and a `File.Stat` structure for each file in the tree. Files are always
returned in sorted order. The `:time` option sets the format of the time in
used in the stat structure (just like `lstat/2`), while the `:symlink_stat`
option controls whether the stat structure for symbolic links is for the link
or the file referenced by the link.

License
-------

Copyright © 2015 Michael Jochimsen.

This work is open source. It can be used or redistributed under the terms of
the Apache License, Version 2.0. See the LICENSE file for details.
