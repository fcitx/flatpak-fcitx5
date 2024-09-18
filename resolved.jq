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
    downloaded_file_path: (
      .attributes.downloaded_file_path // null
    )
  } |
  select(.url != "") |
  {
    type: "file",
    url: .url,
    dest: "bazel-deps",
    "dest-filename": (
        .downloaded_file_path // .url | split("/") | last
    ),
    sha256: .sha256
  }
]

