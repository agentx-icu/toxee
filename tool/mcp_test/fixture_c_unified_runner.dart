// Unified Fixture C / real-UI two-process runner.
//
// The first layer is intentionally hermetic: manifest parsing, filtering,
// grouping, validation, and dry-run command planning do not launch Toxee. Live
// execution builds on that same plan so the expensive two-process work matches
// the CI-checkable contract.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

const _usage = '''
usage: fixture_c_unified_runner.dart [--tier=non-media|media|all]
       [--class=2proc-l3|2proc-ui] [--id=<script>[,<script>]]
       [--real-ui-scenario=<name>[,<name>]]
       [--real-ui-campaign=<name>[,<name>]] [--include-destructive]
       [--list|--plan-json|--dry-run|--validate-only]
       [--list-real-ui-campaigns]

Hermetic modes:
  --list               print filtered manifest entries
  --plan-json          print the grouped execution plan as JSON
  --dry-run            print the shell commands the live runner would execute
  --validate-only      validate manifest/planning invariants

Live execution:
  (no mode flags)      execute the grouped plan

Real-UI helpers:
  --real-ui-scenario=handshake,message
                       narrow the 2proc-ui plan to the selected scenario list
                       in the exact order provided
  --real-ui-campaign=all-current
                       expand a named merged campaign of compatible real-UI
                       scenarios
  --list-real-ui-campaigns
                       print the built-in reusable real-UI campaign catalog
''';

const _manifestPath = 'tool/mcp_test/fixture_c_manifest.json';
const _pairManifest = 'tool/mcp_test/fixtures/paired_for_e2e_manifest.json';
const _pairJson = 'tool/mcp_test/.multi_instance_runtime/pair.json';
const _defaultRealUiNickA = 'RealUiAlice';
const _defaultRealUiNickB = 'RealUiBob';

const _validTiers = {'non-media', 'media', 'all'};
const _validClasses = {'2proc-l3', '2proc-ui'};
const _validBases = {'paired_for_e2e', 'fresh', 'real-ui'};
const _validRealUiScenarios = {
  'handshake',
  'message',
  'message_burst',
  'group_message',
  'group_create',
  'group_profile_open',
  'group_rename',
  'group_search',
  'group_add_member_open',
  'group_add_member_picker',
  'group_conversation_menu',
  'group_menu_pin_unpin',
  'group_menu_mark_read',
  'group_menu_mark_read_unread',
  'group_menu_delete_confirm',
  'group_clear_history',
  'group_clear_preserves_pin',
  'group_burst',
  'group_member_list',
  'conference_message',
  'handshake_detail',
  'decline',
  'custom_message',
  'call_voice',
  'call_reject',
  // Batch 1 — settings sweep 2 (single-instance, no-friend). The 12 cases are
  // individually runnable; sweep_settings2 chains them on one launch.
  'sweep_settings2',
  'settings_surface_sections',
  'settings_theme_dark',
  'settings_theme_light_back',
  'settings_locale_zh_roundtrip',
  'settings_download_limit_edit',
  'settings_bootstrap_mode_cycle',
  'settings_bootstrap_manual_add_node',
  'settings_bootstrap_manual_remove_node',
  'settings_autologin_toggle_hard',
  'settings_notifsound_toggle_hard',
  'settings_password_mismatch_error',
  'settings_logout_cancel',
};
const _realUiCampaigns = <String, List<String>>{
  // Batch 1 — settings sweep 2 (the whole 12-case chain on one launch).
  'rui-settings2': ['sweep_settings2'],
  'all-current': ['handshake', 'message', 'handshake_detail', 'decline'],
  'accepted-friend-inline': ['handshake', 'message'],
  'accepted-friend-detail': ['handshake_detail', 'message'],
  'accepted-friend-inline-burst': ['handshake', 'message_burst'],
  'accepted-friend-detail-burst': ['handshake_detail', 'message_burst'],
  'accepted-friend-inline-group-message': ['handshake', 'group_message'],
  'accepted-friend-detail-group-message': [
    'handshake_detail',
    'group_message',
  ],
  // Single-instance group create/open/composer surface (no friendship needed).
  'group-create': ['group_create'],
  'group-profile-open': ['group_profile_open'],
  'group-rename': ['group_rename'],
  'group-search': ['group_search'],
  'group-add-member-open': ['group_add_member_open'],
  'group-add-member-picker': ['handshake', 'group_add_member_picker'],
  // Single-instance group conversation-row context menu (no friendship needed).
  'group-menu-surface': ['group_conversation_menu'],
  'group-menu-pin': ['group_menu_pin_unpin'],
  'group-menu-mark-read': ['group_menu_mark_read'],
  'group-menu-delete': ['group_menu_delete_confirm'],
  // Combined single-instance group-menu sweep. pin/unpin AND delete-confirm are
  // now driven through the deterministic `l3_open_conversation_menu` action (no
  // flutter_skill PopupMenuItem double-fire), so S132 + S134 are back in the
  // bundle. For a group, "Delete" fires onConversationDeleted (the host
  // suppresses the row until a new inbound) + clears history/pin, so the row
  // leaves the sidebar — the "gone" assertion holds. mark_read here is the
  // single-instance SURFACE check (own sends can't seed unread); the TRUE
  // unread>0→0 transition is the two-process `group-menu-mark-read-unread`
  // campaign.
  'group-menu': [
    'group_conversation_menu',
    'group_menu_pin_unpin',
    'group_menu_mark_read',
    'group_menu_delete_confirm',
  ],
  // Combined single-instance group-surface sweep. Only the live-PASS
  // single-instance scenarios are included so the bundle is green; the
  // currently-BLOCKED single-instance gates (group_profile_open, group_rename,
  // group_search — see their spec Status) keep their own dedicated campaigns.
  'group-surfaces': [
    'group_create',
    'group_conversation_menu',
    'group_menu_pin_unpin',
    'group_menu_mark_read',
  ],
  // Two-process group alternating-burst (S152) + invite→member-list (S155),
  // both require an existing friendship (handshake first), like group_message.
  'group-burst': ['handshake', 'group_burst'],
  'group-member-list': ['handshake', 'group_member_list'],
  // Two-process group menu/clear gates that need REAL inbound state (a peer must
  // send so unread/history actually accrue), so they require a friendship first:
  //  - mark-read-unread (S118/S133): B seeds unread, A marks read → unread→0.
  //  - clear-history (S122): B seeds history, A clears → messageCount→0, row stays.
  //  - clear-preserves-pin (S154): A pins + B seeds, A clears → still pinned.
  'group-menu-mark-read-unread': [
    'handshake',
    'group_menu_mark_read_unread',
  ],
  'group-clear-history': ['handshake', 'group_clear_history'],
  'group-clear-preserves-pin': ['handshake', 'group_clear_preserves_pin'],
  // Legacy Tox conference, same two-process invite+delivery shape as group.
  'accepted-friend-inline-conference-message': [
    'handshake',
    'conference_message',
  ],
  'accepted-friend-detail-conference-message': [
    'handshake_detail',
    'conference_message',
  ],
  'fresh-no-friend': ['decline'],
  'accepted-friend-inline-call': ['handshake', 'message', 'call_voice'],
  'accepted-friend-detail-call': ['handshake_detail', 'message', 'call_voice'],
  'accepted-friend-inline-call-reject': ['handshake', 'call_reject'],
  'accepted-friend-detail-call-reject': ['handshake_detail', 'call_reject'],
  'accepted-friend-inline-chat-stack': [
    'handshake',
    'message',
    'message_burst',
  ],
  'accepted-friend-detail-chat-stack': [
    'handshake_detail',
    'message',
    'message_burst',
  ],
  'accepted-friend-inline-call-stack': [
    'handshake',
    'message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-detail-call-stack': [
    'handshake_detail',
    'message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-inline-full': [
    'handshake',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
  ],
  'accepted-friend-detail-full': [
    'handshake_detail',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
  ],
  'no-friend-then-inline': ['custom_message', 'handshake'],
  'no-friend-then-detail': ['custom_message', 'handshake_detail'],
  'no-friend-inline-chat': ['custom_message', 'handshake', 'message'],
  'no-friend-detail-chat': ['custom_message', 'handshake_detail', 'message'],
  'no-friend-inline-group-message': [
    'custom_message',
    'handshake',
    'group_message',
  ],
  'no-friend-detail-group-message': [
    'custom_message',
    'handshake_detail',
    'group_message',
  ],
  'no-friend-inline-burst': ['custom_message', 'handshake', 'message_burst'],
  'no-friend-detail-burst': [
    'custom_message',
    'handshake_detail',
    'message_burst',
  ],
  'no-friend-inline-call': ['custom_message', 'handshake', 'call_voice'],
  'no-friend-detail-call': ['custom_message', 'handshake_detail', 'call_voice'],
  'no-friend-inline-call-reject': [
    'custom_message',
    'handshake',
    'call_reject',
  ],
  'no-friend-detail-call-reject': [
    'custom_message',
    'handshake_detail',
    'call_reject',
  ],
  'inline-then-decline': ['handshake', 'decline'],
  'detail-then-decline': ['handshake_detail', 'decline'],
  'inline-chat-then-decline': ['handshake', 'message', 'decline'],
  'detail-chat-then-decline': ['handshake_detail', 'message', 'decline'],
  'inline-burst-then-decline': ['handshake', 'message_burst', 'decline'],
  'detail-burst-then-decline': ['handshake_detail', 'message_burst', 'decline'],
  'inline-call-then-decline': ['handshake', 'call_voice', 'decline'],
  'detail-call-then-decline': ['handshake_detail', 'call_voice', 'decline'],
  'inline-call-reject-then-decline': ['handshake', 'call_reject', 'decline'],
  'detail-call-reject-then-decline': [
    'handshake_detail',
    'call_reject',
    'decline',
  ],
  'fresh-custom-message': ['custom_message'],
  'all-expanded': [
    'handshake',
    'message',
    'message_burst',
    'group_message',
    'conference_message',
    'call_voice',
    'call_reject',
    'custom_message',
    'handshake_detail',
    'decline',
  ],
};
const _realUiStateNoFriend = 'no-friend';
const _realUiStateFriends = 'friends';
const _internalRealUiResetScenario = 'reset_friendship';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final opts = _Options.parse(args);
  if (opts.error != null) {
    stderr.writeln(opts.error);
    stderr.writeln(_usage);
    return 64;
  }
  if (opts.listRealUiCampaigns) {
    _printRealUiCampaigns();
    return 0;
  }
  if (opts.showUsage) {
    print(_usage.trim());
    return 0;
  }

  late final _Manifest manifest;
  try {
    manifest = _Manifest.load(_manifestPath);
  } catch (e) {
    stderr.writeln('[unified] manifest load failed: $e');
    return 70;
  }

  final errors = _validate(manifest);
  if (opts.validateOnly) {
    for (final error in errors) {
      stderr.writeln('[unified] VALIDATION ERROR: $error');
    }
    return errors.isEmpty ? 0 : 1;
  }
  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('[unified] VALIDATION ERROR: $error');
    }
    return 1;
  }

  final selected = _select(manifest.entries, opts);
  if (selected.isEmpty) {
    stderr.writeln(
      '[unified] no manifest entries matched the requested filters',
    );
    return 65;
  }
  if (opts.realUiScenarios.isNotEmpty) {
    final realUiEntries = selected.where((entry) => entry.klass == '2proc-ui');
    if (realUiEntries.isEmpty) {
      stderr.writeln(
        '[unified] --real-ui-scenario requires a matching 2proc-ui entry',
      );
      return 64;
    }
    final unknown = opts.realUiScenarios.toSet().difference(
      _validRealUiScenarios,
    );
    if (unknown.isNotEmpty) {
      stderr.writeln(
        '[unified] unknown real-UI scenario(s): ${unknown.join(', ')}',
      );
      return 64;
    }
  }
  if (opts.realUiCampaigns.isNotEmpty) {
    final realUiEntries = selected.where((entry) => entry.klass == '2proc-ui');
    if (realUiEntries.isEmpty) {
      stderr.writeln(
        '[unified] --real-ui-campaign requires a matching 2proc-ui entry',
      );
      return 64;
    }
  }

  final plan = _Plan.fromEntries(selected, opts: opts);

  if (opts.list) {
    _printList(selected);
    return 0;
  }
  if (opts.planJson) {
    print(const JsonEncoder.withIndent('  ').convert(plan.toJson()));
    return 0;
  }
  if (opts.dryRun) {
    _printDryRun(plan);
    return 0;
  }

  try {
    return await _executePlan(plan);
  } catch (e) {
    stderr.writeln('[unified] execution failed: $e');
    return 1;
  }
}

class _Options {
  _Options({
    required this.tier,
    required this.includeDestructive,
    required this.list,
    required this.planJson,
    required this.dryRun,
    required this.validateOnly,
    required this.showUsage,
    required this.listRealUiCampaigns,
    required this.classFilter,
    required this.idFilter,
    required this.realUiScenarios,
    required this.realUiCampaigns,
    this.error,
  });

  final String tier;
  final bool includeDestructive;
  final bool list;
  final bool planJson;
  final bool dryRun;
  final bool validateOnly;
  final bool showUsage;
  final bool listRealUiCampaigns;
  final Set<String> classFilter;
  final Set<String> idFilter;
  final List<String> realUiScenarios;
  final List<String> realUiCampaigns;
  final String? error;

  static _Options parse(List<String> args) {
    var tier = 'non-media';
    var includeDestructive = false;
    var list = false;
    var planJson = false;
    var dryRun = false;
    var validateOnly = false;
    var showUsage = false;
    var listRealUiCampaigns = false;
    final classFilter = <String>{};
    final idFilter = <String>{};
    final realUiScenarios = <String>[];
    final realUiCampaigns = <String>[];
    String? error;

    for (final arg in args) {
      if (arg == '--include-destructive') {
        includeDestructive = true;
      } else if (arg == '--list') {
        list = true;
      } else if (arg == '--plan-json') {
        planJson = true;
      } else if (arg == '--dry-run') {
        dryRun = true;
      } else if (arg == '--validate-only') {
        validateOnly = true;
      } else if (arg.startsWith('--tier=')) {
        tier = arg.substring('--tier='.length);
      } else if (arg.startsWith('--class=')) {
        classFilter.addAll(_splitFlag(arg.substring('--class='.length)));
      } else if (arg.startsWith('--id=')) {
        idFilter.addAll(_splitFlag(arg.substring('--id='.length)));
      } else if (arg.startsWith('--real-ui-scenario=')) {
        realUiScenarios.addAll(
          _splitFlagList(arg.substring('--real-ui-scenario='.length)),
        );
      } else if (arg.startsWith('--real-ui-campaign=')) {
        realUiCampaigns.addAll(
          _splitFlagList(arg.substring('--real-ui-campaign='.length)),
        );
      } else if (arg == '-h' || arg == '--help' || arg == 'help') {
        showUsage = true;
      } else if (arg == '--list-real-ui-campaigns') {
        listRealUiCampaigns = true;
      } else if (arg.trim().isNotEmpty) {
        error = 'unknown argument: $arg';
      }
    }

    if (!_validTiers.contains(tier)) {
      error ??= 'unknown tier: $tier';
    }
    final badClasses = classFilter.difference(_validClasses);
    if (badClasses.isNotEmpty) {
      error ??= 'unknown class value(s): ${badClasses.join(', ')}';
    }
    final badRealUi = realUiScenarios.toSet().difference(_validRealUiScenarios);
    if (badRealUi.isNotEmpty) {
      error ??= 'unknown real-UI scenario(s): ${badRealUi.join(', ')}';
    }
    final badCampaigns = realUiCampaigns.toSet().difference(
      _realUiCampaigns.keys.toSet(),
    );
    if (badCampaigns.isNotEmpty) {
      error ??= 'unknown real-UI campaign(s): ${badCampaigns.join(', ')}';
    }
    if (realUiScenarios.isNotEmpty && realUiCampaigns.isNotEmpty) {
      error ??=
          'choose either --real-ui-scenario=... or --real-ui-campaign=..., not both';
    }

    return _Options(
      tier: tier,
      includeDestructive: includeDestructive,
      list: list,
      planJson: planJson,
      dryRun: dryRun,
      validateOnly: validateOnly,
      showUsage: showUsage,
      listRealUiCampaigns: listRealUiCampaigns,
      classFilter: classFilter,
      idFilter: idFilter,
      realUiScenarios: realUiScenarios,
      realUiCampaigns: realUiCampaigns,
      error: error,
    );
  }
}

Set<String> _splitFlag(String raw) => raw
    .split(',')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toSet();

List<String> _splitFlagList(String raw) => [
  for (final part in raw.split(',').map((part) => part.trim()))
    if (part.isNotEmpty) part,
];

class _Manifest {
  _Manifest(this.entries);

  final List<_Entry> entries;

  static _Manifest load(String path) {
    final root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final rawEntries = (root['entries'] as List? ?? const <dynamic>[]);
    return _Manifest([
      for (var i = 0; i < rawEntries.length; i++)
        _Entry.fromJson(i, rawEntries[i] as Map<String, dynamic>),
    ]);
  }
}

class _Entry {
  _Entry({
    required this.index,
    required this.script,
    required this.scenarios,
    required this.klass,
    required this.media,
    required this.destructive,
    required this.costSecs,
    required this.base,
    required this.driver,
    required this.driverArgs,
    required this.scenarioCommands,
    required this.legacyOnly,
    required this.launchNote,
  });

  final int index;
  final String script;
  final List<String> scenarios;
  final String klass;
  final bool media;
  final bool destructive;
  final int costSecs;
  final String base;
  final String driver;
  final List<String> driverArgs;
  final List<String> scenarioCommands;
  final bool legacyOnly;
  final String? launchNote;

  factory _Entry.fromJson(int index, Map<String, dynamic> json) {
    return _Entry(
      index: index,
      script: json['script']?.toString() ?? '',
      scenarios: _stringList(json['scenarios']),
      klass: json['class']?.toString() ?? '2proc-l3',
      media: json['media'] == true,
      destructive: json['destructive'] == true,
      costSecs: (json['costSecs'] as num?)?.toInt() ?? 0,
      base: json['base']?.toString() ?? '',
      driver: json['driver']?.toString() ?? '',
      driverArgs: _stringList(json['driverArgs']),
      scenarioCommands: _stringList(json['scenarioCommands']),
      legacyOnly: json['legacyOnly'] == true,
      launchNote: json['launchNote']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final doc = <String, dynamic>{
      'script': script,
      'scenarios': scenarios,
      'class': klass,
      'media': media,
      'destructive': destructive,
      'costSecs': costSecs,
      'base': base,
      'driver': driver,
      'driverArgs': driverArgs,
      'legacyOnly': legacyOnly,
    };
    if (scenarioCommands.isNotEmpty) {
      doc['scenarioCommands'] = scenarioCommands;
    }
    if (launchNote != null && launchNote!.isNotEmpty) {
      doc['launchNote'] = launchNote;
    }
    return doc;
  }
}

List<String> _stringList(Object? value) => [
  for (final item in (value as List? ?? const <dynamic>[])) item.toString(),
];

List<String> _validate(_Manifest manifest) {
  final errors = <String>[];
  if (manifest.entries.isEmpty) {
    errors.add('manifest has no entries');
    return errors;
  }

  final seen = <String>{};
  for (final entry in manifest.entries) {
    if (entry.script.isEmpty) {
      errors.add('entry ${entry.index}: missing script');
    }
    if (!seen.add(entry.script)) {
      errors.add('duplicate script: ${entry.script}');
    }
    if (!_validClasses.contains(entry.klass)) {
      errors.add('${entry.script}: unsupported class ${entry.klass}');
    }
    if (entry.scenarios.isEmpty) {
      errors.add('${entry.script}: no scenarios');
    }
    if (!_validBases.contains(entry.base)) {
      errors.add('${entry.script}: unsupported base ${entry.base}');
    }
    if (entry.driver.isEmpty) {
      errors.add('${entry.script}: missing driver');
    }
    if (entry.driverArgs.any((arg) => arg.trim().isEmpty)) {
      errors.add('${entry.script}: driverArgs contains an empty item');
    }
    if (!File('tool/mcp_test/${entry.driver}').existsSync()) {
      errors.add('${entry.script}: driver missing: ${entry.driver}');
    }
    if (entry.legacyOnly &&
        !File('tool/mcp_test/${entry.script}').existsSync()) {
      errors.add('${entry.script}: legacy shell missing');
    }
    if (entry.klass == '2proc-ui') {
      if (entry.base != 'real-ui') {
        errors.add('${entry.script}: 2proc-ui entries must use base "real-ui"');
      }
      if (entry.scenarioCommands.isEmpty) {
        errors.add('${entry.script}: 2proc-ui entry needs scenarioCommands');
      }
      final badScenarios = entry.scenarioCommands.toSet().difference(
        _validRealUiScenarios,
      );
      if (badScenarios.isNotEmpty) {
        errors.add(
          '${entry.script}: unsupported scenarioCommands ${badScenarios.join(', ')}',
        );
      }
    } else if (entry.scenarioCommands.isNotEmpty) {
      errors.add(
        '${entry.script}: only 2proc-ui entries may declare scenarioCommands',
      );
    }
  }
  return errors;
}

List<_Entry> _select(List<_Entry> entries, _Options opts) {
  return [
    for (final entry in entries)
      if (_tierMatches(entry, opts.tier) &&
          (opts.includeDestructive || !entry.destructive) &&
          (opts.classFilter.isEmpty ||
              opts.classFilter.contains(entry.klass)) &&
          (opts.idFilter.isEmpty || opts.idFilter.contains(entry.script)))
        entry,
  ];
}

bool _tierMatches(_Entry entry, String tier) {
  switch (tier) {
    case 'non-media':
      return !entry.media;
    case 'media':
      return entry.media;
    case 'all':
      return true;
  }
  return false;
}

class _Plan {
  _Plan(this.groups);

  final List<_Group> groups;

  factory _Plan.fromEntries(List<_Entry> entries, {required _Options opts}) {
    final paired = <_PlannedEntry>[];
    final fresh = <_PlannedEntry>[];
    final media = <_PlannedEntry>[];
    final realUi = <_PlannedEntry>[];
    final legacy = <_PlannedEntry>[];
    final destructive = <_PlannedEntry>[];

    for (final entry in entries) {
      final planned = _PlannedEntry(
        entry,
        realUiScenarios: entry.klass == '2proc-ui'
            ? _selectedRealUiScenarios(entry, opts)
            : const <String>[],
      );
      if (entry.klass == '2proc-ui') {
        realUi.add(planned);
      } else if (entry.destructive) {
        destructive.add(planned);
      } else if (entry.base == 'fresh') {
        fresh.add(planned);
      } else if (entry.media) {
        if (entry.legacyOnly) {
          legacy.add(planned);
        } else {
          media.add(planned);
        }
      } else if (entry.legacyOnly) {
        legacy.add(planned);
      } else {
        paired.add(planned);
      }
    }

    return _Plan([
      if (paired.isNotEmpty) _Group('paired-reuse', paired),
      for (final entry in fresh) _Group('fresh-isolated', [entry]),
      if (media.isNotEmpty) _Group('media-paired-reuse', media),
      if (realUi.isNotEmpty) _Group('real-ui', realUi),
      for (final entry in legacy) _Group('legacy-isolated', [entry]),
      for (final entry in destructive) _Group('destructive-isolated', [entry]),
    ]);
  }

  Map<String, dynamic> toJson() => {
    'format_version': 2,
    'groups': [for (final group in groups) group.toJson()],
  };
}

class _PlannedEntry {
  _PlannedEntry(this.entry, {required this.realUiScenarios});

  final _Entry entry;
  final List<String> realUiScenarios;

  Map<String, dynamic> toJson() {
    final doc = entry.toJson();
    if (realUiScenarios.isNotEmpty) {
      doc['realUiScenarios'] = realUiScenarios;
    }
    return doc;
  }
}

class _Group {
  _Group(this.mode, this.entries);

  final String mode;
  final List<_PlannedEntry> entries;

  Map<String, dynamic> toJson() => {
    'mode': mode,
    'entries': [for (final entry in entries) entry.toJson()],
    'commands': _commandsForGroup(this),
  };
}

List<String> _selectedRealUiScenarios(_Entry entry, _Options opts) {
  if (opts.realUiScenarios.isNotEmpty) {
    return opts.realUiScenarios;
  }
  if (opts.realUiCampaigns.isNotEmpty) {
    return [
      for (final campaign in opts.realUiCampaigns)
        ...?_realUiCampaigns[campaign],
    ];
  }
  return entry.scenarioCommands;
}

void _printRealUiCampaigns() {
  print('REAL-UI campaigns (${_realUiCampaigns.length})');
  for (final name in _realUiCampaigns.keys.toList()..sort()) {
    print('$name: ${_realUiCampaigns[name]!.join(' -> ')}');
  }
}

void _printList(List<_Entry> entries) {
  print('CLASS      MEDIA  DESTR  LEGACY  BASE             SCRIPT');
  for (final entry in entries) {
    print(
      '${entry.klass.padRight(10)} '
      '${entry.media.toString().padRight(5)}  '
      '${entry.destructive.toString().padRight(5)}  '
      '${entry.legacyOnly.toString().padRight(6)}  '
      '${entry.base.padRight(15)}  '
      '${entry.script} (${entry.scenarios.join(',')})',
    );
  }
}

void _printDryRun(_Plan plan) {
  for (final group in plan.groups) {
    print('# group: ${group.mode}');
    for (final command in _commandsForGroup(group)) {
      print(command);
    }
    print('');
  }
}

List<String> _commandsForGroup(_Group group) {
  switch (group.mode) {
    case 'paired-reuse':
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        for (final entry in group.entries)
          _symbolicDriverCommand(entry.entry, paired: true),
        _stopPairCommand(),
      ];
    case 'fresh-isolated':
      final entry = group.entries.single.entry;
      return [
        _quietStopPairCommand(),
        _launchPairCommand(),
        _symbolicEntryCommand(entry, paired: false),
        _stopPairCommand(),
      ];
    case 'media-paired-reuse':
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        for (final entry in group.entries)
          _symbolicDriverCommand(entry.entry, paired: true),
        _stopPairCommand(),
      ];
    case 'real-ui':
      return [
        for (final entry in group.entries) ..._symbolicRealUiCommands(entry),
      ];
    case 'legacy-isolated':
      return [_legacyShellCommand(group.entries.single.entry)];
    case 'destructive-isolated':
      final entry = group.entries.single.entry;
      if (entry.legacyOnly) {
        return [_legacyShellCommand(entry)];
      }
      return [
        _launchPairCommand(restore: 'paired_for_e2e'),
        _symbolicDriverCommand(entry, paired: true),
        _stopPairCommand(),
      ];
  }
  return const <String>[];
}

String _symbolicEntryCommand(_Entry entry, {required bool paired}) {
  if (entry.legacyOnly) {
    return _legacyShellCommand(entry);
  }
  return _symbolicDriverCommand(entry, paired: paired);
}

String _symbolicDriverCommand(_Entry entry, {required bool paired}) {
  final buffer = StringBuffer(
    'dart run tool/mcp_test/${entry.driver} "\$A_WS" "\$B_WS"',
  );
  if (paired) {
    buffer.write(' --fixture-manifest $_pairManifest');
  }
  for (final arg in entry.driverArgs) {
    buffer.write(' ${_shellLiteral(arg)}');
  }
  return buffer.toString();
}

List<String> _symbolicRealUiCommands(_PlannedEntry planned) {
  final commands = <String>[];
  var pairActive = false;
  String? pairState;
  var pairNeedsRestoreBoot = false;
  String? previousScenario;

  for (var i = 0; i < planned.realUiScenarios.length; i++) {
    final scenario = planned.realUiScenarios[i];
    final requiredState = _requiredRealUiState(scenario);
    if (!pairActive) {
      final restore = _restoreForRealUiState(requiredState);
      commands.add(_launchPairCommand(restore: restore));
      pairActive = true;
      pairState = requiredState;
      pairNeedsRestoreBoot = restore != null;
    } else if (pairState != requiredState) {
      if (pairState == _realUiStateFriends &&
          requiredState == _realUiStateNoFriend) {
        commands.add(_symbolicRealUiResetCommand());
        pairState = _realUiStateNoFriend;
        pairNeedsRestoreBoot = false;
      } else if (pairState == _realUiStateNoFriend &&
          requiredState == _realUiStateFriends) {
        commands.add(_stopPairCommand());
        final restore = _restoreForRealUiState(requiredState);
        commands.add(_launchPairCommand(restore: restore));
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      } else {
        commands.add(_stopPairCommand());
        final restore = _restoreForRealUiState(requiredState);
        commands.add(_launchPairCommand(restore: restore));
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      }
    } else if (pairState == _realUiStateNoFriend &&
        _requiresFreshNoFriendRelaunch(
          previousScenario: previousScenario,
          nextScenario: scenario,
        )) {
      commands.add(_stopPairCommand());
      commands.add(_launchPairCommand());
      pairState = _realUiStateNoFriend;
      pairNeedsRestoreBoot = false;
    }

    commands.add(
      'dart run tool/mcp_test/${planned.entry.driver} '
      '${pairNeedsRestoreBoot ? '--boot-restored ' : ''}'
      '${_shellLiteral(scenario)} '
      '"\$A_WS" "\$A_PID" "\$A_NICK" "\$B_WS" "\$B_PID" "\$B_NICK"',
    );
    pairState = _resultRealUiState(scenario);
    pairNeedsRestoreBoot = false;
    previousScenario = scenario;
  }

  if (pairActive) {
    commands.add(_stopPairCommand());
  }
  return commands;
}

String _requiredRealUiState(String scenario) {
  switch (scenario) {
    case 'message':
    case 'message_burst':
    case 'group_message':
    case 'group_burst':
    case 'group_member_list':
    case 'group_menu_mark_read_unread':
    case 'group_clear_history':
    case 'group_clear_preserves_pin':
    case 'group_add_member_picker':
    case 'conference_message':
    case 'call_voice':
    case 'call_reject':
      return _realUiStateFriends;
    case 'handshake':
    case 'handshake_detail':
    case 'decline':
    case 'custom_message':
    // These single-instance group scenarios only drive A (no friendship needed),
    // so they run from a fresh no-friend launch.
    case 'group_create':
    case 'group_profile_open':
    case 'group_rename':
    case 'group_search':
    case 'group_add_member_open':
    case 'group_conversation_menu':
    case 'group_menu_pin_unpin':
    case 'group_menu_mark_read':
    case 'group_menu_delete_confirm':
    // Batch 1 — settings sweep 2: single-instance (drive only A, B idle), no
    // friendship required, so they run from a fresh no-friend launch.
    case 'sweep_settings2':
    case 'settings_surface_sections':
    case 'settings_theme_dark':
    case 'settings_theme_light_back':
    case 'settings_locale_zh_roundtrip':
    case 'settings_download_limit_edit':
    case 'settings_bootstrap_mode_cycle':
    case 'settings_bootstrap_manual_add_node':
    case 'settings_bootstrap_manual_remove_node':
    case 'settings_autologin_toggle_hard':
    case 'settings_notifsound_toggle_hard':
    case 'settings_password_mismatch_error':
    case 'settings_logout_cancel':
      return _realUiStateNoFriend;
  }
  throw ArgumentError('unsupported real-UI scenario: $scenario');
}

String _resultRealUiState(String scenario) {
  switch (scenario) {
    case 'handshake':
    case 'handshake_detail':
    case 'message':
    case 'message_burst':
    case 'group_message':
    case 'group_burst':
    case 'group_member_list':
    case 'group_menu_mark_read_unread':
    case 'group_clear_history':
    case 'group_clear_preserves_pin':
    case 'group_add_member_picker':
    case 'conference_message':
    case 'call_voice':
    case 'call_reject':
      return _realUiStateFriends;
    case 'decline':
    case 'custom_message':
    // These single-instance group scenarios leave the friendship state untouched.
    case 'group_create':
    case 'group_profile_open':
    case 'group_rename':
    case 'group_search':
    case 'group_add_member_open':
    case 'group_conversation_menu':
    case 'group_menu_pin_unpin':
    case 'group_menu_mark_read':
    case 'group_menu_delete_confirm':
    // Batch 1 — settings sweep 2: single-instance, leaves friendship untouched.
    case 'sweep_settings2':
    case 'settings_surface_sections':
    case 'settings_theme_dark':
    case 'settings_theme_light_back':
    case 'settings_locale_zh_roundtrip':
    case 'settings_download_limit_edit':
    case 'settings_bootstrap_mode_cycle':
    case 'settings_bootstrap_manual_add_node':
    case 'settings_bootstrap_manual_remove_node':
    case 'settings_autologin_toggle_hard':
    case 'settings_notifsound_toggle_hard':
    case 'settings_password_mismatch_error':
    case 'settings_logout_cancel':
      return _realUiStateNoFriend;
  }
  throw ArgumentError('unsupported real-UI scenario: $scenario');
}

bool _requiresFreshNoFriendRelaunch({
  String? previousScenario,
  required String nextScenario,
}) => false;

String? _restoreForRealUiState(String state) {
  if (state == _realUiStateFriends) {
    return 'paired_for_e2e';
  }
  return null;
}

String _symbolicRealUiResetCommand() =>
    'dart run tool/mcp_test/drive_real_ui_pair.dart $_internalRealUiResetScenario '
    '"\$A_WS" "\$A_PID" "\$A_NICK" "\$B_WS" "\$B_PID" "\$B_NICK"';

String _legacyShellCommand(_Entry entry) =>
    'bash tool/mcp_test/${entry.script}';

String _launchPairCommand({String? restore}) {
  if (restore == null || restore.isEmpty) {
    return 'tool/mcp_test/launch_fixture_c_pair.sh';
  }
  return 'TOXEE_FIXTURE_C_RESTORE=$restore tool/mcp_test/launch_fixture_c_pair.sh';
}

String _stopPairCommand() => 'tool/mcp_test/stop_fixture_c_pair.sh';

String _quietStopPairCommand() =>
    'tool/mcp_test/stop_fixture_c_pair.sh >/dev/null 2>&1 || true';

String _shellLiteral(String value) {
  if (value.isEmpty) return "''";
  final simple = RegExp(r'^[A-Za-z0-9_./:=+-]+$');
  if (simple.hasMatch(value)) return value;
  return "'${value.replaceAll("'", "'\"'\"'")}'";
}

Future<int> _executePlan(_Plan plan) async {
  for (final group in plan.groups) {
    stdout.writeln('[unified] >>> ${group.mode}');
    final rc = await _executeGroup(group);
    if (rc != 0) {
      return rc;
    }
  }
  return 0;
}

Future<int> _executeGroup(_Group group) async {
  switch (group.mode) {
    case 'paired-reuse':
      return _executeSharedPairGroup(group.entries);
    case 'fresh-isolated':
      return _executeFreshEntry(group.entries.single.entry);
    case 'media-paired-reuse':
      return _executeSharedPairGroup(group.entries);
    case 'real-ui':
      for (final entry in group.entries) {
        final rc = await _executeRealUiEntry(entry);
        if (rc != 0) return rc;
      }
      return 0;
    case 'legacy-isolated':
      return _executeLegacyEntry(group.entries.single.entry);
    case 'destructive-isolated':
      return _executeDestructiveEntry(group.entries.single.entry);
  }
  return 0;
}

Future<int> _executeSharedPairGroup(List<_PlannedEntry> entries) async {
  await _bestEffortStopPair();
  final launchRc = await _launchPair(restore: 'paired_for_e2e');
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    for (final planned in entries) {
      final rc = await _executeDirectEntry(planned.entry, paired: true);
      if (rc != 0) {
        return rc;
      }
    }
    return 0;
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executeFreshEntry(_Entry entry) async {
  await _bestEffortStopPair();
  final launchRc = await _launchPair();
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    if (entry.legacyOnly) {
      return _executeLegacyEntry(entry);
    }
    return _executeDirectEntry(entry, paired: false);
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executeDestructiveEntry(_Entry entry) async {
  if (entry.legacyOnly) {
    return _executeLegacyEntry(entry);
  }
  await _bestEffortStopPair();
  final launchRc = await _launchPair(restore: 'paired_for_e2e');
  if (launchRc != 0) {
    return launchRc;
  }
  try {
    return _executeDirectEntry(entry, paired: true);
  } finally {
    await _bestEffortStopPair();
  }
}

Future<int> _executeLegacyEntry(_Entry entry) async {
  return _runProcess(['bash', 'tool/mcp_test/${entry.script}']);
}

Future<int> _executeDirectEntry(_Entry entry, {required bool paired}) async {
  final runtime = _RuntimePair.load(_pairJson);
  final args = <String>[
    'run',
    'tool/mcp_test/${entry.driver}',
    runtime.a.wsUri,
    runtime.b.wsUri,
    if (paired) '--fixture-manifest',
    if (paired) _pairManifest,
    ...entry.driverArgs,
  ];
  return _runProcess(['dart', ...args]);
}

Future<int> _executeRealUiEntry(_PlannedEntry planned) async {
  var pairActive = false;
  String? pairState;
  var pairNeedsRestoreBoot = false;
  String? previousScenario;
  try {
    for (var i = 0; i < planned.realUiScenarios.length; i++) {
      final scenario = planned.realUiScenarios[i];
      final requiredState = _requiredRealUiState(scenario);
      var resetApplied = false;
      if (!pairActive) {
        final restore = _restoreForRealUiState(requiredState);
        final launchRc = await _launchPair(restore: restore);
        if (launchRc != 0) {
          return launchRc;
        }
        pairActive = true;
        pairState = requiredState;
        pairNeedsRestoreBoot = restore != null;
      } else if (pairState != requiredState) {
        if (pairState == _realUiStateFriends &&
            requiredState == _realUiStateNoFriend) {
          final resetRc = await _executeInternalRealUiReset();
          if (resetRc != 0) {
            return resetRc;
          }
          pairState = _realUiStateNoFriend;
          pairNeedsRestoreBoot = false;
          resetApplied = true;
        } else {
          await _bestEffortStopPair();
          final restore = _restoreForRealUiState(requiredState);
          final launchRc = await _launchPair(restore: restore);
          if (launchRc != 0) {
            return launchRc;
          }
          pairState = requiredState;
          pairNeedsRestoreBoot = restore != null;
        }
      } else if (pairState == _realUiStateNoFriend &&
          _requiresFreshNoFriendRelaunch(
            previousScenario: previousScenario,
            nextScenario: scenario,
          )) {
        await _bestEffortStopPair();
        final launchRc = await _launchPair();
        if (launchRc != 0) {
          return launchRc;
        }
        pairActive = true;
        pairState = _realUiStateNoFriend;
        pairNeedsRestoreBoot = false;
      }

      var rc = await _executeRealUiScenario(
        planned.entry.driver,
        scenario,
        bootRestored: pairNeedsRestoreBoot,
      );
      if (rc == 78) {
        return rc;
      }
      if (rc != 0 && resetApplied) {
        rc = await _retryRealUiScenarioFromFreshLaunch(
          requiredState: requiredState,
          driver: planned.entry.driver,
          scenario: scenario,
          pairActiveSetter: () {
            pairActive = true;
            pairState = requiredState;
          },
          reason:
              'real-ui reset reuse failed before "$scenario"; relaunching fresh',
          attempts: _maxRealUiAttempts(requiredState),
        );
      } else if (rc != 0 && _maxRealUiAttempts(requiredState) > 1) {
        rc = await _retryRealUiScenarioFromFreshLaunch(
          requiredState: requiredState,
          driver: planned.entry.driver,
          scenario: scenario,
          pairActiveSetter: () {
            pairActive = true;
            pairState = requiredState;
          },
          reason:
              'real-ui scenario "$scenario" failed on a no-friend launch; retrying fresh',
          attempts: _maxRealUiAttempts(requiredState) - 1,
        );
      }
      if (rc != 0) {
        return rc;
      }
      pairState = _resultRealUiState(scenario);
      pairNeedsRestoreBoot = false;
      previousScenario = scenario;
    }
    return 0;
  } finally {
    if (pairActive) {
      await _bestEffortStopPair();
    }
  }
}

int _maxRealUiAttempts(String requiredState) {
  if (requiredState == _realUiStateNoFriend) {
    return 2;
  }
  if (requiredState == _realUiStateFriends) {
    return 2;
  }
  return 1;
}

Future<int> _retryRealUiScenarioFromFreshLaunch({
  required String requiredState,
  required String driver,
  required String scenario,
  required void Function() pairActiveSetter,
  required String reason,
  required int attempts,
}) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    stdout.writeln('[unified] $reason (attempt $attempt/$attempts)');
    await _bestEffortStopPair();
    final relaunchRc = await _launchPair(
      restore: _restoreForRealUiState(requiredState),
    );
    if (relaunchRc != 0) {
      return relaunchRc;
    }
    pairActiveSetter();
    final rc = await _executeRealUiScenario(
      driver,
      scenario,
      bootRestored: requiredState == _realUiStateFriends,
    );
    if (rc == 78) {
      return rc;
    }
    if (rc == 0) {
      return 0;
    }
  }
  return 1;
}

Future<int> _executeRealUiScenario(
  String driver,
  String scenario, {
  required bool bootRestored,
}) async {
  final runtime = _RuntimePair.load(
    _pairJson,
    fallbackNickA: _defaultRealUiNickA,
    fallbackNickB: _defaultRealUiNickB,
  );
  return _runProcess([
    'dart',
    'run',
    'tool/mcp_test/$driver',
    if (bootRestored) '--boot-restored',
    scenario,
    runtime.a.wsUri,
    '${runtime.a.pid}',
    runtime.a.nickname,
    runtime.b.wsUri,
    '${runtime.b.pid}',
    runtime.b.nickname,
  ]);
}

Future<int> _executeInternalRealUiReset() async {
  final runtime = _RuntimePair.load(
    _pairJson,
    fallbackNickA: _defaultRealUiNickA,
    fallbackNickB: _defaultRealUiNickB,
  );
  return _runProcess([
    'dart',
    'run',
    'tool/mcp_test/drive_real_ui_pair.dart',
    _internalRealUiResetScenario,
    runtime.a.wsUri,
    '${runtime.a.pid}',
    runtime.a.nickname,
    runtime.b.wsUri,
    '${runtime.b.pid}',
    runtime.b.nickname,
  ]);
}

Future<int> _launchPair({String? restore}) async {
  final env = <String, String>{
    ...Platform.environment,
    if (restore != null && restore.isNotEmpty)
      'TOXEE_FIXTURE_C_RESTORE': restore,
  };
  return _runProcess([
    'bash',
    'tool/mcp_test/launch_fixture_c_pair.sh',
  ], environment: env);
}

Future<void> _bestEffortStopPair() async {
  await Process.run('bash', ['tool/mcp_test/stop_fixture_c_pair.sh']);
}

Future<int> _runProcess(
  List<String> command, {
  Map<String, String>? environment,
}) async {
  stdout.writeln('[unified] \$ ${command.map(_shellLiteral).join(' ')}');
  final process = await Process.start(
    command.first,
    command.sublist(1),
    environment: environment,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

class _RuntimePair {
  _RuntimePair({required this.a, required this.b});

  final _RuntimeInst a;
  final _RuntimeInst b;

  static _RuntimePair load(
    String path, {
    String fallbackNickA = _defaultRealUiNickA,
    String fallbackNickB = _defaultRealUiNickB,
  }) {
    final root =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final instances = (root['instances'] as Map).cast<String, dynamic>();
    final restored =
        (((root['fixture_restore'] as Map?)?['restored'] as Map?)?['instances']
                as Map?)
            ?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    String restoredNick(String name, String fallback) {
      final raw = ((restored[name] as Map?)?['nickname'])?.toString();
      return (raw == null || raw.isEmpty) ? fallback : raw;
    }

    _RuntimeInst loadInst(String name, String fallbackNick) {
      final raw = (instances[name] as Map).cast<String, dynamic>();
      return _RuntimeInst(
        wsUri: raw['ws_uri']?.toString() ?? '',
        pid: (raw['pid'] as num?)?.toInt() ?? 0,
        nickname: restoredNick(name, fallbackNick),
      );
    }

    return _RuntimePair(
      a: loadInst('A', fallbackNickA),
      b: loadInst('B', fallbackNickB),
    );
  }
}

class _RuntimeInst {
  _RuntimeInst({
    required this.wsUri,
    required this.pid,
    required this.nickname,
  });

  final String wsUri;
  final int pid;
  final String nickname;
}
