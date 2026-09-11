/// Display form of a group's title.
///
/// A group without a name falls back to its 64-hex group ID (callers keep
/// `groupName` equal to `groupID` in that case). Rendered raw at headline size
/// that is ~900 px and overflows every pane, so the fallback is shortened to
/// `8…8` (the same shape `CustomSearch` uses for IDs). A real name is returned
/// untouched — the caller ellipsizes it.
String groupDisplayName(String? name, String groupID) {
  if (name != null && name.isNotEmpty && name != groupID) return name;
  if (groupID.length <= 20) return groupID;
  return '${groupID.substring(0, 8)}…${groupID.substring(groupID.length - 8)}';
}
