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

    fox_path = Path.join(workdir, "fox")
    the1_path = Path.join(fox_path, "the")
    quick_path = Path.join(fox_path, "quick")
    brown_path = Path.join(fox_path, "brown")
    jumps_path = Path.join(workdir, "jumps")
    over_path = Path.join(workdir, "over")
    dog_path = Path.join(over_path, "dog")
    the2_path = Path.join(dog_path, "the")
    lazy_path = Path.join(dog_path, "lazy")

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

    # Make sure we can clean up the working directory behind us.
    File.chmod(fox_path, 0o700)
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

end
