defmodule FileUtils do

  @type posix :: :file.posix
  @type badarg :: {:error, :badarg}

  defp validate_opt({:error, _reason} = error, _opt, _validate), do: error
  defp validate_opt(opts, opt, validate) do
    if validate.(opts[opt]), do: opts, else: {:error, :badarg}
  end

  @doc """
  Create a tree of file / directory specifications under the given root. Each
  file / directory has a name and and optional permission (default permissions
  are `0o755` for directories and `0o644` for files). Files also contain a
  binary which is written to the newly created file. Directories contain a list
  of additional specifications, which are recursed to build a full directory
  tree.

  Example:

      :ok = install_file_tree(System.tmpdir, [
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

  @doc """
  Same as `lstat/2`, but returns the `File.Stat` directly and throws
  `File.Error` if an error is returned.
  """
  @spec lstat!(Path.t, [lstat_opt]) :: File.Stat.t | no_return
  def lstat!(path, opts \\ []) when is_binary(path) and is_list(opts) do
    case FileUtils.lstat(path, opts) do
      {:ok, info}      -> info
      {:error, reason} ->
        raise File.Error, reason: reason, action: "read file stats", path: path
    end
  end

  @doc """
  Return a stream which walks one or more directory trees. The trees are walked
  depth first, with the directory entries returned in sorted order. Each
  directory entry is returned as a `{path, stat}` tuple, where the path is the
  full path to the entry and the stat is a `File.Stat` struct.

  The following option may be set:

  *  `:symlink_stat`  - If set to `true` then symbolic links will return `stat`
                        information about the link instead of the file object
                        referred to by the link. The default is `false`.

  *  `:time`          - Form of the time data returned in the `File.Stat`
                        struct. This may be one of `:local`, `:universal`, or
                        `:posix`. The default is `:local`.

  If an error occurs while walking the tree (a file node is deleted, a symlink
  is invalid, etc.) then the node with the problem will be skipped.
  """
  @type path_tree_walk_option :: {:symlink_stat, boolean} |
                                 {:time, (:local | :universal | :posix)}
  @spec path_tree_walk([Path.t] | Path.t, [path_tree_walk_option]) :: Enumerable.t
  def path_tree_walk(rootdir, opts \\ [])
      when (is_list(rootdir) or is_binary(rootdir)) and is_list(opts) do
    default_opts = [
      symlink_stat: false,
      time: :local
    ]
    default_opts
    |> Dict.merge(opts)
    |> validate_opt(:symlink_stat, &is_boolean/1)
    |> validate_opt(:time, &(&1 in [:local, :universal, :posix]))
    |> tree_walk_opts_to_funcs
    |> stream_for_tree_walk(rootdir)
  end

  defp tree_walk_opts_to_funcs({:error, _reason} = error), do: error
  defp tree_walk_opts_to_funcs(opts) when is_list(opts) do
    [
      stat: stat_fn(opts[:symlink_stat], opts[:time])
    ]
  end

  defp stat_fn(false, time_fmt), do: &File.stat(&1, time: time_fmt)
  defp stat_fn(true, time_fmt),  do: &lstat(&1, time: time_fmt)

  defp stream_for_tree_walk({:error, _reason} = error, _rootdir), do: error
  defp stream_for_tree_walk(funcs, rootdirs) when is_list(rootdirs) do
    {:ok, Stream.resource(
      fn -> {Enum.sort(rootdirs), funcs} end,
      &path_tree_walk_next/1,
      fn _ -> nil end
    )}
  end
  defp stream_for_tree_walk(funcs, rootdir), do: stream_for_tree_walk(funcs, [rootdir])

  defp path_tree_walk_next({[], funcs}), do: {:halt, {[], funcs}}
  defp path_tree_walk_next({[dir_fn | rest], funcs}) when is_function(dir_fn) do
    {[], {dir_fn.() ++ rest, funcs}}
  end
  defp path_tree_walk_next({[path | rest], funcs}) do
    case funcs[:stat].(path) do
      {:ok, stat} ->
        if File.dir?(path) do
          {[{path, stat}], {[walk_to(path) | rest], funcs}}
        else
          {[{path, stat}], {rest, funcs}}
        end
      {:error, _reason} ->
        {[], {rest, funcs}}
    end
  end

  defp walk_to(path) do
    fn ->
      case File.ls(path) do
        {:ok, filenames} when is_list(filenames) ->
          filenames |> Enum.sort |> Enum.map(&Path.join(path, &1))
        {:error, _reason} -> []
      end
    end
  end

end
