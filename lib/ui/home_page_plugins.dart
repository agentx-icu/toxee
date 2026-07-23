part of 'home_page.dart';

extension _HomePagePlugins on _HomePageState {
  void _ensureStickerPluginRegistered() {
    AppLogger.debug(
      '[HomePage] _ensureStickerPluginRegistered called: mounted=$mounted',
    );
    if (!mounted) {
      AppLogger.debug(
        '[HomePage] _ensureStickerPluginRegistered: Early return - not mounted',
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppLogger.debug(
        '[HomePage] _ensureStickerPluginRegistered: PostFrameCallback executing, mounted=$mounted',
      );
      if (!mounted) {
        AppLogger.debug(
          '[HomePage] _ensureStickerPluginRegistered: PostFrameCallback skipped - not mounted',
        );
        return;
      }
      _tryRegisterStickerPlugin();
    });
    AppLogger.debug(
      '[HomePage] _ensureStickerPluginRegistered: Registering other plugins',
    );
    _registerTextTranslatePlugin();
    // The fork derives the voice-message menu item from plugin presence.
    // tim2tox currently has no STT backend, so registering the stub would
    // expose a Convert to Text action that can never produce content.
    if (tim2toxSoundToTextBackendSupported) {
      _registerSoundToTextPlugin();
    }
  }

  void _tryRegisterStickerPluginSync() {
    if (_stickerPluginRegistered) return;
    final userId = widget.service.selfId;
    if (userId.isEmpty) return;

    if (UikitDataFacade.hasPlugin("sticker")) {
      _stickerPluginRegistered = true;
      AppLogger.debug(
        '[HomePage] _tryRegisterStickerPluginSync: Plugin already registered',
      );
      return;
    }

    AppLogger.debug(
      '[HomePage] _tryRegisterStickerPluginSync: Registering sticker plugin synchronously',
    );
    final stickerPlugin = TencentCloudChatStickerPlugin(context: context);
    final initDataObj = TencentCloudChatStickerInitData(
      userID: userId,
      useDefaultSticker: true,
      useDefaultCustomFace_4350: true,
      useDefaultCustomFace_4351: true,
      useDefaultCustomFace_4352: true,
    );
    final initData = initDataObj.toJson();

    stickerPlugin
        .init(json.encode(initData))
        .then((initResult) {
          if (!mounted) return;
          UikitDataFacade.addPlugin(
            TencentCloudChatPluginItem(
              name: "sticker",
              initData: initData,
              pluginInstance: stickerPlugin,
            ),
          );
          _stickerPluginRegistered = true;
          AppLogger.debug(
            '[HomePage] _tryRegisterStickerPluginSync: Plugin registered successfully',
          );
        })
        .catchError((e, stackTrace) {
          AppLogger.logError(
            '[HomePage] _tryRegisterStickerPluginSync: Failed to register: $e',
            e,
            stackTrace,
          );
        });
  }

  void _tryRegisterStickerPlugin() {
    AppLogger.debug(
      '[HomePage] _tryRegisterStickerPlugin called: _stickerPluginRegistered=$_stickerPluginRegistered, mounted=$mounted',
    );
    if (_stickerPluginRegistered || !mounted) {
      AppLogger.debug(
        '[HomePage] _tryRegisterStickerPlugin: Early return - already registered or not mounted',
      );
      return;
    }
    final userId = widget.service.selfId;
    AppLogger.debug(
      '[HomePage] _tryRegisterStickerPlugin: userId=$userId, isEmpty=${userId.isEmpty}',
    );
    if (userId.isEmpty) {
      AppLogger.debug(
        '[HomePage] Sticker plugin: selfId not available yet, will retry when available',
      );
      return;
    }
    final hasPlugin = UikitDataFacade.hasPlugin("sticker");
    AppLogger.debug(
      '[HomePage] _tryRegisterStickerPlugin: hasPlugin("sticker")=$hasPlugin',
    );
    if (hasPlugin) {
      final plugin = UikitDataFacade.getPlugin("sticker");
      AppLogger.debug(
        '[HomePage] _tryRegisterStickerPlugin: Plugin already exists: ${plugin != null}, instance=${plugin?.pluginInstance}',
      );
      _stickerPluginRegistered = true;
      AppLogger.debug('[HomePage] Sticker plugin already registered');
      return;
    }

    AppLogger.debug(
      '[HomePage] Registering sticker plugin with userId: $userId',
    );
    final stickerPlugin = TencentCloudChatStickerPlugin(context: context);
    final initDataObj = TencentCloudChatStickerInitData(
      userID: userId,
      useDefaultSticker: true,
      useDefaultCustomFace_4350: true,
      useDefaultCustomFace_4351: true,
      useDefaultCustomFace_4352: true,
    );
    final initData = initDataObj.toJson();
    AppLogger.debug('[HomePage] Sticker initData: $initData');
    Future(() async {
      try {
        final initResult = await stickerPlugin.init(json.encode(initData));
        AppLogger.debug('[HomePage] Sticker plugin init result: $initResult');
        if (!mounted) return;
        UikitDataFacade.addPlugin(
          TencentCloudChatPluginItem(
            name: "sticker",
            initData: initData,
            pluginInstance: stickerPlugin,
          ),
        );
        _stickerPluginRegistered = true;
        AppLogger.debug('[HomePage] Sticker plugin registered successfully');

        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            UikitDataFacade.notifyAddUsedComponent();
            AppLogger.debug('[HomePage] Triggered plugin update notification');
            try {
              if (UikitDataFacade.currentConversation != null) {
                UikitDataFacade.notifyCurrentConversation();
                AppLogger.debug(
                  '[HomePage] Triggered conversation update to force message component rebuild',
                );
              }
            } catch (e) {
              AppLogger.logError(
                '[HomePage] Failed to trigger conversation update: $e',
                e,
                StackTrace.current,
              );
            }
            try {
              UikitDataFacade.notifyAddUsedComponent();
              AppLogger.debug(
                '[HomePage] Triggered basic data update for plugin registration',
              );
            } catch (e) {
              AppLogger.logError(
                '[HomePage] Failed to trigger basic data update: $e',
                e,
                StackTrace.current,
              );
            }
          }
        });
        final plugin = UikitDataFacade.getPlugin("sticker");
        AppLogger.debug(
          '[HomePage] Plugin verification: plugin=${plugin != null}',
        );
        if (plugin != null) {
          AppLogger.debug(
            '[HomePage] Sticker plugin verified: name=${plugin.name}, instance=${plugin.pluginInstance}, initData=${plugin.initData}',
          );
          try {
            AppLogger.debug('[HomePage] Testing getWidget("stickerPanel")...');
            final widget = await plugin.pluginInstance.getWidget(
              methodName: "stickerPanel",
            );
            AppLogger.debug(
              '[HomePage] Sticker panel widget retrieved: ${widget != null}, type=${widget.runtimeType}',
            );
            if (widget == null) {
              AppLogger.debug('[HomePage] ERROR: getWidget returned null!');
            }
          } catch (e, stackTrace) {
            AppLogger.logError(
              '[HomePage] Failed to get sticker panel widget: $e',
              e,
              stackTrace,
            );
          }
          AppLogger.debug(
            '[HomePage] Plugin instance type: ${plugin.pluginInstance.runtimeType}',
          );
          if (plugin.pluginInstance is TencentCloudChatStickerPlugin) {
            AppLogger.debug(
              '[HomePage] Plugin is TencentCloudChatStickerPlugin, initData.userID=${TencentCloudChatStickerPlugin.initData.userID}',
            );
            AppLogger.debug(
              '[HomePage] Plugin initData.customStickerLists: ${TencentCloudChatStickerPlugin.initData.customStickerLists?.length ?? 0} items',
            );
          }
        } else {
          AppLogger.debug(
            '[HomePage] WARNING: Sticker plugin not found after registration!',
          );
          AppLogger.debug(
            '[HomePage] Available plugins: ${UikitDataFacade.plugins.map((p) => p.name).join(", ")}',
          );
        }
        final finalCheck = UikitDataFacade.hasPlugin("sticker");
        final finalPlugin = UikitDataFacade.getPlugin("sticker");
        AppLogger.debug(
          '[HomePage] Final plugin check: hasPlugins=$finalCheck, getPlugin=${finalPlugin != null}',
        );
      } catch (e, stackTrace) {
        AppLogger.logError(
          '[HomePage] Failed to register sticker plugin: $e',
          e,
          stackTrace,
        );
      }
    });
  }

  void _registerTextTranslatePlugin() {
    if (_textTranslatePluginRegistered || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _textTranslatePluginRegistered) return;
      if (!UikitDataFacade.hasPlugin("textTranslate")) {
        final plugin = TencentCloudChatTextTranslate(
          onTranslateFailed: () {},
          onTranslateSuccess: (localCustomData) {},
        );
        UikitDataFacade.addPlugin(
          TencentCloudChatPluginItem(
            name: "textTranslate",
            pluginInstance: plugin,
          ),
        );
        _textTranslatePluginRegistered = true;
      } else {
        _textTranslatePluginRegistered = true;
      }
    });
  }

  void _registerSoundToTextPlugin() {
    if (_soundToTextPluginRegistered || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _soundToTextPluginRegistered = registerTim2toxSoundToTextIfSupported(
        backendSupported: tim2toxSoundToTextBackendSupported,
        alreadyRegistered: _soundToTextPluginRegistered,
        pluginExists: UikitDataFacade.hasPlugin("soundToText"),
        addPlugin: () {
          UikitDataFacade.addPlugin(
            TencentCloudChatPluginItem(
              name: "soundToText",
              pluginInstance: TencentCloudChatSoundToText(),
            ),
          );
        },
      );
    });
  }
}
