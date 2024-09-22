[
  .[] |
  select(.repositories != null) |
  .repositories[] |
  select(.attributes.name != null) |
  select(.rule_class != null) |
  {
    url: (
      if .attributes.url == "" then
        (.attributes.urls[0] // "")
      else
        (.attributes.url // (.attributes.urls[0] // ""))
      end
    ),
    sha256: (
      .attributes.sha256 // ""
    ),
    remote_patches: (
      .attributes.remote_patches // null
    ),
    patch_args: (
      .attributes.patch_args // null
    ),
    downloaded_file_path: (
      .attributes.downloaded_file_path // null
    ),
  } |
  select(.url != "") |
  {
    type: "file",
    url: .url,
    dest: "bazel-deps",
    } + (
    if .downloaded_file_path != "" and .downloaded_file_path != null then
        { "dest-filename": .downloaded_file_path, } else {} end
    ) + {
    sha256: .sha256,
  }
]

