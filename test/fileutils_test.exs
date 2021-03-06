# Copyright 2015 Michael Jochimsen
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule FileUtilsTest do
  use ExUnit.Case
  use Bitwise

  setup context do
    unless context[:no_workdir] do
      workdir = Path.join(System.tmp_dir, "#{context[:case]}:#{context[:line]}")
      File.mkdir!(workdir)
      on_exit(fn -> File.rm_rf(workdir) end)
      {:ok, workdir: workdir}
    else
      :ok
    end
  end

  test "creating a tree of files", context do
    workdir = context[:workdir]

    fox_path = Path.join(workdir, "fox")
    the1_path = Path.join(fox_path, "the")
    quick_path = Path.join(fox_path, "quick")
    brown_path = Path.join(fox_path, "brown")
    jumps_path = Path.join(workdir, "jumps")
    over_path = Path.join(workdir, "over")
    dog_path = Path.join(over_path, "dog")
    the2_path = Path.join(dog_path, "the")
    lazy_path = Path.join(dog_path, "lazy")

    # Make sure we can clean up the working directory behind us.
    on_exit(fn -> File.chmod(fox_path, 0o700) end)

    assert FileUtils.install_file_tree(workdir, [
      {"fox", 0o500, [
        {"the", 0o400, "article"},
        {"quick", "adjective"},
        {"brown", "adjective"},
      ]},
      {"jumps", []},
      {"over", [
        {"dog", [
          {"the", 0o400, "article"},
          {"lazy", "adjective"},
        ]},
      ]},
    ]) == :ok

    assert File.dir?(fox_path)
    assert File.ls!(fox_path) == ["brown", "quick", "the"]
    assert {:ok, stat} = File.stat(fox_path)
    assert (stat.mode &&& 0o777) == 0o500

    assert File.regular?(the1_path)
    assert File.read!(the1_path) == "article"
    assert {:ok, stat} = File.stat(the1_path)
    assert (stat.mode &&& 0o777) == 0o400

    assert File.regular?(quick_path)
    assert File.read!(quick_path) == "adjective"
    assert {:ok, stat} = File.stat(quick_path)
    assert (stat.mode &&& 0o777) == 0o644

    assert File.regular?(brown_path)
    assert File.read!(brown_path) == "adjective"
    assert {:ok, stat} = File.stat(brown_path)
    assert (stat.mode &&& 0o777) == 0o644

    assert File.dir?(jumps_path)
    assert File.ls!(jumps_path) == []
    assert {:ok, stat} = File.stat(jumps_path)
    assert (stat.mode &&& 0o777) == 0o755

    assert File.dir?(over_path)
    assert File.ls!(over_path) == ["dog"]
    assert {:ok, stat} = File.stat(over_path)
    assert (stat.mode &&& 0o777) == 0o755

    assert File.dir?(dog_path)
    assert File.ls!(dog_path) == ["lazy", "the"]
    assert {:ok, stat} = File.stat(dog_path)
    assert (stat.mode &&& 0o777) == 0o755

    assert File.regular?(the2_path)
    assert File.read!(the2_path) == "article"
    assert {:ok, stat} = File.stat(the2_path)
    assert (stat.mode &&& 0o777) == 0o400

    assert File.regular?(lazy_path)
    assert File.read!(lazy_path) == "adjective"
    assert {:ok, stat} = File.stat(lazy_path)
    assert (stat.mode &&& 0o777) == 0o644
  end

  test "creating a file (or directory) twice results in error", context do
    workdir = context[:workdir]

    assert FileUtils.install_file_tree(workdir, [
      {"hello", ""},
      {"hello", ""},
    ]) == {:error, :eexist, "hello"}

    assert FileUtils.install_file_tree(workdir, [
      {"world", []},
      {"world", []},
    ]) == {:error, :eexist, "world"}

    assert FileUtils.install_file_tree(workdir, [
      {"over", [
        {"dog", [
          {"brown", ""}
        ]},
        {"dog", [
          {"black", ""}
        ]},
      ]},
    ]) == {:error, :eexist, "over/dog"}
  end

  test "failure to create the root directory results in an error", context do
    workdir = context[:workdir]
    rod = Path.join(workdir, "read_only_dir")
    install_dir = Path.join(rod, "install_dir")

    File.mkdir(rod)
    File.chmod(rod, 0o500)

    assert FileUtils.install_file_tree(install_dir, [
      {"hello", ""}
    ]) == {:error, :eacces, ""}
  end

  test "that an invalid file tree description results in an error", context do
    workdir = context[:workdir]

    assert FileUtils.install_file_tree(workdir, [
      {:goodbye, :cruel, :world}
    ]) == {:error, :badarg, {:goodbye, :cruel, :world}}

    assert FileUtils.install_file_tree(workdir, [
      {"foo"}
    ]) == {:error, :badarg, {"foo"}}

    assert FileUtils.install_file_tree(workdir, [
      "foo"
    ]) == {:error, :badarg, "foo"}
  end

  test "that out of range permissions result in an error", context do
    workdir = context[:workdir]

    assert FileUtils.install_file_tree(workdir, [
      {"foo", 0o1000, "bar"}
    ]) == {:error, :badarg, {"foo", 0o1000, "bar"}}

    assert FileUtils.install_file_tree(workdir, [
      {"foo", -1, "bar"}
    ]) == {:error, :badarg, {"foo", -1, "bar"}}
  end

  test "that lstat/2 gets information about files and directories", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    dir = Path.join(workdir, "dir")

    File.write!(file, "")
    File.mkdir!(dir)

    assert FileUtils.lstat(file) == File.stat(file)
    assert FileUtils.lstat(dir) == File.stat(dir)
  end

  test "that lstat/2 gets information about a link", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    dir = Path.join(workdir, "dir")
    link_file = Path.join(workdir, "link_file")
    link_dir = Path.join(workdir, "link_dir")

    File.write!(file, "")
    File.ln_s(file, link_file)
    File.mkdir!(dir)
    File.ln_s(dir, link_dir)

    file_stat = File.stat!(file)
    assert {:ok, lstat} = FileUtils.lstat(link_file)
    assert lstat.size > 0
    assert lstat.type == :symlink
    assert lstat.access == file_stat.access
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.atime
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.mtime
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.ctime
    assert lstat.mode > 0
    assert lstat.links == 1
    assert lstat.major_device == file_stat.major_device
    assert lstat.minor_device == file_stat.minor_device
    assert lstat.inode >= 0
    assert lstat.uid == file_stat.uid
    assert lstat.gid == file_stat.gid

    dir_stat = File.stat!(dir)
    assert {:ok, lstat} = FileUtils.lstat(link_dir)
    assert lstat.size > 0
    assert lstat.type == :symlink
    assert lstat.access == dir_stat.access
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.atime
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.mtime
    assert {{_y, _mon, _d}, {_h, _min, _s}} = lstat.ctime
    assert lstat.mode > 0
    assert lstat.links == 1
    assert lstat.major_device == dir_stat.major_device
    assert lstat.minor_device == dir_stat.minor_device
    assert lstat.inode >= 0
    assert lstat.uid == dir_stat.uid
    assert lstat.gid == dir_stat.gid
  end

  test "that time options for lstat/2 work", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    link = Path.join(workdir, "link")

    File.ln_s(file, link)

    assert {:ok, %File.Stat{ctime: local_time}} = FileUtils.lstat(link, time: :local)
    universal_time = :erlang.localtime_to_universaltime(local_time)
    posix_time = :erlang.universaltime_to_posixtime(universal_time)

    assert {:ok, lstat} = FileUtils.lstat(link, time: :local)
    assert lstat.ctime == local_time
    assert lstat.mtime == local_time
    assert lstat.atime == local_time

    assert {:ok, lstat} = FileUtils.lstat(link, time: :universal)
    assert lstat.ctime == universal_time
    assert lstat.mtime == universal_time
    assert lstat.atime == universal_time

    assert {:ok, lstat} = FileUtils.lstat(link, time: :posix)
    assert lstat.ctime == posix_time
    assert lstat.mtime == posix_time
    assert lstat.atime == posix_time
  end

  test "error conditions in lstat/2", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    link = Path.join(workdir, "link")
    missing = Path.join(workdir, "missing")

    File.ln_s(file, link)

    assert FileUtils.lstat(missing) == {:error, :enoent}
    assert FileUtils.lstat(link, time: :fantasy) == {:error, :badarg}
  end

  test "that lstat!/2 returns information about a link", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    dir = Path.join(workdir, "dir")
    link_file = Path.join(workdir, "link_file")
    link_dir = Path.join(workdir, "link_dir")

    File.write!(file, "")
    File.ln_s(file, link_file)
    File.mkdir!(dir)
    File.ln_s(dir, link_dir)

    {:ok, lstat} = FileUtils.lstat(link_file)
    assert FileUtils.lstat!(link_file) == lstat

    {:ok, lstat} = FileUtils.lstat(link_dir)
    assert FileUtils.lstat!(link_dir) == lstat
  end

  test "that the time options for lstat!/2 work", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    link = Path.join(workdir, "link")

    File.ln_s(file, link)

    {:ok, %File.Stat{ctime: local_time}} = FileUtils.lstat(link, time: :local)
    universal_time = :erlang.localtime_to_universaltime(local_time)
    posix_time = :erlang.universaltime_to_posixtime(universal_time)

    lstat = FileUtils.lstat!(link, time: :local)
    assert lstat.ctime == local_time
    assert lstat.mtime == local_time
    assert lstat.atime == local_time

    lstat = FileUtils.lstat!(link, time: :universal)
    assert lstat.ctime == universal_time
    assert lstat.mtime == universal_time
    assert lstat.atime == universal_time

    lstat = FileUtils.lstat!(link, time: :posix)
    assert lstat.ctime == posix_time
    assert lstat.mtime == posix_time
    assert lstat.atime == posix_time
  end

  test "error conditions in lstat!/2", context do
    workdir = context[:workdir]

    file = Path.join(workdir, "file")
    link = Path.join(workdir, "link")
    missing = Path.join(workdir, "missing")

    File.ln_s(file, link)

    assert_raise File.Error, "could not read file stats #{missing}: no such file or directory", fn ->
      FileUtils.lstat!(missing)
    end
    assert_raise File.Error, "could not read file stats #{link}: bad argument", fn ->
      FileUtils.lstat!(link, time: :fantasy)
    end
  end

  test "walking a basic directory tree", context do
    workdir = context[:workdir]

    fox_path = Path.join(workdir, "fox")
    the1_path = Path.join(fox_path, "the")
    quick_path = Path.join(fox_path, "quick")
    brown_path = Path.join(fox_path, "brown")
    jumps_path = Path.join(workdir, "jumps")
    over_path = Path.join(workdir, "over")
    dog_path = Path.join(over_path, "dog")
    the2_path = Path.join(dog_path, "the")
    lazy_path = Path.join(dog_path, "lazy")

    FileUtils.install_file_tree(workdir, [
      {"fox", [
        {"the", 0o400, "article"},
        {"quick", "adjective"},
        {"brown", "adjective"},
      ]},
      {"jumps", []},
      {"over", [
        {"dog", [
          {"the", 0o400, "article"},
          {"lazy", "adjective"},
        ]},
      ]},
    ])

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir)
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir)   },
      {fox_path,   File.stat!(fox_path)  },
      {brown_path, File.stat!(brown_path)},
      {quick_path, File.stat!(quick_path)},
      {the1_path,  File.stat!(the1_path) },
      {jumps_path, File.stat!(jumps_path)},
      {over_path,  File.stat!(over_path) },
      {dog_path,   File.stat!(dog_path)  },
      {lazy_path,  File.stat!(lazy_path) },
      {the2_path,  File.stat!(the2_path) },
    ]
  end

  test "walking multiple directory trees", context do
    workdir = context[:workdir]

    fox_path = Path.join(workdir, "fox")
    the1_path = Path.join(fox_path, "the")
    quick_path = Path.join(fox_path, "quick")
    brown_path = Path.join(fox_path, "brown")
    jumps_path = Path.join(workdir, "jumps")
    over_path = Path.join(workdir, "over")
    dog_path = Path.join(over_path, "dog")
    the2_path = Path.join(dog_path, "the")
    lazy_path = Path.join(dog_path, "lazy")

    FileUtils.install_file_tree(workdir, [
      {"fox", [
        {"the", 0o400, "article"},
        {"quick", "adjective"},
        {"brown", "adjective"},
      ]},
      {"jumps", []},
      {"over", [
        {"dog", [
          {"the", 0o400, "article"},
          {"lazy", "adjective"},
        ]},
      ]},
    ])

    assert {:ok, stream} = FileUtils.path_tree_walk([over_path, jumps_path, fox_path])
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {fox_path,   File.stat!(fox_path)  },
      {brown_path, File.stat!(brown_path)},
      {quick_path, File.stat!(quick_path)},
      {the1_path,  File.stat!(the1_path) },
      {jumps_path, File.stat!(jumps_path)},
      {over_path,  File.stat!(over_path) },
      {dog_path,   File.stat!(dog_path)  },
      {lazy_path,  File.stat!(lazy_path) },
      {the2_path,  File.stat!(the2_path) },
    ]
  end

  test "walking a directory tree with :symlink_stat", context do
    workdir = context[:workdir]

    file_path = Path.join(workdir, "file")
    link_path = Path.join(workdir, "link")

    File.write!(file_path, "")
    File.ln_s(file_path, link_path)

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir, symlink_stat: false)
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir)  },
      {file_path,  File.stat!(file_path)},
      {link_path,  File.stat!(link_path)},
    ]

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir, symlink_stat: true)
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir)        },
      {file_path,  File.stat!(file_path)      },
      {link_path,  FileUtils.lstat!(link_path)},
    ]
  end

  test "alternate time formats for path_tree_walk/2", context do
    workdir = context[:workdir]

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir, time: :local)
    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir, time: :local)},
    ]

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir, time: :universal)
    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir, time: :universal)},
    ]

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir, time: :posix)
    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir, time: :posix)},
    ]
  end

  test "walking a tree with inaccessable direcotories", context do
    workdir = context[:workdir]

    fox_path = Path.join(workdir, "fox")
    jumps_path = Path.join(workdir, "jumps")

    # Make sure we can clean up the working directory behind us.
    on_exit(fn -> File.chmod(fox_path, 0o700) end)

    FileUtils.install_file_tree(workdir, [
      {"fox", 0o000, [
        {"quick", "adjective"},
        {"brown", "adjective"},
      ]},
      {"jumps", []},
    ])

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir)
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir)   },
      {fox_path,   File.stat!(fox_path)  },
      {jumps_path, File.stat!(jumps_path)},
    ]
  end

  test "walking a tree with invalid files", context do
    workdir = context[:workdir]

    file_path = Path.join(workdir, "file")
    link_path = Path.join(workdir, "link")

    File.ln_s(file_path, link_path)

    assert {:ok, stream} = FileUtils.path_tree_walk(workdir)
    assert is_function(stream)

    assert Enum.take(stream, 99) == [
      {workdir,    File.stat!(workdir)   },
    ]
  end

  test "handling of invalid path_tree_walk/2 options", context do
    workdir = context[:workdir]

    assert FileUtils.path_tree_walk(workdir, time: :mythical) == {:error, :badarg}
    assert FileUtils.path_tree_walk(workdir, symlink_stat: 0) == {:error, :badarg}
  end

end
