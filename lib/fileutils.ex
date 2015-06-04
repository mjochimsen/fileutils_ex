defmodule FileUtils do

  @type posix :: :file.posix
  @type badarg :: {:error, :badarg}

  @doc """
  Create a tree of file / directory specifications under the given root. Each
  file / directory has a name and and optional permission (default permissions
  are `0o755` for directories and `0o644` for files). Files also contain a
  binary which is written to the newly created file. Directories contain a list
  of additional specifications, which are recursed to build a full directory
  tree.

  Example:

      :ok = install(System.tmpdir, [
        {"test-data", [
          {"data", <<0, 1, 2, 3, 4>>},
          {"read_only", 0o444, <<4, 3, 2, 1, 0>>},
          {"no_access", 0o000, <<255, 255>>},
          {"subdir", 0o555, [
            {"more_data", "The quick brown fox..."}
          ]}
        ]}
      ])


  If the function succeeds, `:ok` is returned. If it fails then `{:error,
  reason, pathname}` is returned with the reason being a `:posix` reason and the
  pathname being the file / directory which caused the error (minus the root
  directory portion).
  """
  @type entry :: {Path.t, non_neg_integer, binary} |
                 {Path.t, binary} |
                 {Path.t, non_neg_integer, [entry]} |
                 {Path.t, [entry]}
  @type install_tree_error :: {:error, posix, Path.t} | {:error, :badarg, term}
  @spec install_file_tree(Path.t, [entry]) :: :ok | install_tree_error
  def install_file_tree(rootdir, entries) when is_binary(rootdir) and is_list(entries) do
    case File.mkdir_p(rootdir) do
      :ok -> install_entry_list(rootdir, entries) |> trim_error_path(rootdir)
      {:error, reason} -> {:error, reason, ""}
    end
  end

  defp trim_error_path(:ok, _rootdir), do: :ok
  defp trim_error_path({:error, :badarg, _term} = error, _rootdir), do: error
  defp trim_error_path({:error, reason, pathname}, rootdir) do
    {:error, reason, Path.relative_to(pathname, rootdir)}
  end

  defp install_entry_list(_workdir, []), do: :ok
  defp install_entry_list(workdir, [entry | rest]) do
    case install_entry(workdir, entry) do
      :ok -> install_entry_list(workdir, rest)
      {:error, _reason, _pathname} = error -> error
    end
  end

  defp install_entry(workdir, {filename, perm, data}) when is_binary(filename) and perm in 0..0o777 and is_binary(data) do
    pathname = Path.join(workdir, filename)
    install_entry_using_actions(pathname, [
      fn -> File.write(pathname, data, [:exclusive]) end,
      fn -> File.chmod(pathname, perm) end
    ])
  end
  defp install_entry(workdir, {dirname, perm, entries}) when is_binary(dirname) and perm in 0..0o777 and is_list(entries) do
    pathname = Path.join(workdir, dirname)
    install_entry_using_actions(pathname, [
      fn -> File.mkdir(pathname) end,
      fn -> install_entry_list(pathname, entries) end,
      fn -> File.chmod(pathname, perm) end
    ])
  end
  defp install_entry(workdir, {filename, data}) when is_binary(data) do
    install_entry(workdir, {filename, 0o644, data})
  end
  defp install_entry(workdir, {dirname, entries}) when is_list(entries) do
    install_entry(workdir, {dirname, 0o755, entries})
  end
  defp install_entry(_workdir, badarg) do
    {:error, :badarg, badarg}
  end

  defp install_entry_using_actions(pathname, actions, result \\ :ok)
  defp install_entry_using_actions(_pathname, [], :ok), do: :ok
  defp install_entry_using_actions(pathname, [action | rest], :ok) do
    install_entry_using_actions(pathname, rest, action.())
  end
  defp install_entry_using_actions(pathname, _actions, {:error, reason}) do
    {:error, reason, pathname}
  end
  defp install_entry_using_actions(_pathname, _actions, {:error, _reason, _path} = error) do
    error
  end

  @doc """
  Returns information about the path. If it exists, it returns a {:ok, info}
  tuple, where info is a `File.Stat` struct. Returns {:error, reason} with a
  `:file.posix` reason if a failure occurs.

  This is exactly the same operation as `File.stat/2` except in the case where
  the path is a symbolic link. In this circumstance `lstat/2` returns
  information about the link, where `File.stat/2` returns information about the
  file the link references.

  ### Options

  The accepted options are:

  *  `:time` - `:local` | `:universal` | `:posix`; default: `:local`
  """
  @type lstat_opt :: {:time, (:local | :universal | :posix)}
  @spec lstat(Path.t, [lstat_opt]) :: {:ok, File.Stat.t} | {:error, posix} | badarg
  def lstat(path, opts \\ []) when is_binary(path) and is_list(opts) do
    opts = [
      time: :local
    ] |> Dict.merge(opts)
    :file.read_link_info(path, opts) |> lstat_rec_to_struct
  end

  defp lstat_rec_to_struct({:ok, stat_record}) do
    {:ok, File.Stat.from_record(stat_record)}
  end
  defp lstat_rec_to_struct(error), do: error
end
