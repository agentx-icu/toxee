import 'dart:convert';

/// The longest group name Tox accepts, in UTF-8 BYTES (not characters: 17 CJK
/// characters or 13 emoji already exceed an NGC group's 48).
///
/// TOX_GROUP_MAX_GROUP_NAME_LENGTH for an NGC group; a legacy conference's
/// title is bounded by TOX_MAX_NAME_LENGTH. One rule for creating a group
/// (add_group_dialog.dart) and renaming it (group_name_edit_dialog.dart).
int maxGroupNameBytes({required bool conference}) => conference ? 128 : 48;

/// Whether [name] is over [maxGroupNameBytes] for that kind of group.
bool groupNameTooLong(String name, {required bool conference}) =>
    utf8.encode(name).length > maxGroupNameBytes(conference: conference);
