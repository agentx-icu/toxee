import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/app_spacing.dart';
import '../util/prefs.dart';
import '../util/app_theme_config.dart';
import '../i18n/app_localizations.dart';

/// Desktop / wide-window max dialog width.
const double _kDesktopMaxDialogWidth = 560;

double _dialogMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return (w - 32).clamp(280.0, _kDesktopMaxDialogWidth);
}

class AddGroupDialog extends StatefulWidget {
  const AddGroupDialog({
    super.key,
    required this.service,
    this.onGroupChanged,
    this.onShowSnackBar,
  });

  final FfiChatService service;
  final Future<void> Function(String groupId, {String? displayName})?
      onGroupChanged;
  final void Function(String message)? onShowSnackBar;

  @override
  State<AddGroupDialog> createState() => _AddGroupDialogState();
}

class _AddGroupDialogState extends State<AddGroupDialog> {
  final _joinFormKey = GlobalKey<FormState>();
  final _createFormKey = GlobalKey<FormState>();
  final _groupIdController = TextEditingController();
  final _requestController = TextEditingController();
  final _aliasController = TextEditingController();
  final _createNameController = TextEditingController();
  bool _isJoining = false;
  bool _isCreating = false;
  String? _createdGroupId;
  String _selectedGroupType = 'group'; // 'group' or 'conference'

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requestController.text.isEmpty) {
      _requestController.text =
          AppLocalizations.of(context)!.defaultJoinRequestMessage;
    }
  }

  @override
  void dispose() {
    _groupIdController.dispose();
    _requestController.dispose();
    _aliasController.dispose();
    _createNameController.dispose();
    super.dispose();
  }

  Future<void> _joinGroup() async {
    if (_isJoining) return;
    if (!_joinFormKey.currentState!.validate()) return;
    final gid = _groupIdController.text.trim();
    final wording = _requestController.text.trim();
    final alias = _aliasController.text.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final successText =
        _localeText(context, 'joinSuccess', fallback: 'Join request sent');
    final failurePrefix =
        _localeText(context, 'joinFailed', fallback: 'Join failed');

    setState(() => _isJoining = true);
    try {
      await widget.service.joinGroup(gid, requestMessage: wording);
      if (alias.isNotEmpty) {
        await Prefs.setGroupName(gid, alias);
      }
      await widget.onGroupChanged?.call(gid,
          displayName: alias.isNotEmpty ? alias : null);
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, successText);
      if (mounted) {
        await navigator.maybePop();
      }
    } catch (e) {
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, '$failurePrefix: $e');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  Future<void> _createGroup() async {
    if (_isCreating) return;
    if (!_createFormKey.currentState!.validate()) return;
    final name = _createNameController.text.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final createFailedText = _localeText(context, 'createFailed',
        fallback: 'Failed to create group');
    final createSuccessText =
        _localeText(context, 'createSuccess', fallback: 'Group created');

    setState(() => _isCreating = true);
    try {
      final gid = await widget.service
          .createGroup(name, groupType: _selectedGroupType);
      if (gid == null || gid.isEmpty) {
        await HapticFeedback.lightImpact();
        _notifyVia(messenger, createFailedText);
        return;
      }
      await Prefs.setGroupName(gid, name);
      await widget.onGroupChanged?.call(gid, displayName: name);
      if (!mounted) return;
      setState(() => _createdGroupId = gid);
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, createSuccessText);
      // Close dialog after successful creation
      if (mounted) {
        await navigator.maybePop();
      }
    } catch (e) {
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, '$createFailedText: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _dialogMaxWidth(context)),
        child: Material(
          color: Colors.transparent,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _localeText(context, 'addGroup',
                        fallback: 'Add or Create Group'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                  ),
                  AppSpacing.verticalLg,
                  _buildJoinCard(),
                  AppSpacing.verticalLg,
                  _buildCreateCard(),
                  if (_createdGroupId != null) ...[
                    AppSpacing.verticalLg,
                    _buildCreatedInfo(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildJoinCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _joinFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'joinGroup',
                    fallback: 'Join Group by ID'),
                style: theme.textTheme.titleMedium,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _groupIdController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupId',
                      fallback: 'Group ID'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return _localeText(context, 'enterGroupId',
                        fallback: 'Please enter group ID');
                  }
                  return null;
                },
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _requestController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'requestMessage',
                      fallback: 'Request Message'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
                minLines: 1,
                maxLines: 4,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _aliasController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupAlias',
                      fallback: 'Local group name (optional)'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
              ),
              AppSpacing.verticalLg,
              _buildPrimaryAction(
                scheme: scheme,
                busy: _isJoining,
                icon: Icons.group_add,
                label: _localeText(context, 'joinAction',
                    fallback: 'Send Join Request'),
                onPressed: _joinGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      // Tinted-primary variant signals this is the canonical "create" path.
      color: AppThemeConfig.tintedPrimaryCardColor(scheme.primary),
      shape: AppThemeConfig.tintedPrimaryCardShape(scheme.primary),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _createFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _localeText(context, 'createGroup',
                    fallback: 'Create New Group'),
                style: theme.textTheme.titleMedium,
              ),
              AppSpacing.verticalMd,
              TextFormField(
                controller: _createNameController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: _localeText(context, 'groupName',
                      fallback: 'Group Name'),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.input),
                  ),
                ),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return _localeText(context, 'enterGroupName',
                        fallback: 'Please enter a group name');
                  }
                  return null;
                },
              ),
              AppSpacing.verticalLg,
              Text(
                _localeText(context, 'groupType', fallback: 'Group Type'),
                style: theme.textTheme.bodyMedium,
              ),
              AppSpacing.verticalSm,
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'group',
                    label: Text(AppLocalizations.of(context)!.group),
                    icon: const Icon(Icons.group),
                  ),
                  ButtonSegment(
                    value: 'conference',
                    label: Text(AppLocalizations.of(context)!.conference),
                    icon: const Icon(Icons.forum),
                  ),
                ],
                selected: {_selectedGroupType},
                onSelectionChanged: (Set<String> newSelection) {
                  setState(() {
                    _selectedGroupType = newSelection.first;
                  });
                },
              ),
              AppSpacing.verticalLg,
              _buildPrimaryAction(
                scheme: scheme,
                busy: _isCreating,
                icon: Icons.group,
                label: _localeText(context, 'createAction',
                    fallback: 'Create Group'),
                onPressed: _createGroup,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPrimaryAction({
    required ColorScheme scheme,
    required bool busy,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: busy ? _localeText(context, 'sending', fallback: 'Sending...') : '',
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
          ),
          icon: busy
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                  ),
                )
              : Icon(icon),
          label: Text(label),
          onPressed: busy ? null : onPressed,
        ),
      ),
    );
  }

  Widget _buildCreatedInfo() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppThemeConfig.tintedPrimaryCardColor(scheme.primary),
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(
          color: AppThemeConfig.tintedPrimaryCardBorderColor(scheme.primary),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _localeText(context, 'createdGroupId', fallback: 'New Group ID'),
            style: theme.textTheme.titleMedium,
          ),
          AppSpacing.verticalSm,
          SelectableText(
            _createdGroupId ?? '',
            style:
                theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
          ),
          AppSpacing.verticalSm,
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
              side: BorderSide(
                color: AppThemeConfig
                    .tintedPrimaryCardBorderColor(scheme.primary),
              ),
            ),
            icon: const Icon(Icons.copy),
            label: Text(_localeText(context, 'copyId', fallback: 'Copy ID')),
            onPressed: _createdGroupId == null
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.maybeOf(context);
                    final copiedText = _localeText(context, 'copied',
                        fallback: 'Copied to clipboard');
                    await Clipboard.setData(
                        ClipboardData(text: _createdGroupId!));
                    _notifyVia(messenger, copiedText);
                  },
          ),
        ],
      ),
    );
  }

  void _notifyVia(ScaffoldMessengerState? messenger, String message) {
    if (widget.onShowSnackBar != null) {
      widget.onShowSnackBar!(message);
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _localeText(BuildContext context, String key,
      {required String fallback}) {
    final appL10n = AppLocalizations.of(context)!;
    switch (key) {
      case 'addGroup':
        return appL10n.addOrCreateGroup;
      case 'joinGroup':
        return appL10n.joinGroupById;
      case 'groupId':
        return appL10n.groupId;
      case 'enterGroupId':
        return appL10n.enterGroupId;
      case 'requestMessage':
        return appL10n.requestMessage;
      case 'groupAlias':
        return appL10n.groupAlias;
      case 'joinAction':
        return appL10n.joinAction;
      case 'joinSuccess':
        return appL10n.joinSuccess;
      case 'joinFailed':
        return appL10n.joinFailed;
      case 'createGroup':
        return appL10n.createGroup;
      case 'groupName':
        return appL10n.groupName;
      case 'enterGroupName':
        return appL10n.enterGroupName;
      case 'createAction':
        return appL10n.createAction;
      case 'createSuccess':
        return appL10n.createSuccess;
      case 'createFailed':
        return appL10n.createFailed;
      case 'createdGroupId':
        return appL10n.createdGroupId;
      case 'copyId':
        return appL10n.copyId;
      case 'copied':
        return appL10n.copied;
      case 'sending':
        return fallback;
    }
    return fallback;
  }
}
